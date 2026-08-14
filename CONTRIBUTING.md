# 贡献指南

感谢愿意改进本项目。开始前，请先阅读 [行为准则](CODE_OF_CONDUCT.md)。

本文面向开发者。目标是让你能从源码跑起来、提交一份容易 review 的 Pull Request。

本项目是 [SurveyController](https://github.com/SurveyController/SurveyController)（Windows 桌面端）的 macOS 移植版：业务逻辑以官方 Python 源码为准 1:1 移植，UI 用 SwiftUI 原生重写。移植约定详见 [AGENTS.md](AGENTS.md)。

## 开发环境

需要准备：

- macOS 14（Sonoma）及以上
- Xcode 16 及以上（含 Swift 6 工具链）
- Git

不需要额外安装依赖管理器——唯一的第三方依赖 SwiftSoup 由 Xcode 自动解析。

## 开发流程

下面按第一次参与贡献的流程来写。

### 1. Fork 仓库

先在本仓库主页点击 **Fork**。

Fork 后，你会得到一份自己的仓库，例如：

```text
https://github.com/你的用户名/SurveyController-Mac
```

后续改动**先推送到你自己的仓库**，再向主仓库提交 Pull Request。

### 2. 克隆自己的 Fork

不要直接克隆主仓库——如果你没有被赋予直接推送到主仓库的权限。

```bash
git clone https://github.com/你的用户名/SurveyController-Mac.git
cd SurveyController-Mac
```

### 3. 打开工程并运行

```bash
open SurveyController.xcodeproj   # Xcode 中选择 SurveyController scheme，Cmd+R 运行
```

或命令行构建：

```bash
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController build
```

### 4. 添加主仓库地址并同步最新代码

把主仓库添加为 `upstream`：

```bash
git remote add upstream https://github.com/SurveyController/SurveyController-Mac.git
git remote -v
```

看到 `origin` 和 `upstream` 都存在就行：

```text
origin    你的 Fork 地址
upstream  https://github.com/SurveyController/SurveyController-Mac.git
```

**每次开始新功能前，先同步主仓库最新代码：**

```bash
git checkout main
git fetch upstream
git pull upstream main
```

### 5. 创建开发分支

**不建议直接在 `main` 分支上做出改动。**

每个修复或功能都开一个新分支：

```bash
git checkout -b fix/short-description
```

分支名可以这样写：

```bash
fix/slider-ratio-mismatch
fix/wjx-scene-id-parse
feature/tencent-provider
docs/contributing-flow
```

含义：

- `fix/xxx`：修 bug。
- `feature/xxx`：加功能。
- `docs/xxx`：改文档。
- `refactor/xxx`：重构。

> [!IMPORTANT]
> 每个分支只对应单一的改动，**不要在一个分支里猛塞多个新功能！**

### 6. 暂存与提交文件

Git 提交分两步：

1. 暂存：告诉 Git 这次准备提交哪些文件。
2. 提交：把暂存内容保存成一次历史记录。

在此之前，先看一眼实际会进提交的文件：

```bash
git status --short
```

> [!IMPORTANT]
> **不要把 IDE 工作区垃圾、个人本地配置、临时文件一起提交进来！**

比如 `.idea/`、`.vscode/`、`xcuserdata/`、`DerivedData/`、构建产物目录（`build*/`）、`.DS_Store`、临时导出文件。这些东西和项目代码无关，塞进仓库只会污染 review。

暂存改动并提交：

```bash
git add 改动的文件
git commit -m "类型: 简短说明"
```

常见类型：

```text
feat: 新增功能（含官方移植）
fix: 修复问题
docs: 修改文档
test: 添加或修改测试
refactor: 重构代码
build: 构建或依赖调整
chore: 杂项
```

例子：

```bash
git commit -m "fix: 联动滑杆锁定额度计算错误"
git commit -m "feat: 腾讯问卷解析链路（对标 tencent/provider/parser.py）"
git commit -m "test: 补充 submitdata 转义表 golden 用例"
```

### 7. 推送分支

第一次推送当前分支：

```bash
git push -u origin 当前分支名
```

以后同一个分支继续提交后，只需要：

```bash
git push
```

### 8. 提交 Pull Request

推送后，GitHub 通常会提示 **Compare & pull request**。

确认方向是：

```text
你的 Fork 分支 -> SurveyController/SurveyController-Mac 的 main 分支
```

PR 描述里写清楚：

- 改了什么。
- 为什么改。
- 跑过哪些检查。
- 有没有用户能看见的变化。

### 9. 根据 review 修改

如果维护者提出修改意见，继续在同一个分支上改：

```bash
git add 修改过的文件
git commit -m "fix: address review comments"
git push
```

同一个 PR 会自动更新，不需要重新开 PR。

提交前请确认：

- 改动只包含本次 PR 需要的内容。
- 没有提交 `xcuserdata/`、`DerivedData/`、`build*/` 等构建产物。
- 没有提交日志、缓存、`.DS_Store`。
- 没有提交密钥、卡密、代理套餐等敏感信息。
- 用户数据仍写入用户目录（`~/Library/Application Support/SurveyController/`），不写回安装目录。

## 常见改动位置

| 目标 | 目录 |
| --- | --- |
| 问卷星解析、提交编解码 | `SurveyController/Provider/Wjx/` |
| 平台识别、Provider 协议 | `SurveyController/Provider/` |
| 核心模型（题目/配置/动作） | `SurveyController/Core/Model/` |
| 执行引擎、调度 | `SurveyController/Core/Engine/` |
| 答案生成、逻辑规划 | `SurveyController/Core/Questions/` |
| 随机 IP 后端、代理池、地区 | `SurveyController/Core/Backend/`、`Core/Proxy/` |
| HTTP 客户端 | `SurveyController/Core/Network/` |
| 配置编解码、默认配置 | `SurveyController/Data/` |
| SwiftUI 界面、向导、组件 | `SurveyController/UI/` |
| 单元测试 | `SurveyControllerTests/` |
| 实测链路（门控） | `SurveyControllerTests/LiveSurveyE2ETests.swift` |
| CI / 发布 | `.github/workflows/` |

不要把新功能塞进不相干文件。屎山通常就是这么长出来的。

如果新增或删除顶层目录，需同步更新本文档和 AGENTS.md 里的结构说明。

## 代码要求

- Swift 代码保持简单直白，优先复用现有模块。
- UI 一律使用 SwiftUI 原生组件；品牌图标用 `UI/BrandIcons.swift` 自绘，不引入图标库。
- 不引入带 native 库的第三方依赖（当前唯一依赖 SwiftSoup）。
- 业务逻辑与官方 Python 源码 1:1：变量名可转 camelCase，但**分支、边界值、魔法数字不动**；文件头注释标注对标的 Python 文件路径。
- 涉及 WJX 提交协议（submitdata 转义、jqsign、starttime 格式等）的改动必须有 golden-value 测试。
- 版本号三处同步改：`App/AppVersion.swift`、工程 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`（`major*10000 + minor*100 + patch`）。
- 用户配置与日志写入 `~/Library/Application Support/SurveyController/`。

## 本地检查

只跑单测：

```bash
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController test
```

构建 Release 包验证：

```bash
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController \
  -configuration Release -derivedDataPath build \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO build
```

## 测试建议

改哪一块，就补哪一块测试：

- 解析器、提交编解码：补 `SurveyControllerTests/Wjx*Tests.swift` 的 golden 用例（官方 `CI/unit_tests/` 有对应 Python 用例可移植）。
- 配置编解码：补 `ConfigCodecTests.swift`。
- 执行引擎、代理池：补 `RunEngineTests.swift`。
- 纯 UI 交互逻辑（如联动滑杆算法）抽成纯函数并补测（参考 `RatioSliderMathTests.swift`）。
- 纯展示改动可不强制补单测，但要手动启动看一遍。

不要在测试里访问真实问卷、真实账号、真实付费代理。实测链路走 `LiveSurveyE2ETests` 的环境变量门控，默认跳过。

## Pull Request 要求

PR 描述请写清楚：

- 改了什么。
- 为什么改。
- 影响哪些功能。
- 跑过哪些检查。
- 是否有用户可见变化。

建议格式：

```markdown
## 简述改动
- ...

## 对标的官方实现
- `wjx/provider/http_runtime.py` 中的 ...

## 影响
- ...

## 已跑检查
- [ ] xcodebuild test
- [ ] 手动运行验证
```

如果修复 Issue，请在 PR 描述里关联：

```markdown
Fixes #123
```

## 仓库结构

```markdown
仓库根目录
├── .github/                  # GitHub Actions（CI 与 Release）
├── assets/                   # README 图标、二维码等仓库资源
├── SurveyController/         # 应用主体
│   ├── App/                  # 版本常量
│   ├── Core/                 # 核心业务
│   │   ├── Model/            # 题目/配置/动作等领域模型
│   │   ├── Engine/           # 执行引擎、槽位调度
│   │   ├── Questions/        # 答案生成、逻辑规划、时长采样
│   │   ├── AI/               # AI 填空（规划中）
│   │   ├── Network/          # HTTP 客户端
│   │   ├── Backend/          # 随机 IP 官方后端
│   │   └── Proxy/            # 代理池、地区服务
│   ├── Provider/             # 平台适配
│   │   └── Wjx/              # 问卷星解析/编解码/提交
│   ├── Data/                 # 配置编解码、默认配置、常量
│   ├── Resources/            # 图标 icns、二维码、地区码
│   ├── Support/              # JSON 宽松转换、随机源等辅助
│   └── UI/                   # SwiftUI 界面（向导、社区、关于等）
├── SurveyControllerTests/    # 单元测试（对标官方 CI/unit_tests）
├── SurveyController.xcodeproj
├── AGENTS.md                 # 移植约定（对标文件映射表）
├── CONTRIBUTING.md           # 本文档
└── CODE_OF_CONDUCT.md        # 行为准则
```
