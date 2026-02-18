// WeReadAPIClient.swift
// 微信读书 Web API 封装
// 基于 i.weread.qq.com 非官方 API，通过 Cookie 认证访问用户数据

import Foundation

// MARK: - API 客户端

@MainActor
final class WeReadAPIClient: ObservableObject {

    static let shared = WeReadAPIClient()

    private let baseURL = "https://i.weread.qq.com"
    private let authManager = WeReadAuthManager.shared

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.0",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Origin": "https://weread.qq.com",
            "Referer": "https://weread.qq.com/"
        ]
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - 书架

    /// 获取用户书架书籍列表
    func fetchShelf() async throws -> [WeReadBook] {
        let data = try await request(path: "/shelf/friendCommon", params: ["userVid": 0, "synckey": 0])
        let response = try decode(WeReadShelfResponse.self, from: data)
        return response.books.compactMap { $0.book }
    }

    /// 获取书籍详细信息
    func fetchBookInfo(bookId: String) async throws -> WeReadBook {
        let data = try await request(path: "/book/info", params: ["bookId": bookId])
        return try decode(WeReadBook.self, from: data)
    }

    // MARK: - 划线

    /// 获取指定书籍的所有划线
    func fetchHighlights(bookId: String) async throws -> [WeReadHighlight] {
        let data = try await request(path: "/book/bookmarklist", params: ["bookId": bookId])
        let response = try decode(WeReadBookHighlights.self, from: data)
        return response.updated
    }

    /// 获取用户所有书籍的划线（分页）
    func fetchAllHighlights(syncKey: Int = 0) async throws -> [WeReadHighlight] {
        let data = try await request(path: "/user/notebooks", params: ["synckey": syncKey])

        // notebooks 接口返回按书籍分组的划线
        struct NotebookResponse: Codable {
            struct BookHighlights: Codable {
                let bookId: String?
                let updated: [WeReadHighlight]?
            }
            let books: [BookHighlights]?
        }

        let response = try decode(NotebookResponse.self, from: data)
        return response.books?.flatMap { $0.updated ?? [] } ?? []
    }

    // MARK: - 笔记

    /// 获取用户所有笔记，可按书籍过滤
    func fetchNotes(bookId: String? = nil, count: Int = 20, syncKey: Int = 0) async throws -> WeReadNotesResponse {
        var params: [String: Any] = ["count": count, "synckey": syncKey, "listType": 11]
        if let bookId = bookId {
            params["bookId"] = bookId
        }
        let data = try await request(path: "/review/list", params: params)
        return try decode(WeReadNotesResponse.self, from: data)
    }

    // MARK: - 阅读统计

    /// 获取阅读统计汇总
    func fetchReadingSummary() async throws -> WeReadReadingSummary {
        let data = try await request(path: "/readdata/summary", params: [:])
        return try decode(WeReadReadingSummary.self, from: data)
    }

    /// 获取指定时间范围内的每日阅读时长
    func fetchDailyReadingTime(days: Int = 30) async throws -> [WeReadReadingSummary.DailyRecord] {
        let endTime = Int(Date().timeIntervalSince1970)
        let startTime = endTime - days * 86400
        let data = try await request(path: "/readdata/detail",
                                     params: ["startTime": startTime, "endTime": endTime])

        struct DetailResponse: Codable {
            let datas: [WeReadReadingSummary.DailyRecord]?
        }
        let response = try decode(DetailResponse.self, from: data)
        return response.datas ?? []
    }

    // MARK: - 目录

    /// 获取书籍目录
    func fetchTableOfContents(bookId: String) async throws -> WeReadTableOfContents {
        let data = try await request(path: "/book/chapterInfos",
                                     params: ["bookIds": [bookId], "synckeys": [0]])
        return try decode(WeReadTableOfContents.self, from: data)
    }

    // MARK: - 批量获取（用于分析）

    /// 批量获取书架 + 所有划线 + 笔记，用于 Claude 综合分析
    func fetchAllDataForAnalysis() async throws -> WeReadUserData {
        async let shelfTask = fetchShelf()
        async let highlightsTask = fetchAllHighlights()
        async let notesTask = fetchNotes(count: 100)
        async let summaryTask = fetchReadingSummary()

        let (books, highlights, notesResponse, summary) = try await (
            shelfTask, highlightsTask, notesTask, summaryTask
        )

        let notes = notesResponse.reviews.map { $0.review }
        return WeReadUserData(
            books: books,
            highlights: highlights,
            notes: notes,
            summary: summary
        )
    }

    // MARK: - 私有请求方法

    private func request(path: String, params: [String: Any]) async throws -> Data {
        guard let cookieHeader = authManager.cookieHeader else {
            throw WeReadError.notAuthenticated
        }

        // 构造 URL
        guard var components = URLComponents(string: baseURL + path) else {
            throw WeReadError.invalidResponse
        }

        // GET 参数序列化
        components.queryItems = params.map { key, value in
            URLQueryItem(name: key, value: "\(value)")
        }

        guard let url = components.url else {
            throw WeReadError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WeReadError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                // 检查返回体是否含错误码
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errCode = json["errCode"] as? Int, errCode != 0 {
                    if errCode == -2012 {
                        throw WeReadError.sessionExpired
                    }
                    let errMsg = json["errMsg"] as? String ?? "未知错误"
                    throw WeReadError.apiError(errCode, errMsg)
                }
                return data
            case 401:
                throw WeReadError.sessionExpired
            case 429:
                throw WeReadError.rateLimited
            default:
                throw WeReadError.apiError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
            }
        } catch let error as WeReadError {
            throw error
        } catch {
            throw WeReadError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WeReadError.invalidResponse
        }
    }
}

// MARK: - 聚合数据结构（用于传入 Claude）

struct WeReadUserData {
    let books: [WeReadBook]
    let highlights: [WeReadHighlight]
    let notes: [WeReadNote]
    let summary: WeReadReadingSummary

    /// 将数据序列化为 Markdown 格式，方便 Claude 阅读
    func toMarkdown() -> String {
        var md = "# 我的微信读书数据\n\n"

        // 统计概览
        md += "## 阅读统计\n"
        md += "- 累计阅读时长：\(summary.formattedTotalTime)\n"
        md += "- 读过书籍数：\(summary.totalBookCount) 本\n"
        if let days = summary.totalReadDays {
            md += "- 累计阅读天数：\(days) 天\n"
        }
        md += "\n"

        // 书架
        md += "## 书架（共 \(books.count) 本）\n"
        for book in books.prefix(50) {  // 最多展示 50 本避免 token 过多
            md += "- **\(book.title)** by \(book.author)"
            md += "（已读 \(book.readPercentText)，阅读时长 \(book.formattedReadingTime)）\n"
        }
        md += "\n"

        // 划线
        if !highlights.isEmpty {
            md += "## 划线（共 \(highlights.count) 条）\n"
            for h in highlights.prefix(100) {
                md += "> \(h.markText)\n"
                if let chapter = h.chapterTitle {
                    md += "> *——《章节：\(chapter)》*\n"
                }
                md += "\n"
            }
        }

        // 笔记
        if !notes.isEmpty {
            md += "## 我的笔记（共 \(notes.count) 条）\n"
            for note in notes.prefix(50) {
                if let abstract = note.abstract {
                    md += "**原文**：\(abstract)\n"
                }
                md += "**笔记**：\(note.content)\n\n"
            }
        }

        return md
    }
}
