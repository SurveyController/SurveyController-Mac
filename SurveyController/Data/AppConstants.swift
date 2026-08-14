// 对标 software/app/config.py（按需移植 Mac 版用到的常量子集）

import Foundation

public let userAgentPresets: [String: (label: String, ua: String)] = [
    "pc_web": (
        "电脑网页端",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    ),
    "mobile_android": (
        "安卓手机浏览器",
        "Mozilla/5.0 (Linux; Android 16; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36"
    ),
    "wechat_android": (
        "安卓微信端",
        "Mozilla/5.0 (Linux; Android 16; Pixel 8 Build/BP22.250124.009; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/121.0.0.0 Mobile Safari/537.36 MicroMessenger/8.0.43.2460(0x28002B3B) Process/appbrand0 WeChat/arm64 Weixin NetType/WIFI Language/zh_CN ABI/arm64"
    ),
]

public let defaultUserAgent = userAgentPresets["pc_web"]!.ua

public let defaultHttpHeaders: [String: String] = [
    "User-Agent": defaultUserAgent,
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    "Connection": "close",
]

/// 官方后端（随机IP / AI 免费额度 / 卡密兑换）。
public let backendBaseUrls: [String] = ["https://api-wjx.hungrym0.com"]
public let ipExtractEndpoint = "https://api-wjx.hungrym0.com/api/ip/extract"
public let aiFreeEndpoint = "https://api-wjx.hungrym0.com/api/ai/free"

/// 代理池常量（对标 software/app/config.py PROXY_*）。
public let proxyMaxProxies = 80
public let proxyHealthCheckUrl = "https://www.wjx.cn"
public let proxyPoolOrdinary = "ordinary"
public let proxyPoolQuality = "quality"
public let proxySourceDefault = "default"
public let proxySourceBenefit = "benefit"
public let proxySourceCustom = "custom"

/// 默认填空文本。
public let defaultFillText = "无"

/// 日志。
public let logBufferCapacity = 2000
public let logDirName = "logs"

/// 多选题最少/最多选项的提示语正则库（对标 CN/EN regex banks，阶段3解析用）。
public let multiMinLimitKeywords = ["最少选择", "至少选择", "最少勾选", "至少勾选", "select at least", "choose at least"]
public let multiMaxLimitKeywords = ["最多选择", "至多选择", "最多勾选", "至多勾选", "select at most", "choose at most"]
