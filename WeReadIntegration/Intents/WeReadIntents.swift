// WeReadIntents.swift
// App Intents 集成：Siri、快捷指令 App、Spotlight 搜索
//
// 支持的语音指令示例：
//   "嘿 Siri，用微信读书查一下我今天读了多久"
//   "嘿 Siri，给我一条今天的随机划线"
//   "嘿 Siri，帮我分析《原子习惯》的笔记"
//   "嘿 Siri，我的阅读连续打卡几天了"

import AppIntents
import SwiftUI

// MARK: - 1. 查询今日阅读时长

struct QueryTodayReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "查询今日阅读时长"
    static var description = IntentDescription("查看今天在微信读书上阅读了多久")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let records = try await WeReadAPIClient.shared.fetchDailyReadingTime(days: 1)
        let todayRecord = records.first
        let minutes = (todayRecord?.readingTime ?? 0) / 60
        let hours = minutes / 60
        let mins = minutes % 60

        let summary = try await WeReadAPIClient.shared.fetchReadingSummary()
        let streak = summary.totalReadDays ?? 0

        let text: String
        if hours > 0 {
            text = "今天已经阅读了 \(hours) 小时 \(mins) 分钟，连续打卡 \(streak) 天，继续加油！"
        } else if minutes > 0 {
            text = "今天已阅读 \(minutes) 分钟，连续打卡 \(streak) 天。"
        } else {
            text = "今天还没有阅读记录，要不现在打开微信读书读几页？"
        }

        return .result(dialog: IntentDialog(text)) {
            ReadingTimeSnippetView(minutes: minutes, streak: streak)
        }
    }
}

// MARK: - 2. 获取随机划线

struct RandomHighlightIntent: AppIntent {
    static var title: LocalizedStringResource = "获取随机划线"
    static var description = IntentDescription("从微信读书划线中随机获取一条，作为每日思考")
    static var openAppWhenRun = false

    @Parameter(title: "书名（可选）")
    var bookTitle: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let highlights = try await WeReadAPIClient.shared.fetchAllHighlights()

        let pool: [WeReadHighlight]
        if let title = bookTitle, !title.isEmpty {
            let books = try await WeReadAPIClient.shared.fetchShelf()
            if let book = books.first(where: { $0.title.contains(title) }) {
                pool = try await WeReadAPIClient.shared.fetchHighlights(bookId: book.bookId)
            } else {
                pool = highlights
            }
        } else {
            pool = highlights
        }

        guard let random = pool.randomElement() else {
            return .result(dialog: "暂时没有找到划线，先去微信读书划几条吧！") {
                EmptyView()
            }
        }

        return .result(dialog: IntentDialog(random.markText)) {
            HighlightSnippetView(text: random.markText, chapterTitle: random.chapterTitle)
        }
    }
}

// MARK: - 3. 查询阅读连续天数

struct ReadingStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "查询阅读连续天数"
    static var description = IntentDescription("查看当前微信读书连续阅读打卡天数")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await WeReadAPIClient.shared.fetchReadingSummary()
        let streak = summary.totalReadDays ?? 0
        let total = summary.totalReadingTime / 3600

        let dialog: String
        switch streak {
        case 0:
            dialog = "还没有开始打卡，今天就是第一天！"
        case 1...7:
            dialog = "已经连续阅读 \(streak) 天了，好的开始！"
        case 8...30:
            dialog = "连续阅读 \(streak) 天，习惯正在养成，累计 \(total) 小时！"
        default:
            dialog = "哇！连续阅读 \(streak) 天，累计 \(total) 小时，你是真正的读书人！"
        }

        return .result(dialog: IntentDialog(dialog))
    }
}

// MARK: - 4. AI 分析指定书籍

struct AnalyzeBookIntent: AppIntent {
    static var title: LocalizedStringResource = "AI 分析书籍笔记"
    static var description = IntentDescription("让 Claude 分析某本书的划线和笔记")
    static var openAppWhenRun = true  // 需要打开 App 展示结果

    @Parameter(title: "书名")
    var bookTitle: String

    @Parameter(title: "分析类型", default: .keyInsights)
    var analysisType: WeReadAnalysisTypeEntity

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        // 打开 App 并导航到分析页
        return .result(opensIntent: NavigateToAnalysisIntent(bookTitle: bookTitle))
    }
}

// MARK: - 5. 搜索划线

struct SearchHighlightsIntent: AppIntent {
    static var title: LocalizedStringResource = "搜索划线"
    static var description = IntentDescription("在微信读书划线中搜索相关内容")

    @Parameter(title: "搜索关键词")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let highlights = try await WeReadAPIClient.shared.fetchAllHighlights()
        let matched = highlights.filter {
            $0.markText.localizedCaseInsensitiveContains(query)
        }.prefix(3)

        if matched.isEmpty {
            return .result(dialog: "没有找到包含「\(query)」的划线") {
                EmptyView()
            }
        }

        let preview = matched.map { "• \($0.markText.prefix(50))" }.joined(separator: "\n")
        return .result(dialog: "找到 \(matched.count) 条相关划线：\n\(preview)") {
            SearchResultsSnippetView(query: query, results: Array(matched))
        }
    }
}

// MARK: - 6. 导航到分析页（内部 Intent）

struct NavigateToAnalysisIntent: AppIntent {
    static var title: LocalizedStringResource = "打开书籍分析"

    @Parameter(title: "书名")
    var bookTitle: String

    init(bookTitle: String = "") {
        self.bookTitle = bookTitle
    }

    func perform() async throws -> some IntentResult {
        // 通过 DeepLink 导航
        return .result()
    }
}

// MARK: - 分析类型 Entity

struct WeReadAnalysisTypeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "分析类型"
    static var defaultQuery = WeReadAnalysisTypeQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    static let keyInsights = WeReadAnalysisTypeEntity(id: "核心洞见")
    static let readingSummary = WeReadAnalysisTypeEntity(id: "阅读总结")
    static let bookRecommend = WeReadAnalysisTypeEntity(id: "书单推荐")
    static let notesOrganize = WeReadAnalysisTypeEntity(id: "笔记整理")
}

struct WeReadAnalysisTypeQuery: EntityQuery {
    func entities(for ids: [String]) async throws -> [WeReadAnalysisTypeEntity] {
        ids.map { WeReadAnalysisTypeEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [WeReadAnalysisTypeEntity] {
        [.keyInsights, .readingSummary, .bookRecommend, .notesOrganize]
    }
}

// MARK: - Shortcuts App Provider

struct WeReadShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QueryTodayReadingIntent(),
            phrases: [
                "查看\(.applicationName)今日阅读时长",
                "我今天读了多久书",
                "今天\(.applicationName)读书多久了"
            ],
            shortTitle: "今日阅读时长",
            systemImageName: "clock.fill"
        )

        AppShortcut(
            intent: RandomHighlightIntent(),
            phrases: [
                "给我一条\(.applicationName)划线",
                "随机\(.applicationName)读书名言",
                "\(.applicationName)每日一句"
            ],
            shortTitle: "随机划线",
            systemImageName: "text.quote"
        )

        AppShortcut(
            intent: ReadingStreakIntent(),
            phrases: [
                "我\(.applicationName)连续读书几天了",
                "查看\(.applicationName)打卡天数",
                "\(.applicationName)阅读连续天数"
            ],
            shortTitle: "连续打卡天数",
            systemImageName: "flame.fill"
        )

        AppShortcut(
            intent: SearchHighlightsIntent(),
            phrases: [
                "在\(.applicationName)搜索\(\.$query)",
                "\(.applicationName)查找关于\(\.$query)的划线"
            ],
            shortTitle: "搜索划线",
            systemImageName: "magnifyingglass"
        )
    }
}

// MARK: - Snippet Views（Siri UI 展示）

struct ReadingTimeSnippetView: View {
    let minutes: Int
    let streak: Int

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("\(minutes)").font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundColor(.blue)
                Text("分钟").font(.caption).foregroundColor(.secondary)
            }
            Divider().frame(height: 44)
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("🔥")
                    Text("\(streak)").font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                }
                Text("连续天").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

struct HighlightSnippetView: View {
    let text: String
    let chapterTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.body.italic())
                .padding(12)
                .background(.yellow.opacity(0.15))
                .cornerRadius(8)
            if let chapter = chapterTitle {
                Text("— \(chapter)").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

struct SearchResultsSnippetView: View {
    let query: String
    let results: [WeReadHighlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("「\(query)」相关划线")
                .font(.caption.bold()).foregroundColor(.secondary)
            ForEach(results) { h in
                Text(h.markText)
                    .font(.subheadline)
                    .lineLimit(2)
                    .padding(8)
                    .background(.blue.opacity(0.08))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}
