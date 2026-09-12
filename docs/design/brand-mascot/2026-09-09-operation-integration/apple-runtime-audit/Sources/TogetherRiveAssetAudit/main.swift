import Foundation
import AppKit
import RiveRuntime
import CryptoKit

struct AuditError: Error { let message: String }
func require<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw AuditError(message: message) }
    return value
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    fatalError("Usage: TogetherRiveAssetAudit asset.riv theme.json result.json")
}
var checks: [[String: Any]] = []
var evidence: [String: Any] = [
    "runtimeVersion": "6.25.1",
    "api": "Official legacy RiveRuntime APIs bundled with 6.25.1",
    "platform": "macOS command line; no view, simulator, or App integration",
    "assetPath": arguments[1],
    "createdAt": ISO8601DateFormatter().string(from: Date())
]
func check(_ name: String, _ passed: Bool, details: Any? = nil) {
    var item: [String: Any] = ["name": name, "passed": passed]
    if let details { item["details"] = details }
    checks.append(item)
}
func color(_ hex: String) -> NSColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255,
                   green: CGFloat((n >> 8) & 255) / 255,
                   blue: CGFloat(n & 255) / 255,
                   alpha: CGFloat((n >> 24) & 255) / 255)
}
func hex(_ value: NSColor) -> String {
    let c = value.usingColorSpace(.sRGB)!
    let components = [c.alphaComponent, c.redComponent, c.greenComponent, c.blueComponent]
    let n = components.reduce(UInt32(0)) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
    return String(format: "#%08x", n)
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    evidence["assetBytes"] = data.count
    evidence["assetSHA256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    evidence["stateChangesSemantics"] = "Legacy RiveAnimationState.name returns the referenced animation name, not the editor state node name. Source: rive-ios 6.25.1 Source/Renderer/LayerState.mm lines 86-100."
    let file = try RiveFile(data: data, loadCdn: false)
    let artboardNames = file.artboardNames()
    evidence["artboards"] = artboardNames
    check("TogetherSphere artboard exists", artboardNames.contains("TogetherSphere"))
    let artboard = try file.artboard(fromName: "TogetherSphere")
    evidence["animations"] = artboard.animationNames()
    evidence["stateMachines"] = artboard.stateMachineNames()
    evidence["defaultStateMachine"] = artboard.defaultStateMachine()?.name() ?? "<none>"
    check("30 named timelines exported", artboard.animationNames().count == 30, details: artboard.animationNames().count)
    check("Mascot is default state machine", artboard.defaultStateMachine()?.name() == "Mascot")
    let model = try require(file.viewModelNamed("TogetherSphereModel"), "TogetherSphereModel missing")
    evidence["viewModelName"] = model.name
    evidence["instanceNames"] = model.instanceNames
    let properties = model.properties.map { ["name": $0.name, "type": String(describing: $0.type)] }
    evidence["properties"] = properties
    check("17 ViewModel properties exported", properties.count == 17, details: properties.count)
    let initial = try require(model.createDefaultInstance(), "Default instance missing")
    check("mode is number", initial.numberProperty(fromPath: "mode") != nil)
    check("isTyping is boolean", initial.booleanProperty(fromPath: "isTyping") != nil)
    check("celebrateRequested is boolean", initial.booleanProperty(fromPath: "celebrateRequested") != nil)
    check("acknowledge is trigger", initial.triggerProperty(fromPath: "acknowledge") != nil)

    func setup() throws -> (RiveArtboard, RiveStateMachineInstance, RiveDataBindingViewModel.Instance) {
        let board = try file.artboard(fromName: "TogetherSphere")
        let stateMachine = try board.stateMachine(fromName: "Mascot")
        let instance = try require(model.createDefaultInstance(), "Default instance missing")
        stateMachine.bind(viewModelInstance: instance)
        return (board, stateMachine, instance)
    }
    func advance(_ machine: RiveStateMachineInstance, frames: Int) -> [[String: Any]] {
        var trace: [[String: Any]] = []
        for frame in 0..<frames {
            _ = machine.advance(by: 1.0 / 60.0)
            let changes = machine.stateChanges()
            if !changes.isEmpty { trace.append(["frame": frame, "states": changes]) }
            machine.viewModelInstance?.updateListeners()
        }
        return trace
    }
    var traces: [[String: Any]] = []
    let cases: [(String, Float, Bool, [String])] = [
        ("idle", 0, false, ["Idle", "Idle_Rest", "Idle_Breathe", "Idle_Select"]),
        ("writing", 1, true, ["Writing"]),
        ("holding", 1, false, ["WritingHold"]),
        ("concerned", 2, false, ["Concerned"]),
        ("thinking", 3, false, ["Thinking"]),
        ("doze", 4, false, ["Doze"])
    ]
    for (label, mode, typing, expected) in cases {
        let (board, machine, instance) = try setup()
        instance.numberProperty(fromPath: "mode")!.value = mode
        instance.booleanProperty(fromPath: "isTyping")!.value = typing
        let trace = advance(machine, frames: 600)
        let states = trace.flatMap { $0["states"] as? [String] ?? [] }
        let passed = expected.contains(where: states.contains)
        check("mode: \(label)", passed, details: states)
        traces.append(["case": label, "mode": mode, "isTyping": typing, "fps": 60, "frames": 600, "trace": trace,
                       "boundInstanceSame": machine.viewModelInstance === instance, "artboard": board.name()])
    }
    evidence["modeTraces"] = traces

    let (feedbackBoard, feedbackMachine, feedbackInstance) = try setup()
    _ = advance(feedbackMachine, frames: 120)
    feedbackInstance.triggerProperty(fromPath: "acknowledge")!.trigger()
    let winkTrace = advance(feedbackMachine, frames: 180)
    let winkStates = winkTrace.flatMap { $0["states"] as? [String] ?? [] }
    check("acknowledge plays Expression_Wink", winkStates.contains("Expression_Wink"))
    check("acknowledge returns to Idle", winkStates.last == "Idle")
    feedbackInstance.booleanProperty(fromPath: "celebrateRequested")!.value = true
    let celebrateTrace = advance(feedbackMachine, frames: 300)
    let celebrationStates = celebrateTrace.flatMap { $0["states"] as? [String] ?? [] }
    check("celebrateRequested reaches celebration", celebrationStates.contains(where: { $0.contains("Celebrate") }))
    check("celebration request resets", feedbackInstance.booleanProperty(fromPath: "celebrateRequested")!.value == false)
    evidence["feedback"] = ["artboard": feedbackBoard.name(), "acknowledgeTrace": winkTrace, "celebrationTrace": celebrateTrace]

    let themeData = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
    let theme = try JSONSerialization.jsonObject(with: themeData) as! [String: Any]
    let groups = theme["groups"] as! [[String: Any]]
    check("12 semantic colors described", groups.count == 12)
    let (colorBoard, colorMachine, colorInstance) = try setup()
    colorInstance.numberProperty(fromPath: "mode")!.value = 1
    colorInstance.booleanProperty(fromPath: "isTyping")!.value = true
    _ = advance(colorMachine, frames: 60)
    var colorResults: [[String: Any]] = []
    for appearance in ["dark", "light"] {
        for group in groups {
            let name = group["name"] as! String
            let property = try require(colorInstance.colorProperty(fromPath: name), "Missing color \(name)")
            property.value = color(group[appearance] as! String)
        }
        _ = advance(colorMachine, frames: 1)
        for group in groups {
            let name = group["name"] as! String
            let expected = (group[appearance] as! String).lowercased()
            let actual = hex(colorInstance.colorProperty(fromPath: name)!.value)
            let passed = expected == actual
            check("\(appearance) color: \(name)", passed)
            colorResults.append(["appearance": appearance, "property": name, "expected": expected, "actual": actual, "passed": passed])
        }
        check("\(appearance) retains bound instance", colorMachine.viewModelInstance === colorInstance)
        check("\(appearance) preserves writing mode", colorInstance.numberProperty(fromPath: "mode")!.value == 1 && colorInstance.booleanProperty(fromPath: "isTyping")!.value)
    }
    evidence["colorReadWrite"] = colorResults
    evidence["colorArtboard"] = colorBoard.name()
    evidence["limits"] = ["No pixels rendered; property read/write does not independently verify visible bound fills.", "No App, iOS device, layout, or performance validation."]
} catch {
    evidence["error"] = String(describing: error)
    check("runtime audit completed", false, details: String(describing: error))
}
evidence["checks"] = checks
evidence["passed"] = !checks.isEmpty && checks.allSatisfy { $0["passed"] as? Bool == true }
let result = try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
try result.write(to: URL(fileURLWithPath: arguments[3]))
print(String(data: result, encoding: .utf8)!)
if evidence["passed"] as? Bool != true { exit(1) }
