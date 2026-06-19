import PhotosUI
import SwiftUI
import UIKit

struct OCRImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: OCRImportViewModel
    let appContext: AppContext
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.spacing.lg) {
                    sourceSection
                    statusSection
                    draftSection
                }
                .padding(.horizontal, AppTheme.spacing.xl)
                .padding(.vertical, AppTheme.spacing.lg)
            }
            .background(AppTheme.colors.background)
            .navigationTitle("OCR 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") {
                        Task {
                            if await viewModel.apply(to: appContext) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.canApply == false || viewModel.draft.status == .applying)
                }
            }
            .sheet(isPresented: $viewModel.isCameraPresented) {
                OCRCameraImagePicker { image in
                    Task { await viewModel.processImage(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Text("拍摄或选择纸面笔记")
                .font(AppTheme.typography.sized(19, weight: .bold))
                .foregroundStyle(AppTheme.colors.title)

            HStack(spacing: AppTheme.spacing.md) {
                Button {
                    viewModel.isCameraPresented = true
                } label: {
                    Label("拍照", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(UIImagePickerController.isSourceTypeAvailable(.camera) == false)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("照片", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) == false {
                Text("当前环境不支持拍照，可以先从照片中选择图片。")
                    .font(AppTheme.typography.sized(13, weight: .medium))
                    .foregroundStyle(AppTheme.colors.body.opacity(0.56))
            }

            if let image = viewModel.sourceImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(AppTheme.colors.outline.opacity(0.5), lineWidth: 1)
                    }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch viewModel.draft.status {
        case .idle:
            Text("OCR 结果会先生成草稿，确认前不会写入任务。")
                .font(AppTheme.typography.sized(14, weight: .medium))
                .foregroundStyle(AppTheme.colors.body.opacity(0.62))
        case .recognizing:
            HStack(spacing: AppTheme.spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("正在识别文字")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
            }
            .foregroundStyle(AppTheme.colors.body.opacity(0.72))
        case .failed:
            Text(viewModel.errorMessage ?? "识别失败，请换一张更清晰的图片。")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(AppTheme.colors.coral)
        case .needsReview:
            rawTextSection
        case .applying:
            HStack(spacing: AppTheme.spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("正在写入")
                    .font(AppTheme.typography.sized(14, weight: .semibold))
            }
        case .applied:
            Text("已导入")
                .font(AppTheme.typography.sized(14, weight: .semibold))
                .foregroundStyle(.green)
        case .discarded:
            EmptyView()
        }
    }

    private var rawTextSection: some View {
        DisclosureGroup {
            Text(viewModel.draft.rawText)
                .font(AppTheme.typography.sized(13, weight: .regular))
                .foregroundStyle(AppTheme.colors.body.opacity(0.72))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, AppTheme.spacing.sm)
        } label: {
            Text("原始识别文本")
                .font(AppTheme.typography.sized(14, weight: .semibold))
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            if viewModel.draft.projectDrafts.isEmpty == false {
                Text("项目草稿")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)

                ForEach(viewModel.draft.projectDrafts) { project in
                    OCRProjectDraftEditor(project: projectBinding(project.id))
                }
            }

            if viewModel.draft.taskDrafts.isEmpty == false {
                Text("待办草稿")
                    .font(AppTheme.typography.sized(17, weight: .bold))
                    .foregroundStyle(AppTheme.colors.title)

                ForEach(viewModel.draft.taskDrafts) { task in
                    OCRTaskDraftEditor(task: taskBinding(task.id))
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            await viewModel.processImage(image)
        } else {
            viewModel.errorMessage = "无法读取所选图片。"
            viewModel.draft.status = .failed
        }
        selectedPhotoItem = nil
    }

    private func taskBinding(_ id: UUID) -> Binding<OCRImportTaskDraft> {
        Binding {
            viewModel.draft.taskDrafts.first { $0.id == id }
                ?? OCRImportTaskDraft(title: "")
        } set: { updated in
            viewModel.updateTask(updated)
        }
    }

    private func projectBinding(_ id: UUID) -> Binding<OCRImportProjectDraft> {
        Binding {
            viewModel.draft.projectDrafts.first { $0.id == id }
                ?? OCRImportProjectDraft(name: "")
        } set: { updated in
            viewModel.updateProject(updated)
        }
    }
}

private struct OCRTaskDraftEditor: View {
    @Binding var task: OCRImportTaskDraft

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.sm) {
            Toggle(isOn: $task.isSelected) {
                TextField("待办标题", text: $task.title)
                    .font(AppTheme.typography.sized(15, weight: .semibold))
            }

            TextField(
                "备注",
                text: Binding(
                    get: { task.notes ?? "" },
                    set: { task.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .font(AppTheme.typography.sized(13, weight: .regular))
            .lineLimit(1...3)

            if task.subtasks.isEmpty == false {
                VStack(alignment: .leading, spacing: AppTheme.spacing.xs) {
                    Text("子任务")
                        .font(AppTheme.typography.sized(13, weight: .semibold))
                        .foregroundStyle(AppTheme.colors.body.opacity(0.62))

                    ForEach($task.subtasks) { $subtask in
                        Toggle(isOn: $subtask.isSelected) {
                            TextField("子任务标题", text: $subtask.title)
                                .font(AppTheme.typography.sized(13, weight: .medium))
                        }
                    }
                }
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated)
        .clipShape(.rect(cornerRadius: 14))
    }
}

private struct OCRProjectDraftEditor: View {
    @Binding var project: OCRImportProjectDraft

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.spacing.md) {
            Toggle(isOn: $project.isSelected) {
                TextField("项目名称", text: $project.name)
                    .font(AppTheme.typography.sized(15, weight: .bold))
            }

            ForEach($project.taskDrafts) { $task in
                OCRTaskDraftEditor(task: $task)
            }
        }
        .padding(AppTheme.spacing.md)
        .background(AppTheme.colors.surfaceElevated.opacity(0.82))
        .clipShape(.rect(cornerRadius: 16))
    }
}

private struct OCRCameraImagePicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImagePicked: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImagePicked = onImagePicked
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImagePicked(image)
            }
            dismiss()
        }
    }
}
