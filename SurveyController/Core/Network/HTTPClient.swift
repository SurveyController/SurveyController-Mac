// 对标 software/network/http/（httpx 封装）
// URLSession 封装：GET / POST 表单 / POST JSON，支持 per-session 代理。

import Foundation

public struct HTTPResponse: @unchecked Sendable {
    public let statusCode: Int
    public let body: Data
    public let text: String

    public var isSuccess: Bool { (200..<300).contains(statusCode) }

    public func raiseForStatus() throws {
        guard isSuccess else {
            throw NSError(domain: "HTTPClient", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
        }
    }
}

public enum TransportError: Error, LocalizedError {
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .network(let message): return message
        }
    }
}

/// HTTP 客户端（对标 software.network.http 的 aget/apost）。
public final class HTTPClient: @unchecked Sendable {
    public static let shared = HTTPClient()

    private let session: URLSession
    private var proxySessions: [String: URLSession] = [:]
    private let lock = NSLock()

    public init(timeoutSeconds: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds * 3
        configuration.httpAdditionalHeaders = nil
        session = URLSession(configuration: configuration)
    }

    /// 对标 proxies= 参数：同代理地址复用会话。
    func sessionForProxy(_ proxyAddress: String?) -> URLSession {
        guard let proxyAddress, !proxyAddress.isEmpty else { return session }
        lock.lock()
        defer { lock.unlock() }
        if let existing = proxySessions[proxyAddress] { return existing }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        // 支持协议前缀（http://user:pass@host:port 或 host:port）
        var proxyHost = proxyAddress
        var port: Int = 80
        for prefix in ["http://", "https://", "socks5://"] where proxyHost.hasPrefix(prefix) {
            proxyHost = String(proxyHost.dropFirst(prefix.count))
        }
        var host = proxyHost
        if let colonIndex = proxyHost.lastIndex(of: ":") {
            host = String(proxyHost[..<colonIndex])
            port = Int(proxyHost[proxyHost.index(after: colonIndex)...]) ?? port
        }
        // 内嵌认证信息拆出（URLSession 代理不支持 URL 内凭证，v0.1 忽略并记录于注释）
        let credentialsSeparator = host.range(of: "@")
        if let separator = credentialsSeparator {
            host = String(host[separator.upperBound...])
        }
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as AnyHashable: true,
            kCFNetworkProxiesHTTPProxy as AnyHashable: host,
            kCFNetworkProxiesHTTPPort as AnyHashable: port,
            kCFNetworkProxiesHTTPSEnable as AnyHashable: true,
            kCFNetworkProxiesHTTPSProxy as AnyHashable: host,
            kCFNetworkProxiesHTTPSPort as AnyHashable: port,
        ]
        let created = URLSession(configuration: configuration)
        proxySessions[proxyAddress] = created
        return created
    }

    func request(
        method: String,
        urlString: String,
        headers: [String: String],
        query: [String: String]? = nil,
        body: Data? = nil,
        proxyAddress: String? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(string: urlString) else {
            throw TransportError.network("无效 URL：\(urlString)")
        }
        if let query, !query.isEmpty {
            let ordered = query.sorted { $0.key < $1.key }
            let items = ordered.map { key, value in
                URLQueryItem(name: key, value: value)
            }
            if components.queryItems == nil {
                components.queryItems = items
            } else {
                components.queryItems! += items
            }
        }
        guard let url = components.url else {
            throw TransportError.network("无效 URL：\(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    public func get(
        _ urlString: String,
        headers: [String: String],
        proxyAddress: String? = nil
    ) async throws -> HTTPResponse {
        let request = try request(method: "GET", urlString: urlString, headers: headers, proxyAddress: proxyAddress)
        return try await send(request, proxyAddress: proxyAddress)
    }

    /// 对标 apost：查询参数 + urlencoded 表单体。
    public func postForm(
        _ urlString: String,
        query: [String: String],
        formData: [String: String],
        headers: [String: String],
        proxyAddress: String? = nil
    ) async throws -> HTTPResponse {
        var formHeaders = headers
        if formHeaders["Content-Type"] == nil {
            formHeaders["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        }
        let body = formData
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let request = try request(
            method: "POST", urlString: urlString, headers: formHeaders,
            query: query, body: body, proxyAddress: proxyAddress
        )
        return try await send(request, proxyAddress: proxyAddress)
    }

    public func postJSON(
        _ urlString: String,
        query: [String: String] = [:],
        json: Any,
        headers: [String: String],
        proxyAddress: String? = nil
    ) async throws -> HTTPResponse {
        var jsonHeaders = headers
        jsonHeaders["Content-Type"] = "application/json"
        let body = try JSONSerialization.data(withJSONObject: json)
        let request = try request(
            method: "POST", urlString: urlString, headers: jsonHeaders,
            query: query, body: body, proxyAddress: proxyAddress
        )
        return try await send(request, proxyAddress: proxyAddress)
    }

    func send(_ request: URLRequest, proxyAddress: String?) async throws -> HTTPResponse {
        let session = sessionForProxy(proxyAddress)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TransportError.network("非 HTTP 响应")
            }
            return HTTPResponse(
                statusCode: http.statusCode,
                body: data,
                text: String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
            )
        } catch let error as TransportError {
            throw error
        } catch {
            throw TransportError.network(error.localizedDescription)
        }
    }

    /// x-www-form-urlencoded 编码（对标 httpx 的表单编码；空格与中文等全部转义）。
    func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
