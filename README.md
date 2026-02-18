# WeRead Integration for Claude iOS App

将微信读书数据接入 Claude iOS App，实现 AI 驱动的个性化阅读分析。

## 功能概述

| 功能 | 说明 |
|------|------|
| 二维码登录 | 通过内嵌 WKWebView 扫码登录微信读书，Cookie 安全存储在 Keychain |
| 书架同步 | 获取用户全部书架书籍，含阅读进度和时长 |
| 划线读取 | 读取所有书籍的划线（支持按颜色分类） |
| 笔记同步 | 同步用户的想法/评注 |
| 阅读统计 | 累计阅读时长、天数、书籍数等 |
| Claude AI 分析 | 6 种分析模式，流式输出 |
| 对话附加 | 在 Claude 对话中一键附加书籍划线 |

## 架构

```
WeReadIntegration/
├── WeReadIntegration.swift          # 公开入口 View 和集成配置
├── API/
│   ├── WeReadModels.swift           # 数据模型（Book, Highlight, Note...）
│   ├── WeReadAuthManager.swift      # 认证管理（WKWebView + Keychain）
│   └── WeReadAPIClient.swift        # HTTP API 封装（i.weread.qq.com）
├── Claude/
│   └── ClaudeWeReadAnalyzer.swift   # Claude API 调用（流式 SSE）
├── Views/
│   ├── WeReadLoginView.swift        # 登录界面
│   ├── WeReadDashboardView.swift    # 主界面（书架/划线/AI分析）
│   └── BookDetailView.swift         # 书籍详情页
└── Utils/
    └── WeReadAuthManagerPublic.swift # Auth 扩展方法
```

## 快速集成

### 1. 添加到 Claude App

在 `AppDelegate.application(_:didFinishLaunchingWithOptions:)` 中：

```swift
import WeReadIntegration

func application(_ application: UIApplication, ...) -> Bool {
    WeReadIntegration.setup()  // 恢复上次 Session
    return true
}
```

### 2. 显示主界面

```swift
// 在任意 NavigationStack 中
NavigationLink("微信读书") {
    WeReadIntegrationView()
}
```

### 3. 在对话框附加书籍划线

```swift
// 在消息输入框旁添加按钮
WeReadAttachButton { markdownText in
    // markdownText 包含书籍信息和划线，直接附加到对话
    appendToCurrentConversation(markdownText)
}
```

## Claude AI 分析类型

| 类型 | 说明 |
|------|------|
| 阅读总结 | 生成个人阅读报告，分析偏好和习惯 |
| 书单推荐 | 基于已读书单推荐相似书籍 |
| 笔记整理 | 将划线整理为 Zettelkasten 知识卡片 |
| 主题分析 | 分析阅读内容折射的思想主题 |
| 核心洞见 | 提炼最有价值的 20 条洞见 |
| 自定义提问 | 基于阅读数据的任意问答 |

## 认证原理

微信读书 Web 端通过 Cookie 认证，关键 Cookie：
- `wr_vid`：用户 ID
- `wr_skey`：会话密钥
- `wr_rt`：刷新 Token

通过 WKWebView 加载 `https://weread.qq.com/#login`，用户完成扫码登录后，
从 `WKHTTPCookieStore` 提取上述 Cookie 并存储至 iOS Keychain。

## API 端点

基础地址：`https://i.weread.qq.com`

| 端点 | 功能 |
|------|------|
| `GET /shelf/friendCommon` | 获取书架 |
| `GET /book/bookmarklist` | 获取书籍划线 |
| `GET /user/notebooks` | 获取全部划线 |
| `GET /review/list` | 获取笔记 |
| `GET /readdata/summary` | 获取阅读统计 |
| `GET /user/profile` | 获取用户信息 |

> **注意**：以上 API 为非官方接口，基于微信读书 Web 端逆向，可能随官方更新变化。

## 系统要求

- iOS 16.0+
- Swift 5.9+
- Xcode 15+
- 需要 Claude App 已登录（用于读取 Claude API Key）

## 隐私说明

- 所有数据仅在用户设备本地处理
- Cookie 使用 iOS Keychain 安全存储
- 发送给 Claude API 的数据受 Anthropic 隐私政策保护
- 不向任何第三方服务器上传用户数据
