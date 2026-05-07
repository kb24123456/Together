import Foundation

struct AnniversaryWidgetSnapshot: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case isPaired
        case title
        case startDate
        case daysTogether
        case startDateText
        case startDateLongText
        case countdownDays
        case nextMilestoneDays
        case avatars
    }

    var generatedAt: Date
    var isPaired: Bool
    var title: String
    var startDate: Date?
    var daysTogether: Int
    var startDateText: String
    var startDateLongText: String
    var countdownDays: Int?
    var nextMilestoneDays: Int?
    var avatars: [AnniversaryWidgetAvatarSnapshot]

    nonisolated init(
        generatedAt: Date,
        isPaired: Bool,
        title: String,
        startDate: Date?,
        daysTogether: Int,
        startDateText: String,
        startDateLongText: String,
        countdownDays: Int?,
        nextMilestoneDays: Int?,
        avatars: [AnniversaryWidgetAvatarSnapshot]
    ) {
        self.generatedAt = generatedAt
        self.isPaired = isPaired
        self.title = title
        self.startDate = startDate
        self.daysTogether = daysTogether
        self.startDateText = startDateText
        self.startDateLongText = startDateLongText
        self.countdownDays = countdownDays
        self.nextMilestoneDays = nextMilestoneDays
        self.avatars = avatars
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        isPaired = try container.decode(Bool.self, forKey: .isPaired)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        daysTogether = try container.decode(Int.self, forKey: .daysTogether)
        startDateText = try container.decode(String.self, forKey: .startDateText)
        startDateLongText = try container.decodeIfPresent(String.self, forKey: .startDateLongText) ?? startDateText
        countdownDays = try container.decodeIfPresent(Int.self, forKey: .countdownDays)
        nextMilestoneDays = try container.decodeIfPresent(Int.self, forKey: .nextMilestoneDays)
        avatars = try container.decodeIfPresent([AnniversaryWidgetAvatarSnapshot].self, forKey: .avatars) ?? []
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(isPaired, forKey: .isPaired)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encode(daysTogether, forKey: .daysTogether)
        try container.encode(startDateText, forKey: .startDateText)
        try container.encode(startDateLongText, forKey: .startDateLongText)
        try container.encodeIfPresent(countdownDays, forKey: .countdownDays)
        try container.encodeIfPresent(nextMilestoneDays, forKey: .nextMilestoneDays)
        try container.encode(avatars, forKey: .avatars)
    }

    nonisolated static var empty: AnniversaryWidgetSnapshot {
        AnniversaryWidgetSnapshot(
            generatedAt: .now,
            isPaired: false,
            title: "双人纪念日",
            startDate: nil,
            daysTogether: 0,
            startDateText: "",
            startDateLongText: "",
            countdownDays: nil,
            nextMilestoneDays: nil,
            avatars: []
        )
    }
}

struct AnniversaryWidgetAvatarSnapshot: Codable, Equatable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case systemName
        case imageData
        case tintIndex
    }

    let id: UUID
    var displayName: String
    var systemName: String
    var imageData: Data?
    var tintIndex: Int

    nonisolated init(id: UUID, displayName: String, systemName: String, imageData: Data?, tintIndex: Int) {
        self.id = id
        self.displayName = displayName
        self.systemName = systemName
        self.imageData = imageData
        self.tintIndex = tintIndex
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        systemName = try container.decode(String.self, forKey: .systemName)
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        tintIndex = try container.decode(Int.self, forKey: .tintIndex)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(systemName, forKey: .systemName)
        try container.encodeIfPresent(imageData, forKey: .imageData)
        try container.encode(tintIndex, forKey: .tintIndex)
    }
}

struct AnniversaryWidgetSnapshotStore {
    private let containerURL: URL?

    nonisolated init(
        containerURL: URL? = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TodayWidgetConstants.appGroupIdentifier
        )
    ) {
        self.containerURL = containerURL
    }

    nonisolated func read() throws -> AnniversaryWidgetSnapshot {
        guard let fileURL else { return .empty }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.anniversaryWidget.decode(AnniversaryWidgetSnapshot.self, from: data)
    }

    nonisolated var diagnosticFilePath: String {
        fileURL?.path ?? "<missing app group container>"
    }

    nonisolated var fileExistsForDiagnostics: Bool {
        guard let fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    private nonisolated var fileURL: URL? {
        containerURL?.appending(path: TodayWidgetConstants.anniversarySnapshotFileName)
    }
}

extension AnniversaryWidgetSnapshot {
    nonisolated func resolved(for referenceDate: Date, calendar: Calendar = .current) -> AnniversaryWidgetSnapshot {
        guard let startDate else {
            return self
        }

        let referenceDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.startOfDay(for: startDate)
        let resolvedDays = max(0, calendar.dateComponents([.day], from: startDay, to: referenceDay).day ?? daysTogether)

        return AnniversaryWidgetSnapshot(
            generatedAt: generatedAt,
            isPaired: isPaired,
            title: title,
            startDate: startDate,
            daysTogether: resolvedDays,
            startDateText: startDateText,
            startDateLongText: startDateLongText,
            countdownDays: Self.nextAnnualCountdownDays(from: startDate, referenceDate: referenceDate, calendar: calendar),
            nextMilestoneDays: max(100, ((resolvedDays / 100) + 1) * 100),
            avatars: avatars
        )
    }

    private nonisolated static func nextAnnualCountdownDays(
        from startDate: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int? {
        let today = calendar.startOfDay(for: referenceDate)
        let month = calendar.component(.month, from: startDate)
        let day = calendar.component(.day, from: startDate)
        var year = calendar.component(.year, from: today)

        for _ in 0..<5 {
            if let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.month, from: candidate) == month,
               calendar.component(.day, from: candidate) == day {
                let target = calendar.startOfDay(for: candidate)
                if target >= today {
                    return max(0, calendar.dateComponents([.day], from: today, to: target).day ?? 0)
                }
            }
            year += 1
        }

        return nil
    }
}

private extension JSONDecoder {
    nonisolated static var anniversaryWidget: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
