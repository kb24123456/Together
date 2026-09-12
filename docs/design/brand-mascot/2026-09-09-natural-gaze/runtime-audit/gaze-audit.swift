import Foundation
import AppKit
import RiveRuntime
import CryptoKit

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let file = try RiveFile(data: data, loadCdn: false)
let model = file.viewModelNamed("TogetherSphereModel")!
let mainGazes = ["Idle", "Idle_QuietMedium", "Idle_GazeUp", "Idle_GazeDown", "Idle_GazeUpRight"]
let gazes = mainGazes + ["Idle_Look"]
func setup() throws -> (RiveArtboard, RiveStateMachineInstance, RiveDataBindingViewModel.Instance) {
    let board = try file.artboard(fromName: "TogetherSphere")
    let machine = try board.stateMachine(fromName: "Mascot")
    let vm = model.createDefaultInstance()!
    machine.bind(viewModelInstance: vm)
    vm.numberProperty(fromPath: "mode")!.value = 0
    return (board, machine, vm)
}
var firstCounts = Dictionary(uniqueKeysWithValues: mainGazes.map { ($0, 0) })
for _ in 0..<100 {
    let (board, sm, vm) = try setup()
    var states: [String] = []
    for _ in 0..<12 { _ = sm.advance(by: 1/60); states += sm.stateChanges() }
    if let first = states.first(where: mainGazes.contains) { firstCounts[first, default: 0] += 1 }
    withExtendedLifetime((board,vm)) {}
}
var sequence: [String] = []
let (sequenceBoard, sequenceMachine, sequenceVM) = try setup()
for _ in 0..<12000 {
    _ = sequenceMachine.advance(by: 1/20)
    sequence += sequenceMachine.stateChanges().filter { gazes.contains($0) || $0 == "Idle_QuietShort" }
}
withExtendedLifetime((sequenceBoard,sequenceVM)) {}
let noDirectRepeat = zip(sequence, sequence.dropFirst()).allSatisfy { $0 != $1 }
let fullCoverage = Set(gazes).isSubset(of: Set(sequence))
var cases: [[String:Any]] = []
for direction in gazes {
    for event in ["edit", "overdue", "process", "doze", "acknowledge", "celebrate", "celebrateOverdue"] {
        let (board, sm, vm) = try setup()
        var found = false
        for _ in 0..<18000 {
            _ = sm.advance(by: 1/30)
            if sm.stateChanges().contains(direction) { found = true; break }
        }
        // Interrupt a visible glance instead of only testing the initial selector.
        for _ in 0..<20 { _ = sm.advance(by: 1/60); _ = sm.stateChanges() }
        let expected: String
        switch event {
        case "edit": vm.numberProperty(fromPath:"mode")!.value = 1; vm.booleanProperty(fromPath:"isTyping")!.value = true; expected = "Writing"
        case "overdue": vm.numberProperty(fromPath:"mode")!.value = 2; expected = "Concerned"
        case "process": vm.numberProperty(fromPath:"mode")!.value = 3; expected = "Thinking"
        case "doze": vm.numberProperty(fromPath:"mode")!.value = 4; expected = "Doze"
        case "acknowledge": vm.triggerProperty(fromPath:"acknowledge")!.trigger(); expected = "Expression_Wink"
        default:
            if event == "celebrateOverdue" { vm.numberProperty(fromPath:"mode")!.value = 2 }
            vm.booleanProperty(fromPath:"celebrateRequested")!.value = true; expected = "Celebrate"
        }
        var observed: [String] = []
        for _ in 0..<180 { _ = sm.advance(by: 1/60); observed += sm.stateChanges() }
        let passed = found && observed.contains(expected)
        cases.append(["from":direction,"event":event,"sourceReached":found,"expected":expected,"observed":observed,"passed":passed])
        withExtendedLifetime((board,vm)) {}
    }
}
let passed = firstCounts.values.reduce(0,+) == 100 && firstCounts.values.allSatisfy { $0 > 0 }
    && noDirectRepeat && fullCoverage && cases.allSatisfy { $0["passed"] as? Bool == true }
let evidence: [String:Any] = [
    "passed":passed, "runtimeVersion":"6.25.1", "api":"Official inspection API, no rendered view",
    "assetSHA256":SHA256.hash(data:data).map { String(format:"%02x", $0) }.joined(),
    "initialChoiceSamples":100, "firstDirectionCounts":firstCounts,
    "sequenceSeconds":600, "sequence":sequence, "sixDirectionCoverage":fullCoverage,
    "noDirectRepeatedClip":noDirectRepeat, "interruptions":cases,
    "limits":["Statistical samples demonstrate varied native choices; not a mathematical probability guarantee.","No iOS device rendering, layout or energy validation."]
]
try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("Initial directions: \(firstCounts). Six-direction coverage: \(fullCoverage). Interruptions: \(cases.filter { $0["passed"] as? Bool == true }.count)/\(cases.count).")
if !passed { exit(1) }
