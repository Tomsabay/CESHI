// WeReadModels.swift
// 微信读书数据模型定义
// 对应微信读书 Web API (i.weread.qq.com) 的返回结构

import Foundation

// MARK: - 书架书籍

/// 书架上的书籍信息
struct WeReadBook: Codable, Identifiable {
    let bookId: String
    let title: String
    let author: String
    let cover: String
    let intro: String?
    let category: String?
    let language: String?
    let publishTime: String?
    let isbn: String?
    let totalWords: Int?
    let readingTime: Int?         // 累计阅读时长（秒）
    let finishReading: Bool?
    let readPercent: Double?      // 阅读进度 0.0~1.0

    var id: String { bookId }

    /// 格式化阅读时长为可读字符串
    var formattedReadingTime: String {
        guard let seconds = readingTime else { return "未读" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }

    /// 阅读进度百分比字符串
    var readPercentText: String {
        guard let p = readPercent else { return "0%" }
        return String(format: "%.1f%%", p * 100)
    }

    enum CodingKeys: String, CodingKey {
        case bookId, title, author, cover, intro, category
        case language, publishTime, isbn, totalWords
        case readingTime, finishReading, readPercent
    }
}

/// 书架响应
struct WeReadShelfResponse: Codable {
    let books: [WeReadShelfBook]
    let synckey: Int?

    struct WeReadShelfBook: Codable {
        let bookId: String
        let readInfo: ReadInfo?
        let book: WeReadBook?

        struct ReadInfo: Codable {
            let readingTime: Int?
            let finishReading: Bool?
            let readPercent: Double?
            let markedStatus: Int?
        }
    }
}

// MARK: - 划线与笔记

/// 划线（高亮）条目
struct WeReadHighlight: Codable, Identifiable {
    let bookmarkId: String
    let bookId: String
    let chapterTitle: String?
    let chapterUid: Int?
    let createTime: Int           // Unix 时间戳
    let markText: String          // 划线文本内容
    let style: Int?               // 划线样式（颜色）

    var id: String { bookmarkId }

    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createTime))
    }

    var styleColor: HighlightColor {
        switch style {
        case 0: return .yellow
        case 1: return .pink
        case 2: return .blue
        case 3: return .green
        default: return .yellow
        }
    }

    enum HighlightColor: String {
        case yellow = "#FFE066"
        case pink   = "#FF8FAB"
        case blue   = "#89C4F4"
        case green  = "#A8E6CF"
    }
}

/// 书籍的所有划线
struct WeReadBookHighlights: Codable {
    let bookId: String
    let updated: [WeReadHighlight]
    let synckey: Int?
}

// MARK: - 笔记（想法）

/// 用户评注/笔记
struct WeReadNote: Codable, Identifiable {
    let reviewId: String
    let bookId: String
    let chapterTitle: String?
    let createTime: Int
    let content: String           // 笔记正文
    let abstract: String?         // 引用的原文摘要
    let type: NoteType

    var id: String { reviewId }

    var createdDate: Date {
        Date(timeIntervalSince1970: Double(createTime))
    }

    enum NoteType: Int, Codable {
        case bookNote    = 1   // 书籍笔记
        case chapterNote = 2   // 章节笔记
        case highlight   = 3   // 划线评论
    }
}

/// 笔记列表响应
struct WeReadNotesResponse: Codable {
    let reviews: [NoteWrapper]
    let synckey: Int?
    let total: Int?

    struct NoteWrapper: Codable {
        let review: WeReadNote
        let book: WeReadBook?
    }
}

// MARK: - 阅读数据统计

/// 用户阅读统计概览
struct WeReadReadingSummary: Codable {
    let totalReadingTime: Int     // 总阅读时长（秒）
    let totalBookCount: Int       // 读过的书籍数量
    let totalReadDays: Int?       // 连续/累计阅读天数
    let weekReadingTime: Int?     // 本周阅读时长（秒）
    let monthReadingTime: Int?    // 本月阅读时长（秒）
    let dailyRecords: [DailyRecord]?

    struct DailyRecord: Codable {
        let date: String          // "yyyy-MM-dd"
        let readingTime: Int      // 当天阅读秒数
    }

    var formattedTotalTime: String {
        let hours = totalReadingTime / 3600
        let minutes = (totalReadingTime % 3600) / 60
        return "\(hours)小时\(minutes)分钟"
    }
}

// MARK: - 目录章节

struct WeReadChapter: Codable, Identifiable {
    let chapterUid: Int
    let title: String
    let level: Int?
    let anchors: [ChapterAnchor]?

    var id: Int { chapterUid }

    struct ChapterAnchor: Codable {
        let anchorId: String
        let title: String
        let level: Int?
    }
}

struct WeReadTableOfContents: Codable {
    let bookId: String
    let updated: [WeReadChapter]
}

// MARK: - 用户信息

struct WeReadUserProfile: Codable {
    let userVid: Int?
    let name: String
    let avatar: String?
    let intro: String?
    let followerCount: Int?
    let followingCount: Int?
    let bookCount: Int?
    let noteCount: Int?
}

// MARK: - 错误

enum WeReadError: Error, LocalizedError {
    case notAuthenticated
    case networkError(Error)
    case invalidResponse
    case apiError(Int, String)
    case rateLimited
    case sessionExpired

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "未登录，请先扫码登录微信读书"
        case .networkError(let e):
            return "网络错误：\(e.localizedDescription)"
        case .invalidResponse:
            return "服务器返回数据格式错误"
        case .apiError(let code, let msg):
            return "API 错误 [\(code)]：\(msg)"
        case .rateLimited:
            return "请求过于频繁，请稍后再试"
        case .sessionExpired:
            return "登录已过期，请重新扫码登录"
        }
    }
}
