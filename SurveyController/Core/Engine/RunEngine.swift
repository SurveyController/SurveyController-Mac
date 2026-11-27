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
    private var submissionWaiters: [CheckedContinuation<Bool?, Never>] = []
    private var intervalWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var consecutiveFailures = 0
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
        let stopped = queue.sync {
            guard runTask != nil, !stopRequested else { return false }
            stopRequested = true
            wakeWaiters()
            return true
        }
        if stopped { appendLog("收到停止请求，正在停止…") }
    }

    public func requestPause() {
        let paused = queue.sync {
            guard runTask != nil, !stopRequested, !pauseRequested else { return false }
            pauseRequested = true
            progress.phase = .paused
            return true
        }
        if paused {
            emitProgress()
            appendLog("任务已暂停。")
        }
    }

    public func resume() {
        let resumed = queue.sync {
            guard runTask != nil, !stopRequested, pauseRequested else { return false }
            pauseRequested = false
            progress.phase = .running
            wakeSubmissionWaiters()
            return true
        }
        if resumed {
            emitProgress()
            appendLog("任务已继续。")
        }
    }

    private func wakeSubmissionWaiters() {
        let pending = submissionWaiters
        submissionWaiters.removeAll()
        pending.forEach { $0.resume(returning: nil) }
    }

    private func wakeWaiters() {
        wakeSubmissionWaiters()
        let pending = intervalWaiters.values
        intervalWaiters.removeAll()
        pending.forEach { $0.resume() }
    }

    private func claimSubmission() async -> Bool {
        while true {
            let decision = await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
                queue.sync {
                    guard !stopRequested, progress.successCount < progress.target else {
                        continuation.resume(returning: false)
                        return
                    }
                    guard !pauseRequested, progress.claimedCount < progress.target else {
                        submissionWaiters.append(continuation)
                        return
                    }
                    progress.claimedCount += 1
                    continuation.resume(returning: true)
                }
            }
            if let decision { return decision }
        }
    }

    private func waitForInterval(_ seconds: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.sync {
                guard !stopRequested, progress.successCount < progress.target else {
                    continuation.resume()
                    return
                }
                let id = UUID()
                intervalWaiters[id] = continuation
                queue.asyncAfter(deadline: .now() + seconds) { [weak self] in
                    self?.intervalWaiters.removeValue(forKey: id)?.resume()
                }
            }
        }
    }

    public func start(
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: SubmitHandler? = nil
    ) {
        let submit: SubmitHandler = submitHandler ?? { config, context in
            try await ProviderRegistry.submit(config, context: context)
        }
        let threadCount = min(max(1, config.numThreads), Self.maxThreads)
        queue.sync {
            guard runTask == nil else { return }
            progress = RunProgress()
            progress.phase = .running
            progress.target = max(1, config.targetNum)
            progress.slots = (1...threadCount).map { SlotStatus(id: $0) }
            stopRequested = false
            pauseRequested = false
            consecutiveFailures = 0
            runTask = Task {
                await self.run(threadCount: threadCount, config: config, proxyPool: proxyPool, submitHandler: submit)
            }
        }
    }

    private func run(
        threadCount: Int,
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: @escaping SubmitHandler
    ) async {
        emitProgress()
        appendLog("任务启动：目标 \(config.targetNum) 份，并发 \(threadCount)。")

        await withTaskGroup(of: Void.self) { group in
            for slot in 1...threadCount {
                group.addTask {
                    await self.runSlot(slot: slot, config: config, proxyPool: proxyPool, submitHandler: submitHandler)
                }
            }
        }

        let result = currentProgress()
        appendLog("任务结束：成功 \(result.successCount) 份，失败 \(result.failCount) 份。")
        queue.sync {
            if progress.phase != .failed {
                progress.phase = progress.successCount >= progress.target || !stopRequested ? .finished : .stopped
            }
            streamContinuation.yield(.progress(progress))
            streamContinuation.yield(.finished(progress))
            runTask = nil
        }
    }

    private func runSlot(
        slot: Int,
        config: ExecutionConfig,
        proxyPool: ProxyPool?,
        submitHandler: @escaping SubmitHandler
    ) async {
        let threadName = "线程\(slot)"
        while await claimSubmission() {
            updateSlot(slot) { $0.status = "提交中" }
            emitProgress()

            let rng = SystemRandomSource()
            let profile = config.randomUserAgentEnabled
                ? ConfigCodec.selectUserAgent(fromRatios: config.userAgentRatios, rng: rng)
                : nil
            var lease: ProxyLease?
            let leaseFactory: (() async throws -> String?)?
            if config.randomProxyIpEnabled, let proxyPool {
                leaseFactory = {
                    let acquired = try await proxyPool.acquire()
                    lease = acquired
                    return acquired.address
                }
            } else {
                leaseFactory = nil
            }
            let sample = await config.reverseFill?.reserve()
            if config.reverseFill != nil, sample == nil {
                recordFailure(SurveyProviderUnavailableAtRuntimeError("可用的反填样本不足，已停止"), config: config)
                break
            }
            var state = ExecutionState(config: config)
            state.reverseFillAnswers = sample?.answers ?? [:]
            var context = WjxProvider.SubmitContext(
                state: state,
                threadName: threadName,
                userAgent: profile?.ua ?? WjxSubmitCodec.resolveUserAgent(nil),
                userAgentProfile: profile,
                rng: rng
            )
            context.submitProxyLeaseFactory = leaseFactory
            context.isStopRequested = { [weak self] in
                guard let self else { return true }
                return self.queue.sync { self.stopRequested }
            }

            do {
                if try await submitHandler(config, context) {
                    queue.sync {
                        progress.successCount += 1
                        consecutiveFailures = 0
                        if progress.successCount >= progress.target { wakeWaiters() }
                    }
                    updateSlot(slot) { $0.success += 1; $0.status = "已成功" }
                    if let lease { await proxyPool?.markSuccess(lease) }
                } else {
                    if let sample { await config.reverseFill?.release(sample) }
                    queue.sync {
                        progress.claimedCount -= 1
                        wakeSubmissionWaiters()
                    }
                }
            } catch {
                if let sample, !(error is SubmissionResultUnknownError) {
                    await config.reverseFill?.retryOnce(sample)
                }
                recordFailure(error, config: config)
                updateSlot(slot) { $0.fail += 1; $0.status = "失败" }
                if let lease {
                    if error is SubmissionVerificationRequiredError {
                        await proxyPool?.markTemporarilyBad(lease)
                    } else if case .proxyConnection? = error as? TransportError {
                        await proxyPool?.markTemporarilyBad(lease)
                    }
                }
                appendLog("\(threadName)：提交失败（\(Self.failureCategory(error))）\(error.localizedDescription)")
            }
            if let lease { await proxyPool?.release(lease) }

            let (minInterval, maxInterval) = config.submitIntervalRangeSeconds
            let delay = maxInterval > minInterval
                ? Double.random(in: Double(minInterval)...Double(maxInterval))
                : Double(max(0, minInterval))
            if delay > 0, !queue.sync(execute: { stopRequested || progress.successCount >= progress.target }) {
                updateSlot(slot) { $0.status = "等待中" }
                emitProgress()
                await waitForInterval(delay)
            }
        }
        updateSlot(slot) { $0.status = "已结束" }
        emitProgress()
    }

    private func recordFailure(_ error: Error, config: ExecutionConfig) {
        queue.sync {
            progress.failCount += 1
            progress.failureReasons[Self.failureCategory(error), default: 0] += 1
            consecutiveFailures += 1
            if !(error is SubmissionResultUnknownError) {
                progress.claimedCount -= 1
            }

            let terminalReason: String?
            if error is SubmissionResultUnknownError || error is SurveyProviderStatusError {
                terminalReason = error.localizedDescription
            } else if config.stopOnFailEnabled && consecutiveFailures >= config.failThreshold {
                terminalReason = "连续失败已达阈值，任务停止"
            } else {
                terminalReason = nil
            }
            if let terminalReason, !stopRequested {
                stopRequested = true
                progress.phase = .failed
                progress.stopReason = terminalReason
                wakeWaiters()
            } else {
                wakeSubmissionWaiters()
            }
        }
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
        if error is SubmissionResultUnknownError { return "提交结果不确定" }
        if case .proxyConnection? = error as? TransportError { return "代理连接失败" }
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
