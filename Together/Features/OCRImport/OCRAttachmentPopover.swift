import PhotosUI
import SwiftUI
import UIKit

enum OCRMediaLayout {
    static func controlsBottomPadding(
        safeAreaBottom: CGFloat,
        designSpacing: CGFloat
    ) -> CGFloat {
        safeAreaBottom + designSpacing
    }
}

enum OCRSourceKind: Hashable {
    case camera
    case photos
}

@MainActor
@Observable
final class OCRSourceSheetSession: Identifiable {
    let id = UUID()
    let viewModel: OCRImportViewModel
    let availableHeight: CGFloat

    init(source: OCRSourceKind) {
        availableHeight = OCRWindowMetrics.availableHeight
        viewModel = OCRImportViewModel()
        viewModel.reset()
        switch source {
        case .camera:
            viewModel.showCamera()
        case .photos:
            viewModel.showPhotos()
        }
    }

    init(viewModel: OCRImportViewModel) {
        availableHeight = OCRWindowMetrics.availableHeight
        self.viewModel = viewModel
    }
}

struct OCRSourceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: OCRSourceSheetSession
    let onReviewReady: (OCRSourceSheetSession) -> Void
    let onRetryCamera: () -> Void

    @State private var selectedDetent: PresentationDetent
    @State private var processingTask: Task<Void, Never>?
    @State private var didHandOffReview = false
    @State private var isPresentingSystemPhotoPicker: Bool
    @State private var photoPickerSelection: [PhotosPickerItem] = []
    @State private var didPickPhotos = false

    init(
        session: OCRSourceSheetSession,
        onReviewReady: @escaping (OCRSourceSheetSession) -> Void,
        onRetryCamera: @escaping () -> Void = {}
    ) {
        self.session = session
        self.onReviewReady = onReviewReady
        self.onRetryCamera = onRetryCamera
        _selectedDetent = State(
            initialValue: session.viewModel.flowState == .photos ? .large : .medium
        )
        _isPresentingSystemPhotoPicker = State(
            initialValue: session.viewModel.flowState == .photos
        )
    }

    var body: some View {
        GeometryReader { proxy in
            content(bottomSafeAreaInset: proxy.safeAreaInsets.bottom)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(.black)
                .ignoresSafeArea()
        }
        .presentationDetents(availableDetents, selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .presentationContentInteraction(.scrolls)
        .interactiveDismissDisabled(viewModel.isRecognizing)
        .photosPicker(
            isPresented: $isPresentingSystemPhotoPicker,
            selection: $photoPickerSelection,
            maxSelectionCount: 6,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: viewModel.flowState) { _, newState in
            handleFlowState(newState)
        }
        .onChange(of: photoPickerSelection) { _, newValue in
            loadImages(from: newValue)
        }
        .onChange(of: isPresentingSystemPhotoPicker) { _, isPresented in
            guard isPresented == false else { return }
            if didPickPhotos == false && viewModel.flowState == .photos {
                dismiss()
            }
        }
        .onDisappear {
            processingTask?.cancel()
        }
    }

    private var viewModel: OCRImportViewModel {
        session.viewModel
    }

    private var availableDetents: Set<PresentationDetent> {
        switch viewModel.flowState {
        case .photos:
            [.large]
        case .sourcePicker, .camera, .processing, .review, .failed:
            [.medium, .large]
        }
    }

    @ViewBuilder
    private func content(bottomSafeAreaInset: CGFloat) -> some View {
        switch viewModel.flowState {
        case .camera:
            Color.black
        case .photos:
            Color.black
                .overlay {
                    ProgressView("正在打开照片…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
        case .processing, .review:
            OCRAttachmentProcessingView(sourceImage: viewModel.sourceImage)
        case .failed:
            OCRAttachmentFailureView(
                sourceImage: viewModel.sourceImage,
                message: viewModel.errorMessage,
                onCamera: { onRetryCamera() },
                onPhotos: { viewModel.showPhotos() }
            )
        case .sourcePicker:
            Color.black
        }
    }

    private func process(images: [UIImage]) {
        guard images.isEmpty == false else { return }
        processingTask?.cancel()
        processingTask = Task {
            await viewModel.processImages(images)
        }
    }

    private func handleFlowState(_ state: OCRImportFlowState) {
        switch state {
        case .camera:
            selectedDetent = .medium
            isPresentingSystemPhotoPicker = false
        case .photos:
            selectedDetent = .large
            didPickPhotos = false
            photoPickerSelection = []
            if isPresentingSystemPhotoPicker == false {
                isPresentingSystemPhotoPicker = true
            }
        case .review:
            guard didHandOffReview == false else { return }
            didHandOffReview = true
            onReviewReady(session)
        case .sourcePicker, .processing, .failed:
            break
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        guard items.isEmpty == false else { return }
        didPickPhotos = true
        photoPickerSelection = []
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            if images.isEmpty == false {
                process(images: images)
            } else {
                didPickPhotos = false
                dismiss()
            }
        }
    }
}

private struct OCRAttachmentProcessingView: View {
    let sourceImage: UIImage?

    var body: some View {
        VStack(spacing: AppTheme.spacing.xl) {
            if let sourceImage {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
            }

            ProgressView("正在识别文字")
                .tint(.white)
                .foregroundStyle(.white)
        }
        .padding(AppTheme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OCRAttachmentFailureView: View {
    let sourceImage: UIImage?
    let message: String?
    let onCamera: () -> Void
    let onPhotos: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.spacing.lg) {
            if let sourceImage {
                Image(uiImage: sourceImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
            }

            Image(systemName: "exclamationmark.triangle")
                .font(AppTheme.typography.sized(30, weight: .semibold))
                .foregroundStyle(AppTheme.colors.coral)

            Text(message ?? "识别失败，请换一张更清晰的图片。")
                .font(AppTheme.typography.textStyle(.body, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: AppTheme.spacing.md) {
                Button("重新拍照", action: onCamera)
                    .buttonStyle(.glass)
                Button("选择照片", action: onPhotos)
                    .buttonStyle(.glass)
            }
        }
        .padding(AppTheme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
enum OCRWindowMetrics {
    static var availableHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .bounds.height ?? 844
    }
}
