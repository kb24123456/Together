import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(AppContext.self) private var appContext
    @State private var editorStageMounted = false
    @State private var editorStageVisible = false
    @State private var stagedItem: Item?
    @State private var stagedDraft: HomeEditorDraft?
    @State private var hasStableKeyboardReserve = false
    @State private var shouldRunKeyboardPrewarm = true

    var body: some View {
        @Bindable var router = appContext.router
        @Bindable var homeViewModel = appContext.homeViewModel

        TabView(selection: $router.selectedTab) {
            NavigationStack {
                HomeView(viewModel: appContext.homeViewModel)
            }
            .tabItem {
                Image(systemName: "house.fill")
            }
            .tag(AppTab.home)

            NavigationStack {
                DecisionsView(viewModel: appContext.decisionsViewModel)
            }
            .tabItem {
                Image(systemName: "checklist.checked")
            }
            .tag(AppTab.decisions)

            NavigationStack {
                AnniversariesView(viewModel: appContext.anniversariesViewModel)
            }
            .tabItem {
                Image(systemName: "calendar")
            }
            .tag(AppTab.anniversaries)

            NavigationStack {
                ProfileView(viewModel: appContext.profileViewModel)
            }
            .tabItem {
                Image(systemName: "person.crop.circle")
            }
            .tag(AppTab.profile)
        }
        .sheet(item: $router.activeComposer) { route in
            ComposerPlaceholderSheet(route: route)
        }
        .background(AppTheme.colors.background.ignoresSafeArea())
        .overlay {
            if editorStageMounted, let item = stageItemForRender(homeViewModel) {
                ItemEditorStageView(
                    item: item,
                    draft: stageDraftBinding(homeViewModel),
                    ownershipTokens: homeViewModel.ownershipTokens(for: item),
                    reservedKeyboardHeight: appContext.keyboardMetrics.reservedHeight,
                    isVisible: editorStageVisible,
                    onClose: { closeEditorStage(homeViewModel) },
                    onSave: { saveEditorStage(homeViewModel) }
                )
                .zIndex(20)
            }
        }
        .overlay {
            KeyboardPrewarmView(shouldPrewarm: $shouldRunKeyboardPrewarm)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task {
            shouldRunKeyboardPrewarm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }

            let screenHeight = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.screen.bounds.height }
                .first ?? frame.maxY
            let visibleHeight = max(0, screenHeight - frame.minY)
            appContext.keyboardMetrics.updateVisibleHeight(visibleHeight)
            if visibleHeight > 0 {
                hasStableKeyboardReserve = true
                shouldRunKeyboardPrewarm = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            appContext.keyboardMetrics.keyboardDidHide()
        }
        .onChange(of: homeViewModel.isEditorPresented) { _, isPresented in
            guard isPresented else {
                homeViewModel.isEditorStageVisible = false
                return
            }

            guard let item = homeViewModel.selectedEditorItem, let draft = homeViewModel.editorDraft else {
                return
            }

            stagedItem = item
            stagedDraft = draft
            editorStageMounted = true

            if hasStableKeyboardReserve, appContext.keyboardMetrics.cachedHeight > 0 {
                withAnimation(openStageAnimation) {
                    editorStageVisible = true
                    homeViewModel.isEditorStageVisible = true
                }
            } else {
                editorStageVisible = false
                homeViewModel.isEditorStageVisible = false
                shouldRunKeyboardPrewarm = true
            }
        }
        .onChange(of: appContext.keyboardMetrics.currentHeight) { _, currentHeight in
            guard currentHeight > 0 else { return }

            hasStableKeyboardReserve = true

            guard homeViewModel.isEditorPresented, editorStageMounted, editorStageVisible == false else {
                return
            }

            withAnimation(openStageAnimation) {
                editorStageVisible = true
                homeViewModel.isEditorStageVisible = true
            }
        }
    }

    private var openStageAnimation: Animation {
        .spring(response: 0.96, dampingFraction: 0.86, blendDuration: 0.22)
    }

    private var closeStageAnimation: Animation {
        .spring(response: 0.84, dampingFraction: 0.9, blendDuration: 0.18)
    }

    private func stageItemForRender(_ homeViewModel: HomeViewModel) -> Item? {
        homeViewModel.selectedEditorItem ?? stagedItem
    }

    private func stageDraftBinding(_ homeViewModel: HomeViewModel) -> Binding<HomeEditorDraft> {
        Binding(
            get: {
                homeViewModel.editorDraft ?? stagedDraft ?? HomeEditorDraft(
                    itemID: UUID(),
                    title: "",
                    notes: "",
                    dueAt: Date(),
                    remindAt: nil,
                    locationText: "",
                    executionRole: .initiator,
                    priority: .normal,
                    isPinned: false
                )
            },
            set: { newValue in
                stagedDraft = newValue
                homeViewModel.editorDraft = newValue
            }
        )
    }

    private func closeEditorStage(_ homeViewModel: HomeViewModel) {
        guard editorStageMounted else { return }

        homeViewModel.beginEditorDismissal()
        withAnimation(closeStageAnimation) {
            editorStageVisible = false
        }
        homeViewModel.isEditorStageVisible = false

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            homeViewModel.finalizeEditorDismissal()
            editorStageMounted = false
            stagedItem = nil
            stagedDraft = nil
        }
    }

    private func saveEditorStage(_ homeViewModel: HomeViewModel) {
        Task {
            let didSave = await homeViewModel.applyDraft()
            guard didSave else { return }
            await MainActor.run {
                closeEditorStage(homeViewModel)
            }
        }
    }
}

private struct KeyboardPrewarmView: UIViewRepresentable {
    @Binding var shouldPrewarm: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let hostView = UIView(frame: .zero)
        hostView.isUserInteractionEnabled = false

        let textField = context.coordinator.textField
        if textField.superview == nil {
            hostView.addSubview(textField)
        }

        return hostView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.prewarmIfNeeded(in: uiView, shouldPrewarm: shouldPrewarm) {
            shouldPrewarm = false
        }
    }

    final class Coordinator {
        private var isPrewarming = false

        let textField: UITextField = {
            let field = UITextField(frame: CGRect(x: -1200, y: -1200, width: 1, height: 1))
            field.alpha = 0.01
            field.tintColor = .clear
            field.textColor = .clear
            field.backgroundColor = .clear
            field.autocorrectionType = .no
            field.spellCheckingType = .no
            field.inputAssistantItem.leadingBarButtonGroups = []
            field.inputAssistantItem.trailingBarButtonGroups = []
            return field
        }()

        func prewarmIfNeeded(in hostView: UIView, shouldPrewarm: Bool, onFinished: @escaping () -> Void) {
            guard shouldPrewarm, !isPrewarming, hostView.window != nil else { return }

            isPrewarming = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self else { return }
                self.textField.becomeFirstResponder()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                    self?.textField.resignFirstResponder()
                    self?.isPrewarming = false
                    onFinished()
                }
            }
        }
    }
}
