import SwiftUI

struct ItemEditorStageView: View {
    let item: Item
    @Binding var draft: HomeEditorDraft
    let ownershipTokens: [HomeAvatarToken]
    let reservedKeyboardHeight: CGFloat
    let isVisible: Bool
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeTop = max(geometry.safeAreaInsets.top, windowSafeAreaTopInset)
            let effectiveReserve = max(0, reservedKeyboardHeight)
            let stageHeight = max(geometry.size.height - safeTop - effectiveReserve, 320)

            ZStack(alignment: .top) {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isVisible {
                            onClose()
                        }
                    }

                VStack(spacing: 0) {
                    HomeItemEditorView(
                        item: item,
                        draft: $draft,
                        ownershipTokens: ownershipTokens,
                        isStageVisible: isVisible,
                        onClose: onClose,
                        onSave: onSave
                    )
                    .frame(maxWidth: min(geometry.size.width - (AppTheme.spacing.md * 2), 560))
                    .frame(height: stageHeight, alignment: .top)
                    .padding(.horizontal, AppTheme.spacing.md)
                    .padding(.top, safeTop)
                    .opacity(isVisible ? 1 : 0)
                    .scaleEffect(isVisible ? 1 : 0.968, anchor: .top)
                    .offset(y: isVisible ? 0 : -30)
                    .allowsHitTesting(isVisible)

                    Spacer(minLength: effectiveReserve)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .ignoresSafeArea()
        .animation(.spring(response: 0.96, dampingFraction: 0.86, blendDuration: 0.22), value: isVisible)
        .animation(.spring(response: 0.8, dampingFraction: 0.9, blendDuration: 0.18), value: reservedKeyboardHeight)
    }

    private var windowSafeAreaTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
            .first ?? 0
    }
}
