// 对标 software/network/session_policy.py + network/proxy/pool/pool.py + api/provider.py（custom 源）
// 代理池：租约获取/释放/冷却/TTL；官方源与自定义 API 源两种提取方式。

import Foundation

/// 对标 ProxyLease。
public struct ProxyLease: @unchecked Sendable, Equatable {
    public let address: String
    public let expireAt: Double
    /// 剩余有效期是否足够（对标 proxy_lease_has_sufficient_ttl）
    public let ttlSufficient: Bool

    public init(address: String, expireAt: Double, ttlSufficient: Bool = true) {
        self.address = address
        self.expireAt = expireAt
        self.ttlSufficient = ttlSufficient
    }
}

public enum ProxySourceKind: String, Sendable {
    case `default` = "default"
    case benefit = "benefit"
    case custom = "custom"
}

/// 代理提供方协议（官方后端 / 自定义 API）。
public protocol ProxyProvider: Sendable {
    /// 对标 fetch_proxy_batch_async：提取一批代理地址（host:port 或 host:port:user:pass）。
    func fetchBatch(minute: Int, pool: String, area: String?, count: Int) async throws -> [ProxyLease]
}

/// 官方后端源（对标 default 源）。
public struct OfficialProxyProvider: ProxyProvider {
    let backend: BackendClient
    let upstream: String

    public init(backend: BackendClient = .shared, upstream: String = "default") {
        self.backend = backend
        self.upstream = upstream
    }

    public func fetchBatch(minute: Int, pool: String, area: String?, count: Int) async throws -> [ProxyLease] {
        var leases: [ProxyLease] = []
        for _ in 0..<max(1, count) {
            let proxy = try await backend.extractProxy(minute: minute, pool: pool, area: area, upstream: upstream)
            let expireAt = ISO8601ToEpochSeconds(proxy.expireAt)
            leases.append(ProxyLease(
                address: proxy.address,
                expireAt: expireAt,
                ttlSufficient: expireAt <= 0 || expireAt - Date().timeIntervalSince1970 > 60
            ))
        }
        return leases
    }

    func ISO8601ToEpochSeconds(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date.timeIntervalSince1970 }
        return 0
    }
}

/// 自定义 API 源（对标 custom 源：GET 用户 API，递归解析出代理）。
public struct CustomProxyProvider: ProxyProvider {
    let apiUrl: String
    let client: HTTPClient

    public init(apiUrl: String, client: HTTPClient = .shared) {
        self.apiUrl = apiUrl
        self.client = client
    }

    public func fetchBatch(minute: Int, pool: String, area: String?, count: Int) async throws -> [ProxyLease] {
        guard let url = URL(string: apiUrl), url.scheme != nil else {
            throw TransportError.network("自定义代理 API 地址无效")
        }
        let response = try await client.get(apiUrl, headers: ["Accept": "*/*"])
        try response.raiseForStatus()
        var addresses: [String] = []
        if let payload = try? JSONSerialization.jsonObject(with: response.body) {
            collectAddresses(payload, into: &addresses)
        } else {
            // 纯文本：按行/逗号切分
            addresses = response.text
                .split(whereSeparator: { "\n\r,;".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        var seen: Set<String> = []
        let leases = addresses
            .filter { seen.insert($0).inserted }
            .prefix(proxyMaxProxies)
            .map { ProxyLease(address: $0, expireAt: 0) }
        guard !leases.isEmpty else {
            throw TransportError.network("自定义代理 API 未返回可用代理")
        }
        return Array(leases)
    }

    /// 对标 _parse_proxy_payload：递归提取形如 host:port[:user:pass] 的字符串。
    func collectAddresses(_ payload: Any, into addresses: inout [String]) {
        if let text = payload as? String {
            let candidate = text.trimmingCharacters(in: .whitespaces)
            if looksLikeAddress(candidate) {
                addresses.append(candidate)
            } else {
                addresses.append(contentsOf: candidate
                    .split(whereSeparator: { "\n\r,;".contains($0) })
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter(looksLikeAddress))
            }
        } else if let list = payload as? [Any] {
            for item in list { collectAddresses(item, into: &addresses) }
        } else if let dict = payload as? [String: Any] {
            for key in ["data", "items", "proxies", "list", "result", "content"] {
                if let nested = dict[key] {
                    collectAddresses(nested, into: &addresses)
                }
            }
        }
    }

    func looksLikeAddress(_ text: String) -> Bool {
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let port = Int(parts[1]), (1...65535).contains(port) else { return false }
        return !parts[0].isEmpty
    }
}

/// 对标 session_policy 的代理池（actor 保证并发安全，替代 Python 锁）。
public actor ProxyPool {
    public static let cooldownSeconds: TimeInterval = 45
    public static let minTtlSeconds: TimeInterval = 60

    private var available: [ProxyLease] = []
    private var inUse: Set<String> = []
    private var blocked: Set<String> = []
    private var cooldowns: [String: Date] = [:]
    private var successful: Set<String> = []
    private let provider: ProxyProvider

    public init(provider: ProxyProvider) {
        self.provider = provider
    }

    public var availableCount: Int { available.count }

    /// 地区码（nil/空 = 不限制）；指定地区时默认源使用优质池（对标 _resolve_default_pool_by_area）。
    public private(set) var areaCode: String?

    /// 从任意执行域设置地区码。
    public func setAreaCode(_ code: String?) {
        areaCode = AreaService.normalizeAreaCode(code).isEmpty ? nil : AreaService.normalizeAreaCode(code)
    }

    /// 对标 acquire_submit_proxy：取可用租约，池空时提取一批。
    public func acquire() async throws -> ProxyLease {
        if let lease = popUsable() {
            inUse.insert(lease.address)
            return lease
        }
        let normalizedArea = AreaService.normalizeAreaCode(areaCode)
        let pool = normalizedArea.isEmpty
            ? proxyPoolOrdinary
            : (AreaService.resolveDefaultPool(areaCode: normalizedArea) ?? proxyPoolOrdinary)
        let fetched = try await provider.fetchBatch(
            minute: 1, pool: pool, area: normalizedArea.isEmpty ? nil : normalizedArea, count: 1
        )
        for lease in fetched where isUsable(lease) {
            available.append(lease)
        }
        guard let lease = popUsable() else {
            throw SubmitProxyUnavailableError("随机IP暂不可用，请稍后重试")
        }
        inUse.insert(lease.address)
        return lease
    }

    /// 对标 release_submit_proxy：释放并回池（仍可用时复用）。
    public func release(_ lease: ProxyLease) {
        inUse.remove(lease.address)
        if isUsable(lease) {
            available.append(lease)
        }
    }

    /// 对标 mark_submit_proxy_success。
    public func markSuccess(_ lease: ProxyLease) {
        successful.insert(lease.address)
    }

    /// 对标 _mark_proxy_temporarily_bad：智能验证后冷却。
    public func markTemporarilyBad(_ lease: ProxyLease) {
        cooldowns[lease.address] = Date().addingTimeInterval(Self.cooldownSeconds)
        inUse.remove(lease.address)
    }

    func isUsable(_ lease: ProxyLease) -> Bool {
        if inUse.contains(lease.address) || blocked.contains(lease.address) { return false }
        if let until = cooldowns[lease.address], until > Date() { return false }
        if lease.expireAt > 0 {
            if Date().timeIntervalSince1970 >= lease.expireAt { return false }
            if lease.expireAt - Date().timeIntervalSince1970 < Self.minTtlSeconds { return false }
        }
        return true
    }

    func popUsable() -> ProxyLease? {
        while !available.isEmpty {
            let lease = available.removeFirst()
            if isUsable(lease) { return lease }
        }
        return nil
    }
}
