# OCR 相机改用原生 UIImagePickerController + fullScreenCover

## Summary

将 OCR 流程中的相机路径从「自建 `AVCaptureSession + 自定义快门 UI` + sheet `.medium` detent」改为「原生 `UIImagePickerController` + `fullScreenCover` 满屏呈现」。

解决两个问题：
1. **底部黑边**：sheet `.medium` detent 高度 ≠ 相机 4:3 预览比例，预览 `resizeAspectFill` 被裁切后底部留黑。
2. **非原生相机 UI**：当前是自建快门按钮、自建权限请求、自建 AVCaptureSession，与 iOS 原生相机交互不一致。改为 `UIImagePickerController` 后获得原生快门、闪光灯、前后摄切换等系统控件。

## Current State Analysis

### 相机当前链路
1. [AppRootView.swift:182](file:///Users/papertiger/Desktop/Together/Together/App/AppRootView.swift#L182) menu "相机" → `openOCRSource(.camera)`
2. `openOCRSource` 创建 `OCRSourceSheetSession(source: .camera)` → 弹 `.sheet(item: $activeOCRSourceSession)`
3. [OCRAttachmentPopover.swift:113-114](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L113) `.camera` 分支强制 detent 为 `[.medium]`
4. [OCRAttachmentPopover.swift:123-129](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L123) 渲染 `OCRCameraCapturePanel`
5. [OCRMediaPickerViews.swift:7-163](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRMediaPickerViews.swift#L7) `OCRCameraCapturePanel` 自建预览 + 自建快门按钮
6. [OCRMediaPickerViews.swift:361-461](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRMediaPickerViews.swift#L361) `OCRCameraController` 用 `AVCaptureSession` + `AVCapturePhotoOutput`
7. [OCRMediaPickerViews.swift:338-359](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRMediaPickerViews.swift#L338) `OCRCameraPreview` 是 `UIViewRepresentable` 包装 `AVCaptureVideoPreviewLayer`

### 黑边根因
- `presentationDetents([.medium])` 让 sheet 高度约为屏幕一半
- `AVCaptureVideoPreviewLayer.videoGravity = .resizeAspectFill` 在 4:3 比例下被裁切
- sheet 容器高度 ≠ 相机预览实际高度 → 底部留黑

### 项目已有原生相机包装参考
[EditProfileView.swift:572-619](file:///Users/papertiger/Desktop/Together/Together/Features/Profile/EditProfileView.swift#L572) `CameraCaptureView` 已实现 `UIViewControllerRepresentable` 包装 `UIImagePickerController`，但属于 Profile 模块，OCR 不直接复用，按项目惯例在 OCR 模块独立实现一份。

## Proposed Changes

### 1. 新建 `Together/Features/OCRImport/OCRNativeCameraPicker.swift`

`UIViewControllerRepresentable` 包装 `UIImagePickerController(sourceType: .camera)`，独立于 Profile 模块的 `CameraCaptureView`，避免跨模块耦合。

```swift
import SwiftUI
import UIKit

struct OCRNativeCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        picker.view.backgroundColor = .black
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }
    }
}
```

**说明**：
- 不做 `isSourceTypeAvailable(.camera)` 检查——原生 picker 在不可用设备（模拟器、无相机 iPad）会自动呈现「相机不可用」提示，由系统处理。
- 不自建权限请求 UI——`UIImagePickerController` 第一次调用时系统会自动弹权限询问，符合 iOS 标准。
- `modalPresentationStyle = .fullScreen` 在 fullScreenCover 内是默认行为，显式设置以兜底。

### 2. 修改 `Together/App/AppRootView.swift`

**新增 state**：
```swift
@State private var isPresentingDirectOCRCamera = false
@State private var directOCRCameraCapturedImage: UIImage?
```

**修改 menu "相机" 按钮**（line 181-185）：
```swift
Button {
    openDirectOCRCamera()
} label: {
    Label("相机", systemImage: "camera")
}
```

**新增 fullScreenCover**（紧跟 `.photosPicker` modifier 之后）：
```swift
.fullScreenCover(isPresented: $isPresentingDirectOCRCamera) {
    OCRNativeCameraPicker(
        onCapture: { image in
            isPresentingDirectOCRCamera = false
            handleDirectOCRCapture(image)
        },
        onCancel: {
            isPresentingDirectOCRCamera = false
        }
    )
}
```

**新增函数**：
```swift
private func openDirectOCRCamera() {
    HomeInteractionFeedback.selection()
    isPresentingDirectOCRCamera = true
}

private func handleDirectOCRCapture(_ image: UIImage) {
    directOCRProcessingTask?.cancel()
    directOCRProcessingTask = Task { @MainActor in
        let viewModel = OCRImportViewModel()
        await viewModel.processImages([image])
        switch viewModel.flowState {
        case .review:
            appContext.router.activeOCRReviewSession = OCRReviewSession(
                viewModel: viewModel,
                availableHeight: OCRWindowMetrics.availableHeight
            )
        case .failed:
            activeOCRSourceSession = OCRSourceSheetSession(viewModel: viewModel)
        default:
            break
        }
    }
}
```

**删除旧相机入口**：
- `openOCRSource(.camera)` 不再被 menu 调用，但函数本身保留（测试或其它路径可能引用，删除前确认无引用即可）。检查后若无引用则删除。

### 3. 修改 `Together/Features/OCRImport/OCRAttachmentPopover.swift`

**删除 `OCRSourceSheet` 中相机分支**：
- [line 113-114](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L113) `availableDetents` 删除 `.camera` case，合并为 `default` 返回 `[.medium, .large]`
- [line 122-129](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L122) `content` 删除 `.camera` case
- [line 159-163](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L159) `handleFlowState` 删除 `.camera` case

**修改失败 UI 的"重新拍照"按钮**：
- [line 143](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRAttachmentPopover.swift#L143) `onCamera: { viewModel.showCamera() }` 改为触发外部回调
- `OCRSourceSheet` 新增 `onRetryCamera: () -> Void` 参数
- 失败 UI 的"重新拍照"按钮改为调用 `onRetryCamera`
- `onRetryCamera` 由 `AppRootView` 注入：dismiss OCRSourceSheet + 设置 `isPresentingDirectOCRCamera = true`

**`OCRSourceSheetSession(source: .camera)` 处理**：
- 该 init 不再被生产代码使用
- 测试 [TogetherTests.swift:20-25](file:///Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift#L20) 仍引用 `.camera` case
- 方案：保留 `OCRSourceKind.camera` 枚举值与 `OCRSourceSheetSession(source: .camera)` init（不破坏 API），但 `OCRSourceSheet` 内部不再渲染相机内容。`OCRSourceSheetSession(source: .camera)` 仅作为 placeholder，调 `viewModel.showCamera()` 设置 `flowState = .camera`，但 `OCRSourceSheet` 遇到 `.camera` 直接渲染 `Color.black`（等价于不可达分支）。

**简化方案（推荐）**：
直接保留 `OCRImportFlowState.camera` 枚举值不删，但 `OCRSourceSheet.content` 不再 case `.camera`，由 `default` 兜底渲染 `Color.black`。这样：
- 测试不破坏
- 生产代码不再走相机分支
- 后续清理时再统一删除

### 4. 删除 `Together/Features/OCRImport/OCRMediaPickerViews.swift` 中相机相关代码

完整删除以下类型（line 1-163 + 324-481 + 相关 private types）：
- `OCRCameraCapturePanel`
- `OCRCameraController`
- `OCRCameraPreview`
- `OCRCameraAuthorizationState`（private enum）
- `OCRCameraError`（private enum）
- `OCRCameraController.PreviewView`（private nested class）

**保留**：
- `OCRPhotoLibraryGridPanel`（虽然当前 OCRSourceSheet 不再使用，但用户未要求删除，保留以免破坏其它引用）
- `OCRPhotoAssetThumbnail`、`OCRPhotoLibraryImageLoader`、`OCRPhotoLibraryError`、`OCRMediaLoadingView`、`OCRMediaPermissionView`、`OCRMediaLayout`、UIApplication/UIViewController extensions（同上理由）
- `OCRMediaLayout.controlsBottomPadding` 仍被 OCRSourceSheet 使用

**验证方式**：删除后用 Grep 确认无残留引用。

### 5. 修改 `TogetherTests/TogetherTests.swift`

[line 20-25](file:///Users/papertiger/Desktop/Together/TogetherTests/TogetherTests.swift#L20) `ocrSourceSheetSessionStartsFromSelectedMenuAction` 测试：
- 保留 `.photos` 分支断言
- `.camera` 分支：若 `OCRImportFlowState.camera` 仍保留，断言 `cameraSession.viewModel.flowState == .camera` 不变
- 若决定彻底删除 `.camera` case，则删除该测试的 camera 部分

**推荐**：保留 `.camera` 枚举值不破坏测试。

### 6. `OCRImportViewModel.showCamera()` 处理

[line 148-151](file:///Users/papertiger/Desktop/Together/Together/Features/OCRImport/OCRImportViewModel.swift#L148)：
- 生产代码不再调用 `showCamera()`
- 但 `OCRSourceSheetSession(source: .camera)` init 仍调用它
- 保留该方法不删，避免破坏测试和 API

## Assumptions & Decisions

1. **不删除 `OCRImportFlowState.camera` / `OCRSourceSheetSession(source: .camera)` / `OCRImportViewModel.showCamera()`**：避免破坏测试和 API，仅在生产路径中不再使用。
2. **不删除 `OCRPhotoLibraryGridPanel` 等照片相关旧代码**：用户本次只要求改相机路径，照片相关代码保留。
3. **`UIImagePickerController` 在模拟器上的行为**：模拟器无相机，`UIImagePickerController(sourceType: .camera)` 会自动呈现系统「相机不可用」提示，无需自建 fallback。
4. **fullScreenCover 内的 UIImagePickerController**：iOS 会自动处理权限请求、闪光灯、前后摄切换，无需自建 UI。
5. **失败 UI 重试相机路径**：通过 `onRetryCamera` 回调让 AppRootView 关闭 OCRSourceSheet 并重新打开 fullScreenCover，保持单一职责。

## Verification Steps

1. **编译验证**：Xcode 编译 Together scheme，确保无 error / warning。
2. **真机验证**（必需，模拟器无相机）：
   - 进入首页 → OCR menu → "相机" → 弹出满屏原生相机 UI（无黑边）
   - 拍照 → 自动关闭相机 → 进入 review sheet
   - 拍照后 OCR 失败 → 弹失败 sheet → 点"重新拍照" → 关闭失败 sheet → 重新弹出满屏原生相机
   - 在相机 UI 点取消 → 关闭相机，无后续 sheet
3. **测试验证**：`xcodebuild test -scheme Together` 确认 `ocrSourceSheetSessionStartsFromSelectedMenuAction` 等测试通过。
4. **Grep 残留检查**：搜索 `OCRCameraCapturePanel`、`OCRCameraController`、`OCRCameraPreview` 确认无残留引用。
5. **照片路径回归**：确认 OCR menu → "照片" 路径仍正常工作（本次未改动）。
