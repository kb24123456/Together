import SwiftUI
import RiveRuntime
#if DEBUG
import OSLog
#endif

extension EnvironmentValues {
    @Entry var isMascotSurfaceUncovered = true
}

struct BrandMascotView: View {
    let session: MascotPlaybackSession
    let surface: MascotSurface
    let diameter: CGFloat

    var body: some View {
        MascotAnchor(session: session, surface: surface)
            .frame(width: diameter * 512 / 368, height: diameter * 512 / 368)
            .offset(y: diameter * 16 / 368)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MascotAnchor: UIViewRepresentable {
    let session: MascotPlaybackSession
    let surface: MascotSurface

    func makeUIView(context: Context) -> MascotAnchorView {
        let view = MascotAnchorView(surface: surface)
        view.attach(to: session)
        return view
    }

    func updateUIView(_ view: MascotAnchorView, context: Context) {
        session.anchorChanged(view)
    }

    static func dismantleUIView(_ view: MascotAnchorView, coordinator: ()) {
        view.detach()
    }
}

/// Native toolbars own placement and accessibility; this anchor never draws a second ball.
final class MascotAnchorView: UIView {
    let registrationID = UUID()
    let surface: MascotSurface
    private weak var session: MascotPlaybackSession?

    init(surface: MascotSurface) {
        self.surface = surface
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        session?.anchorChanged(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        session?.anchorChanged(self)
    }

    func attach(to session: MascotPlaybackSession) {
        guard self.session !== session else { return }
        detach()
        self.session = session
        session.register(self)
    }

    func detach() {
        session?.unregister(self)
        session = nil
    }
}

/// Energy and accessibility policy belongs to the root, not to either toolbar's lifetime.
struct MascotPlaybackEnvironment: ViewModifier {
    let session: MascotPlaybackSession
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isMascotSurfaceUncovered) private var isSurfaceUncovered
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var thermalState = ProcessInfo.processInfo.thermalState

    private var playbackAllowed: Bool {
        scenePhase == .active && isSurfaceUncovered && !reduceMotion && !isLowPower
            && thermalState != .serious && thermalState != .critical
    }

    private var surfaceVisible: Bool { scenePhase == .active && isSurfaceUncovered }

    func body(content: Content) -> some View {
        content
            .onAppear {
                updateEnergyState()
                updatePlayback()
            }
            .onChange(of: playbackAllowed) { _, _ in updatePlayback() }
            .onChange(of: surfaceVisible) { _, _ in updatePlayback() }
            .onChange(of: colorScheme) { _, _ in updatePlayback() }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                updateEnergyState()
            }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
                updateEnergyState()
            }
    }

    private func updatePlayback() {
        #if DEBUG
        Logger(subsystem: "com.pigdog.Together", category: "Motion").notice(
            "[Motion] mascot policy allowed=\(playbackAllowed) visible=\(surfaceVisible) active=\(scenePhase == .active) uncovered=\(isSurfaceUncovered) reduceMotion=\(reduceMotion) lowPower=\(isLowPower) thermal=\(thermalState.rawValue) liveThermal=\(ProcessInfo.processInfo.thermalState.rawValue)"
        )
        #endif
        session.setEnvironment(
            animationAllowed: playbackAllowed, isDark: colorScheme == .dark, surfaceVisible: surfaceVisible
        )
    }

    private func updateEnergyState() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
    }
}
