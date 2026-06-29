import Foundation
import Observation
import UIKit

enum OCRImportFlowState: Hashable {
    case sourcePicker
    case camera
    case photos
    case processing
    case review
    case failed

    var prefersLargeDetent: Bool {
        switch self {
        case .sourcePicker:
            return false
        case .camera, .photos, .processing, .review, .failed:
            return true
        }
    }

    var isImmersiveMedia: Bool {
        switch self {
        case .camera, .photos:
            return true
        case .sourcePicker, .processing, .review, .failed:
            return false
        }
    }
}

enum OCRReviewSheetDetent: Hashable {
    case medium
    case large
}

enum OCRReviewDetentPolicy {
    private static let sheetChromeHeight: CGFloat = 72
    private static let minimumMediumContentHeight: CGFloat = 220
    private static let taskBaseHeight: CGFloat = 196
    private static let subtaskHeight: CGFloat = 44
    private static let taskSpacing: CGFloat = 16

    static func initialDetent(
        for draft: OCRImportDraft,
        availableHeight: CGFloat
    ) -> OCRReviewSheetDetent {
        estimatedContentHeight(for: draft) > mediumContentCapacity(availableHeight: availableHeight)
            ? .large
            : .medium
    }

    static func resolvedDetent(
        current: OCRReviewSheetDetent,
        measuredContentHeight: CGFloat,
        availableHeight: CGFloat,
        keyboardIsVisible: Bool
    ) -> OCRReviewSheetDetent {
        guard current == .medium else { return .large }
        guard keyboardIsVisible == false else { return .large }
        return measuredContentHeight > mediumContentCapacity(availableHeight: availableHeight)
            ? .large
            : .medium
    }

    static func mediumContentCapacity(availableHeight: CGFloat) -> CGFloat {
        max(availableHeight * 0.5 - sheetChromeHeight, minimumMediumContentHeight)
    }

    private static func estimatedContentHeight(for draft: OCRImportDraft) -> CGFloat {
        draft.taskDrafts.enumerated().reduce(0) { total, entry in
            let (index, task) = entry
            let spacing = index == draft.taskDrafts.startIndex ? 0 : taskSpacing
            return total + spacing + taskBaseHeight + CGFloat(task.subtasks.count) * subtaskHeight
        }
    }
}

@MainActor
final class OCRReviewSession: Identifiable {
    let id = UUID()
    let viewModel: OCRImportViewModel
    let availableHeight: CGFloat

    private let initialTaskDrafts: [OCRImportTaskDraft]

    init(viewModel: OCRImportViewModel, availableHeight: CGFloat) {
        self.viewModel = viewModel
        self.availableHeight = availableHeight
        self.initialTaskDrafts = viewModel.draft.taskDrafts
    }

    var hasUserChanges: Bool {
        viewModel.draft.taskDrafts != initialTaskDrafts
    }

    var initialDetent: OCRReviewSheetDetent {
        OCRReviewDetentPolicy.initialDetent(
            for: viewModel.draft,
            availableHeight: availableHeight
        )
    }

    func discard() {
        viewModel.draft.status = .discarded
    }
}

@MainActor
@Observable
final class OCRImportViewModel {
    private let recognizer: OCRTextRecognizing

    var draft = OCRImportDraft(rawText: "", status: .idle)
    var flowState: OCRImportFlowState = .sourcePicker
    var sourceImage: UIImage?
    var errorMessage: String?

    init(recognizer: OCRTextRecognizing = OCRTextRecognizer()) {
        self.recognizer = recognizer
    }

    var isRecognizing: Bool {
        draft.status == .recognizing
    }

    var canApply: Bool {
        selectedTaskDrafts.isEmpty == false
    }

    var selectedTaskDrafts: [OCRImportTaskDraft] {
        draft.taskDrafts.compactMap { task in
            guard task.isSelected && task.title.trimmedForOCR.isEmpty == false else {
                return nil
            }
            var copy = task
            copy.subtasks = task.subtasks.filter {
                $0.isSelected && $0.title.trimmedForOCR.isEmpty == false
            }
            return copy
        }
    }

    func showSourcePicker() {
        flowState = .sourcePicker
    }

    func showCamera() {
        errorMessage = nil
        flowState = .camera
    }

    func showPhotos() {
        errorMessage = nil
        flowState = .photos
    }

    func processImage(_ image: UIImage) async {
        await processImages([image])
    }

    func processImages(_ images: [UIImage]) async {
        guard images.isEmpty == false else { return }
        let firstImage = images[0]
        sourceImage = firstImage
        errorMessage = nil
        flowState = .processing
        draft = OCRImportDraft(rawText: "", status: .recognizing)

        var recognizedTexts: [String] = []
        var lastError: Error?
        for image in images {
            do {
                let rawText = try await recognizer.recognizeText(in: image)
                recognizedTexts.append(rawText)
            } catch {
                lastError = error
            }
        }

        if recognizedTexts.isEmpty {
            errorMessage = lastError.map { ($0 as? LocalizedError)?.errorDescription ?? $0.localizedDescription }
                ?? "没有识别到可导入的文字。"
            draft.status = .failed
            flowState = .failed
            return
        }

        let combinedRawText = recognizedTexts.joined(separator: "\n")
        let parsed = OCRImportDraftParser.parse(rawText: combinedRawText)
        draft = parsed
        if parsed.taskDrafts.isEmpty {
            errorMessage = "没有识别到可导入的待办。"
            draft.status = .failed
            flowState = .failed
        } else {
            flowState = .review
        }
    }

    func updateTask(_ task: OCRImportTaskDraft) {
        guard let index = draft.taskDrafts.firstIndex(where: { $0.id == task.id }) else { return }
        draft.taskDrafts[index] = task
        draft.updatedAt = Date.now
    }

    func apply(to appContext: AppContext) async -> Bool {
        guard
            let spaceID = appContext.sessionStore.currentSpace?.id,
            let actorID = appContext.sessionStore.currentUser?.id
        else {
            errorMessage = "请先完成登录。"
            return false
        }

        let tasks = selectedTaskDrafts
        guard tasks.isEmpty == false else {
            errorMessage = "请至少保留一个待办。"
            return false
        }

        draft.status = .applying
        do {
            var insertedTaskIDs: [UUID] = []
            for task in tasks {
                let item = try await appContext.container.taskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: TaskDraft(
                        title: task.title.trimmedForOCR,
                        notes: task.notes?.nilIfBlank,
                        dueAt: task.dueAt,
                        hasExplicitTime: task.hasExplicitTime,
                        remindAt: task.remindAt,
                        repeatRule: task.repeatRule,
                        subtasks: task.subtasks.enumerated().map { index, subtask in
                            TaskSubtaskDraft(
                                title: subtask.title.trimmedForOCR,
                                sortOrder: index
                            )
                        }
                    )
                )
                insertedTaskIDs.append(item.id)
            }

            if insertedTaskIDs.isEmpty {
                await appContext.homeViewModel.reload(reason: .userInserted)
            } else {
                await appContext.homeViewModel.reload(insertedItemIDs: Set(insertedTaskIDs), reason: .userInserted)
            }
            await appContext.refreshTodayWidgetSnapshot()
            draft.status = .applied
            return true
        } catch {
            errorMessage = error.localizedDescription
            draft.status = .needsReview
            flowState = .review
            return false
        }
    }

    func reset() {
        draft = OCRImportDraft(rawText: "", status: .idle)
        flowState = .sourcePicker
        sourceImage = nil
        errorMessage = nil
    }
}

private extension String {
    var trimmedForOCR: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmedForOCR
        return trimmed.isEmpty ? nil : trimmed
    }
}
