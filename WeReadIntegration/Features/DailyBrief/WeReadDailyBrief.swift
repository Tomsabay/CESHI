// WeReadDailyBrief.swift
// 每日阅读简报：早晨自动生成 AI 摘要并推送通知
//
// 功能：
//   1. BGAppRefreshTask 后台拉取昨日阅读数据
//   2. Claude 生成 3 段式简报（昨日回顾 / 今日推荐 / 随机精华）
//   3. UNUserNotificationCenter 推送富文本通知
//   4. 应用内展示完整简报（时间线样式）

import Foundation
import UserNotifications
import BackgroundTasks
import SwiftUI

// MARK: - 简报数据

struct DailyBrief: Codable, Identifiable {
    let id: UUID
    let date: Date
    let yesterdayRecap: String      // 昨日阅读回顾
    let todayRecommendation: String // 今日推荐阅读片段
    let goldHighlight: String       // 精选划线
    let goldHighlightBook: String   // 精选划线来源书
    let readingMinutes: Int         // 昨日阅读时长
    let bookCount: Int              // 昨日阅读书目数

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

// MARK: - 简报管理器

@MainActor
final class WeReadDailyBriefManager: ObservableObject {

    static let shared = WeReadDailyBriefManager()

    @Published var todayBrief: DailyBrief?
    @Published var briefHistory: [DailyBrief] = []
    @Published var isGenerating = false
    @Published var notificationsEnabled = false

    private let bgTaskIdentifier = "com.claudeapp.weread.dailybrief"
    private let storageKey = "weread_daily_briefs"
    private let apiClient = WeReadAPIClient.shared

    private init() {
        loadHistory()
        todayBrief = briefHistory.first { Calendar.current.isDateInToday($0.date) }
        checkNotificationStatus()
    }

    // MARK: - 通知权限

    func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsEnabled = granted
            if granted { scheduleMorningNotification() }
            return granted
        } catch {
            return false
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsEnabled = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - 生成简报

    func generateTodayBrief() async {
        guard !isGenerating else { return }
        isGenerating = true

        do {
            // 拉取昨日数据
            let records = try await apiClient.fetchDailyReadingTime(days: 2)
            let yesterday = records.first { record in
                let cal = Calendar.current
                guard let recordDate = parseDate(record.date) else { return false }
                return cal.isDateInYesterday(recordDate)
            }

            let highlights = try await apiClient.fetchAllHighlights()
            let recentHighlights = highlights
                .filter { $0.createTime > Int(Date().addingTimeInterval(-86400 * 2).timeIntervalSince1970) }

            let brief = await generateWithClaude(
                yesterdayMinutes: (yesterday?.readingTime ?? 0) / 60,
                recentHighlights: recentHighlights,
                allHighlights: highlights
            )

            todayBrief = brief
            briefHistory.insert(brief, at: 0)
            if briefHistory.count > 30 { briefHistory = Array(briefHistory.prefix(30)) }
            saveBriefHistory()

            // 推送通知
            if notificationsEnabled {
                scheduleImmediateNotification(brief: brief)
            }

            // 更新 Widget
            updateWidget(brief: brief, highlights: allHighlightsForWidget(highlights))

        } catch {
            // 静默失败，不打断用户
        }

        isGenerating = false
    }

    // MARK: - Claude 生成

    private func generateWithClaude(
        yesterdayMinutes: Int,
        recentHighlights: [WeReadHighlight],
        allHighlights: [WeReadHighlight]
    ) async -> DailyBrief {
        let gold = allHighlights.randomElement()
        let goldBook = "未知书籍" // 实际应 join book 数据

        guard let apiKey = KeychainHelper.shared.getString(
            service: "com.anthropic.claudeapp", key: "api_key"),
              !recentHighlights.isEmpty else {
            // 无 API Key 或无数据 → 用模板简报
            return DailyBrief(
                id: UUID(), date: Date(),
                yesterdayRecap: "昨日阅读了 \(yesterdayMinutes) 分钟，继续保持！",
                todayRecommendation: "每天坚持阅读，知识在复利积累中生长。",
                goldHighlight: gold?.markText ?? "坚持阅读，是最好的投资。",
                goldHighlightBook: goldBook,
                readingMinutes: yesterdayMinutes, bookCount: 1
            )
        }

        let highlightTexts = recentHighlights.prefix(15).map { $0.markText }.joined(separator: "\n")
        let prompt = """
        今天是\(formattedToday())，用户昨天阅读了 \(yesterdayMinutes) 分钟，
        以下是他最近的划线：
        \(highlightTexts)

        请生成一份简洁的早晨阅读简报，返回 JSON：
        {
          "recap": "昨日回顾，1-2句，鼓励而不夸张",
          "recommendation": "今日推荐，基于划线主题给一个今天可以思考的问题或行动，1-2句",
          "goldHighlight": "从上述划线中选出最有价值的一句，原文返回"
        }
        语气：清晨的轻盈感，不说教，有温度。只返回 JSON。
        """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return fallbackBrief(minutes: yesterdayMinutes, gold: gold)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 512,
            "messages": [["role": "user", "content": prompt]]
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (json["content"] as? [[String: Any]])?.first?["text"] as? String else {
            return fallbackBrief(minutes: yesterdayMinutes, gold: gold)
        }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let d = cleaned.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return DailyBrief(
                id: UUID(), date: Date(),
                yesterdayRecap: obj["recap"] as? String ?? "",
                todayRecommendation: obj["recommendation"] as? String ?? "",
                goldHighlight: obj["goldHighlight"] as? String ?? gold?.markText ?? "",
                goldHighlightBook: goldBook,
                readingMinutes: yesterdayMinutes,
                bookCount: Set(recentHighlights.map { $0.bookId }).count
            )
        }

        return fallbackBrief(minutes: yesterdayMinutes, gold: gold)
    }

    private func fallbackBrief(minutes: Int, gold: WeReadHighlight?) -> DailyBrief {
        DailyBrief(
            id: UUID(), date: Date(),
            yesterdayRecap: "昨天阅读了 \(minutes) 分钟，积累在悄悄发生。",
            todayRecommendation: "今天可以回顾昨天的一条划线，让它在脑海中发酵。",
            goldHighlight: gold?.markText ?? "阅读是最安静的冒险。",
            goldHighlightBook: "你的书架",
            readingMinutes: minutes, bookCount: 1
        )
    }

    // MARK: - 推送通知

    private func scheduleMorningNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weread.morning"])

        var components = DateComponents()
        components.hour = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "📚 今日阅读简报"
        content.body = "点击查看 Claude 为你生成的今日阅读摘要"
        content.sound = .default
        content.categoryIdentifier = "WEREAD_BRIEF"

        let request = UNNotificationRequest(
            identifier: "weread.morning",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func scheduleImmediateNotification(brief: DailyBrief) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "📚 \(brief.formattedDate)阅读简报"
        content.subtitle = brief.goldHighlight.prefix(50) + (brief.goldHighlight.count > 50 ? "…" : "")
        content.body = brief.yesterdayRecap
        content.sound = .default

        // 富文本通知附件（摘要）
        content.userInfo = ["brief_id": brief.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "weread.brief.\(brief.id.uuidString)",
            content: content, trigger: nil
        )
        center.add(request)
    }

    // MARK: - 后台刷新注册

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                await self.generateTodayBrief()
                task.setTaskCompleted(success: true)
                self.scheduleNextBackgroundRefresh()
            }
        }
        scheduleNextBackgroundRefresh()
    }

    private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        var tomorrow7AM = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date()
        if tomorrow7AM < Date() {
            tomorrow7AM = Calendar.current.date(byAdding: .day, value: 1, to: tomorrow7AM) ?? tomorrow7AM
        }
        request.earliestBeginDate = tomorrow7AM
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Widget 更新

    private func updateWidget(brief: DailyBrief, highlights: [(text: String, bookTitle: String)]) {
        // 调用之前实现的 WeReadWidgetDataWriter
    }

    private func allHighlightsForWidget(_ highlights: [WeReadHighlight]) -> [(text: String, bookTitle: String)] {
        return highlights.prefix(30).map { ($0.markText, "书籍") }
    }

    // MARK: - 持久化

    private func saveBriefHistory() {
        if let data = try? JSONEncoder().encode(briefHistory) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let history = try? JSONDecoder().decode([DailyBrief].self, from: data) else { return }
        briefHistory = history
    }

    // MARK: - Helpers

    private func formattedToday() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy年M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    private func parseDate(_ str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: str)
    }
}

// MARK: - 简报 UI

struct WeReadDailyBriefView: View {
    @ObservedObject private var manager = WeReadDailyBriefManager.shared
    @State private var showPermissionAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 今日简报
                if manager.isGenerating {
                    generatingView
                } else if let brief = manager.todayBrief {
                    BriefCard(brief: brief, isToday: true)
                } else {
                    generatePrompt
                }

                // 历史简报
                if !manager.briefHistory.filter({ !Calendar.current.isDateInToday($0.date) }).isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("历史简报")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(manager.briefHistory.filter {
                            !Calendar.current.isDateInToday($0.date)
                        }.prefix(7)) { brief in
                            BriefCard(brief: brief, isToday: false)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("每日简报")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("立即生成", systemImage: "sparkles") {
                        Task { await manager.generateTodayBrief() }
                    }
                    if !manager.notificationsEnabled {
                        Button("开启早晨推送", systemImage: "bell.badge") {
                            Task {
                                _ = await manager.requestNotificationPermission()
                            }
                        }
                    } else {
                        Label("已开启早 8:00 推送", systemImage: "bell.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.3)
            Text("Claude 正在生成今日简报...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var generatePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.horizon.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("今日简报未生成")
                .font(.headline)
            Text("点击生成基于你阅读数据的个性化早晨简报")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await manager.generateTodayBrief() }
            } label: {
                Label("生成今日简报", systemImage: "sparkles")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding(40)
    }
}

struct BriefCard: View {
    let brief: DailyBrief
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 日期头
            HStack {
                if isToday {
                    Label("今日", systemImage: "sun.max.fill").foregroundColor(.orange)
                        .font(.caption.bold())
                }
                Text(brief.formattedDate)
                    .font(isToday ? .headline : .subheadline)
                    .foregroundColor(isToday ? .primary : .secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.caption2)
                    Text("\(brief.readingMinutes)分钟")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }

            // 三段内容
            BriefSection(icon: "📖", title: "昨日回顾", content: brief.yesterdayRecap)
            BriefSection(icon: "💡", title: "今日推荐", content: brief.todayRecommendation)

            // 精华划线
            VStack(alignment: .leading, spacing: 6) {
                Label("精选划线", systemImage: "highlighter")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text(brief.goldHighlight)
                    .font(.body.italic())
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.15))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.yellow.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .padding(.horizontal)
        .overlay(
            isToday ? RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.4), lineWidth: 1.5)
                .padding(.horizontal) : nil
        )
    }
}

private struct BriefSection: View {
    let icon: String
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(icon) \(title)")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(content)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
