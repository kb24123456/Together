import SwiftUI
import Combine

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
#if canImport(UIKit)
    let overrideImage: UIImage?
#endif

    init(
        avatarAsset: UserAvatarAsset,
        displayName: String,
        size: CGFloat,
        fillColor: Color,
        symbolColor: Color,
        symbolFont: Font,
        overrideImage: UIImage? = nil
    ) {
        self.avatarAsset = avatarAsset
        self.displayName = displayName
        self.size = size
        self.fillColor = fillColor
        self.symbolColor = symbolColor
        self.symbolFont = symbolFont
        self.overrideImage = overrideImage
    }

    var body: some View {
        ZStack {
#if canImport(UIKit)
            if let overrideImage {
                Image(uiImage: overrideImage)
                    .resizable()
                    .scaledToFill()
            } else {
                avatarContent
            }
#else
            avatarContent
#endif
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(displayName)
    }

    @ViewBuilder
    private var avatarContent: some View {
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
}

private struct AvatarPhotoView: View {
    let fileName: String
    let size: CGFloat

    #if canImport(UIKit)
    @State private var loadedImage: UIImage?
    @State private var reloadTick: Int = 0

    private var partnerAvatarPublisher: AnyPublisher<Notification, Never> {
        NotificationCenter.default.publisher(for: .partnerAvatarDownloaded)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
    #endif

    var body: some View {
        #if canImport(UIKit)
        if let loadedImage {
            Image(uiImage: loadedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .onReceive(partnerAvatarPublisher) { notif in
                    handleDownloadNotification(notif)
                }
        } else if let image = UserAvatarRuntimeStore.image(for: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .onReceive(partnerAvatarPublisher) { notif in
                    handleDownloadNotification(notif)
                }
        } else {
            fallbackView
                .task(id: "\(fileName)-\(reloadTick)") {
                    await loadImageIfNeeded()
                }
                .onReceive(partnerAvatarPublisher) { notif in
                    handleDownloadNotification(notif)
                }
        }
        #else
        fallbackView
        #endif
    }

    #if canImport(UIKit)
    private func handleDownloadNotification(_ notif: Notification) {
        // Partner avatar just landed on disk for some fileName — if it matches
        // the one this view is rendering, drop our cached UIImage state and
        // force a reload on the next render.
        guard
            let assetID = notif.userInfo?["assetID"] as? String,
            let version = notif.userInfo?["version"] as? Int
        else { return }
        let expected = UserAvatarStorage.partnerFileName(forAssetID: assetID, version: version)
        guard expected == fileName else { return }
        loadedImage = nil
        UserAvatarRuntimeStore.remove(fileName: fileName)
        reloadTick &+= 1
    }
    #endif

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

    #if canImport(UIKit)
    @MainActor
    private func loadImageIfNeeded() async {
        guard loadedImage == nil else { return }

        if let cachedImage = UserAvatarRuntimeStore.image(for: fileName) {
            loadedImage = cachedImage
            return
        }

        await Task.yield()

        guard let image = UIImage(
            contentsOfFile: UserAvatarStorage.fileURL(fileName: fileName).path(percentEncoded: false)
        ) else {
            loadedImage = nil
            return
        }

        UserAvatarRuntimeStore.store(image, for: fileName)
        loadedImage = image
    }
    #endif
}

#if canImport(UIKit)
enum UserAvatarRuntimeStore {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    nonisolated static func image(for fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    nonisolated static func store(_ image: UIImage, for fileName: String) {
        cache.setObject(image, forKey: fileName as NSString)
    }

    nonisolated static func remove(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }
}
#endif
