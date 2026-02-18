// WeReadDashboardView.swift
// 微信读书数据主界面
// 展示书架、统计数据，并入口进入 Claude 分析

import SwiftUI

// MARK: - 主 Dashboard

struct WeReadDashboardView: View {
    @ObservedObject private var authManager = WeReadAuthManager.shared
    @ObservedObject private var apiClient = WeReadAPIClient.shared
    @ObservedObject private var analyzer = ClaudeWeReadAnalyzer()

    @State private var books: [WeReadBook] = []
    @State private var summary: WeReadReadingSummary?
    @State private var recentHighlights: [WeReadHighlight] = []
    @State private var isLoading = false
    @State private var loadError: Error?

    @State private var showAnalysisSheet = false
    @State private var showLoginSheet = false
    @State private var showSearchSheet = false
    @State private var showKnowledgeGraph = false
    @State private var showDailyBrief = false
    @State private var selectedTab: DashboardTab = .shelf

    enum DashboardTab: String, CaseIterable {
        case shelf      = "书架"
        case highlights = "划线"
        case analyze    = "AI 分析"
    }

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                authenticatedContent
            } else {
                unauthenticatedPlaceholder
            }
        }
        .onAppear { loadDataIfNeeded() }
    }

    // MARK: - 已登录内容

    private var authenticatedContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部统计栏
                if let summary = summary {
                    ReadingStatsBar(summary: summary)
                }

                // Tab 选择器
                Picker("", selection: $selectedTab) {
                    ForEach(DashboardTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                // 内容区
                Group {
                    switch selectedTab {
                    case .shelf:
                        BookShelfView(books: books, analyzer: analyzer)
                    case .highlights:
                        HighlightsListView(highlights: recentHighlights)
                    case .analyze:
                        AnalysisHubView(analyzer: analyzer)
                    }
                }
            }
            .navigationTitle("微信读书")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 14) {
                        // 语义搜索
                        Button {
                            showSearchSheet = true
                        } label: {
                            Image(systemName: "sparkle.magnifyingglass")
                        }
                        // 知识图谱
                        Button {
                            showKnowledgeGraph = true
                        } label: {
                            Image(systemName: "circle.hexagongrid.fill")
                        }
                        // 每日简报
                        Button {
                            showDailyBrief = true
                        } label: {
                            Image(systemName: "sun.horizon.fill")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("刷新数据", systemImage: "arrow.clockwise") { loadData() }
                        Divider()
                        Button("退出登录", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            authManager.logout()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSearchSheet) {
                WeReadSemanticSearchView(books: books)
            }
            .navigationDestination(isPresented: $showKnowledgeGraph) {
                if let summary = summary {
                    KnowledgeGraphView(userData: WeReadUserData(
                        books: books,
                        highlights: recentHighlights,
                        notes: [],
                        summary: summary
                    ))
                }
            }
            .navigationDestination(isPresented: $showDailyBrief) {
                WeReadDailyBriefView()
            }
            .overlay {
                if isLoading {
                    LoadingOverlay()
                }
            }
            .alert("加载失败", isPresented: .constant(loadError != nil), presenting: loadError) { _ in
                Button("重试") { loadData() }
                Button("取消", role: .cancel) { loadError = nil }
            } message: { error in
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - 未登录占位

    private var unauthenticatedPlaceholder: some View {
        WeReadLoginView(onLoginSuccess: loadData)
    }

    // MARK: - 数据加载

    private func loadDataIfNeeded() {
        guard authManager.isAuthenticated, books.isEmpty else { return }
        loadData()
    }

    private func loadData() {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil

        Task {
            do {
                async let shelfTask = apiClient.fetchShelf()
                async let summaryTask = apiClient.fetchReadingSummary()
                async let highlightsTask = apiClient.fetchAllHighlights()

                let (fetchedBooks, fetchedSummary, fetchedHighlights) = try await (
                    shelfTask, summaryTask, highlightsTask
                )

                books = fetchedBooks
                summary = fetchedSummary
                recentHighlights = Array(fetchedHighlights
                    .sorted { $0.createTime > $1.createTime }
                    .prefix(100))
            } catch {
                loadError = error
            }
            isLoading = false
        }
    }
}

// MARK: - 统计栏

struct ReadingStatsBar: View {
    let summary: WeReadReadingSummary

    var body: some View {
        HStack(spacing: 0) {
            StatCell(value: "\(summary.totalBookCount)", label: "读过")
            Divider().frame(height: 36)
            StatCell(value: summary.formattedTotalTime, label: "累计时长")
            if let days = summary.totalReadDays {
                Divider().frame(height: 36)
                StatCell(value: "\(days)天", label: "阅读天数")
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

private struct StatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.bold())
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 书架视图

struct BookShelfView: View {
    let books: [WeReadBook]
    let analyzer: ClaudeWeReadAnalyzer

    let columns = [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book, analyzer: analyzer)
                    } label: {
                        BookCoverCard(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

struct BookCoverCard: View {
    let book: WeReadBook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 封面
            AsyncImage(url: URL(string: book.cover)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "book.closed.fill")
                        .foregroundColor(.secondary))
            }
            .frame(width: 100, height: 136)
            .clipped()
            .cornerRadius(6)
            .shadow(radius: 2, y: 1)

            // 书名
            Text(book.title)
                .font(.caption.bold())
                .lineLimit(2)
                .frame(width: 100, alignment: .leading)

            // 进度条
            ProgressView(value: book.readPercent ?? 0)
                .tint(.green)
                .frame(width: 100)
        }
        .frame(width: 100)
    }
}

// MARK: - 划线列表视图

struct HighlightsListView: View {
    let highlights: [WeReadHighlight]

    var body: some View {
        if highlights.isEmpty {
            ContentUnavailableView(
                "暂无划线",
                systemImage: "highlighter",
                description: Text("在微信读书中划线后，数据将同步至此")
            )
        } else {
            List(highlights) { highlight in
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.markText)
                        .font(.body)
                        .padding(8)
                        .background(Color(hex: highlight.styleColor.rawValue).opacity(0.3))
                        .cornerRadius(6)

                    HStack {
                        if let chapter = highlight.chapterTitle {
                            Label(chapter, systemImage: "book.pages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(highlight.createdDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - AI 分析中心

struct AnalysisHubView: View {
    @ObservedObject var analyzer: ClaudeWeReadAnalyzer
    @State private var selectedType: WeReadAnalysisType = .readingSummary
    @State private var customQuery = ""
    @State private var showResult = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 分析类型选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择分析类型")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(WeReadAnalysisType.allCases.filter { $0 != .customQuery }, id: \.self) { type in
                            AnalysisTypeCard(type: type, isSelected: selectedType == type) {
                                selectedType = type
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // 自定义提问
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.bubble.fill").foregroundColor(.blue)
                        Text("自定义提问").font(.headline)
                    }
                    .padding(.horizontal)

                    TextField("例如：帮我找出所有关于\"专注力\"的划线...", text: $customQuery, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                        .padding(.horizontal)
                        .onTapGesture { selectedType = .customQuery }
                }

                // 开始分析按钮
                Button {
                    Task {
                        await analyzer.analyze(type: selectedType, customQuery: customQuery)
                        showResult = true
                    }
                } label: {
                    HStack {
                        if analyzer.isAnalyzing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(analyzer.isAnalyzing ? "正在分析..." : "开始 AI 分析")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(analyzer.isAnalyzing ? .gray : .blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(analyzer.isAnalyzing)
                .padding(.horizontal)

                // 实时流式输出预览
                if analyzer.isAnalyzing && !analyzer.streamingContent.isEmpty {
                    StreamingPreview(content: analyzer.streamingContent)
                }

                // 历史分析结果
                if !analyzer.recentResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近分析").font(.headline).padding(.horizontal)
                        ForEach(analyzer.recentResults.prefix(5)) { result in
                            NavigationLink {
                                AnalysisResultView(result: result)
                            } label: {
                                AnalysisResultCard(result: result)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showResult) {
            if let result = analyzer.analysisResult {
                NavigationStack {
                    AnalysisResultView(result: result)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") { showResult = false }
                            }
                        }
                }
            }
        }
        .alert("分析失败", isPresented: .constant(analyzer.error != nil), presenting: analyzer.error) { _ in
            Button("好的", role: .cancel) { analyzer.error = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

// MARK: - 分析类型卡片

struct AnalysisTypeCard: View {
    let type: WeReadAnalysisType
    let isSelected: Bool
    let onTap: () -> Void

    var typeIcon: String {
        switch type {
        case .readingSummary: return "doc.text.magnifyingglass"
        case .bookRecommend:  return "books.vertical"
        case .notesOrganize:  return "note.text.badge.plus"
        case .themeAnalysis:  return "brain.head.profile"
        case .keyInsights:    return "lightbulb.fill"
        case .customQuery:    return "text.bubble"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                Text(type.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? .blue : Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - 流式输出预览

struct StreamingPreview: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").foregroundColor(.blue)
                Text("Claude 正在分析...")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            ScrollView {
                Text(content)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

// MARK: - 分析结果卡片

struct AnalysisResultCard: View {
    let result: WeReadAnalysisResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.type.rawValue).font(.subheadline.bold())
                Text(result.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(result.bookCount) 本书 · \(result.highlightCount) 条划线 · \(result.noteCount) 条笔记")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - 分析结果详情页

struct AnalysisResultView: View {
    let result: WeReadAnalysisResult
    @State private var showShareSheet = false

    var body: some View {
        ScrollView {
            Text(result.content)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .navigationTitle(result.type.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [result.content])
        }
    }
}

// MARK: - 加载覆盖层

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().scaleEffect(1.3)
                Text("正在同步微信读书数据...").font(.caption)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(16)
        }
    }
}

// MARK: - ShareSheet UIViewControllerRepresentable

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var hexValue: UInt64 = 0
        scanner.scanHexInt64(&hexValue)
        let r = Double((hexValue & 0xFF0000) >> 16) / 255
        let g = Double((hexValue & 0x00FF00) >> 8) / 255
        let b = Double(hexValue & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
