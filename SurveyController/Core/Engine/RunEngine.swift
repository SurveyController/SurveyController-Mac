// 对标 software/core/engine/（async_engine.py + async_runtime_loop.py + async_scheduler.py + run_stop_policy.py）
// 运行引擎：actor 化的槽位调度器。Swift 并发替代 Python 的事件循环 + 锁。

import Foundation

public enum RunPhase: String, Sendable {
    case idle
    case running
    case paused
    case finished
    case stopped
    case failed
}

public struct SlotStatus: Sendable, Identifiable {
    public let id: Int
    public var status: String
    public var success: Int
    public var fail: Int

    public init(id: Int, status: String = "待命", success: Int = 0, fail: Int = 0) {
        self.id = id
        self.status = status
        self.success = success
        self.fail = fail
    }
}

public struct RunProgress: @unchecked Sendable {
    public var phase: RunPhase = .idle
    public var successCount: Int = 0
    public var failCount: Int = 0
    /// 已认领的名额数（含进行中），保证并发下不超目标
    public var claimedCount: Int = 0
    public var target: Int = 1
    public var slots: [SlotStatus] = []
    public var failureReasons: [String: Int] = [:]
    public var logs: [String] = []
    public var stopReason: String = ""

    public init() {}
}

public enum RunEngineEvent: Sendable {
    case progress(RunProgress)
    case log(String)
    case finished(RunProgress)
}

/// 运行引擎（对标 AsyncRuntimeEngine + AsyncSlotRunner）。
public final class RunEngine: @unchecked Sendable {

    /// 单次提交的注入点（WJX 提交流程；测试可注入假实现）。
    public typealias SubmitHandler = @Sendable (
        _ config: ExecutionConfig,
        _ context: WjxProvider.SubmitContext
    ) async throws -> Bool

    public static let maxThreads = 16

    private let queue = DispatchQueue(label: "surveycontroller.engine")
    private var progress = RunProgress()
    private var stopRequested = false
    private var pauseRequested = false
    private var pausedContinuations: [CheckedContinuation<Void, Never>] = []
    private var runTask: Task<Void, Never>?
    private let logCapacity = 500

    private let streamContinuation: AsyncStream<RunEngineEvent>.Continuation
    private let eventStream: AsyncStream<RunEngineEvent>

    /// 进度事件流（unbounded 缓冲：启动后再订阅也能收到历史进度）。
    public var progressStream: AsyncStream<RunEngineEvent> {
        eventStream
    }

    public init() {
        var continuation: AsyncStream<RunEngineEvent>.Continuation? = nil
        eventStream = AsyncStream { continuation = $0 }
        streamContinuation = continuation!
    }

    // MARK: - 状态读写（串行队列保证安全）

    func withProgress<T>(_ body: (inout RunProgress) -> T) -> T {
        queue.sync { body(&progress) }
    }

    public func currentProgress() -> RunProgress {
        withProgress { $0 }
    }

    func emitProgress() {
        let snapshot = withProgress { $0 }
        streamContinuation.yield(.progress(snapshot))
    }

    func appendLog(_ message: String) {
        let timestamp = DateFormatter.logTimeString()
        let line = "\(timestamp) [信息] \(message)"
        _ = withProgress { p in
            p.logs.append(line)
            if p.logs.count > logCapacity {
                p.logs.removeFirst(p.logs.count - logCapacity)
            }
        }
        streamContinuation.yield(.log(line))
    }

    // MARK: - 控制

    public func requestStop() {
        stopRequested = true
        resumePaused()
        appendLog("收到停止请求，正在停止…")
    }

    public func requestPause() {
        pauseRequested = true
        _ = withProgress { $0.phase = .paused }
        emitProgress()
        appendLog("任务已暂停。")
    }

    public func resume() {
        pauseRequested = false
        resumePaused()
        _ = withProgress { p in
            if p.phase == .paused { p.phase = .running }
        }
        emitProgress()
        appendLog("任务已继续。")
    }

    private func resumePaused() {
        queue.sync {
            let continuations = pausedContinuations
            pausedContinuations.removeAll()
            continuations.forEach { $0.resume() }
        }
    }

    func waitIfPaused() async {
        while true {
            let shouldWait: Bool = queue.sync { pauseRequested && !stopRequested }
            guard shouldWait else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let registered = queue.sync { () -> Bool in
                    guard pauseRequested, !stopRequested else { return false }
                    pausedContinuations.append(continuation)
                    return true
                }
                if !registered {
                    continuation.resume()
                }
            }
        }
    }

    /// 对标 start_run：启动任务。
    /// submitHandler 默认为 WJX 提交（对标 fill_survey_http → brush_wjx_http）。
    public func start(
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: @escaping SubmitHandler = { config, context in
            try await WjxProvider.submit(config, context: context)
        }
    ) {
        runTask?.cancel()
        runTask = Task { [weak self] in
            guard let self else { return }
            await self.run(config: config, proxyPool: proxyPool, submitHandler: submitHandler)
        }
    }

    /// 对标 AsyncSlotRunner.run + AsyncScheduler 间隔调度。
    func run(
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: @escaping SubmitHandler
    ) async {
        stopRequested = false
        pauseRequested = false


        let threadCount = min(max(1, config.numThreads), Self.maxThreads)
        _ = withProgress { p in
            p = RunProgress()
            p.phase = .running
            p.target = config.targetNum
            p.slots = (1...threadCount).map { SlotStatus(id: $0) }
        }
        emitProgress()
        appendLog("任务启动：目标 \(config.targetNum) 份，并发 \(threadCount)。")

        await withTaskGroup(of: Void.self) { group in
            for slot in 1...threadCount {
                group.addTask { [weak self] in
                    await self?.runSlot(
                        slot: slot, config: config, proxyPool: proxyPool, submitHandler: submitHandler
                    )
                }
            }
        }

        let finalPhase: RunPhase = withProgress { p in
            p.phase = stopRequested ? .stopped : .finished
            p.slots = p.slots.map { var s = $0; s.status = "已结束"; return s }
            return p.phase
        }
        appendLog("任务结束：成功 \(withProgress(\.successCount)) 份，失败 \(withProgress(\.failCount)) 份。")
        let snapshot = withProgress { $0 }
        emitProgress()
        if finalPhase != .stopped {
            streamContinuation.yield(.finished(snapshot))
        } else {
            streamContinuation.yield(.finished(snapshot))
        }
    }

    func runSlot(
        slot: Int,
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: @escaping SubmitHandler
    ) async {
        let threadName = "线程\(slot)"
        var localRng = SystemRandomSource()

        while !stopRequested {
            await waitIfPaused()
            if stopRequested { break }

            // 达到目标份数 → 结束（对标 _should_stop_loop 的 target_reached）
            // 认领必须原子预留（串行队列内 +1），否则并发槽位会重复认领导致超额提交
            let claimed = withProgress { p -> Int in
                p.claimedCount += 1
                guard p.claimedCount <= p.target else { return -1 }
                return p.claimedCount
            }
            if claimed < 0 { break }

            updateSlot(slot) { $0.status = "提交中" }
            emitProgress()

            // UA 选择（对标 select_user_agent：随机 UA 或默认 PC）
            var userProfile: UserAgentProfile? = nil
            if config.randomUserAgentEnabled {
                userProfile = ConfigCodec.selectUserAgent(fromRatios: config.userAgentRatios, rng: localRng)
            }
            let userAgent = userProfile?.ua ?? WjxSubmitCodec.resolveUserAgent(nil)

            // 随机 IP：提交前惰性获取
            var lease: ProxyLease? = nil
            let leaseFactory: (() async throws -> String?)? = config.randomProxyIpEnabled && proxyPool != nil ? {
                do {
                    let acquired = try await proxyPool!.acquire()
                    lease = acquired
                    return acquired.address
                } catch {
                    throw error
                }
            } : nil

            let state = ExecutionState(config: config)
            var context = WjxProvider.SubmitContext(
                state: state,
                threadName: threadName,
                userAgent: userAgent,
                userAgentProfile: userProfile,
                rng: localRng
            )
            context.submitProxyLeaseFactory = leaseFactory

            do {
                let ok = try await submitHandler(config, context)
                if ok {
                    _ = withProgress { $0.successCount += 1 }
                    updateSlot(slot) { $0.success += 1; $0.status = "已成功" }
                    if let lease { await proxyPool?.markSuccess(lease) }
                } else {
                    _ = withProgress { $0.failCount += 1 }
                    updateSlot(slot) { $0.fail += 1; $0.status = "跳过" }
                }
            } catch {
                _ = withProgress { $0.failCount += 1 }
                updateSlot(slot) { $0.fail += 1; $0.status = "失败" }
                let reason = Self.failureCategory(error)
                _ = withProgress { $0.failureReasons[reason, default: 0] += 1 }
                if let lease {
                    if error is SubmissionVerificationRequiredError {
                        // 智能验证 → 冷却该 IP（对标 _mark_proxy_temporarily_bad）
                        await proxyPool?.markTemporarilyBad(lease)
                        appendLog("\(threadName)：随机IP触发风控，已冷却更换。")
                    } else {
                        await proxyPool?.release(lease)
                    }
                }
                appendLog("\(threadName)：提交失败（\(reason)）\(error.localizedDescription)")

                // 对标 RunStopPolicy：连续失败达到阈值停止（AI 类失败阈值 5）
                if config.stopOnFailEnabled {
                    let shouldStop = withProgress { p -> Bool in
                        p.successCount == 0 && p.failCount >= config.failThreshold
                    }
                    if shouldStop {
                        withProgress { p in
                            p.phase = .failed
                            p.stopReason = "连续失败已达阈值，任务停止"
                        }
                        appendLog("连续失败 \(config.failThreshold) 次，任务已停止。请检查配置或网络。")
                        stopRequested = true
                        break
                    }
                }
            }

            if let lease {
                await proxyPool?.release(lease)
            }

            // 提交间隔（对标 dispatch_delay_seconds = uniform(min, max)）
            let (minInterval, maxInterval) = config.submitIntervalRangeSeconds
            let delaySeconds: Double
            if maxInterval > minInterval {
                delaySeconds = Double.random(in: Double(minInterval)...Double(maxInterval))
            } else {
                delaySeconds = Double(max(0, minInterval))
            }
            if delaySeconds > 0 {
                updateSlot(slot) { $0.status = "等待中" }
                emitProgress()
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
        updateSlot(slot) { $0.status = "已结束" }
        emitProgress()
    }

    func updateSlot(_ slot: Int, _ update: (inout SlotStatus) -> Void) {
        _ = withProgress { p in
            guard let index = p.slots.firstIndex(where: { $0.id == slot }) else { return }
            update(&p.slots[index])
        }
    }

    /// 对标 failure_reason 的分类摘要。
    static func failureCategory(_ error: Error) -> String {
        if error is SubmissionVerificationRequiredError { return "智能验证" }
        if error is SubmitProxyUnavailableError { return "随机IP不可用" }
        if error is SurveyProviderUnavailableAtRuntimeError { return "问卷不可用" }
        if error is SurveyPausedError { return "问卷已暂停" }
        if error is SurveyStoppedError { return "问卷已停止" }
        if error is TransportError { return "网络错误" }
        if error is RandomIPAuthError { return "随机IP额度" }
        return "其他错误"
    }
}

extension DateFormatter {
    static func logTimeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}
