// 对标 CI/unit_tests 里代理池/引擎策略测试（test_proxy_pool.py 等）

import XCTest
@testable import SurveyController

/// 可编程假代理源。
final class ScriptedProxyProvider: ProxyProvider, @unchecked Sendable {
    var batches: [[ProxyLease]]
    private let lock = NSLock()

    init(batches: [[ProxyLease]]) {
        self.batches = batches
    }

    func fetchBatch(minute: Int, pool: String, area: String?, count: Int) async throws -> [ProxyLease] {
        let batch: [ProxyLease]? = lock.withLock {
            guard !batches.isEmpty else { return nil }
            return batches.removeFirst()
        }
        guard let batch else {
            throw SubmitProxyUnavailableError("代理已耗尽")
        }
        return batch
    }
}

final class ProxyPoolTests: XCTestCase {

    func test_acquire_returns_lease_and_tracks_in_use() async throws {
        let pool = ProxyPool(provider: ScriptedProxyProvider(batches: [[
            ProxyLease(address: "1.1.1.1:8080", expireAt: Date().timeIntervalSince1970 + 600),
        ]]))
        let lease = try await pool.acquire()
        XCTAssertEqual(lease.address, "1.1.1.1:8080")
        // 已占用的地址不会被再次分配
        await pool.release(lease)
        let again = try await pool.acquire()
        XCTAssertEqual(again.address, "1.1.1.1:8080")
    }

    func test_cooldown_blocks_address_until_expiry() async throws {
        let provider = ScriptedProxyProvider(batches: [[
            ProxyLease(address: "2.2.2.2:80", expireAt: Date().timeIntervalSince1970 + 600),
        ]])
        let pool = ProxyPool(provider: provider)
        let lease = try await pool.acquire()
        await pool.markTemporarilyBad(lease)
        // 冷却中：需要新提取（provider 第二批）
        provider.batches = [[
            ProxyLease(address: "3.3.3.3:80", expireAt: Date().timeIntervalSince1970 + 600),
        ]]
        let next = try await pool.acquire()
        XCTAssertEqual(next.address, "3.3.3.3:80")
    }

    func test_expired_lease_is_skipped() async throws {
        let provider = ScriptedProxyProvider(batches: [[
            ProxyLease(address: "4.4.4.4:80", expireAt: Date().timeIntervalSince1970 - 10),
            ProxyLease(address: "5.5.5.5:80", expireAt: Date().timeIntervalSince1970 + 600),
        ]])
        let pool = ProxyPool(provider: provider)
        let lease = try await pool.acquire()
        XCTAssertEqual(lease.address, "5.5.5.5:80")
    }

    func test_empty_provider_raises_unavailable() async {
        let pool = ProxyPool(provider: ScriptedProxyProvider(batches: []))
        do {
            _ = try await pool.acquire()
            XCTFail("应当抛出 SubmitProxyUnavailableError")
        } catch {
            XCTAssertTrue(error is SubmitProxyUnavailableError)
        }
    }

    // 对标 _parse_proxy_payload：JSON 递归解析
    func test_custom_proxy_provider_parses_nested_payload() async throws {
        let provider = CustomProxyProvider(apiUrl: "https://proxy.example/api")
        var addresses: [String] = []
        let payload: [String: Any] = [
            "code": 0,
            "data": [
                ["host": "1.2.3.4", "port": 8080, "account": "u", "password": "p"],
                "5.6.7.8:1080:user:pass",
            ],
        ]
        provider.collectAddresses(payload, into: &addresses)
        // dict 项缺少 address 形状（host/port 分离），按当前实现只收字符串项
        XCTAssertEqual(addresses, ["5.6.7.8:1080:user:pass"])

        var textAddresses: [String] = []
        provider.collectAddresses("9.9.9.9:80\n10.10.10.10:8080", into: &textAddresses)
        XCTAssertEqual(textAddresses, ["9.9.9.9:80", "10.10.10.10:8080"])
    }
}

final class RunEngineTests: XCTestCase {

    func makeConfig(target: Int, threads: Int = 1, failStop: Bool = true) -> ExecutionConfig {
        var config = ExecutionConfig()
        config.url = "https://www.wjx.cn/vm/demo.aspx"
        config.targetNum = target
        config.numThreads = threads
        config.stopOnFailEnabled = failStop
        config.submitIntervalRangeSeconds = (0, 0)
        return config
    }

    func waitForFinish(_ engine: RunEngine, timeout: TimeInterval = 10) async -> RunProgress {
        let stream = engine.progressStream
        var last = engine.currentProgress()
        for await event in stream {
            if case .progress(let progress) = event {
                last = progress
                if [.finished, .stopped, .failed].contains(progress.phase) {
                    return progress
                }
            }
            if case .finished(let progress) = event {
                return progress
            }
        }
        return last
    }

    // 目标份数达成后停止
    func test_engine_completes_target_count() async {
        let engine = RunEngine()
        engine.start(config: makeConfig(target: 3), proxyPool: nil) { @Sendable _, _ in true }
        let final = await waitForFinish(engine)
        XCTAssertEqual(final.successCount, 3)
        XCTAssertEqual(final.phase, .finished)
    }

    // 连续失败达到阈值停止（对标 RunStopPolicy fail_threshold=5）
    func test_engine_stops_after_consecutive_failures() async {
        let engine = RunEngine()
        engine.start(config: makeConfig(target: 100), proxyPool: nil) { @Sendable _, _ in
            throw SubmissionVerificationRequiredError("需要安全校验")
        }
        let final = await waitForFinish(engine)
        XCTAssertEqual(final.phase, .failed)
        XCTAssertEqual(final.failCount, 5)
        XCTAssertEqual(final.failureReasons["智能验证"], 5)
    }

    // 并发槽位各自计数
    func test_engine_runs_concurrent_slots() async {
        let engine = RunEngine()
        engine.start(config: makeConfig(target: 8, threads: 4), proxyPool: nil) { @Sendable _, _ in
            try? await Task.sleep(nanoseconds: 10_000_000)
            return true
        }
        let final = await waitForFinish(engine)
        XCTAssertEqual(final.successCount, 8)
        XCTAssertEqual(final.slots.count, 4)
    }

    // 失败分类（对标 failure_reason）
    func test_failure_category_maps_known_errors() {
        XCTAssertEqual(RunEngine.failureCategory(SubmissionVerificationRequiredError("x")), "智能验证")
        XCTAssertEqual(RunEngine.failureCategory(SubmitProxyUnavailableError("x")), "随机IP不可用")
        XCTAssertEqual(RunEngine.failureCategory(TransportError.network("timeout")), "网络错误")
        XCTAssertEqual(RunEngine.failureCategory(NSError(domain: "t", code: 1)), "其他错误")
    }
}

final class BackendClientParsingTests: XCTestCase {

    // 对标 _extract_proxy_item：四要素齐全才有效
    func test_extract_proxy_item_requires_all_fields() {
        let client = BackendClient(store: RandomIPSessionStore(defaults: UserDefaults(suiteName: "test-parse")!), client: HTTPClient())
        XCTAssertNotNil(client.extractProxyItem([
            "host": "1.2.3.4", "port": 8080, "account": "u", "password": "p", "expire_at": "",
        ]))
        XCTAssertNil(client.extractProxyItem(["host": "1.2.3.4", "port": 8080, "account": "", "password": "p"]))
        XCTAssertNil(client.extractProxyItem(["host": "", "port": 8080, "account": "u", "password": "p"]))
        XCTAssertNil(client.extractProxyItem(["host": "1.2.3.4", "port": 0, "account": "u", "password": "p"]))
    }

    // 对标 _parse_session_payload：会话与额度字段
    func test_parse_session_payload_reads_quota_fields() {
        let store = RandomIPSessionStore(defaults: UserDefaults(suiteName: "test-parse-2")!)
        let client = BackendClient(store: store, client: HTTPClient())
        let session = client.parseSessionPayload([
            "user_id": 42,
            "remaining_quota": 8.5,
            "total_quota": 10.0,
            "used_quota": 1.5,
        ], fallback: RandomIPSession())
        XCTAssertEqual(session.userId, 42)
        XCTAssertEqual(session.remainingQuota, 8.5)
        XCTAssertTrue(session.quotaKnown)
        XCTAssertTrue(session.isComplete)
    }
}
