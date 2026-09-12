import Foundation
import AppKit
import RiveRuntime
import CryptoKit

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let file = try RiveFile(data: data, loadCdn: false)
let model = file.viewModelNamed("TogetherSphereModel")!
let names: [Float: String] = [2: "SoftHappy", 5: "WinkSmile", 8: "Smug", 21: "CuriousQuiet"]
let phases: [(String, Int, Int)] = [("pending",0,0),("close-auto",2,0),("resolve-enter",6,0),("blend-enter",10,0),("holding-short",24,0),("holding",60,0),("exit-start",60,1),("exit-mid",60,4),("exit-resolve",60,7),("exit-auto-blend",60,10)]
let targets: [(String, Float, Bool)] = [("idle",0,false),("write",1,true),("hold",1,false),("concern",2,false),("think",3,false)]
let flows: [(String, String?, Int)] = [("visible-exit",nil,0),("pause-expression-only",nil,0),("pause-pending-ack","ack",0),("pause-active-ack","ack",20),("pause-pending-celebrate","celebrate",0),("pause-active-celebrate","celebrate",30)]
var results: [[String: Any]] = []
for expression: Float in [2,5,8,21] {
  for (phase, expressionFrames, exitFrames) in phases {
    for (targetName, targetMode, targetTyping) in targets {
      for (flow, feedback, feedbackFrames) in flows {
        try autoreleasepool {
          let board = try file.artboard(fromName: "TogetherSphere")
          let sm = try board.stateMachine(fromName: "Mascot")
          let vm = model.createDefaultInstance()!
          sm.bind(viewModelInstance: vm)
          var lastExpression = ""
          var lastBehavior = ""
          var states: [String] = []
          func step(_ dt: Double) -> [String] {
            _ = sm.advance(by: dt)
            let changes = sm.stateChanges()
            states += changes
            for name in changes {
              if name.hasPrefix("Expr_") { lastExpression = name }
              else if !name.hasPrefix("Action_") { lastBehavior = name }
            }
            return changes
          }
          func frames(_ count: Int) { for _ in 0..<count { _ = step(1/60) } }
          vm.numberProperty(fromPath: "mode")!.value = 0
          vm.numberProperty(fromPath: "expression")!.value = 0
          frames(60)
          vm.numberProperty(fromPath: "expression")!.value = expression
          frames(expressionFrames)
          if exitFrames > 0 { vm.numberProperty(fromPath: "expression")!.value = 0; frames(exitFrames) }
          let expressionBefore = lastExpression
          if let feedback {
            // Exact production ordering: clear expression before issuing feedback.
            vm.numberProperty(fromPath: "expression")!.value = 0
            if feedback == "ack" { vm.triggerProperty(fromPath: "acknowledge")!.trigger() }
            else { vm.booleanProperty(fromPath: "celebrateRequested")!.value = true }
            frames(feedbackFrames)
          }
          vm.numberProperty(fromPath: "expression")!.value = 0
          vm.numberProperty(fromPath: "mode")!.value = targetMode
          vm.booleanProperty(fromPath: "isTyping")!.value = targetTyping
          var drainTrace: [[String]] = []
          if flow != "visible-exit" {
            vm.booleanProperty(fromPath: "celebrateRequested")!.value = false
            let steps: [Double] = feedback == nil ? [0,0.12,0.12,0.12] : [0,2,0.1,0.1]
            for dt in steps { drainTrace.append(step(dt)) }
          }
          let expressionAtPauseEnd = lastExpression
          let behaviorAtPauseEnd = lastBehavior
          let resumeStart = states.count
          frames(240)
          let resumed = Array(states.dropFirst(resumeStart))
          let behaviorCorrect: Bool
          switch targetName {
          case "idle": behaviorCorrect = lastBehavior.hasPrefix("Idle")
          case "write": behaviorCorrect = lastBehavior == "Writing"
          case "hold": behaviorCorrect = lastBehavior == "WritingHold"
          case "concern": behaviorCorrect = lastBehavior == "Concerned"
          default: behaviorCorrect = lastBehavior == "Thinking"
          }
          let noSleep = !states.contains { $0.contains("Doze") || $0.contains("Wake") || $0.contains("Sleepy") }
          let cleanAfterPause = flow == "visible-exit" || expressionAtPauseEnd == "Expr_Auto"
          let noResumedFeedback = flow == "visible-exit" || !resumed.contains { $0.contains("Celebrate") || $0 == "Expression_Wink" }
          let passed = lastExpression == "Expr_Auto" && cleanAfterPause && behaviorCorrect && noSleep && noResumedFeedback
            && vm.numberProperty(fromPath:"expression")!.value == 0
            && vm.numberProperty(fromPath:"mode")!.value == targetMode
            && vm.booleanProperty(fromPath:"celebrateRequested")!.value == false
          results.append(["expression":expression,"name":names[expression]!,"phase":phase,"target":targetName,"flow":flow,
                          "expressionBefore":expressionBefore,"expressionAtPauseEnd":expressionAtPauseEnd,"behaviorAtPauseEnd":behaviorAtPauseEnd,
                          "drainTrace":drainTrace,"finalExpression":lastExpression,"finalBehavior":lastBehavior,"resumedStates":resumed,
                          "noSleep":noSleep,"cleanAfterPause":cleanAfterPause,"behaviorCorrect":behaviorCorrect,"noResumedFeedback":noResumedFeedback,"passed":passed])
        }
      }
    }
  }
  print("Audited \(names[expression]!) - \(results.count) cases")
}
let failed = results.filter { $0["passed"] as? Bool == false }
let evidence: [String: Any] = ["caseCount":results.count,"failedCount":failed.count,"runtimeVersion":"6.25.1",
  "assetPath":CommandLine.arguments[1],"assetSHA256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),
  "phaseCount":phases.count,"targetModes":[0,1,2,3],"expressionOnlyDrainSteps":[0,0.12,0.12,0.12],"feedbackDrainSteps":[0,2,0.1,0.1],
  "api":"Official RiveRuntime inspection API with the same exported core state machine. State changes name animations, not editor state nodes.",
  "limits":["This verifies state execution and cleanup, not pixels or iPhone behavior.","Production uses New Runtime worker API; this fixture tests the same core transitions synchronously."],
  "cases":results]
try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("\(results.count-failed.count)/\(results.count) checks passed")
for result in failed.prefix(8) { print(result) }
if !failed.isEmpty { exit(1) }
