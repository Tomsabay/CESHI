// WeReadWidget.swift
// WidgetKit 扩展：在 iOS 桌面展示微信读书数据
//
// 支持三种尺寸：
//   Small  — 今日阅读时长 + 连续天数火焰
//   Medium — 随机一条今日划线
//   Large  — 最近 3 条划线 + 阅读进度最高的书

import WidgetKit
import SwiftUI
import Intents

// MARK: - 共享数据容器（App Group 传递）

private let appGroupID = "group.com.anthropic.claudeapp.weread"

struct WeReadWidgetEntry: TimelineEntry {
    let date: Date
    let readingStreak: Int          // 连续阅读天数
    let todayMinutes: Int           // 今日阅读分钟数
    let randomHighlight: String?    // 随机一条划线
    let highlightBook: String?      // 划线来源书名
    let recentHighlights: [HighlightSnippet]  // 近期划线列表
    let topBook: BookSnippet?       // 进度最高的书

    struct HighlightSnippet: Codable {
        let text: String
        let bookTitle: String
    }

    struct BookSnippet: Codable {
        let title: String
        let author: String
        let percent: Double
        let coverURL: String
    }

    static var placeholder: WeReadWidgetEntry {
        WeReadWidgetEntry(
            date: Date(),
            readingStreak: 7,
            todayMinutes: 42,
            randomHighlight: "读书是在别人思想的帮助下，建立起自己的思想。",
            highlightBook: "《如何阅读一本书》",
            recentHighlights: [
                .init(text: "专注力是最稀缺的资源。", bookTitle: "《深度工作》"),
                .init(text: "系统比目标更重要。", bookTitle: "《原子习惯》"),
                .init(text: "复利效应在时间维度上近乎奇迹。", bookTitle: "《穷查理宝典》")
            ],
            topBook: .init(title: "《思考，快与慢》", author: "卡尼曼",
                           percent: 0.73, coverURL: "")
        )
    }
}

// MARK: - Timeline Provider

struct WeReadWidgetProvider: TimelineProvider {
    typealias Entry = WeReadWidgetEntry

    func placeholder(in context: Context) -> WeReadWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WeReadWidgetEntry) -> Void) {
        completion(loadEntry() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeReadWidgetEntry>) -> Void) {
        let entry = loadEntry() ?? .placeholder
        // 每小时刷新一次
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    // 从 App Group UserDefaults 读取 App 写入的缓存数据
    private func loadEntry() -> WeReadWidgetEntry? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: "widget_snapshot") else { return nil }

        struct Snapshot: Codable {
            let streak: Int
            let todaySeconds: Int
            let highlights: [WeReadWidgetEntry.HighlightSnippet]
            let topBook: WeReadWidgetEntry.BookSnippet?
        }

        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        let random = snap.highlights.randomElement()

        return WeReadWidgetEntry(
            date: Date(),
            readingStreak: snap.streak,
            todayMinutes: snap.todaySeconds / 60,
            randomHighlight: random?.text,
            highlightBook: random?.bookTitle,
            recentHighlights: snap.highlights,
            topBook: snap.topBook
        )
    }
}

// MARK: - Widget 配置

@main
struct WeReadWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeReadSmallWidget()
        WeReadMediumWidget()
        WeReadLargeWidget()
    }
}

// MARK: - Small Widget：阅读火焰

struct WeReadSmallWidget: Widget {
    let kind = "WeReadSmall"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeReadWidgetProvider()) { entry in
            WeReadSmallView(entry: entry)
        }
        .configurationDisplayName("微信读书 · 阅读火焰")
        .description("显示今日阅读时长和连续打卡天数")
        .supportedFamilies([.systemSmall])
    }
}

struct WeReadSmallView: View {
    let entry: WeReadWidgetEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#1a1a2e"), Color(hex: "#16213e")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: 8) {
                // 火焰 + 天数
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("🔥")
                        .font(.system(size: 32))
                    Text("\(entry.readingStreak)")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.orange)
                }

                Text("连续阅读天")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))

                Divider().background(.white.opacity(0.2))

                // 今日时长
                VStack(spacing: 2) {
                    Text("\(entry.todayMinutes)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("今日分钟")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(12)
        }
        .cornerRadius(16)
    }
}

// MARK: - Medium Widget：今日划线

struct WeReadMediumWidget: Widget {
    let kind = "WeReadMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeReadWidgetProvider()) { entry in
            WeReadMediumView(entry: entry)
        }
        .configurationDisplayName("微信读书 · 每日一句")
        .description("显示今天的随机划线，每小时更新")
        .supportedFamilies([.systemMedium])
    }
}

struct WeReadMediumView: View {
    let entry: WeReadWidgetEntry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#0f3460"), Color(hex: "#533483")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            HStack(spacing: 0) {
                // 左侧装饰
                Rectangle()
                    .frame(width: 4)
                    .foregroundColor(.yellow.opacity(0.8))
                    .cornerRadius(2)
                    .padding(.vertical, 16)
                    .padding(.leading, 12)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.randomHighlight ?? "开始你的阅读之旅")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    HStack {
                        Text(entry.highlightBook ?? "微信读书")
                            .font(.caption2)
                            .foregroundColor(.yellow.opacity(0.8))
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill").foregroundColor(.orange)
                            Text("\(entry.readingStreak)天")
                        }
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .cornerRadius(16)
    }
}

// MARK: - Large Widget：全貌

struct WeReadLargeWidget: Widget {
    let kind = "WeReadLarge"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeReadWidgetProvider()) { entry in
            WeReadLargeView(entry: entry)
        }
        .configurationDisplayName("微信读书 · 阅读全貌")
        .description("显示近期划线和进度最高的书")
        .supportedFamilies([.systemLarge])
    }
}

struct WeReadLargeView: View {
    let entry: WeReadWidgetEntry

    var body: some View {
        ZStack {
            Color(hex: "#0a0a0a")
            VStack(alignment: .leading, spacing: 0) {
                // 头部：统计
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("微信读书").font(.headline).foregroundColor(.white)
                        Text(Date(), style: .date)
                            .font(.caption2).foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        StatPill(icon: "🔥", value: "\(entry.readingStreak)天")
                        StatPill(icon: "⏱", value: "\(entry.todayMinutes)min")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Divider().background(.white.opacity(0.1)).padding(.top, 10)

                // 近期划线
                VStack(alignment: .leading, spacing: 0) {
                    Text("近期划线")
                        .font(.caption.bold())
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    ForEach(entry.recentHighlights.prefix(3), id: \.text) { hl in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 1.5)
                                .frame(width: 3)
                                .foregroundColor(.yellow.opacity(0.7))
                                .padding(.vertical, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hl.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(2)
                                Text(hl.bookTitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }

                Divider().background(.white.opacity(0.1))

                // 当前在读
                if let book = entry.topBook {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("进度最高")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.4))
                            Text(book.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(book.author)
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.5))
                            ProgressView(value: book.percent)
                                .tint(.green)
                                .scaleEffect(x: 1, y: 1.5)
                            Text(String(format: "%.0f%%", book.percent * 100))
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .cornerRadius(16)
    }
}

// MARK: - Widget 数据写入器（在主 App 中调用）

public final class WeReadWidgetDataWriter {
    public static func updateWidgetSnapshot(
        streak: Int,
        todaySeconds: Int,
        highlights: [(text: String, bookTitle: String)],
        topBook: (title: String, author: String, percent: Double, coverURL: String)?
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }

        struct Snapshot: Codable {
            let streak: Int
            let todaySeconds: Int
            let highlights: [WeReadWidgetEntry.HighlightSnippet]
            let topBook: WeReadWidgetEntry.BookSnippet?
        }

        let snap = Snapshot(
            streak: streak,
            todaySeconds: todaySeconds,
            highlights: highlights.map { .init(text: $0.text, bookTitle: $0.bookTitle) },
            topBook: topBook.map {
                .init(title: $0.title, author: $0.author, percent: $0.percent, coverURL: $0.coverURL)
            }
        )

        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: "widget_snapshot")
        }

        // 通知 WidgetKit 刷新
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Helpers

private struct StatPill: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(icon).font(.caption2)
            Text(value).font(.caption2.bold()).foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.1))
        .cornerRadius(8)
    }
}

extension Color {
    init(hex: String) {
        let s = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var v: UInt64 = 0; s.scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
