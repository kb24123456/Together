import Foundation
import AppKit
import RiveRuntime
import CryptoKit

let asset = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: asset)
let file = try RiveFile(data: data, loadCdn: false)
let model = file.viewModelNamed("TogetherSphereModel")!
let phases: [(String, Int, Int, Int)] = [("pending",0,0,90),("enter-1",1,0,90),("enter-4",4,0,90),("enter-7",7,0,90),("enter-12",12,0,90),("hold-short",30,0,90),("holding",60,0,90),("exit-1",60,1,90),("exit-4",60,4,90),("exit-7",60,7,90),("exit-12",60,12,90),("acquire-pending",1,0,0),("acquire-early",18,0,0),("acquire-mid",40,0,0),("acquire-late",58,0,0)]
let targets: [(String, Float, Bool)] = [("idle",0,false),("write",1,true),("hold",1,false),("concern",2,false),("think",3,false)]
let flows: [(String, String?, Int)] = [("visible-release",nil,0),("pause-home-only",nil,0),("pause-pending-ack","ack",0),("pause-active-ack","ack",20),("pause-pending-celebrate","celebrate",0),("pause-active-celebrate","celebrate",30)]
var results: [[String: Any]] = []

final class Run {
    let board: RiveArtboard
    let machine: RiveStateMachineInstance
    let vm: RiveDataBindingViewModel.Instance
    var lastExpression = ""
    var lastBehavior = ""
    var states: [String] = []
    init() throws {
        board = try file.artboard(fromName:"TogetherSphere")
        machine = try board.stateMachine(fromName:"Mascot")
        vm = model.createDefaultInstance()!
        board.bind(viewModelInstance:vm)
        machine.bind(viewModelInstance:vm)
    }
    func number(_ name: String, _ value: Float) { vm.numberProperty(fromPath:name)!.value = value }
    @discardableResult func step(_ dt: Double) -> [String] {
        _ = machine.advance(by:dt)
        let changed = machine.stateChanges()
        states += changed
        for name in changed {
            if name.hasPrefix("Expr_") || name.hasPrefix("Home_") { lastExpression = name }
            else if !name.hasPrefix("Action_") { lastBehavior = name }
        }
        return changed
    }
    func frames(_ count: Int) { for _ in 0..<count { step(1/60) } }
    func home(_ value: Float) { number("expression",0); number("mode",0); number("idleFace",value) }
}

for homeFace: Float in [0,2,21] {
    for (phase, enteredFrames, exitFrames, warmupFrames) in phases {
        for (targetName,targetMode,targetTyping) in targets {
            for (flow,feedback,feedbackFrames) in flows {
                try autoreleasepool {
                    let run = try Run()
                    run.home(0); run.frames(warmupFrames)
                    let acquiredBeforePhase = warmupFrames == 0 || run.lastExpression == "Home_Calm"
                    run.number("idleFace",homeFace); run.frames(enteredFrames)
                    if exitFrames > 0 { run.number("idleFace",0); run.frames(exitFrames) }
                    let before = run.lastExpression
                    if let feedback {
                        run.number("idleFace",-1); run.number("expression",0)
                        if feedback == "ack" { run.vm.triggerProperty(fromPath:"acknowledge")!.trigger() }
                        else { run.vm.booleanProperty(fromPath:"celebrateRequested")!.value = true }
                        run.frames(feedbackFrames)
                    }
                    run.number("idleFace",-1); run.number("expression",0)
                    run.number("mode",targetMode); run.vm.booleanProperty(fromPath:"isTyping")!.value = targetTyping
                    var drain: [[String]] = []
                    if flow != "visible-release" {
                        run.vm.booleanProperty(fromPath:"celebrateRequested")!.value = false
                        for dt in feedback == nil ? [0,0.3,0.3,0.1] : [0,2,0.1,0.1] { drain.append(run.step(dt)) }
                    }
                    let expressionAfterDrain = run.lastExpression
                    let resumedStart = run.states.count
                    run.frames(240)
                    let resumed = Array(run.states.dropFirst(resumedStart))
                    let expectedBehavior: Bool
                    switch targetName {
                    case "idle": expectedBehavior = run.lastBehavior.hasPrefix("Idle")
                    case "write": expectedBehavior = run.lastBehavior == "Writing"
                    case "hold": expectedBehavior = run.lastBehavior == "WritingHold"
                    case "concern": expectedBehavior = run.lastBehavior == "Concerned"
                    default: expectedBehavior = run.lastBehavior == "Thinking"
                    }
                    let noSleep = !run.states.contains { $0.contains("Doze") || $0.contains("Wake") || $0.contains("Sleepy") }
                    let cleanDrain = flow == "visible-release" || expressionAfterDrain == "Expr_Auto"
                    let noStaleHomeOnResume = flow == "visible-release" || !resumed.contains { $0.hasPrefix("Home_") }
                    let noResumedFeedback = flow == "visible-release" || !resumed.contains { $0.contains("Celebrate") || $0 == "Expression_Wink" }
                    let passed = acquiredBeforePhase && expectedBehavior && noSleep && cleanDrain && noStaleHomeOnResume && noResumedFeedback && run.lastExpression == "Expr_Auto"
                    results.append(["kind":"home-interruption","homeFace":homeFace,"phase":phase,"target":targetName,"flow":flow,"before":before,"warmupFrames":warmupFrames,"acquiredBeforePhase":acquiredBeforePhase,"afterDrain":expressionAfterDrain,"drainTrace":drain,"finalExpression":run.lastExpression,"finalBehavior":run.lastBehavior,"resumedStates":resumed,"noSleep":noSleep,"cleanDrain":cleanDrain,"noStaleHomeOnResume":noStaleHomeOnResume,"noResumedFeedback":noResumedFeedback,"expectedBehavior":expectedBehavior,"passed":passed])
                }
            }
        }
    }
    print("Audited Home \(homeFace): \(results.count)")
}

// Rapid selector changes during every transition phase should converge to the latest target.
for from: Float in [0,2,21] {
    for to: Float in [0,2,21] {
        for phase in [0,1,4,7,12,17,30] {
            try autoreleasepool {
                let run = try Run(); run.home(0); run.frames(90)
                run.number("idleFace",from);run.frames(phase)
                run.number("idleFace",to);run.frames(180)
                let expected = to == 2 ? "Home_HappyHold" : to == 21 ? "Home_CuriousHold" : "Home_Calm"
                let settled = run.lastExpression
                let start = run.states.count
                for _ in 0..<120 { run.number("idleFace",to);run.frames(1) }
                let repeated = Array(run.states.dropFirst(start)).filter { $0.hasPrefix("Home_") }
                results.append(["kind":"fast-target-and-repeat","from":from,"to":to,"phaseFrame":phase,"settled":settled,"expected":expected,"repeatedHomeTransitions":repeated,"passed":settled == expected && run.lastExpression == expected && repeated.isEmpty])
            }
        }
    }
}
// Re-entering after a completed hidden release starts from current calm, never cancelled expression.
for value: Float in [0,2,21] {
    for phase in [1,7,12,30,60] {
        try autoreleasepool {
            let run = try Run();run.home(0);run.frames(90);run.number("idleFace",value);run.frames(phase)
            run.number("idleFace",-1)
            for dt in [0,0.3,0.3,0.1] { run.step(dt) }
            let afterDrain = run.lastExpression
            let start=run.states.count;run.home(0);run.frames(120)
            let resumed=Array(run.states.dropFirst(start)).filter { $0.hasPrefix("Home_") }
            results.append(["kind":"home-resume-calm","from":value,"phaseFrame":phase,"afterDrain":afterDrain,"resumed":resumed,"final":run.lastExpression,"passed":afterDrain == "Expr_Auto" && run.lastExpression == "Home_Calm" && !resumed.contains { $0.contains("Happy") || $0.contains("Curious") }])
        }
    }
}
// Backwards-compatible default: old standalone expressions still work with untouched idleFace=-1.
let legacyNames = ["Calm","SoftHappy","Laugh","Excited","WinkSmile","Love","Blush","Smug","CuriousOpen","PuzzledOpen","ThinkingUp","GentleFocus","Surprised","Embarrassed","MildAngry","Speechless","SleepyYawn","Content","Sad","SmallTears","CuriousQuiet","PuzzledQuiet","Determined","Realization","ShyLookAway","Helpless","Nervous","SleepyLow"]
for value: Float in (1...28).map(Float.init) {
    try autoreleasepool {
        let run=try Run();let defaultValue=run.vm.numberProperty(fromPath:"idleFace")!.value
        run.number("expression",value);run.frames(90);let held=run.lastExpression
        run.number("expression",0);run.frames(90)
        let noHome = !run.states.contains { $0.hasPrefix("Home_") }
        results.append(["kind":"legacy-expression-default","expression":value,"defaultIdleFace":defaultValue,"held":held,"final":run.lastExpression,"noHome":noHome,"passed":defaultValue == -1 && held == "Expr_" + legacyNames[Int(value)-1] && run.lastExpression == "Expr_Auto" && noHome])
    }
}
let failed=results.filter { $0["passed"] as? Bool == false }
let evidence: [String: Any] = ["assetPath":asset.path,"assetSHA256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),"runtimeVersion":"6.25.1","caseCount":results.count,"failedCount":failed.count,"homeDrainSteps":[0,0.3,0.3,0.1],"feedbackDrainSteps":[0,2,0.1,0.1],"api":"Official synchronous Apple RiveRuntime inspection; same exported core graph as New Runtime", "limits":["State and input cleanup checks; does not directly introspect per-component opacity.","Pixel continuity and device behavior require separate rendering/device evidence."],"cases":results]
try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("\(results.count-failed.count)/\(results.count) passed")
for item in failed.prefix(8) { print(item) }
if !failed.isEmpty { exit(1) }
