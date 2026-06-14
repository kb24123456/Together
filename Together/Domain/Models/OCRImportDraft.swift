import Foundation

enum OCRDraftStatus: String, Hashable, Sendable, Codable {
    case idle
    case recognizing
    case needsReview
    case applying
    case applied
    case failed
    case discarded
}

struct OCRImportTaskDraft: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var title: String
    var notes: String?
    var isSelected: Bool
    var sourceText: String?

    nonisolated init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        isSelected: Bool = true,
        sourceText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isSelected = isSelected
        self.sourceText = sourceText
    }
}

struct OCRImportProjectDraft: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var name: String
    var notes: String?
    var isSelected: Bool
    var taskDrafts: [OCRImportTaskDraft]
    var sourceText: String?

    nonisolated init(
        id: UUID = UUID(),
        name: String,
        notes: String? = nil,
        isSelected: Bool = true,
        taskDrafts: [OCRImportTaskDraft] = [],
        sourceText: String? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.isSelected = isSelected
        self.taskDrafts = taskDrafts
        self.sourceText = sourceText
    }
}

struct OCRImportDraft: Identifiable, Hashable, Sendable, Codable {
    var id: UUID
    var sourceImageID: UUID?
    var rawText: String
    var createdAt: Date
    var updatedAt: Date
    var status: OCRDraftStatus
    var taskDrafts: [OCRImportTaskDraft]
    var projectDrafts: [OCRImportProjectDraft]

    nonisolated init(
        id: UUID = UUID(),
        sourceImageID: UUID? = nil,
        rawText: String,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now,
        status: OCRDraftStatus,
        taskDrafts: [OCRImportTaskDraft] = [],
        projectDrafts: [OCRImportProjectDraft] = []
    ) {
        self.id = id
        self.sourceImageID = sourceImageID
        self.rawText = rawText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
        self.taskDrafts = taskDrafts
        self.projectDrafts = projectDrafts
    }
}

enum OCRImportDraftParser {
    nonisolated static func parse(rawText: String, now: Date = Date.now) -> OCRImportDraft {
        let lines = normalizedLines(from: rawText)
        guard lines.isEmpty == false else {
            return OCRImportDraft(
                rawText: rawText,
                createdAt: now,
                updatedAt: now,
                status: .failed
            )
        }

        let projectDrafts = parseProjectDrafts(from: lines)
        let consumedProjectLines = Set(projectDrafts.flatMap { project in
            [project.sourceText].compactMap { $0 } + project.taskDrafts.compactMap(\.sourceText)
        })
        let taskDrafts = lines
            .filter { consumedProjectLines.contains($0) == false }
            .map { OCRImportTaskDraft(title: $0, sourceText: $0) }

        return OCRImportDraft(
            rawText: rawText,
            createdAt: now,
            updatedAt: now,
            status: .needsReview,
            taskDrafts: taskDrafts,
            projectDrafts: projectDrafts
        )
    }

    private nonisolated static func parseProjectDrafts(from lines: [String]) -> [OCRImportProjectDraft] {
        var projects: [OCRImportProjectDraft] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            guard let projectName = projectTitle(from: line) else {
                index += 1
                continue
            }

            var tasks: [OCRImportTaskDraft] = []
            var next = index + 1
            while next < lines.count, projectTitle(from: lines[next]) == nil {
                tasks.append(OCRImportTaskDraft(title: lines[next], sourceText: lines[next]))
                next += 1
            }

            if tasks.isEmpty == false {
                projects.append(
                    OCRImportProjectDraft(
                        name: projectName,
                        taskDrafts: tasks,
                        sourceText: line
                    )
                )
                index = next
            } else {
                index += 1
            }
        }

        return projects
    }

    private nonisolated static func normalizedLines(from rawText: String) -> [String] {
        rawText
            .components(separatedBy: .newlines)
            .map(normalizedLine)
            .filter { $0.isEmpty == false }
    }

    private nonisolated static func normalizedLine(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["- ", "• ", "* ", "· ", "☐ ", "□ ", "✅ ", "✓ "]
        for prefix in prefixes where result.hasPrefix(prefix) {
            result.removeFirst(prefix.count)
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let match = result.range(
            of: #"^\d+[\.\)、\)]\s*"#,
            options: .regularExpression
        ) {
            result.removeSubrange(match)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func projectTitle(from line: String) -> String? {
        let markers = ["项目：", "项目:", "Project:", "project:"]
        for marker in markers where line.hasPrefix(marker) {
            let name = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }

        guard line.hasSuffix(":") || line.hasSuffix("：") else { return nil }
        let name = String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
