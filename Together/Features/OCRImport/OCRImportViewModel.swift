import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class OCRImportViewModel {
    private let recognizer: OCRTextRecognizer

    var draft = OCRImportDraft(rawText: "", status: .idle)
    var sourceImage: UIImage?
    var errorMessage: String?
    var isCameraPresented = false

    init(recognizer: OCRTextRecognizer = OCRTextRecognizer()) {
        self.recognizer = recognizer
    }

    var isRecognizing: Bool {
        draft.status == .recognizing
    }

    var canApply: Bool {
        selectedTaskDrafts.isEmpty == false || selectedProjectDrafts.isEmpty == false
    }

    var selectedTaskDrafts: [OCRImportTaskDraft] {
        draft.taskDrafts.filter { $0.isSelected && $0.title.trimmedForOCR.isEmpty == false }
    }

    var selectedProjectDrafts: [OCRImportProjectDraft] {
        draft.projectDrafts.compactMap { project in
            let tasks = project.taskDrafts.filter { $0.isSelected && $0.title.trimmedForOCR.isEmpty == false }
            guard project.isSelected, project.name.trimmedForOCR.isEmpty == false, tasks.isEmpty == false else {
                return nil
            }
            var copy = project
            copy.taskDrafts = tasks
            return copy
        }
    }

    func processImage(_ image: UIImage) async {
        sourceImage = image
        errorMessage = nil
        draft = OCRImportDraft(rawText: "", status: .recognizing)

        do {
            let rawText = try await recognizer.recognizeText(in: image)
            let parsed = OCRImportDraftParser.parse(rawText: rawText)
            draft = parsed
            if parsed.taskDrafts.isEmpty && parsed.projectDrafts.isEmpty {
                errorMessage = "没有识别到可导入的待办。"
                draft.status = .failed
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            draft.status = .failed
        }
    }

    func updateTask(_ task: OCRImportTaskDraft) {
        guard let index = draft.taskDrafts.firstIndex(where: { $0.id == task.id }) else { return }
        draft.taskDrafts[index] = task
        draft.updatedAt = Date.now
    }

    func updateProject(_ project: OCRImportProjectDraft) {
        guard let index = draft.projectDrafts.firstIndex(where: { $0.id == project.id }) else { return }
        draft.projectDrafts[index] = project
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
        let projects = selectedProjectDrafts
        guard tasks.isEmpty == false || projects.isEmpty == false else {
            errorMessage = "请至少保留一个待办或项目。"
            return false
        }

        draft.status = .applying
        do {
            var insertedTaskIDs: [UUID] = []
            for task in tasks {
                let item = try await appContext.container.taskApplicationService.createTask(
                    in: spaceID,
                    actorID: actorID,
                    draft: TaskDraft(title: task.title.trimmedForOCR, notes: task.notes?.nilIfBlank)
                )
                insertedTaskIDs.append(item.id)
            }

            for projectDraft in projects {
                let project = Project(
                    id: UUID(),
                    spaceID: spaceID,
                    creatorID: actorID,
                    name: projectDraft.name.trimmedForOCR,
                    notes: projectDraft.notes?.nilIfBlank,
                    colorToken: nil,
                    status: .active,
                    targetDate: nil,
                    remindAt: nil,
                    taskCount: projectDraft.taskDrafts.count,
                    sortOrder: Date.now.timeIntervalSinceReferenceDate,
                    createdAt: Date.now,
                    updatedAt: Date.now,
                    completedAt: nil
                )
                _ = await appContext.projectsViewModel.createNew(
                    project,
                    subtasks: projectDraft.taskDrafts.map {
                        (title: $0.title.trimmedForOCR, isCompleted: false)
                    }
                )
            }

            if insertedTaskIDs.isEmpty {
                await appContext.homeViewModel.reload(reason: .userInserted)
            } else {
                await appContext.homeViewModel.reload(insertedItemIDs: Set(insertedTaskIDs), reason: .userInserted)
            }
            await appContext.projectsViewModel.load()
            await appContext.refreshTodayWidgetSnapshot()
            draft.status = .applied
            return true
        } catch {
            errorMessage = error.localizedDescription
            draft.status = .needsReview
            return false
        }
    }

    func reset() {
        draft = OCRImportDraft(rawText: "", status: .idle)
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
