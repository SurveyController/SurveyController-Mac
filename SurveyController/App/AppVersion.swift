// 对标 software/app/version.py
// 版本号必须与 Xcode 工程 MARKETING_VERSION / CURRENT_PROJECT_VERSION 同步修改。

import Foundation

/// 应用版本与 GitHub 仓库信息。
public enum AppVersion {
    /// 当前版本（与 MARKETING_VERSION 同步）。
    public static let version = "0.1.0"
    /// 当前对齐的官方桌面端版本。
    public static let alignedOfficialVersion = "4.0.6"

    public static let githubOwner = "SurveyController"
    public static let githubRepo = "SurveyController-Mac"

    public static let githubApiUrl = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"
    public static let githubReleasesUrl = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases"
    public static let githubReleasesPageUrl = "https://github.com/\(githubOwner)/\(githubRepo)/releases"
    public static let issueFeedbackUrl = "https://github.com/\(githubOwner)/\(githubRepo)/issues/new"

    /// 比较语义化版本字符串；返回正数表示 lhs 更新，负数表示 rhs 更新，0 表示相等。
    /// 预发布版本（如 2.0.0-rc1）小于同版本号的正式版本。
    public static func compareSemVer(_ lhs: String, _ rhs: String) -> Int {
        func split(_ version: String) -> (core: [Int], prerelease: String) {
            let parts = version.split(separator: "-", maxSplits: 1)
            let core = parts[0].split(separator: ".").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let prerelease = parts.count > 1 ? String(parts[1]) : ""
            return (core, prerelease)
        }
        let left = split(lhs)
        let right = split(rhs)
        for index in 0..<max(left.core.count, right.core.count) {
            let l = index < left.core.count ? left.core[index] : 0
            let r = index < right.core.count ? right.core[index] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        if left.prerelease.isEmpty && right.prerelease.isEmpty { return 0 }
        if left.prerelease.isEmpty { return 1 }
        if right.prerelease.isEmpty { return -1 }
        return left.prerelease.compare(right.prerelease, options: .numeric) == .orderedAscending ? -1 : 1
    }
}
