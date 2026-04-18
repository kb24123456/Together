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
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )
}
