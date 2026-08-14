// 对标 software/network/proxy/session/（auth.py + client.py）
// 随机IP官方后端：设备指纹、试用领取、额度同步、代理提取、卡密兑换。

import Foundation

public let authTrialEndpoint = "https://api-wjx.hungrym0.com/api/auth/trial"
public let authBonusClaimEndpoint = "https://api-wjx.hungrym0.com/api/bonus"
public let cardRedeemEndpoint = "https://api-wjx.hungrym0.com/api/cards/redeem"

public struct RandomIPSession: Codable, Sendable {
    public var deviceId: String = ""
    public var userId: Int = 0
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
}

public enum RandomIPAuthError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case serverDetail(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "随机IP未认证，请先领取试用或兑换卡密"
        case .invalidResponse: return "随机IP服务响应异常"
        case .serverDetail(let detail): return Self.friendlyMessage(detail)
        case .network(let message): return "网络错误：\(message)"
        }
    }

    static func friendlyMessage(_ detail: String) -> String {
        if detail.hasPrefix("quota_exhausted") { return "随机IP额度已用完，请兑换卡密后重试" }
        if detail.hasPrefix("not_authenticated") { return "随机IP会话已失效，请重新领取试用" }
        if detail.hasPrefix("server_unavailable:") { return "服务端暂时不可用（\(String(detail.dropFirst("server_unavailable:".count)))）" }
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

    private let store: RandomIPSessionStore
    private let client: HTTPClient

    public init(store: RandomIPSessionStore = .shared, client: HTTPClient = .shared) {
        self.store = store
        self.client = client
    }

    func requestHeaders() -> [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-Device-ID": store.deviceId,
        ]
    }

    func postJSON(_ urlString: String, body: [String: Any], timeout: TimeInterval = 15) async throws -> [String: Any] {
        do {
            let response = try await client.postJSON(urlString, json: body, headers: requestHeaders())
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

    func parseSessionPayload(_ data: [String: Any], fallback: RandomIPSession) -> RandomIPSession {
        var session = fallback
        session.deviceId = store.deviceId
        if data["user_id"] != nil {
            session.userId = JSONCoercion.asInt(data["user_id"])
        }
        session.token = JSONCoercion.asString(data["token"])
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
            updated.totalQuota = quota.total
            updated.usedQuota = quota.used
            updated.quotaKnown = quota.known
        }
        store.setSession(updated)
        return updated
    }

    /// 对标 activate_trial_async：领取试用（同时刷新额度）。
    @discardableResult
    public func activateTrial() async throws -> RandomIPSession {
        let payload = try await postJSON(authTrialEndpoint, body: [:])
        let session = parseSessionPayload(payload, fallback: RandomIPSession())
        guard session.isComplete else { throw RandomIPAuthError.invalidResponse }
        store.setSession(session)
        return session
    }

    /// 对标 sync_quota_snapshot_from_server_async。
    @discardableResult
    public func syncQuotaFromServer() async throws -> RandomIPSession {
        let current = try requireAuthenticatedSession()
        let payload = try await postJSON(authTrialEndpoint, body: [:])
        let refreshed = parseSessionPayload(payload, fallback: current)
        store.setSession(refreshed)
        return refreshed
    }

    func requireAuthenticatedSession() throws -> RandomIPSession {
        let session = store.readSession()
        guard session.isComplete else { throw RandomIPAuthError.notAuthenticated }
        return session
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
        let session = try requireAuthenticatedSession()
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

    /// 对标 redeem_card_async：卡密兑换。
    public func redeemCard(cardCode: String) async throws -> (redeemed: Bool, remaining: Double, detail: String) {
        let session = try requireAuthenticatedSession()
        let payload = try await postJSON(cardRedeemEndpoint, body: [
            "user_id": session.userId,
            "card_code": cardCode.trimmingCharacters(in: .whitespaces),
        ])
        let updated = applyQuotaPayload(payload, to: session)
        return (
            JSONCoercion.asBool(payload["redeemed"]),
            updated.remainingQuota,
            JSONCoercion.asTrimmedString(payload["detail"])
        )
    }
}
