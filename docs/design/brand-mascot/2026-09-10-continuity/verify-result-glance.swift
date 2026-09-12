import Foundation
import RiveRuntime

// A deterministic state-machine probe. The separate Metal previews are visual
// evidence, not a substitute for these trigger and interruption assertions.
let file = try RiveFile(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])), loadCdn: false)
let model = file.viewModelNamed("TogetherSphereModel")!
var results: [[String: Any]] = []
// Inspection state machines reference their owning artboard. Keep each board
// alive until all fixture assertions have completed.
var boards: [RiveArtboard] = []

func fixture(_ mode: Float) throws -> (RiveStateMachineInstance, RiveDataBindingViewModel.Instance) {
    let board = try file.artboard(fromName: "TogetherSphere")
    boards.append(board)
    let machine = try board.stateMachine(fromName: "Mascot")
    let vm = model.createDefaultInstance()!
    board.bind(viewModelInstance: vm)
    machine.bind(viewModelInstance: vm)
    vm.numberProperty(fromPath: "mode")!.value = mode
    for _ in 0..<120 { _ = machine.advance(by: 1.0/60) }
    return (machine, vm)
}
func advance(_ machine: RiveStateMachineInstance, frames: Int) -> [String] {
    var states: [String] = []
    for _ in 0..<frames {
        _ = machine.advance(by: 1.0/60)
        states += machine.stateChanges().filter { $0.hasPrefix("Action_") }
    }
    return states
}
for mode: Float in [0,1,2,3,4] {
    let (machine, vm) = try fixture(mode)
    vm.triggerProperty(fromPath: "noticeResult")!.trigger()
    let trace = advance(machine, frames: 90)
    let allowed = mode == 0 || mode == 2
    let passed = allowed ? trace.contains("Action_NoticeResult") && trace.last == "Action_Rest"
                         : !trace.contains("Action_NoticeResult")
    vm.numberProperty(fromPath: "mode")!.value = 0
    let after = advance(machine, frames: 90)
    results.append(["case":"admission", "mode":mode, "trace":trace,
                    "afterModeIdle":after, "passed":passed && !after.contains("Action_NoticeResult")])
}
for initial: Float in [0,2] {
    for consumed in [0,1,6,18,34,53] {
        for target: Float in [1,3,4] {
            let (machine, vm) = try fixture(initial)
            vm.triggerProperty(fromPath: "noticeResult")!.trigger()
            _ = advance(machine, frames: consumed)
            vm.numberProperty(fromPath: "mode")!.value = target
            let trace = advance(machine, frames: 12)
            let resumed = advance(machine, frames: 90)
            let passed = (consumed == 0 || trace.contains("Action_Rest"))
                         && !resumed.contains("Action_NoticeResult")
                         && vm.numberProperty(fromPath: "mode")!.value == target
            results.append(["case":"interruption", "initialMode":initial,
                            "consumedFrames":consumed, "targetMode":target,
                            "trace":trace, "after":resumed, "passed":passed])
        }
        let (machine, vm) = try fixture(initial)
        vm.triggerProperty(fromPath: "noticeResult")!.trigger()
        _ = advance(machine, frames: consumed)
        var drained: [String] = []
        for step: Double in [0,2,0.1,0.1] {
            _ = machine.advance(by: step)
            drained += machine.stateChanges().filter { $0.hasPrefix("Action_") }
        }
        let resumed = advance(machine, frames: 120)
        results.append(["case":"pause-drain", "mode":initial, "consumedFrames":consumed,
                        "trace":drained, "after":resumed,
                        "passed":drained.last == "Action_Rest" && !resumed.contains("Action_NoticeResult")])
    }
}
let failed = results.filter { $0["passed"] as? Bool == false }
let output: [String: Any] = ["runtime":"Rive Apple Runtime 6.25.1 inspection API",
    "scope":"trigger admission, editing/OCR interruption, pause drainage; no performance claim",
    "caseCount":results.count, "failedCount":failed.count, "cases":results]
try JSONSerialization.data(withJSONObject: output, options:[.prettyPrinted,.sortedKeys])
    .write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("\(results.count-failed.count)/\(results.count) noticeResult checks passed")
for item in failed.prefix(5) { print(item) }
if !failed.isEmpty { exit(1) }
