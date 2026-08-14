// 对标 software/providers/errors.py

import Foundation

/// 问卷平台状态异常基类。
public class SurveyProviderStatusError: Error, LocalizedError, @unchecked Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public final class SurveyPausedError: SurveyProviderStatusError {}
public final class SurveyStoppedError: SurveyProviderStatusError {}
public final class SurveyEnterpriseUnavailableError: SurveyProviderStatusError {}
public final class SurveyNotOpenError: SurveyProviderStatusError {}
public final class SurveyProviderUnavailableAtRuntimeError: SurveyProviderStatusError {}

/// 提交触发智能验证（需换 IP 重试或停止）。
public final class SubmissionVerificationRequiredError: Error, LocalizedError, @unchecked Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// 随机 IP 提交代理解不可用。
public final class SubmitProxyUnavailableError: Error, LocalizedError, @unchecked Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
