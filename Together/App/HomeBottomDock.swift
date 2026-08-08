import SwiftUI

struct HomeBottomDock: View {
    let showsAuxiliaryVisual: Bool
    let showsAddButtonVisual: Bool
    let isInteractive: Bool
    let onCamera: () -> Void
    let onPhotos: () -> Void
    let onAdd: () -> Void
    let onAddFrameChanged: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Button(action: onCamera) {
                    Label("相机", systemImage: "camera")
                }
                Button(action: onPhotos) {
                    Label("照片", systemImage: "photo.on.rectangle")
                }
            } label: {
                HomeDockButtonSurface(systemImage: "doc.text.viewfinder")
            }
            .disabled(isInteractive == false)
            .opacity(showsAuxiliaryVisual ? 1 : 0)
            .accessibilityIdentifier("together.dock.ocr")
            .accessibilityLabel("OCR 导入")
            .accessibilityHint("拍摄或选择纸面笔记生成草稿")
            .accessibilityHidden(showsAuxiliaryVisual == false)

            Spacer(minLength: 24)

            Button(action: onAdd) {
                HomeDockButtonSurface(systemImage: "plus")
            }
            .buttonStyle(.plain)
            .disabled(isInteractive == false)
            .opacity(showsAddButtonVisual ? 1 : 0)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                guard frame.width > 0, frame.height > 0 else { return }
                onAddFrameChanged(frame)
            }
            .accessibilityIdentifier("together.dock.add")
            .accessibilityLabel("新建")
            .accessibilityHint("在当前视图下新建一项")
            .accessibilityHidden(showsAddButtonVisual == false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.2, extraBounce: 0),
            value: showsAuxiliaryVisual
        )
        .animation(nil, value: showsAddButtonVisual)
    }
}

private struct HomeDockButtonSurface: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.colors.title)
            .frame(width: 52, height: 52)
            .background {
                HomeDockMaterialSurface()
            }
            .contentShape(Circle())
    }
}

private struct HomeDockMaterialSurface: View {
    var body: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.48), lineWidth: 0.5)
                }
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        }
    }
}
