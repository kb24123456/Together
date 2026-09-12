import Foundation
import AppKit
import RiveRuntime

let file = try RiveFile(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), loadCdn: false)
let model = file.viewModelNamed("TogetherSphereModel")!
var results: [[String: Any]] = []
for kind in ["acknowledge", "celebrate"] {
    for initialMode: Float in kind == "celebrate" ? [0, 2] : [0] {
        for consumedFrames in [0, 1, 10, 40, 75, 100] {
            for finalMode: Float in [0, 1, 2, 3, 4] {
                let board = try file.artboard(fromName: "TogetherSphere")
                let sm = try board.stateMachine(fromName: "Mascot")
                let vm = model.createDefaultInstance()!
                sm.bind(viewModelInstance: vm)
                vm.numberProperty(fromPath: "mode")!.value = initialMode
                var lastState = ""
                for _ in 0..<120 { _ = sm.advance(by: 1/60); lastState = sm.stateChanges().last ?? lastState }
                if kind == "acknowledge" { vm.triggerProperty(fromPath: "acknowledge")!.trigger() }
                else { vm.booleanProperty(fromPath: "celebrateRequested")!.value = true }
                for _ in 0..<consumedFrames { _ = sm.advance(by: 1/60); lastState = sm.stateChanges().last ?? lastState }
                vm.numberProperty(fromPath: "mode")!.value = finalMode
                vm.booleanProperty(fromPath: "isTyping")!.value = false
                vm.booleanProperty(fromPath: "celebrateRequested")!.value = false
                var drainTrace: [[String]] = []
                for dt: Double in [0, 2, 0.1, 0.1] {
                    _ = sm.advance(by: dt)
                    let changes = sm.stateChanges()
                    drainTrace.append(changes)
                    lastState = changes.last ?? lastState
                }
                var resumed: [String] = []
                for _ in 0..<240 {
                    _ = sm.advance(by: 1/60)
                    resumed += sm.stateChanges()
                }
                let passed = !lastState.contains("Celebrate") && lastState != "Expression_Wink" && !resumed.contains { $0.contains("Celebrate") || $0 == "Expression_Wink" }
                    && vm.booleanProperty(fromPath: "celebrateRequested")!.value == false
                    && vm.numberProperty(fromPath: "mode")!.value == finalMode
                    && sm.viewModelInstance === vm
                results.append(["kind":kind,"initialMode":initialMode,"consumedFrames":consumedFrames,
                                "finalMode":finalMode,"drainTrace":drainTrace,"stateAtPauseEnd":lastState,"resumedStates":resumed,"passed":passed])
            }
        }
    }
}
let failed = results.filter { $0["passed"] as? Bool == false }
let evidence: [String: Any] = ["caseCount":results.count,"failedCount":failed.count,"drainSteps":[0,2,0.1,0.1],
    "api":"6.25.1 inspection API using the same core state machine; App uses only New Runtime advance(by:)",
    "cases":results]
try JSONSerialization.data(withJSONObject:evidence, options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("\(results.count-failed.count)/\(results.count) pause/resume checks passed")
for item in failed.prefix(5) { print(item) }
if !failed.isEmpty { exit(1) }
