import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct UserAvatarView: View {
    let avatarAsset: UserAvatarAsset
    let displayName: String
    let size: CGFloat
    let fillColor: Color
    let symbolColor: Color
    let symbolFont: Font

    var body: some View {
        ZStack {
            switch avatarAsset {
            case .system(let symbolName):
                Circle()
                    .fill(fillColor)

                Image(systemName: symbolName)
                    .font(symbolFont)
                    .foregroundStyle(symbolColor)
            case .photo(let fileName):
                AvatarPhotoView(fileName: fileName, size: size)
                    .clipShape(Circle())
                    .id(fileName)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(displayName)
    }
}

private struct AvatarPhotoView: View {
    let fileName: String
    let size: CGFloat

    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(contentsOfFile: UserAvatarStorage.fileURL(fileName: fileName).path()) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        } else {
            fallbackView
        }
        #else
        fallbackView
        #endif
    }

    private var fallbackView: some View {
        Circle()
            .fill(AppTheme.colors.avatarWarm)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "person.crop.circle.fill")
                    .font(AppTheme.typography.sized(22, weight: .semibold))
                    .foregroundStyle(AppTheme.colors.title.opacity(0.82))
            }
    }
}
