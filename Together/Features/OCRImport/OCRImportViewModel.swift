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
        touchDraft()
    }

    @discardableResult
    func addTask(after taskID: UUID? = nil) -> UUID {
        let task = OCRImportTaskDraft(title: "")
        if let taskID,
           let index = draft.taskDrafts.firstIndex(where: { $0.id == taskID }) {
            draft.taskDrafts.insert(task, at: index + 1)
        } else {
            draft.taskDrafts.append(task)
        }
        touchDraft()
        return task.id
    }

    func deleteTask(id: UUID) {
        guard let index = draft.taskDrafts.firstIndex(where: { $0.id == id }) else { return }
        draft.taskDrafts.remove(at: index)
        touchDraft()
    }

    func moveTasks(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let validOffsets = offsets.filter { draft.taskDrafts.indices.contains($0) }
        guard validOffsets.isEmpty == false else { return }

        let movingTasks = validOffsets.map { draft.taskDrafts[$0] }
        for index in validOffsets.sorted(by: >) {
            draft.taskDrafts.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            draft.taskDrafts.count
        )
        draft.taskDrafts.insert(contentsOf: movingTasks, at: insertionIndex)
        touchDraft()
    }

    @discardableResult
    func mergeTaskWithPrevious(id: UUID) -> Bool {
        guard
            let index = draft.taskDrafts.firstIndex(where: { $0.id == id }),
            index > draft.taskDrafts.startIndex
        else { return false }

        let current = draft.taskDrafts[index]
        let previousIndex = index - 1
        let mergedSubtask = OCRImportSubtaskDraft(
            title: current.title,
            isSelected: current.isSelected,
            sourceText: current.sourceText
        )
        draft.taskDrafts[previousIndex].isSelected = draft.taskDrafts[previousIndex].isSelected || current.isSelected
        if current.title.trimmedForOCR.isEmpty == false {
            draft.taskDrafts[previousIndex].subtasks.append(mergedSubtask)
        }
        draft.taskDrafts[previousIndex].subtasks.append(contentsOf: current.subtasks)
        draft.taskDrafts.remove(at: index)
        touchDraft()
        return true
    }

    @discardableResult
    func splitSubtask(taskID: UUID, subtaskID: UUID) -> Bool {
        guard
            let taskIndex = draft.taskDrafts.firstIndex(where: { $0.id == taskID }),
            let subtaskIndex = draft.taskDrafts[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return false }

        let subtask = draft.taskDrafts[taskIndex].subtasks.remove(at: subtaskIndex)
        let newTask = OCRImportTaskDraft(
            title: subtask.title,
            isSelected: subtask.isSelected,
            sourceText: subtask.sourceText
        )
        draft.taskDrafts.insert(newTask, at: taskIndex + 1)
        touchDraft()
        return true
    }

    func apply(to appContext: AppContext) async -> Bool {
        guard
            let spaceID = appContext.sessionStore.currentSpace?.id,
            let actorID = appContext.sessionStore.currentUser?.id
        else {
            errorMessage = "个人空间尚未准备好，请稍后重试。"
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
                        isUrgent: task.isUrgent,
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

    private func touchDraft() {
        draft.updatedAt = Date.now
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
