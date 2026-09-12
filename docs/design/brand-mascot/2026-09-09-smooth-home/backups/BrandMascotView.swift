import SwiftUI
import RiveRuntime

extension EnvironmentValues {
    /// The containing surface also gates playback when covered by the app lock.
    @Entry var isMascotSurfaceUncovered = true
}

struct BrandMascotView: View {
    let controller: MascotController
    let diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isMascotSurfaceUncovered) private var isSurfaceUncovered
    @State private var runtime = MascotRuntime()
    @State private var hasAppeared = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    private var playbackAllowed: Bool {
        hasAppeared && scenePhase == .active && isSurfaceUncovered && !reduceMotion
            && !isLowPower && thermalState != .serious && thermalState != .critical
    }

    private var isAnimating: Bool {
        playbackAllowed && controller.isPlaying && runtime.rive != nil
    }

    var body: some View {
        ZStack {
            if let rive = runtime.rive {
                RiveUIViewRepresentable(rive: rive)
                    .frameRate(.fps(30))
                    .paused(!isAnimating)
                    .opacity(isAnimating ? 1 : 0)
            }
            if !isAnimating {
                SwiftUI.Image(staticAssetName)
                    .resizable()
                    .scaledToFit()
            }
        }
        // Reserve the full artboard for the hands and pen; callers own the button hit area.
        .frame(width: diameter * 512 / 368, height: diameter * 512 / 368)
        .offset(y: diameter * 16 / 368)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: playbackAllowed && controller.isPlaying) {
            guard playbackAllowed && controller.isPlaying else { return }
            await runtime.load(controller: controller, isDark: colorScheme == .dark)
        }
        .onAppear {
            hasAppeared = true
            updateEnergyState()
            updatePlayback()
        }
        .onDisappear {
            hasAppeared = false
            controller.setPlaybackAllowed(false)
            synchronize()
            runtime.suspend()
        }
        .onChange(of: playbackAllowed) { _, _ in updatePlayback() }
        .onChange(of: controller.mode) { _, _ in synchronize() }
        .onChange(of: controller.expression) { _, _ in synchronize() }
        .onChange(of: controller.isTyping) { _, _ in synchronize() }
        .onChange(of: controller.isPlaying) { _, playing in
            if !playing {
                synchronize()
                runtime.suspend()
            }
        }
        .onChange(of: colorScheme) { _, _ in synchronize() }
        .onChange(of: controller.feedback?.id) { _, _ in
            synchronize()
            runtime.consumeFeedback(controller.feedback, canPlay: isAnimating)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            updateEnergyState()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            updateEnergyState()
        }
    }

    private var staticAssetName: String {
        switch controller.staticPose {
        case .idle: "MascotIdle"
        case .holding: "MascotHolding"
        case .concerned: "MascotConcerned"
        case .thinking: "MascotThinking"
        }
    }

    private func synchronize() {
        runtime.synchronize(controller: controller, isDark: colorScheme == .dark)
    }

    private func updatePlayback() {
        controller.setPlaybackAllowed(playbackAllowed)
        synchronize()
        if !playbackAllowed {
            runtime.suspend()
        }
    }

    private func updateEnergyState() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }
}
