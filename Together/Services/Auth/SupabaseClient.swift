import Foundation
import Supabase

/// Supabase 客户端单例
/// anonKey 是公开的（通过 RLS 保护数据），不需要保密
/// nonisolated(unsafe) 允许从任意 actor 访问（SupabaseClient 内部已线程安全）
enum SupabaseClientProvider: Sendable {

    private nonisolated(unsafe) static let projectURL = URL(string: "https://nxielmwdoiwiwhzczrmt.supabase.co")!
    private nonisolated(unsafe) static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im54aWVsbXdkb2l3aXdoemN6cm10Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYyNTc5MDgsImV4cCI6MjA5MTgzMzkwOH0.fXFkOsnIfETVqnk5okY5OYe_F_VwQ6K-0fzCD0tq3EQ"

    nonisolated(unsafe) static let shared = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey,
        options: .init(
            db: .init(
                encoder: isoEncoder,
                decoder: isoDecoder
            ),
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )

    // MARK: - Explicit ISO8601 Date coding
    //
    // The Supabase Swift SDK's default encoder/decoder use ISO8601-like custom
    // strategies internally (see PostgREST/Defaults.swift → JSON{En,De}coder.supabase()).
    // Re-declare them here at the application layer so:
    //   1. Date wire format stays pinned if the SDK changes its internal default.
    //   2. Decoder accepts all shapes PostgREST may emit (fractional-second ISO8601,
    //      no-fraction ISO8601, and PostgreSQL's space-separated "2026-04-19 11:17:11.847+00"
    //      which can surface from views / RPC responses).

    nonisolated(unsafe) static let isoEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }()

    nonisolated(unsafe) static let isoDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first (PostgREST's dominant shape).
            let isoFraction = ISO8601DateFormatter()
            isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFraction.date(from: raw) { return date }

            // Plain ISO8601 without fractional seconds.
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: raw) { return date }

            // PostgreSQL native output: "2026-04-19 11:17:11.847+00" (space, not T).
            let pgFormatter = DateFormatter()
            pgFormatter.locale = Locale(identifier: "en_US_POSIX")
            pgFormatter.timeZone = TimeZone(identifier: "UTC")
            for pattern in [
                "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
                "yyyy-MM-dd HH:mm:ss.SSSXXXXX",
                "yyyy-MM-dd HH:mm:ssXXXXX",
                "yyyy-MM-dd"  // bare date column (pre-migration-019 rows, if any replay)
            ] {
                pgFormatter.dateFormat = pattern
                if let date = pgFormatter.date(from: raw) { return date }
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(raw)"
            )
        }
        return decoder
    }()
}
