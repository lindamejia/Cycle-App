import Foundation

enum BackendError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("error.notConfigured")
        case .http(_, let message): return message
        case .decoding: return L("error.generic")
        }
    }

    var isInvalidCode: Bool {
        if case .http(_, let m) = self { return m.contains("invalid_code") }
        return false
    }
}

/// Tiny Supabase REST client (anonymous auth, RPC, insert, Edge Functions). No SDK dependency.
actor SupabaseClient {
    static let shared = SupabaseClient()

    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: String
    }

    private struct AuthResponse: Decodable {
        struct User: Decodable { let id: String }
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
    }

    private let keychainAccount = "supabase"
    private var session: Session?

    private init() {
        if let data = Keychain.load(account: keychainAccount) {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    var hasSession: Bool { session != nil }

    // MARK: Auth

    func ensureSession() async throws -> Session {
        guard Config.isBackendConfigured else { throw BackendError.notConfigured }
        if let s = session, s.expiresAt.timeIntervalSinceNow > 120 { return s }
        if let s = session, let refreshed = try? await refresh(s) { return refreshed }
        return try await signInAnonymously()
    }

    private func signInAnonymously() async throws -> Session {
        let data = try await send("/auth/v1/signup", body: Data("{}".utf8), token: nil)
        return try store(data)
    }

    private func refresh(_ s: Session) async throws -> Session {
        let body = try JSONEncoder().encode(["refresh_token": s.refreshToken])
        let data = try await send("/auth/v1/token?grant_type=refresh_token", body: body, token: nil)
        return try store(data)
    }

    private func store(_ data: Data) throws -> Session {
        guard let r = try? JSONDecoder().decode(AuthResponse.self, from: data) else { throw BackendError.decoding }
        let s = Session(accessToken: r.access_token, refreshToken: r.refresh_token,
                        expiresAt: Date().addingTimeInterval(r.expires_in), userID: r.user.id)
        session = s
        if let encoded = try? JSONEncoder().encode(s) { Keychain.save(encoded, account: keychainAccount) }
        return s
    }

    func signOut() {
        session = nil
        Keychain.delete(account: keychainAccount)
    }

    // MARK: Data

    func rpc(_ function: String, params: [String: Any] = [:]) async throws -> Data {
        let s = try await ensureSession()
        let body = try JSONSerialization.data(withJSONObject: params)
        return try await send("/rest/v1/rpc/\(function)", body: body, token: s.accessToken)
    }

    func insert(_ table: String, json: Data) async throws {
        let s = try await ensureSession()
        _ = try await send("/rest/v1/\(table)", body: json, token: s.accessToken,
                           headers: ["Prefer": "return=minimal,resolution=ignore-duplicates"])
    }

    func invokeFunction(_ name: String, body: Data) async throws -> Data {
        let s = try await ensureSession()
        return try await send("/functions/v1/\(name)", body: body, token: s.accessToken, timeout: 120)
    }

    // MARK: Transport

    private func send(_ path: String, body: Data, token: String?, headers: [String: String] = [:],
                      timeout: TimeInterval = 30) async throws -> Data {
        guard let url = URL(string: Config.supabaseURL + path) else { throw BackendError.notConfigured }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401, token != nil { session = nil } // force a fresh session next time
            throw BackendError.http(status, String(data: data, encoding: .utf8) ?? "HTTP \(status)")
        }
        return data
    }
}
