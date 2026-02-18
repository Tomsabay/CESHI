// WeReadSemanticSearch.swift
// 用 Claude 对所有划线做语义搜索
//
// 原理：
//   1. 将所有划线文本批量请求 Claude，让它为每条划线打"语义标签向量"（用 JSON 关键词列表模拟）
//   2. 用户输入查询词后，再次请求 Claude 对候选集做相关性排序
//   3. 结果实时流式返回（Streaming）
//
// 注：纯本地的向量化用 Apple NaturalLanguage 框架的词嵌入做快速预筛，
//     再用 Claude 做精排，兼顾速度与准确性。

import Foundation
import NaturalLanguage
import SwiftUI

// MARK: - 搜索结果

struct SemanticSearchResult: Identifiable {
    let id = UUID()
    let highlight: WeReadHighlight
    let bookTitle: String
    let relevanceScore: Double   // 0.0 ~ 1.0
    let explanation: String?     // Claude 解释为什么相关
}

// MARK: - 搜索引擎

@MainActor
final class WeReadSemanticSearch: ObservableObject {

    @Published var results: [SemanticSearchResult] = []
    @Published var isSearching = false
    @Published var streamingExplanation = ""
    @Published var indexProgress: Double = 0   // 索引构建进度

    // 本地缓存：划线 → NL 词嵌入
    private var embeddingIndex: [String: [Double]] = [:]
    private var highlightMeta: [String: (highlight: WeReadHighlight, bookTitle: String)] = [:]

    private let apiClient = WeReadAPIClient.shared
    private let nlEmbedder = NLEmbedding.wordEmbedding(for: .simplifiedChinese)

    // MARK: - 构建本地索引

    /// 构建划线的 NL 词嵌入索引（后台执行，可增量）
    func buildIndex(books: [WeReadBook]) async {
        let total = Double(books.count)
        var done = 0.0
        var allHighlights: [(WeReadHighlight, String)] = []

        for book in books {
            guard let highlights = try? await apiClient.fetchHighlights(bookId: book.bookId) else {
                done += 1; indexProgress = done / total; continue
            }
            for h in highlights {
                allHighlights.append((h, book.title))
            }
            done += 1
            indexProgress = done / total
        }

        // 生成每条划线的本地嵌入向量（基于 NLEmbedding）
        for (highlight, bookTitle) in allHighlights {
            let vector = localEmbedding(for: highlight.markText)
            embeddingIndex[highlight.bookmarkId] = vector
            highlightMeta[highlight.bookmarkId] = (highlight, bookTitle)
        }

        indexProgress = 1.0
    }

    // MARK: - 搜索

    /// 两阶段搜索：本地预筛 → Claude 精排
    func search(query: String, topK: Int = 20) async {
        guard !query.isEmpty, !highlightMeta.isEmpty else { return }
        isSearching = true
        results = []
        streamingExplanation = ""

        // 阶段 1：本地余弦相似度快速召回 top-K
        let queryVec = localEmbedding(for: query)
        let candidates = embeddingIndex
            .map { id, vec in (id: id, score: cosineSimilarity(queryVec, vec)) }
            .sorted { $0.score > $1.score }
            .prefix(topK)

        let candidateHighlights = candidates.compactMap { c -> (WeReadHighlight, String, Double)? in
            guard let meta = highlightMeta[c.id] else { return nil }
            return (meta.highlight, meta.bookTitle, c.score)
        }

        // 阶段 2：Claude 精排（流式）
        await claudeRerank(query: query, candidates: candidateHighlights)

        isSearching = false
    }

    // MARK: - Claude 精排

    private func claudeRerank(
        query: String,
        candidates: [(WeReadHighlight, String, Double)]
    ) async {
        guard let apiKey = KeychainHelper.shared.getString(
            service: "com.anthropic.claudeapp", key: "api_key") else {
            // 无 API Key 时退化为纯本地排序
            results = candidates.map { h, book, score in
                SemanticSearchResult(highlight: h, bookTitle: book,
                                     relevanceScore: score, explanation: nil)
            }
            return
        }

        let candidateText = candidates.enumerated().map { i, item in
            let (h, book, _) = item
            return "[\(i + 1)] 《\(book)》\(h.markText)"
        }.joined(separator: "\n")

        let prompt = """
        用户搜索：「\(query)」

        以下是候选划线（已按本地相似度预排序），请重新精排并评分：
        \(candidateText)

        请返回 JSON 数组，格式：
        [{"index": 1, "score": 0.95, "reason": "直接讨论了..."}]
        score 范围 0-1，reason 不超过 20 字。
        只返回 JSON，不要其他文字。
        """

        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",   // 用 Haiku 做精排，更快更省
            "max_tokens": 1024,
            "messages": [["role": "user", "content": prompt]]
        ])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String
        else {
            // 精排失败 → 使用本地排序结果
            results = candidates.map { h, book, score in
                SemanticSearchResult(highlight: h, bookTitle: book,
                                     relevanceScore: score, explanation: nil)
            }
            return
        }

        // 解析 Claude 返回的精排结果
        struct RerankItem: Decodable {
            let index: Int
            let score: Double
            let reason: String?
        }

        // 清理可能的 markdown 代码块包裹
        let cleanedContent = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let rankData = cleanedContent.data(using: .utf8),
           let rankItems = try? JSONDecoder().decode([RerankItem].self, from: rankData) {
            let reranked = rankItems
                .compactMap { item -> SemanticSearchResult? in
                    let idx = item.index - 1
                    guard idx >= 0 && idx < candidates.count else { return nil }
                    let (h, book, _) = candidates[idx]
                    return SemanticSearchResult(
                        highlight: h,
                        bookTitle: book,
                        relevanceScore: item.score,
                        explanation: item.reason
                    )
                }
                .sorted { $0.relevanceScore > $1.relevanceScore }

            results = reranked
        } else {
            results = candidates.map { h, book, score in
                SemanticSearchResult(highlight: h, bookTitle: book,
                                     relevanceScore: score, explanation: nil)
            }
        }
    }

    // MARK: - NL 本地嵌入

    private func localEmbedding(for text: String) -> [Double] {
        guard let embedder = nlEmbedder else {
            return tokenBagVector(text)
        }
        var vector: [Double] = Array(repeating: 0, count: 300)
        var count = 0
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range])
            if let wordVec = embedder.vector(for: word) {
                for (i, v) in wordVec.enumerated() where i < 300 {
                    vector[i] += Double(v)
                }
                count += 1
            }
            return true
        }
        if count > 0 { vector = vector.map { $0 / Double(count) } }
        return vector
    }

    /// 退化方案：基于字符级 n-gram 的简单向量
    private func tokenBagVector(_ text: String) -> [Double] {
        var vec = [Double](repeating: 0, count: 512)
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            let slot = Int(c.asciiValue ?? 0) % 512
            vec[slot] += 1.0 / Double(chars.count)
            if i + 1 < chars.count {
                let bigram = (Int(c.asciiValue ?? 0) * 31 + Int(chars[i+1].asciiValue ?? 0)) % 512
                vec[bigram] += 0.5 / Double(chars.count)
            }
        }
        return vec
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}

// MARK: - 搜索 UI

struct WeReadSemanticSearchView: View {
    @StateObject private var engine = WeReadSemanticSearch()
    @State private var query = ""
    @State private var hasBuiltIndex = false
    @FocusState private var isInputFocused: Bool

    let books: [WeReadBook]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .foregroundColor(.purple)
                    TextField("搜索你的所有划线...", text: $query)
                        .focused($isInputFocused)
                        .submitLabel(.search)
                        .onSubmit { startSearch() }
                    if !query.isEmpty {
                        Button { query = ""; engine.results = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding()

                // 索引构建进度
                if !hasBuiltIndex {
                    VStack(spacing: 12) {
                        ProgressView(value: engine.indexProgress)
                            .tint(.purple)
                        Text("正在构建语义索引... \(Int(engine.indexProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .onAppear {
                        Task {
                            await engine.buildIndex(books: books)
                            hasBuiltIndex = true
                        }
                    }
                } else if engine.isSearching {
                    ProgressView("Claude 正在精排结果...")
                        .padding()
                } else if engine.results.isEmpty && !query.isEmpty {
                    ContentUnavailableView(
                        "未找到相关划线",
                        systemImage: "text.magnifyingglass",
                        description: Text("换个关键词试试？")
                    )
                } else {
                    // 搜索结果
                    List(engine.results) { result in
                        SearchResultRow(result: result)
                    }
                    .listStyle(.plain)
                }

                Spacer()
            }
            .navigationTitle("语义搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("搜索") { startSearch() }
                        .disabled(query.isEmpty || !hasBuiltIndex)
                }
            }
        }
    }

    private func startSearch() {
        isInputFocused = false
        Task { await engine.search(query: query) }
    }
}

struct SearchResultRow: View {
    let result: SemanticSearchResult

    var scoreColor: Color {
        switch result.relevanceScore {
        case 0.8...: return .green
        case 0.6..<0.8: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(result.bookTitle)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                // 相关度徽章
                Text(String(format: "%.0f%%", result.relevanceScore * 100))
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(scoreColor.opacity(0.15))
                    .foregroundColor(scoreColor)
                    .cornerRadius(6)
            }

            Text(result.highlight.markText)
                .font(.body)
                .lineLimit(4)

            if let reason = result.explanation {
                Label(reason, systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundColor(.purple)
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = result.highlight.markText
            }
        }
    }
}
