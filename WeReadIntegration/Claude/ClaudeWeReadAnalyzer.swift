// ClaudeWeReadAnalyzer.swift
// 将微信读书数据传入 Claude 进行分析
// 支持：阅读总结、书单推荐、笔记整理、知识图谱构建

import Foundation
import Combine

// MARK: - 分析类型

enum WeReadAnalysisType: String, CaseIterable {
    case readingSummary    = "阅读总结"
    case bookRecommend     = "书单推荐"
    case notesOrganize     = "笔记整理"
    case themeAnalysis     = "主题分析"
    case keyInsights       = "核心洞见"
    case customQuery       = "自定义提问"

    var systemPrompt: String {
        switch self {
        case .readingSummary:
            return """
            你是一位专业的阅读分析师。请根据用户的微信读书数据，
            生成一份全面的个人阅读报告，包括：
            1. 阅读习惯分析（偏好类型、阅读时间规律）
            2. 已读书籍的主题分布
            3. 阅读深度评估（基于划线和笔记数量）
            4. 个人阅读里程碑
            请用中文回答，语言生动有趣。
            """
        case .bookRecommend:
            return """
            你是一位精通各类书籍的资深书评人。请根据用户已读书籍的题材、
            作者风格和划线偏好，推荐 10 本他可能喜欢的书，每本书附上：
            - 推荐理由（与已读书籍的关联）
            - 核心内容简介
            - 适合阅读时机
            请用中文回答。
            """
        case .notesOrganize:
            return """
            你是一位知识管理专家，擅长 Zettelkasten 方法。
            请将用户的微信读书划线和笔记整理为结构化的知识卡片，
            提取核心观点，找出不同书籍间的概念关联，
            最终输出一份 Markdown 格式的知识库文档。
            """
        case .themeAnalysis:
            return """
            你是一位具有深厚人文素养的思想分析师。
            请深入分析用户划线内容所体现的思想主题、价值观取向和关注领域，
            揭示这些阅读材料背后的共同线索和个人思想脉络。
            分析要有深度，避免泛泛而谈。
            """
        case .keyInsights:
            return """
            你是一位善于提炼精华的知识导师。
            请从用户所有的划线和笔记中，提炼出最有价值的 20 条核心洞见，
            每条洞见需要：原文引用 + 深度解析 + 实践建议。
            重点关注那些跨书籍反复出现的重要观点。
            """
        case .customQuery:
            return """
            你是用户的私人阅读助手，对用户的微信读书数据了如指掌。
            请根据用户的具体问题，结合他的阅读数据给出个性化的回答。
            """
        }
    }

    var userPromptTemplate: String {
        switch self {
        case .readingSummary:
            return "请根据以下我的微信读书数据，为我生成一份个人阅读报告：\n\n{DATA}"
        case .bookRecommend:
            return "根据以下我的阅读历史，请给我推荐新书：\n\n{DATA}"
        case .notesOrganize:
            return "请帮我整理以下微信读书的划线和笔记，构建知识卡片：\n\n{DATA}"
        case .themeAnalysis:
            return "请分析以下我的阅读内容所体现的思想主题：\n\n{DATA}"
        case .keyInsights:
            return "请从以下我的所有划线中提炼核心洞见：\n\n{DATA}"
        case .customQuery:
            return "{DATA}\n\n用户问题：{QUERY}"
        }
    }
}

// MARK: - 分析结果

struct WeReadAnalysisResult: Identifiable {
    let id = UUID()
    let type: WeReadAnalysisType
    let content: String
    let createdAt: Date
    let bookCount: Int
    let highlightCount: Int
    let noteCount: Int

    var isCached: Bool = false
}

// MARK: - Claude 分析器

@MainActor
final class ClaudeWeReadAnalyzer: ObservableObject {

    @Published var isAnalyzing = false
    @Published var analysisResult: WeReadAnalysisResult?
    @Published var streamingContent: String = ""
    @Published var error: Error?
    @Published var recentResults: [WeReadAnalysisResult] = []

    private let apiClient = WeReadAPIClient.shared

    // Claude API 配置（从 iOS App 的共享配置读取）
    private var claudeAPIKey: String? {
        // 从 Keychain 读取已登录 Claude App 的 API Key
        // 实际集成中应从 ClaudeApp 的共享 Keychain group 读取
        return KeychainHelper.shared.getString(
            service: "com.anthropic.claudeapp",
            key: "api_key"
        )
    }

    private let claudeBaseURL = "https://api.anthropic.com/v1/messages"
    private let claudeModel = "claude-opus-4-6"

    // MARK: - 公开方法

    /// 加载微信读书数据并启动 Claude 分析（流式输出）
    func analyze(type: WeReadAnalysisType, customQuery: String = "") async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        streamingContent = ""
        error = nil

        do {
            // 1. 拉取微信读书数据
            let userData = try await apiClient.fetchAllDataForAnalysis()
            let markdownData = userData.toMarkdown()

            // 2. 构造 Prompt
            let userMessage = buildPrompt(
                type: type,
                data: markdownData,
                customQuery: customQuery
            )

            // 3. 调用 Claude API（流式）
            let resultText = try await callClaudeStreaming(
                systemPrompt: type.systemPrompt,
                userMessage: userMessage
            )

            // 4. 存储结果
            let result = WeReadAnalysisResult(
                type: type,
                content: resultText,
                createdAt: Date(),
                bookCount: userData.books.count,
                highlightCount: userData.highlights.count,
                noteCount: userData.notes.count
            )
            analysisResult = result
            recentResults.insert(result, at: 0)
            // 保留最近 20 条分析结果
            if recentResults.count > 20 {
                recentResults = Array(recentResults.prefix(20))
            }
            persistResult(result)

        } catch {
            self.error = error
        }

        isAnalyzing = false
    }

    /// 仅分析指定书籍的划线和笔记
    func analyzeBook(_ book: WeReadBook, type: WeReadAnalysisType) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        streamingContent = ""
        error = nil

        do {
            async let highlightsTask = apiClient.fetchHighlights(bookId: book.bookId)
            async let notesTask = apiClient.fetchNotes(bookId: book.bookId, count: 100)

            let (highlights, notesResponse) = try await (highlightsTask, notesTask)
            let notes = notesResponse.reviews.map { $0.review }

            var bookData = "# 《\(book.title)》by \(book.author)\n\n"
            bookData += "阅读进度：\(book.readPercentText)，阅读时长：\(book.formattedReadingTime)\n\n"

            if !highlights.isEmpty {
                bookData += "## 划线（\(highlights.count) 条）\n"
                for h in highlights {
                    bookData += "> \(h.markText)\n\n"
                }
            }

            if !notes.isEmpty {
                bookData += "## 笔记（\(notes.count) 条）\n"
                for note in notes {
                    if let abs = note.abstract {
                        bookData += "**原文**：\(abs)\n"
                    }
                    bookData += "**笔记**：\(note.content)\n\n"
                }
            }

            let userMessage = buildPrompt(type: type, data: bookData, customQuery: "")
            let resultText = try await callClaudeStreaming(
                systemPrompt: type.systemPrompt,
                userMessage: userMessage
            )

            let result = WeReadAnalysisResult(
                type: type,
                content: resultText,
                createdAt: Date(),
                bookCount: 1,
                highlightCount: highlights.count,
                noteCount: notes.count
            )
            analysisResult = result
            recentResults.insert(result, at: 0)

        } catch {
            self.error = error
        }

        isAnalyzing = false
    }

    // MARK: - 私有方法

    private func buildPrompt(type: WeReadAnalysisType, data: String, customQuery: String) -> String {
        var prompt = type.userPromptTemplate
        prompt = prompt.replacingOccurrences(of: "{DATA}", with: data)
        if !customQuery.isEmpty {
            prompt = prompt.replacingOccurrences(of: "{QUERY}", with: customQuery)
        }
        return prompt
    }

    private func callClaudeStreaming(systemPrompt: String, userMessage: String) async throws -> String {
        guard let apiKey = claudeAPIKey else {
            // 若未找到 API Key，回退到非流式模式并提示
            throw ClaudeAnalyzerError.apiKeyNotFound
        }

        guard let url = URL(string: claudeBaseURL) else {
            throw ClaudeAnalyzerError.invalidURL
        }

        let body: [String: Any] = [
            "model": claudeModel,
            "max_tokens": 4096,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ClaudeAnalyzerError.apiError
        }

        var fullText = ""

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]" else { break }

            if let data = jsonStr.data(using: .utf8),
               let event = try? JSONDecoder().decode(ClaudeStreamEvent.self, from: data),
               let delta = event.delta?.text {
                fullText += delta
                streamingContent = fullText
            }
        }

        return fullText
    }

    private func persistResult(_ result: WeReadAnalysisResult) {
        // 简单持久化到 UserDefaults（实际可用 Core Data）
        var stored = UserDefaults.standard.array(forKey: "weread_analysis_history") as? [[String: Any]] ?? []
        stored.insert([
            "type": result.type.rawValue,
            "content": result.content,
            "date": result.createdAt.timeIntervalSince1970,
            "books": result.bookCount,
            "highlights": result.highlightCount,
            "notes": result.noteCount
        ], at: 0)
        if stored.count > 20 { stored = Array(stored.prefix(20)) }
        UserDefaults.standard.set(stored, forKey: "weread_analysis_history")
    }
}

// MARK: - Claude SSE 事件解析

private struct ClaudeStreamEvent: Decodable {
    let type: String?
    let delta: Delta?

    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
}

// MARK: - 错误

enum ClaudeAnalyzerError: Error, LocalizedError {
    case apiKeyNotFound
    case invalidURL
    case apiError

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "未找到 Claude API Key，请确保已在 Claude App 中登录"
        case .invalidURL:
            return "API URL 配置错误"
        case .apiError:
            return "Claude API 调用失败，请检查网络连接"
        }
    }
}

// MARK: - Keychain 辅助

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}

    func getString(service: String, key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
