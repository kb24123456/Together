import AVFoundation
import Foundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class EditProfileViewModel {
    enum CameraPermissionState: Equatable {
        case idle
        case denied
        case restricted
        case unsupported
    }

    enum AvatarDraftState: Equatable {
        case existingSystem(String)
        case existingPhoto(String)
        case newPhoto
        case removedToSystem(String)
    }

    private let sessionStore: SessionStore
    private let userProfileRepository: UserProfileRepositoryProtocol
    private let originalUser: User

    var displayName: String
    var avatarDraftState: AvatarDraftState
    var draftAvatarImage: UIImage?
    var pendingCropImage: UIImage?
    var showsCameraPicker = false
    var cameraPermissionState: CameraPermissionState = .idle
    var cameraErrorMessage: String?
    var errorMessage: String?
    var isSaving = false

    init(
        sessionStore: SessionStore,
        userProfileRepository: UserProfileRepositoryProtocol
    ) {
        self.sessionStore = sessionStore
        self.userProfileRepository = userProfileRepository
        let user = sessionStore.currentUser ?? MockDataFactory.makeCurrentUser()
        self.originalUser = user
        self.displayName = user.displayName

        if let avatarPhotoFileName = user.avatarPhotoFileName {
            self.avatarDraftState = .existingPhoto(avatarPhotoFileName)
        } else {
            self.avatarDraftState = .existingSystem(user.avatarSystemName ?? "person.crop.circle.fill")
        }
    }

    var navigationTitle: String {
        "编辑资料"
    }

    var isNameValid: Bool {
        let sanitized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sanitized.isEmpty && sanitized.count <= 20
    }

    var nameValidationMessage: String? {
        let sanitized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            return "名称不能为空"
        }
        if sanitized.count > 20 {
            return "名称最多 20 个字符"
        }
        return nil
    }

    var canRemovePhoto: Bool {
        switch avatarDraftState {
        case .existingPhoto, .newPhoto:
            return true
        case .existingSystem, .removedToSystem:
            return false
        }
    }

    var hasUnsavedChanges: Bool {
        let sanitizedCurrentName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedOriginalName = originalUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitizedCurrentName != sanitizedOriginalName {
            return true
        }

        switch avatarDraftState {
        case .newPhoto, .removedToSystem:
            return true
        case .existingPhoto(let fileName):
            return fileName != originalUser.avatarPhotoFileName
        case .existingSystem(let symbolName):
            return symbolName != (originalUser.avatarSystemName ?? "person.crop.circle.fill")
                || originalUser.avatarPhotoFileName != nil
        }
    }

    var isSaveDisabled: Bool {
        isSaving || !isNameValid || !hasUnsavedChanges
    }

    var previewAvatarAsset: UserAvatarAsset {
        switch avatarDraftState {
        case .existingPhoto(let fileName):
            return .photo(fileName: fileName)
        case .existingSystem(let symbolName), .removedToSystem(let symbolName):
            return .system(symbolName)
        case .newPhoto:
            return originalUser.avatarAsset
        }
    }

    var previewUIImage: UIImage? {
        draftAvatarImage
    }

    var placeholderSymbolName: String {
        originalUser.avatarSystemName ?? "person.crop.circle.fill"
    }

    var shouldShowCameraSettingsAction: Bool {
        cameraPermissionState == .denied
    }

    func receiveSelectedPhotoData(_ data: Data?) {
        guard let data else {
            errorMessage = "读取照片失败，请重新选择。"
            return
        }

        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            errorMessage = "无法解析所选照片，请更换一张图片。"
            return
        }
        pendingCropImage = image.normalizedOrientationImage()
        #else
        errorMessage = "当前设备不支持头像编辑。"
        #endif
    }

    func handleCameraTapped() async {
        #if canImport(UIKit)
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraPermissionState = .unsupported
            cameraErrorMessage = "当前设备不支持拍照。"
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionState = .idle
            cameraErrorMessage = nil
            showsCameraPicker = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                cameraPermissionState = .idle
                cameraErrorMessage = nil
                showsCameraPicker = true
            } else {
                cameraPermissionState = .denied
                cameraErrorMessage = "未获得相机权限，可前往系统设置开启。"
            }
        case .denied:
            cameraPermissionState = .denied
            cameraErrorMessage = "未获得相机权限，可前往系统设置开启。"
        case .restricted:
            cameraPermissionState = .restricted
            cameraErrorMessage = "当前设备限制了相机使用。"
        @unknown default:
            cameraPermissionState = .denied
            cameraErrorMessage = "当前无法使用相机，请稍后重试。"
        }
        #else
        cameraPermissionState = .unsupported
        cameraErrorMessage = "当前设备不支持拍照。"
        #endif
    }

    func receiveCapturedPhoto(_ image: UIImage?) {
        showsCameraPicker = false
        guard let image else { return }
        pendingCropImage = image.normalizedOrientationImage()
    }

    func clearCameraError() {
        cameraErrorMessage = nil
        if cameraPermissionState == .unsupported || cameraPermissionState == .restricted {
            cameraPermissionState = .idle
        }
    }

    func cancelCropping() {
        pendingCropImage = nil
    }

    func applyCroppedImage(_ image: UIImage) {
        draftAvatarImage = image
        avatarDraftState = .newPhoto
        pendingCropImage = nil
    }

    func removePhoto() {
        draftAvatarImage = nil
        avatarDraftState = .removedToSystem(placeholderSymbolName)
    }

    func clearError() {
        errorMessage = nil
    }

    func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func save() async -> Bool {
        guard isSaveDisabled == false else { return false }

        isSaving = true
        defer { isSaving = false }

        let avatarUpdate: UserAvatarUpdate
        switch avatarDraftState {
        case .newPhoto:
            #if canImport(UIKit)
            guard
                let draftAvatarImage,
                let data = draftAvatarImage.jpegData(compressionQuality: 0.88)
            else {
                errorMessage = "头像保存失败，请重新裁剪。"
                return false
            }
            avatarUpdate = .replacePhoto(data)
            #else
            errorMessage = "当前设备不支持头像编辑。"
            return false
            #endif
        case .removedToSystem:
            avatarUpdate = .removeCustomPhoto
        case .existingPhoto, .existingSystem:
            avatarUpdate = .preserveExisting
        }

        do {
            let updatedUser = try await userProfileRepository.saveProfile(
                for: originalUser,
                displayName: displayName,
                avatarUpdate: avatarUpdate
            )

            #if canImport(UIKit)
            switch avatarUpdate {
            case .replacePhoto:
                if let fileName = updatedUser.avatarPhotoFileName, let draftAvatarImage {
                    UserAvatarRuntimeStore.store(draftAvatarImage, for: fileName)
                }
                if let previousFileName = originalUser.avatarPhotoFileName,
                   previousFileName != updatedUser.avatarPhotoFileName
                {
                    UserAvatarRuntimeStore.remove(fileName: previousFileName)
                }
            case .removeCustomPhoto:
                if let previousFileName = originalUser.avatarPhotoFileName {
                    UserAvatarRuntimeStore.remove(fileName: previousFileName)
                }
            case .preserveExisting:
                break
            }
            #endif

            sessionStore.currentUser = updatedUser
            return true
        } catch {
            #if DEBUG
            print("[EditProfile] save failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
            return false
        }
    }
}

#if canImport(UIKit)
extension UIImage {
    func normalizedOrientationImage() -> UIImage {
        guard imageOrientation != .up else { return self }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
