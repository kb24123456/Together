import Foundation

private struct PreviewRandom: RandomNumberGenerator {
    var state: UInt64 = 0xD1CE_BA11
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

@main struct IdleStory {
    static func main() throws {
        var behavior = MascotBehaviorState()
        var random = PreviewRandom()
        behavior.updateContext(MascotContext(isVisible: true), at: 0)
        behavior.setPlaybackAllowed(true, at: 0)
        let fps = 30
        let frames = 2400
        var previous: MascotPresentation?
        var events: [[String: Any]] = []
        var pngFrames = [0, 450, 900, 1800, 2399]
        // Sampling the production policy on a virtual clock; the App wakes only at
        // nextDeadline. Repeated samples do not consume randomness or publish frames.
        for frame in 0..<frames {
            let now = Double(frame) / Double(fps)
            behavior.advanceIdleExpression(at: now, using: &random)
            let next = behavior.presentation(at: now)
            precondition(next.mode == 0 && next.staticPose == .idle)
            if next != previous {
                events.append(["frame": frame, "numbers": ["mode": next.mode, "expression": next.expression]])
                if next.expression != 0 { pngFrames.append(min(frames - 1, frame + 18)) }
            }
            previous = next
        }
        let story: [String: Any] = [
            "name": "80 seconds of App idle policy with a fixed preview seed",
            "fps": fps, "frames": frames, "width": 168, "height": 168,
            "pngEvery": 0, "pngFrames": pngFrames, "video": true,
            "events": events
        ]
        let data = try JSONSerialization.data(withJSONObject: story, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
