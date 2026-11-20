// 对标 software/network/proxy/session/（auth.py + client.py + store.py）
// 随机IP官方后端：设备指纹、会话令牌、额度同步、代理提取、卡密激活。
// v5.0.0 起改为 Bearer 鉴权（access_token），免费试用下线。

import Foundation

public let authTrialEndpoint = "https://api-wjx.hungrym0.com/api/auth/trial"
public let authSessionEndpoint = "https://api-wjx.hungrym0.com/api/auth/session"
public let authBonusClaimEndpoint = "https://api-wjx.hungrym0.com/api/bonus"
public let cardRedeemEndpoint = "https://api-wjx.hungrym0.com/api/cards/redeem"

public struct RandomIPSession: Codable, Sendable {
    public var deviceId: String = ""
    public var userId: Int = 0
    /// Bearer access_token（官方 v5 字段 access_token，旧字段 token 兼容）。
    public var token: String = ""
    public var remainingQuota: Double = 0
    public var totalQuota: Double = 0
    public var usedQuota: Double = 0
    public var quotaKnown: Bool = false
    public var activatedAt: Double = 0

    public init() {}

    public var isComplete: Bool {
        !deviceId.isEmpty && userId > 0
    }

    /// 具备完整凭据（user_id + access_token），可直接调用需鉴权接口。
    public var isReady: Bool {
        userId > 0 && !token.isEmpty
    }

    /// 会话状态：ready / legacy / anonymous，对齐官方 _session_state_name。
    public var stateName: String {
        if isReady { return "ready" }
        return userId > 0 ? "legacy" : "anonymous"
    }
}

public enum RandomIPAuthError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverDetail(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "随机IP未激活，请使用额度卡密激活"
        case .invalidResponse: return "随机IP服务响应异常"
        case .serverDetail(let detail): return Self.friendlyMessage(detail)
        case .network(let message): return "网络错误：\(message)"
        }
    }

    static func friendlyMessage(_ detail: String) -> String {
        let lower = detail.lowercased()
        if lower.hasPrefix("quota_exhausted") { return "随机IP额度已用完，请兑换卡密后重试" }
        if lower.contains("invalid_access_token") { return "登录状态已失效，请重新激活或刷新额度" }
        if lower.contains("not_authenticated") { return "随机IP未激活，请使用额度卡密激活" }
        if lower.contains("trial") { return "服务端已停止发放免费试用，请使用额度卡密激活" }
        if lower.contains("invalid_redeem_card_code") { return "卡密格式不正确，应为 16 位字母或数字" }
        if lower.hasPrefix("server_unavailable:") { return "服务端暂时不可用（\(String(detail.dropFirst("server_unavailable:".count)))）" }
        return detail.isEmpty ? "请求失败，请稍后重试" : detail
    }
}

/// 随机IP会话存储 + 后端客户端。
public final class RandomIPSessionStore: @unchecked Sendable {
    public static let shared = RandomIPSessionStore()

    private let lock = NSLock()
    private var session = RandomIPSession()
    private let storageKey = "surveycontroller.randomip.session"
    private let deviceKey = "surveycontroller.device-id"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(RandomIPSession.self, from: data) {
            session = stored
        }
    }

    /// 对标 get_device_id：设备稳定指纹（安装级 UUID）。
    public var deviceId: String {
        lock.lock()
        defer { lock.unlock() }
        if let existing = defaults.string(forKey: deviceKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: deviceKey)
        return created
    }

    public func readSession() -> RandomIPSession {
        lock.lock()
        defer { lock.unlock() }
        return session
    }

    public var hasAuthenticatedSession: Bool {
        readSession().isComplete
    }

    func setSession(_ newSession: RandomIPSession) {
        lock.lock()
        defer { lock.unlock() }
        session = newSession
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: storageKey)
        }
    }

    public func clearSession() {
        lock.lock()
        defer { lock.unlock() }
        session = RandomIPSession()
        defaults.removeObject(forKey: storageKey)
    }

    /// 对标 get_quota_snapshot。
    public func quotaSnapshot() -> (remaining: Double, total: Double, used: Double, known: Bool) {
        let current = readSession()
        return (current.remainingQuota, current.totalQuota, current.usedQuota, current.quotaKnown)
    }
}

/// 后端 API 客户端。
public final class BackendClient: @unchecked Sendable {
    public static let shared = BackendClient()

    let store: RandomIPSessionStore
    private let client: HTTPClient

    public init(store: RandomIPSessionStore = .shared, client: HTTPClient = .shared) {
        self.store = store
        self.client = client
    }

    /// 对齐官方 `_build_headers`：有令牌时带 Bearer，始终带设备 ID。
    /// 传空串表示"本次不要令牌"（激活卡密时用）。
    func requestHeaders(accessToken: String? = nil) -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Device-ID": store.deviceId,
        ]
        let token = accessToken ?? store.readSession().token
        if !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        return headers
    }

    func postJSON(
        _ urlString: String,
        body: [String: Any],
        timeout: TimeInterval = 15,
        accessToken: String? = nil
    ) async throws -> [String: Any] {
        do {
            let response = try await client.postJSON(
                urlString, json: body, headers: requestHeaders(accessToken: accessToken)
            )
            guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                throw RandomIPAuthError.invalidResponse
            }
            if response.statusCode == 200 { return payload }
            let detail = JSONCoercion.asTrimmedString(payload["detail"])
            throw RandomIPAuthError.serverDetail(detail)
        } catch let error as RandomIPAuthError {
            throw error
        } catch let error as TransportError {
            throw RandomIPAuthError.network(error.localizedDescription)
        }
    }

    /// GET + JSON 解析。v5 的 /api/auth/session 是 GET。
    func getJSON(_ urlString: String, timeout: TimeInterval = 15) async throws -> [String: Any] {
        do {
            let response = try await client.get(urlString, headers: requestHeaders())
            guard let payload = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
                throw RandomIPAuthError.invalidResponse
            }
            if response.statusCode == 200 { return payload }
            let detail = JSONCoercion.asTrimmedString(payload["detail"])
            throw RandomIPAuthError.serverDetail(detail)
        } catch let error as RandomIPAuthError {
            throw error
        } catch let error as TransportError {
            throw RandomIPAuthError.network(error.localizedDescription)
        }
    }

    /// 读取响应里的 Bearer 令牌（官方 access_token / token_type，兼容旧 token 字段）。
    func extractAccessToken(_ data: [String: Any], expected: String = "") -> String {
        var token = JSONCoercion.asTrimmedString(data["access_token"])
        if token.isEmpty { token = JSONCoercion.asTrimmedString(data["token"]) }
        guard !token.isEmpty else { return "" }
        let tokenType = JSONCoercion.asTrimmedString(data["token_type"]).lowercased()
        if !tokenType.isEmpty && tokenType != "bearer" { return "" }
        if !expected.isEmpty && token != expected { return "" }
        return token
    }

    func parseSessionPayload(_ data: [String: Any], fallback: RandomIPSession) -> RandomIPSession {
        var session = fallback
        session.deviceId = store.deviceId
        if data["user_id"] != nil {
            session.userId = JSONCoercion.asInt(data["user_id"])
        }
        let token = extractAccessToken(data)
        if !token.isEmpty { session.token = token }
        if let quota = quotaFields(data) {
            session.remainingQuota = quota.remaining
            session.totalQuota = quota.total
            session.usedQuota = quota.used
            session.quotaKnown = quota.known
        }
        if data["activated_at"] != nil {
            session.activatedAt = JSONCoercion.asDouble(data["activated_at"])
        }
        return session
    }

    func quotaFields(_ data: [String: Any]) -> (remaining: Double, total: Double, used: Double, known: Bool)? {
        var found = false
        var remaining = 0.0
        var total = 0.0
        var used = 0.0
        if data["remaining_quota"] != nil {
            remaining = JSONCoercion.asDouble(data["remaining_quota"]); found = true
        }
        if data["total_quota"] != nil {
            total = JSONCoercion.asDouble(data["total_quota"]); found = true
        }
        if data["used_quota"] != nil {
            used = JSONCoercion.asDouble(data["used_quota"]); found = true
        }
        return found ? (remaining, total, used, true) : nil
    }

    func applyQuotaPayload(_ data: [String: Any], to session: RandomIPSession) -> RandomIPSession {
        var updated = session
        if let quota = quotaFields(data) {
            updated.remainingQuota = quota.remaining
            updated.totalQuota = max(quota.total, quota.remaining)
            updated.usedQuota = quota.used
            updated.quotaKnown = quota.known
        }
        store.setSession(updated)
        return updated
    }

    /// 把会话响应落库（校验 user_id，保留已有令牌）。
    @discardableResult
    func storeSession(from payload: [String: Any], fallback: RandomIPSession) throws -> RandomIPSession {
        let session = parseSessionPayload(payload, fallback: fallback)
        guard session.userId > 0 else { throw RandomIPAuthError.invalidResponse }
        store.setSession(session)
        return session
    }

    /// 对标 ensure_authenticated_session_async：有令牌直接用，
    /// 旧会话用 user_id 换令牌，全新设备尝试领取（服务端停止发放会返回明确错误）。
    @discardableResult
    public func ensureSession() async throws -> RandomIPSession {
        let current = store.readSession()
        if !current.token.isEmpty { return current }
        var body: [String: Any] = [:]
        if current.userId > 0 { body["user_id"] = current.userId }
        let payload = try await postJSON(authTrialEndpoint, body: body, accessToken: "")
        return try storeSession(from: payload, fallback: current)
    }

    /// 兼容旧调用点。
    @discardableResult
    public func activateTrial() async throws -> RandomIPSession {
        try await ensureSession()
    }

    /// 对标 sync_quota_snapshot_from_server_async：有令牌走 GET /api/auth/session，
    /// 令牌失效时清空并重新换取；无令牌则回落旧的 trial 接口。
    @discardableResult
    public func syncQuotaFromServer() async throws -> RandomIPSession {
        let current = try requireAuthenticatedSession()
        if current.token.isEmpty {
            let payload = try await postJSON(authTrialEndpoint, body: ["user_id": current.userId], accessToken: "")
            return try storeSession(from: payload, fallback: current)
        }
        do {
            let payload = try await getJSON(authSessionEndpoint)
            return try storeSession(from: payload, fallback: current)
        } catch let error as RandomIPAuthError {
            if case .serverDetail(let detail) = error, detail.lowercased().contains("invalid_access_token") {
                var cleared = current
                cleared.token = ""
                store.setSession(cleared)
                return try await ensureSession()
            }
            throw error
        }
    }

    func requireAuthenticatedSession() throws -> RandomIPSession {
        let session = store.readSession()
        guard session.isComplete else { throw RandomIPAuthError.notAuthenticated }
        return session
    }

    /// 需要 Bearer 的接口：旧会话先自动换一次令牌。
    func requireReadySession() async throws -> RandomIPSession {
        let session = try requireAuthenticatedSession()
        return session.isReady ? session : try await ensureSession()
    }

    /// 对标 _extract_proxy_item。
    func extractProxyItem(_ data: [String: Any]) -> [String: Any]? {
        let host = JSONCoercion.asTrimmedString(data["host"])
        let port = JSONCoercion.asInt(data["port"], default: 0)
        let account = JSONCoercion.asTrimmedString(data["account"])
        let password = JSONCoercion.asTrimmedString(data["password"])
        guard !host.isEmpty, port > 0, !account.isEmpty, !password.isEmpty else { return nil }
        return [
            "host": host,
            "port": port,
            "account": account,
            "password": password,
            "expire_at": JSONCoercion.asTrimmedString(data["expire_at"]),
        ]
    }

    public struct ExtractedProxy {
        public let host: String
        public let port: Int
        public let account: String
        public let password: String
        public let expireAt: String

        /// 对标代理地址格式：host:port:account:password。
        public var address: String {
            "\(host):\(port):\(account):\(password)"
        }
    }

    /// 对标 extract_proxy_async：提取代理（单个）。
    public func extractProxy(
        minute: Int,
        pool: String,
        area: String?,
        upstream: String = "default"
    ) async throws -> ExtractedProxy {
        let session = try await requireReadySession()
        var body: [String: Any] = [
            "user_id": session.userId,
            "minute": minute,
            "pool": pool.trimmingCharacters(in: .whitespaces),
        ]
        let upstreamValue = upstream.trimmingCharacters(in: .whitespaces).lowercased()
        if !upstreamValue.isEmpty { body["upstream"] = upstreamValue }
        if let area, !area.trimmingCharacters(in: .whitespaces).isEmpty {
            body["area"] = area.trimmingCharacters(in: .whitespaces)
        }

        let data = try await postJSON(ipExtractEndpoint, body: body, timeout: 30)
        guard let item = extractProxyItem(data) else {
            throw RandomIPAuthError.invalidResponse
        }
        _ = applyQuotaPayload(data, to: session)
        return ExtractedProxy(
            host: item["host"] as? String ?? "",
            port: item["port"] as? Int ?? 0,
            account: item["account"] as? String ?? "",
            password: item["password"] as? String ?? "",
            expireAt: item["expire_at"] as? String ?? ""
        )
    }

    /// 对标 redeem_card_async：卡密激活（无令牌时）或充值（有令牌时）。
    /// 激活路径由客户端生成 64 位 hex `activation_token`，服务端回显的 access_token 必须一致。
    public func redeemCard(cardCode: String) async throws -> (redeemed: Bool, remaining: Double, detail: String) {
        let current = store.readSession()
        let activating = current.token.isEmpty
        let normalized = cardCode.trimmingCharacters(in: .whitespaces)
        var body: [String: Any] = ["card_code": normalized]
        var activationToken = ""
        if activating {
            activationToken = Self.randomHexToken()
            body["activation_token"] = activationToken
            if current.userId > 0 { body["user_id"] = current.userId }
        }
        let payload = try await postJSON(
            cardRedeemEndpoint, body: body, accessToken: activating ? "" : nil
        )
        let updated: RandomIPSession
        if activating {
            let token = extractAccessToken(payload, expected: activationToken)
            // 返回了 access_token 就必须与本地 activation_token 一致（对齐官方校验）
            if token.isEmpty && !JSONCoercion.asTrimmedString(payload["access_token"]).isEmpty {
                throw RandomIPAuthError.serverDetail("invalid_response:access_token")
            }
            var session = parseSessionPayload(payload, fallback: current)
            if !token.isEmpty { session.token = token }
            guard session.userId > 0 else { throw RandomIPAuthError.invalidResponse }
            store.setSession(session)
            updated = session
        } else {
            updated = applyQuotaPayload(payload, to: current)
        }
        return (
            JSONCoercion.asBool(payload["redeemed"]),
            updated.remainingQuota,
            JSONCoercion.asTrimmedString(payload["detail"])
        )
    }

    /// 生成 64 位十六进制激活令牌，对齐官方 `secrets.token_hex(32)`。
    static func randomHexToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var rng = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0...255, using: &rng)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
