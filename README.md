<div align="center">
  <h1>SurveyController Mac</h1>

  [![GitHub Stars](https://img.shields.io/github/stars/SurveyController/SurveyController-Mac?style=flat&logo=github&color=yellow)](https://github.com/SurveyController/SurveyController-Mac/stargazers)
  [![GitHub Release](https://img.shields.io/github/v/release/SurveyController/SurveyController-Mac?style=flat&logo=github&color=blue)](https://github.com/SurveyController/SurveyController-Mac/releases/latest)
  ![Downloads](https://img.shields.io/github/downloads/SurveyController/SurveyController-Mac/total?style=flat&logo=github&color=green)
  [![Issues](https://img.shields.io/github/issues/SurveyController/SurveyController-Mac?style=flat&logo=github)](https://github.com/SurveyController/SurveyController-Mac/issues)
  [![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org/)
  [![macOS](https://img.shields.io/badge/macOS-14+-000000?style=flat&logo=macos&logoColor=white)](https://www.apple.com/macos/)
  [![License](https://img.shields.io/github/license/SurveyController/SurveyController-Mac?style=flat&color=orange)](./LICENSE)

  <p><strong>一站式问卷自动化处理程序 macOS 端，适配问卷星、腾讯问卷、Credamo见数平台</strong></p>
  <p>支持指定ip填写地区、信度系数、作答时长与分布比例</p>

</div>

> [!WARNING]
> **该项目仅供 HTTP 接口自动化学习与测试使用。** 请确保拥有目标测试问卷的授权再使用，**严禁污染他人问卷数据！**

---

## 主要特性

1. **原生 Mac 体验** - 纯 Swift + SwiftUI 构建，macOS 14+ 原生界面
2. **多平台支持** - 逐步对齐官方功能：v0.1 起支持问卷星，腾讯问卷、Credamo见数后续版本跟进
3. **定制答案比例** - 自定义各选项权重与多选题命中概率分布
4. **指定ip地区** - 支持随机IP或指定特定地区IP提交
5. **配置导入导出** - 与桌面版配置文件互通，跨设备同步
6. **AI 主观题作答** - 填空题自动生成作答内容（自定义服务商）

## 演示视频

![演示视频](https://github.com/SurveyController/SurveyController-Mac/releases/download/v0.1.0/demo.gif)

> 高清带声音版本：[demo.mp4](https://github.com/SurveyController/SurveyController-Mac/releases/download/v0.1.0/demo.mp4)

## 开始使用

> [!TIP]
> **安装包：** 前往 [发行版](https://github.com/SurveyController/SurveyController-Mac/releases/latest) 下载最新版本压缩包，解压后拖入「应用程序」文件夹即可

**系统要求：** macOS 14（Sonoma）及以上

> 首个版本未做 Developer ID 公证，首次打开请右键 →「打开」，或在「系统设置 → 隐私与安全性」中允许。

建议配合[教程文档](https://surveydoc.hungrym0.com/)食用。Windows 版请前往 [SurveyController](https://github.com/SurveyController/SurveyController)，安卓版请前往 [SurveyController-Android](https://github.com/shiaho777/SurveyController-Android)。

### 从源码构建

**环境要求：** Xcode 16+ / macOS 14+

```bash
git clone https://github.com/SurveyController/SurveyController-Mac.git
cd SurveyController-Mac
open SurveyController.xcodeproj   # Xcode 中 Cmd+R 运行

# 或命令行构建
xcodebuild -project SurveyController.xcodeproj -scheme SurveyController build
```

## 使用方法

1. **输入问卷** - 在概览页粘贴问卷链接
2. **自动解析** - 点击 `自动配置问卷`，自动识别平台和题目结构
3. **调整配置** - 在配置向导中调整各题答案权重和概率分布
4. **设置运行参数** - 指定目标提交份数、并发数、随机IP等设置项
5. **启动任务** - 点击 `开始执行` 并等待任务完成

## 技术架构

```mermaid
flowchart TB
  link["问卷链接"]
  detect["平台识别"]
  config["答题配置<br/>选项权重 / 多选概率 / 填空内容 / 作答时长"]
  session["HTTP 会话<br/>User-Agent / Referer / 代理 IP"]
  result["提交结果<br/>成功 / 失败 / 重试"]

  link --> detect
  detect --> wjx
  config --> session
  session --> result
```

- **UI 层**：SwiftUI（NavigationSplitView 侧边导航），对标官方 PySide6 Fluent 界面结构
- **引擎层**：Swift Concurrency（actor + TaskGroup），对标官方 asyncio 引擎
- **平台适配层**：Provider 协议 + 注册表，对标官方 providers/registry.py
- **依赖**：仅 SwiftSoup（HTML 解析），其余全部系统框架

## 参与贡献

欢迎提交 Pull Request，改进方向包括但不限于：
- 腾讯问卷 / Credamo见数 链路移植
- macOS 原生特性（菜单栏、快捷键、Touch Bar、小组件）
- 性能优化与代码重构

## 致谢

本项目基于 [SurveyController](https://github.com/SurveyController/SurveyController) macOS 端移植，感谢原项目团队的开源贡献。

## 交流群

如有疑问或需要技术支持，可加入QQ群：
346131215
