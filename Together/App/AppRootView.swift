import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @State private var quickCaptureInputBridge = QuickCaptureInputBridge()
    @State private var isQuickCapturePresented = false
    @State private var quickCaptureText = ""
    @State private var isSubmittingQuickCapture = false
    @State private var isQuickCaptureFocused = false
    @State private var quickCaptureDebugMessage: String?
    @State private var quickCaptureHasVisibleText = false
    @State private var lastKeyboardOverlap: CGFloat = 0
    @State private var quickCaptureSpeechRecognizer = QuickCaptureSpeechRecognizer()
    @StateObject private var keyboardObserver = TaskEditorKeyboardObserver()

    var body: some View {
        @Bindable var router = appContext.router

        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                NavigationStack {
                    HomeView(
                        viewModel: appContext.homeViewModel,
                        isProjectLayerPresented: false
                    )
                }
                .blur(radius: isQuickCapturePresented ? 8 : 0)
                .allowsHitTesting(!isQuickCapturePresented)
                .animation(.easeOut(duration: 0.2), value: isQuickCapturePresented)

                if isQuickCapturePresented {
                    quickCaptureBackdrop
                        .transition(.opacity)
                }

                overlayChrome(bottomInset: proxy.safeAreaInsets.bottom, router: router)
            }
            .background(
                AppTheme.colors.homeBackground.ignoresSafeArea()
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .fullScreenCover(isPresented: $router.isProfilePresented) {
            NavigationStack {
                ProfileView(viewModel: appContext.profileViewModel)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("关闭") {
                                router.isProfilePresented = false
                            }
                        }
                }
            }
        }
        .sheet(item: $router.activeComposer, onDismiss: {
            router.pendingComposerTitle = nil
        }) { route in
            ComposerPlaceholderSheet(
                route: route,
                appContext: appContext,
                initialTitle: router.pendingComposerTitle
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(40)
            .presentationBackground(AppTheme.colors.surface)
            .presentationBackgroundInteraction(.enabled)
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled(false)
            .modifier(ComposerPresentationSizingModifier())
        }
        .environment(\.symbolVariants, .none)
        .font(AppTheme.typography.body)
        .tint(AppTheme.colors.title)
        .onChange(of: quickCaptureSpeechRecognizer.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            quickCaptureText = newValue
        }
        .onChange(of: quickCaptureText) { _, newValue in
            guard newValue != quickCaptureSpeechRecognizer.transcript else { return }
            quickCaptureSpeechRecognizer.syncDraftText(newValue)
            if quickCaptureSpeechRecognizer.isListening {
                quickCaptureSpeechRecognizer.stopListening()
            }
        }
        .onChange(of: keyboardObserver.overlap) { _, newValue in
            if newValue > 0 {
                lastKeyboardOverlap = newValue
            }
        }
        .onChange(of: isQuickCapturePresented) { _, isPresented in
            if !isPresented {
                quickCaptureSpeechRecognizer.stopListening()
                quickCaptureSpeechRecognizer.clearError()
            } else {
                quickCaptureText = ""
                quickCaptureSpeechRecognizer.resetDraft()
            }
        }
        .alert(
            "语音输入不可用",
            isPresented: Binding(
                get: { quickCaptureSpeechRecognizer.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        quickCaptureSpeechRecognizer.clearError()
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                quickCaptureSpeechRecognizer.clearError()
            }
        } message: {
            Text(quickCaptureSpeechRecognizer.errorMessage ?? "")
        }
        .alert(
            "快速捕捉提交诊断",
            isPresented: Binding(
                get: { quickCaptureDebugMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        quickCaptureDebugMessage = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {
                quickCaptureDebugMessage = nil
            }
        } message: {
            Text(quickCaptureDebugMessage ?? "")
        }
    }

    @ViewBuilder
    private func overlayChrome(bottomInset: CGFloat, router: AppRouter) -> some View {
        let collapsedDockBottom = max(4, bottomInset - 28)
        let pinnedKeyboardOverlap =
            keyboardObserver.overlap > 0
            ? keyboardObserver.overlap
            : ((quickCaptureSpeechRecognizer.state == .authorizing || quickCaptureSpeechRecognizer.isListening) ? lastKeyboardOverlap : 0)
        let captureBottom = pinnedKeyboardOverlap > 0 ? pinnedKeyboardOverlap + 8 : bottomInset + 8

        ZStack(alignment: .bottom) {
            if let debugMessage = quickCaptureDebugMessage, isQuickCapturePresented {
                quickCaptureDebugPanel(debugMessage)
                    .padding(.horizontal, AppTheme.spacing.xl)
                    .padding(.bottom, captureBottom + 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }

            if !isQuickCapturePresented {
                HomeDockBar(
                    isQuickCapturePresented: false,
                    onProfileTapped: {
                        dismissQuickCapture()
                        router.isProfilePresented = true
                    },
                    onComposeTapped: {
                        dismissQuickCapture()
                        router.pendingComposerTitle = nil
                        router.activeComposer = .newTask
                    },
                    onQuickCaptureTapped: {
                        toggleQuickCapture()
                    }
                )
                .padding(.bottom, collapsedDockBottom)
                .transition(
                    .move(edge: .bottom)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.96, anchor: .bottom))
                )
            }

            if isQuickCapturePresented {
                quickCaptureBar
                    .padding(.bottom, captureBottom)
                    .transition(
                        .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isQuickCapturePresented)
        .animation(.easeOut(duration: 0.2), value: quickCaptureDebugMessage)
        .allowsHitTesting(true)
    }

    private func quickCaptureDebugPanel(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.bubble")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Text("快速捕捉提交诊断")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
                Spacer(minLength: 0)
                Button {
                    quickCaptureDebugMessage = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(AppTheme.typography.sized(12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            Text(message)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(AppTheme.colors.body.opacity(0.84))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.96))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.colors.separator.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: AppTheme.colors.shadow.opacity(0.16), radius: 16, y: 8)
    }

    private var quickCaptureBackdrop: some View {
        ZStack {
            NativeBackdropBlur(style: .systemUltraThinMaterial)
                .opacity(0.78)
                .ignoresSafeArea()

            Color.black
                .opacity(0.02)
                .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissQuickCapture()
        }
    }

    private var quickCaptureBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.9))
                    .frame(width: 22, height: 22)

                ZStack(alignment: .leading) {
                    if quickCaptureText.isEmpty {
                        Text("快速记下一件事")
                            .font(AppTheme.typography.sized(17, weight: .regular))
                            .foregroundStyle(AppTheme.colors.body.opacity(0.35))
                            .allowsHitTesting(false)
                    }

                    NativeQuickCaptureTextEditor(
                        bridge: quickCaptureInputBridge,
                        text: $quickCaptureText,
                        isFocused: $isQuickCaptureFocused,
                        isSubmitting: isSubmittingQuickCapture,
                        onContentPresenceChanged: { hasContent in
                            quickCaptureHasVisibleText = hasContent
                        },
                        onSubmit: { finalText in
                            submitQuickCapture(finalText)
                        },
                        onDebug: { message in
                            quickCaptureDebugMessage = message
                        }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if quickCaptureSpeechRecognizer.isListening || quickCaptureSpeechRecognizer.state == .authorizing {
                    VoiceActivityIndicator(
                        level: quickCaptureSpeechRecognizer.audioLevel,
                        isAuthorizing: quickCaptureSpeechRecognizer.state == .authorizing,
                        isVoiceDetected: quickCaptureSpeechRecognizer.isVoiceDetected
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }

                Button {
                    toggleSpeechInput()
                } label: {
                    Image(systemName: quickCaptureSpeechRecognizer.isListening ? "mic.fill" : "mic")
                        .font(AppTheme.typography.sized(18, weight: .semibold))
                        .foregroundStyle(
                            quickCaptureSpeechRecognizer.isListening
                            ? AppTheme.colors.coral
                            : AppTheme.colors.body.opacity(0.9)
                        )
                        .frame(width: 52, height: 52)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(isSubmittingQuickCapture)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .frame(height: 52)
            .modifier(QuickCaptureFieldGlassModifier())

            ZStack {
                NativeQuickCaptureSendButton(
                    bridge: quickCaptureInputBridge,
                    isEnabled: !isSubmittingQuickCapture
                )
                .frame(width: 50, height: 50)

                Image(systemName: "arrow.up")
                    .font(AppTheme.typography.sized(18, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.9))
                    .frame(width: 50, height: 50)
                    .allowsHitTesting(false)
            }
            .modifier(QuickCaptureSendGlassModifier())
            .opacity(quickCaptureHasVisibleText ? 1 : 0.42)
        }
        .padding(.horizontal, AppTheme.spacing.xl)
    }

    private func toggleQuickCapture() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            isQuickCapturePresented.toggle()
        }

        if isQuickCapturePresented {
            quickCaptureText = ""
            quickCaptureHasVisibleText = false
            quickCaptureSpeechRecognizer.resetDraft()
            DispatchQueue.main.async {
                isQuickCaptureFocused = true
            }
        } else {
            isQuickCaptureFocused = false
        }
    }

    private func dismissQuickCapture() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            isQuickCapturePresented = false
        }
        quickCaptureSpeechRecognizer.stopListening()
        quickCaptureSpeechRecognizer.resetDraft()
        isQuickCaptureFocused = false
        quickCaptureDebugMessage = nil
        quickCaptureText = ""
        quickCaptureHasVisibleText = false
    }

    private func submitQuickCapture(_ rawTitle: String? = nil) {
        let trimmedTitle = (rawTitle ?? quickCaptureText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !isSubmittingQuickCapture else {
            quickCaptureDebugMessage = quickCaptureSubmissionSnapshot(
                reason: "提交前被拦截",
                chosenTitle: trimmedTitle
            )
            return
        }

        isSubmittingQuickCapture = true
        HomeInteractionFeedback.selection()
        isQuickCaptureFocused = false

        Task {
            let didSave = await appContext.homeViewModel.createQuickCaptureTask(title: trimmedTitle)
            await MainActor.run {
                isSubmittingQuickCapture = false
                guard didSave else {
                    quickCaptureDebugMessage = quickCaptureSubmissionSnapshot(
                        reason: "createQuickCaptureTask 返回 false",
                        chosenTitle: trimmedTitle
                    )
                    return
                }
                quickCaptureDebugMessage = nil
                quickCaptureText = ""
                quickCaptureHasVisibleText = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    isQuickCapturePresented = false
                }
                quickCaptureSpeechRecognizer.stopListening()
                quickCaptureSpeechRecognizer.resetDraft()
                HomeInteractionFeedback.soft()
            }
        }
    }

    private func quickCaptureSubmissionSnapshot(reason: String, chosenTitle: String) -> String {
        let transcript = quickCaptureSpeechRecognizer.transcript

        return [
            "原因: \(reason)",
            "quickCaptureText: \(quickCaptureText)",
            "speechTranscript: \(transcript)",
            "chosenTitle: \(chosenTitle)"
        ].joined(separator: "\n")
    }

    private func toggleSpeechInput() {
        HomeInteractionFeedback.selection()
        if !quickCaptureSpeechRecognizer.isListening {
            quickCaptureSpeechRecognizer.beginAuthorization()
        }
        Task {
            await quickCaptureSpeechRecognizer.toggleListening(currentText: quickCaptureText)
            if quickCaptureSpeechRecognizer.isListening {
                isQuickCaptureFocused = false
            } else {
                isQuickCaptureFocused = true
            }
        }
    }
}

private struct VoiceActivityIndicator: View {
    let level: CGFloat
    let isAuthorizing: Bool
    let isVoiceDetected: Bool

    private let barBaseHeights: [CGFloat] = [5, 7.5, 11, 7.5, 5]
    private let barAmplitudeWeights: [CGFloat] = [0.16, 0.42, 1.0, 0.42, 0.16]
    private let phaseOffsets: [Double] = [0.15, 0.75, 1.25, 1.75, 2.35]

    var body: some View {
        let effectiveLevel = isAuthorizing ? 0 : level
        let showsDotState = isAuthorizing || !isVoiceDetected

        Group {
            if showsDotState {
                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(AppTheme.colors.body.opacity(0.75))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let voiceStrength = min(max(effectiveLevel, 0.72), 1)

                    HStack(alignment: .center, spacing: 2.5) {
                        ForEach(Array(barBaseHeights.enumerated()), id: \.offset) { index, baseHeight in
                            let ripple = (sin((time * 8.4) + phaseOffsets[index]) + 1) * 0.5
                            let animatedWeight = 0.25 + ripple * 0.75
                            let height = baseHeight + (voiceStrength * 22 * barAmplitudeWeights[index] * animatedWeight)

                            Capsule(style: .continuous)
                                .fill(AppTheme.colors.body.opacity(0.78))
                                .frame(width: 3, height: height)
                                .offset(y: index == 2 ? 0 : 0.5)
                        }
                    }
                }
            }
        }
        .frame(width: 28, height: 24)
        .accessibilityHidden(true)
    }
}

private struct NativeBackdropBlur: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

private final class QuickCaptureInputBridge {
    weak var coordinator: NativeQuickCaptureTextEditor.Coordinator?

    func submit() {
        coordinator?.submitFromExternalButton()
    }
}

private struct NativeQuickCaptureTextEditor: UIViewRepresentable {
    let bridge: QuickCaptureInputBridge
    @Binding var text: String
    @Binding var isFocused: Bool
    let isSubmitting: Bool
    let onContentPresenceChanged: (Bool) -> Void
    let onSubmit: (String) -> Void
    let onDebug: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, bridge: bridge)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.enablesReturnKeyAutomatically = true
        textView.returnKeyType = .send
        textView.tintColor = UIColor(AppTheme.colors.title)
        textView.font = AppTheme.typography.sizedUIFont(17, weight: .regular)
        textView.textColor = UIColor(AppTheme.colors.title)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 0, bottom: 12, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textView = textView
        bridge.coordinator = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onDebug = onDebug
        context.coordinator.onContentPresenceChanged = onContentPresenceChanged
        context.coordinator.textView = textView
        bridge.coordinator = context.coordinator

        if textView.text != text {
            textView.text = text
        }
        context.coordinator.updateContentPresence(using: textView)

        textView.isEditable = !isSubmitting
        textView.isSelectable = !isSubmitting
        textView.isUserInteractionEnabled = !isSubmitting

        let isFirstResponder = textView.isFirstResponder
        if isFocused && !isFirstResponder {
            DispatchQueue.main.async {
                textView.becomeFirstResponder()
            }
        } else if !isFocused && isFirstResponder {
            DispatchQueue.main.async {
                textView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        weak var bridge: QuickCaptureInputBridge?
        weak var textView: UITextView?
        var onSubmit: (String) -> Void = { _ in }
        var onDebug: (String) -> Void = { _ in }
        var onContentPresenceChanged: (Bool) -> Void = { _ in }

        init(text: Binding<String>, isFocused: Binding<Bool>, bridge: QuickCaptureInputBridge) {
            _text = text
            _isFocused = isFocused
            self.bridge = bridge
        }

        func submitFromExternalButton() {
            guard let textView else {
                onDebug("原因: UITextView 不存在\nsource: sendButton")
                return
            }
            submitCurrentText(from: textView, source: "sendButton")
        }

        func textViewDidChange(_ textView: UITextView) {
            text = currentDocumentText(from: textView)
            updateContentPresence(using: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let currentText = currentDocumentText(from: textView)
            if !currentText.isEmpty {
                text = currentText
            }
            updateContentPresence(using: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            text = currentDocumentText(from: textView)
            isFocused = false
            updateContentPresence(using: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            guard replacementText == "\n" else { return true }
            submitCurrentText(from: textView, source: "keyboardSend")
            return false
        }

        private func submitCurrentText(from textView: UITextView, source: String) {
            let finalText = resolvedSubmissionText(from: textView).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !finalText.isEmpty else {
                onDebug([
                    "原因: UIKit 提交拿到空文本",
                    "source: \(source)",
                    "textView.text: \(textView.text ?? "")",
                    "documentText: \(currentDocumentText(from: textView))",
                    "hasMarkedText: \(textView.markedTextRange != nil ? "yes" : "no")",
                    "bindingText: \(text)"
                ].joined(separator: "\n"))
                return
            }

            self.text = finalText
            isFocused = false
            textView.resignFirstResponder()
            onSubmit(finalText)
        }

        func updateContentPresence(using textView: UITextView) {
            let hasContent = !resolvedSubmissionText(from: textView)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            onContentPresenceChanged(hasContent)
        }

        private func resolvedSubmissionText(from textView: UITextView) -> String {
            let documentText = currentDocumentText(from: textView)
            let plainText = textView.text ?? ""
            let bindingText = text

            let candidates = [documentText, bindingText, plainText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return candidates.max(by: { $0.count < $1.count }) ?? ""
        }

        private func currentDocumentText(from textView: UITextView) -> String {
            if let markedRange = textView.markedTextRange,
               let markedText = textView.text(in: markedRange) {
                let prefixText: String
                if let prefixRange = textView.textRange(
                    from: textView.beginningOfDocument,
                    to: markedRange.start
                ) {
                    prefixText = textView.text(in: prefixRange) ?? ""
                } else {
                    prefixText = ""
                }

                let suffixText: String
                if let suffixRange = textView.textRange(
                    from: markedRange.end,
                    to: textView.endOfDocument
                ) {
                    suffixText = textView.text(in: suffixRange) ?? ""
                } else {
                    suffixText = ""
                }

                return prefixText + markedText + suffixText
            }

            if let range = textView.textRange(from: textView.beginningOfDocument, to: textView.endOfDocument),
               let fullText = textView.text(in: range) {
                return fullText
            }

            return textView.text ?? ""
        }
    }
}

private struct NativeQuickCaptureSendButton: UIViewRepresentable {
    let bridge: QuickCaptureInputBridge
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.backgroundColor = .clear
        button.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        let bridge: QuickCaptureInputBridge

        init(bridge: QuickCaptureInputBridge) {
            self.bridge = bridge
        }

        @objc
        func handleTap() {
            bridge.submit()
        }
    }
}

private struct QuickCaptureFieldGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 14, y: 6)
        }
    }
}

private struct QuickCaptureSendGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.62), lineWidth: 1)
                }
                .shadow(color: AppTheme.colors.shadow.opacity(0.08), radius: 14, y: 6)
        }
    }
}

private struct ComposerPresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.presentationSizing(.page)
        } else {
            content
        }
    }
}
