# AGENTS.md

> 本文档供 AI Agent（如 ZCode、Claude、Cursor 等）阅读，用于理解项目背景、移植规则与协作约定。请先完整阅读本文档再开始任何任务。

## 项目身份

- **项目名称**：SurveyController Mac
- **项目性质**：SurveyController 官方 Windows 桌面端的 **macOS 端独立移植版**
- **GitHub 仓库**：https://github.com/SurveyController/SurveyController-Mac
- **License**：GPL-3.0（与官方一致）
- **当前版本**：v0.1.0（开发中，逐步对齐官方 v4.0.6）

## 官方源仓库

- **官方主仓库**：https://github.com/SurveyController/SurveyController
- **官方语言**：Python 3.13+ + PySide6（Qt）
- **官方平台**：Windows（桌面端）
- **官方文档**：https://surveydoc.hungrym0.com/
- **官方 Release**：https://github.com/SurveyController/SurveyController/releases

> **注意**：本地 checkout 根目录即官方源码 fork（`software/` 为 Windows 原版 Python 源码），**只读不写**。所有移植产物都在 `mac/` 目录下。

## 移植规则

### 核心原则

1. **移植来源是 Windows 原版**：一切业务逻辑以 `software/`（及顶层 `wjx/`、`tencent/`、`credamo/`）的 Python 源码为准，1:1 移植。
2. **安卓端仅是方法论参考**：同 checkout 下的 `android/`（Kotlin 移植版）只借鉴其移植实践——文件头对标注释、工程分层、测试移植方法，**不作为代码移植对象**。
3. **不改动 `software/` 目录**：那是官方源码，只读。所有产物在 `mac/`。
4. **对应关系**：每个 Swift 文件在文件头注释标注对标的 Python 文件（如 `// 对标 software/providers/common.py`）。
5. **UI 对标 Windows 原版布局**：概览/运行参数/题目策略/反填/日志 + 设置/更多的侧边导航结构，用 SwiftUI 原生重写，不模仿移动端布局。

### 版本管理策略

独立 semver 版本号，跟随官方节奏递增（与安卓端策略一致）：

| 官方更新类型 | Mac 版本递增规则 |
|-------------|-----------------|
| Patch（修 bug） | patch +1 |
| Minor（新功能） | minor +1 |
| Major（大改/破坏性） | major +1 |
| Mac 独有修复/功能 | patch / minor +1 |

`CFBundleShortVersionString`（marketing version）与 `AppVersion.swift` 的 `VERSION` 常量**必须同步**；`CFBundleVersion` 单调递增整数（`major*10000 + minor*100 + patch`）。

修改位置：Xcode 工程配置（`project.pbxproj` 的 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）+ `SurveyController/App/AppVersion.swift`。

### 不需要移植的内容

- **PySide6 UI 层**：`software/ui/` 用 SwiftUI 重写，不移植
- **Velopack 自动更新**：官方桌面端更新机制，Mac 端用 GitHub Release（更新检查 API 移植，`software/update/`）
- **Windows 系统集成**：注册表、电源管理、设备指纹（`software/system/`）——电源管理对应 macOS 的 `ProcessInfo.processInfo.beginActivity`（防止运行中休眠）
- **Python 工具链配置**：pyproject.toml、uv.lock 等

## 技术栈

| 层 | 技术 | 对标官方 |
|----|------|---------|
| 语言 | Swift 6（严格并发） | Python 3.13 |
| UI | SwiftUI（最低 macOS 14） | PySide6 + Fluent Widgets |
| 异步 | Swift Concurrency（actor / TaskGroup / AsyncStream） | asyncio |
| HTTP | URLSession | httpx |
| HTML 解析 | SwiftSoup（Jsoup 同源移植，唯一第三方依赖） | BeautifulSoup4 |
| 哈希 | CryptoKit（Insecure.SHA1，见数签名用） | hashlib |
| JSON | Codable + JSONSerialization（动态形状） | json 标准库 |
| 存储 | UserDefaults + Application Support JSON | QSettings |
| 二维码 | CoreImage CIQRCodeDetector | zxing-cpp |
| 测试 | XCTest | pytest（对标 CI/unit_tests/） |

> **依赖纪律**（沿用安卓端体积优化教训）：不引入带 native 库的依赖，优先纯 Swift 实现。当前唯一第三方依赖是 SwiftSoup。

## 项目结构

```
mac/
├── SurveyController.xcodeproj        # 文件系统同步式工程（Xcode 16+）
├── SurveyController/                 # 主 target
│   ├── SurveyControllerApp.swift     # @main 入口
│   ├── App/                          # 版本常量（对标 software/app/version.py）
│   ├── Core/
│   │   ├── Model/                    # 领域模型（对标 core/task/、providers/contracts.py）
│   │   ├── Engine/                   # 执行引擎（对标 core/engine/）
│   │   ├── Questions/                # 答案生成（对标 core/questions/）
│   │   ├── AI/                       # AI 填空（对标 core/ai/ + integrations/ai/）
│   │   ├── Network/                  # HTTP 客户端、UA（对标 network/http/）
│   │   ├── Backend/                  # 官方后端通信（对标 network/proxy/session/ 等）
│   │   └── Proxy/                    # 代理池与会话策略（对标 network/proxy/ + session_policy.py）
│   ├── Provider/                     # 平台适配（对标 software/providers/ + 顶层 wjx/）
│   │   └── Wjx/                      # 问卷星
│   ├── Data/                         # 配置编解码、存储（对标 core/config/ + app/config.py）
│   └── UI/                           # SwiftUI 界面（重写，不移植 software/ui/）
├── SurveyControllerTests/            # 单元测试（对标 CI/unit_tests/）
└── .github/workflows/                # ci.yml + release.yml
```

## 构建与测试

环境要求：Xcode 16+ / macOS 14+

```bash
# 编译
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController build

# 单元测试
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController test

# 构建 release .app（产物在 build/）
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController \
  -configuration Release -derivedDataPath build CONFIGURATION_BUILD_DIR=build clean build
```

## 踩坑记录

### 1. ICU regex 的 `{`/`}` 转义（安卓端血泪教训，同样适用 macOS）

NSRegularExpression 底层同为 ICU：单独的 `}`（不闭合量词组）是**语法错误**。Swift 的 `Regex` 字面量与 `NSRegularExpression` 都受影响。规则：**字面量 `{` 和 `}` 一律转义**，字符类内 `[^{}]` 不受影响。

### 2. Foundation 与 Python 的 URL 解析差异

`URLComponents`/`URL(string:)` 对非规范输入（无 scheme、中文、尾随空格）的行为与 Python `urlparse` 不同。URL 识别统一走 `ProviderType`（对标 `providers/common.py`）里的手工解析逻辑，不要在各处散落 `URL(string:)` 判断。

### 3. WJX 协议敏感点（golden-value 测试强制覆盖）

- `starttime` 格式**非补零**：`{y}/{m}/{d} {H}:{M}:{S}`
- `jqsign` 是 jqnonce 逐字符 XOR（`ktimes % 10`，整除 10 时取 1），不是哈希
- `submitdata` 的转义表（`$ } ^ | ! <` → 全角/形近字符）与题型编码顺序
- `rn` 是 `2000000000 + random*1e8` 的**字符串**（非整数）
- 渠道参数按 UA 类型区分（微信渠道有额外 openid/unionId 等）

### 4. Swift 6 严格并发

引擎层用 actor 隔离可变状态；UI 层 `@Observable`。Python 源码里的锁（`state.lock`）在 Swift 里靠 actor 保证，**不要**再用 NSLock 平移。

## 协作约定

### Git 提交规范

`<type>: <描述>`，type 取值：`feat` / `fix` / `docs` / `refactor` / `perf` / `build` / `chore` / `test`。

示例：
- `feat: 移植问卷星解析链路（对标 wjx/provider/html_parser.py）`
- `fix: 修正 submitdata 转义表缺少 '<' 的问题`
- `test: 移植 WjxSubmitCodec golden-value 用例`

### 代码风格

- Swift 4 空格缩进，文件头注释标注对标 Python 文件路径
- public API 写 Swift Doc 注释
- 业务逻辑保持与 Python 源码 1:1：变量名可转 camelCase，但**分支、边界值、魔法数字不动**

### 测试要求

- 核心逻辑（Provider、Questions、Engine、ConfigCodec）必须有单元测试
- 协议编解码类（WjxSubmitCodec 等）用 golden-value 断言（对标桌面端已知输出）
- 移植官方功能时，同步移植 `CI/unit_tests/` 对应测试用例

## 联系方式

- **GitHub Issues**：https://github.com/SurveyController/SurveyController-Mac/issues
- **QQ 交流群**：346131215
