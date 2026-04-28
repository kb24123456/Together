import Foundation
import Supabase

struct SoloSpaceUpsertDTO: Codable, Sendable {
    let id: UUID?
    let ownerUserID: UUID
    let type: String
    let displayName: String
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, status
        case ownerUserID = "owner_user_id"
        case displayName = "display_name"
        case updatedAt = "updated_at"
    }

    static func newSingle(ownerUserID: UUID, displayName: String, now: Date = .now) -> SoloSpaceUpsertDTO {
        SoloSpaceUpsertDTO(
            id: nil,
            ownerUserID: ownerUserID,
            type: "single",
            displayName: displayName,
            status: "active",
            updatedAt: now
        )
    }
}

struct DeviceInstallationUpsertDTO: Codable, Sendable {
    let userID: UUID
    let installationID: UUID
    let platform: String
    let deviceName: String?
    let appVersion: String?
    let buildNumber: String?
    let pushToken: String?
    let isActive: Bool
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case platform
        case userID = "user_id"
        case installationID = "installation_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case pushToken = "push_token"
        case isActive = "is_active"
        case lastSeenAt = "last_seen_at"
    }

    init(
        userID: UUID,
        installationID: UUID,
        platform: SoloDevicePlatform,
        deviceName: String?,
        appVersion: String?,
        buildNumber: String?,
        pushToken: String? = nil,
        now: Date = .now
    ) {
        self.userID = userID
        self.installationID = installationID
        self.platform = platform.rawValue
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.pushToken = pushToken
        self.isActive = true
        self.lastSeenAt = now
    }
}

struct EnsureSingleSpaceRPCParams: Encodable, Sendable {
    let userID: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userID = "p_user_id"
        case displayName = "p_display_name"
    }
}

struct SoloRemoteSnapshot: Sendable {
    var tasks: [TaskDTO] = []
    var taskLists: [TaskListDTO] = []
    var projects: [ProjectDTO] = []
    var projectSubtasks: [ProjectSubtaskDTO] = []
    var periodicTasks: [PeriodicTaskDTO] = []
    var importantDates: [ImportantDateDTO] = []
}

protocol SupabaseSoloRemoteGatewayProtocol: Sendable {
    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID
    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws
    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot
    func upsert(snapshot: SoloRemoteSnapshot) async throws
}

actor SupabaseSoloRemoteGateway: SupabaseSoloRemoteGatewayProtocol {
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseClientProvider.shared) {
        self.client = client
    }

    func ensureSingleSpace(userID: UUID, displayName: String) async throws -> UUID {
        struct SpaceRow: Decodable { let id: UUID }

        let row: SpaceRow = try await client
            .rpc(
                "ensure_single_space",
                params: EnsureSingleSpaceRPCParams(userID: userID, displayName: displayName)
            )
            .single()
            .execute()
            .value

        return row.id
    }

    func registerDevice(_ dto: DeviceInstallationUpsertDTO) async throws {
        try await client.from("device_installations")
            .upsert(dto, onConflict: "user_id,installation_id")
            .execute()
    }

    func fetchSnapshot(spaceID: UUID, since: Date?) async throws -> SoloRemoteSnapshot {
        var snapshot = SoloRemoteSnapshot()
        let sinceDate = since ?? .distantPast
        let sinceISO = ISO8601DateFormatter().string(from: sinceDate)

        snapshot.taskLists = try await client.from("task_lists").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.projects = try await client.from("projects").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.projectSubtasks = try await client.from("project_subtasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.periodicTasks = try await client.from("periodic_tasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.importantDates = try await client.from("important_dates").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        snapshot.tasks = try await client.from("tasks").select().eq("space_id", value: spaceID.uuidString).gte("updated_at", value: sinceISO).execute().value
        return snapshot
    }

    func upsert(snapshot: SoloRemoteSnapshot) async throws {
        if snapshot.taskLists.isEmpty == false {
            try await client.from("task_lists").upsert(snapshot.taskLists, onConflict: "id").execute()
        }
        if snapshot.projects.isEmpty == false {
            try await client.from("projects").upsert(snapshot.projects, onConflict: "id").execute()
        }
        if snapshot.projectSubtasks.isEmpty == false {
            try await client.from("project_subtasks").upsert(snapshot.projectSubtasks, onConflict: "id").execute()
        }
        if snapshot.periodicTasks.isEmpty == false {
            try await client.from("periodic_tasks").upsert(snapshot.periodicTasks, onConflict: "id").execute()
        }
        if snapshot.importantDates.isEmpty == false {
            try await client.from("important_dates").upsert(snapshot.importantDates, onConflict: "id").execute()
        }
        if snapshot.tasks.isEmpty == false {
            try await client.from("tasks").upsert(snapshot.tasks, onConflict: "id").execute()
        }
    }

}
