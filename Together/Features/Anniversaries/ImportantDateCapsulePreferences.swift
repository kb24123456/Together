import Foundation

enum ImportantDateCapsuleCountMode: String, Codable, Hashable, Sendable {
    case next
    case elapsed
}

enum ImportantDateCapsulePreferences {
    static func selectedID(from storageString: String?) -> UUID? {
        guard let storageString, storageString.isEmpty == false else { return nil }
        return UUID(uuidString: storageString)
    }

    static func storageString(for selectedID: UUID?) -> String {
        selectedID?.uuidString ?? ""
    }

    static func decodeCountModes(_ storageString: String) -> [UUID: ImportantDateCapsuleCountMode] {
        guard let data = storageString.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return rawValues.reduce(into: [:]) { result, entry in
            guard let id = UUID(uuidString: entry.key),
                  let mode = ImportantDateCapsuleCountMode(rawValue: entry.value) else {
                return
            }
            result[id] = mode
        }
    }

    static func encodeCountModes(_ countModes: [UUID: ImportantDateCapsuleCountMode]) -> String {
        let rawValues = Dictionary(uniqueKeysWithValues: countModes.map { id, mode in
            (id.uuidString, mode.rawValue)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rawValues) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

enum ImportantDateCapsuleSelection {
    static func displayedID(
        candidateIDs: [UUID],
        userSelectedID: UUID?,
        autoHighlightID: UUID?,
        suppressedAutoHighlightID: UUID?
    ) -> UUID? {
        guard candidateIDs.isEmpty == false else { return nil }
        let validIDs = Set(candidateIDs)
        let userSelectedID = userSelectedID.flatMap { validIDs.contains($0) ? $0 : nil }
        let autoHighlightID = autoHighlightID.flatMap { validIDs.contains($0) ? $0 : nil }
        let suppressedAutoHighlightID = suppressedAutoHighlightID.flatMap { validIDs.contains($0) ? $0 : nil }

        if let autoHighlightID, suppressedAutoHighlightID != autoHighlightID {
            return autoHighlightID
        }
        if let userSelectedID {
            return userSelectedID
        }
        return candidateIDs.first
    }

    static func shouldClearSuppressedAutoHighlightID(
        _ suppressedAutoHighlightID: UUID?,
        currentAutoHighlightID: UUID?
    ) -> Bool {
        guard let suppressedAutoHighlightID else { return false }
        return suppressedAutoHighlightID != currentAutoHighlightID
    }
}
