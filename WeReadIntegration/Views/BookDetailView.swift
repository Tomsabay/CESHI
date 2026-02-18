// BookDetailView.swift
// 单本书籍详情页：显示书籍信息、划线列表，并支持对单书进行 Claude 分析

import SwiftUI

struct BookDetailView: View {
    let book: WeReadBook
    @ObservedObject var analyzer: ClaudeWeReadAnalyzer

    @State private var highlights: [WeReadHighlight] = []
    @State private var notes: [WeReadNote] = []
    @State private var isLoadingHighlights = false
    @State private var showAnalysisSheet = false
    @State private var selectedAnalysisType: WeReadAnalysisType = .keyInsights

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 书籍头部信息
                BookHeaderView(book: book)

                // 操作按钮行
                HStack(spacing: 12) {
                    ActionButton(icon: "sparkles", title: "AI 分析") {
                        showAnalysisSheet = true
                    }
                    ActionButton(icon: "square.and.arrow.up", title: "导出笔记") {
                        exportNotes()
                    }
                }
                .padding(.horizontal)

                // 划线列表
                if isLoadingHighlights {
                    ProgressView("加载划线中...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if !highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "划线", count: highlights.count, icon: "highlighter")

                        ForEach(highlights) { highlight in
                            HighlightRow(highlight: highlight)
                        }
                    }
                    .padding(.horizontal)
                }

                // 笔记列表
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "笔记", count: notes.count, icon: "note.text")
                        ForEach(notes) { note in
                            NoteRow(note: note)
                        }
                    }
                    .padding(.horizontal)
                }

                // 空状态
                if !isLoadingHighlights && highlights.isEmpty && notes.isEmpty {
                    ContentUnavailableView(
                        "暂无划线和笔记",
                        systemImage: "book.pages",
                        description: Text("在微信读书中为《\(book.title)》添加划线和笔记")
                    )
                    .padding()
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadBookData() }
        .sheet(isPresented: $showAnalysisSheet) {
            BookAnalysisSheet(
                book: book,
                analyzer: analyzer,
                selectedType: $selectedAnalysisType
            )
        }
    }

    private func loadBookData() {
        guard highlights.isEmpty else { return }
        isLoadingHighlights = true

        Task {
            do {
                async let highlightsTask = WeReadAPIClient.shared.fetchHighlights(bookId: book.bookId)
                async let notesTask = WeReadAPIClient.shared.fetchNotes(bookId: book.bookId, count: 200)
                let (h, notesResp) = try await (highlightsTask, notesTask)
                highlights = h.sorted { $0.createTime < $1.createTime }
                notes = notesResp.reviews.map { $0.review }
            } catch {
                // 加载失败时静默处理，保持空状态
            }
            isLoadingHighlights = false
        }
    }

    private func exportNotes() {
        var text = "# 《\(book.title)》读书笔记\n\n"
        text += "作者：\(book.author)\n"
        text += "阅读进度：\(book.readPercentText)\n\n"

        if !highlights.isEmpty {
            text += "## 划线（\(highlights.count) 条）\n\n"
            for h in highlights {
                text += "> \(h.markText)\n\n"
            }
        }

        if !notes.isEmpty {
            text += "## 笔记（\(notes.count) 条）\n\n"
            for note in notes {
                if let abs = note.abstract {
                    text += "**原文**：\(abs)\n"
                }
                text += "**笔记**：\(note.content)\n\n"
            }
        }

        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}

// MARK: - 书籍头部

struct BookHeaderView: View {
    let book: WeReadBook

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: URL(string: book.cover)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "book.closed.fill").foregroundColor(.secondary))
            }
            .frame(width: 80, height: 110)
            .clipped()
            .cornerRadius(8)
            .shadow(radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.headline).lineLimit(2)
                Text(book.author).font(.subheadline).foregroundColor(.secondary)

                if let category = book.category {
                    Text(category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("阅读进度")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(book.readPercentText)
                            .font(.caption.bold())
                    }
                    ProgressView(value: book.readPercent ?? 0)
                        .tint(.green)
                }

                Text("已读 \(book.formattedReadingTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - 划线行

struct HighlightRow: View {
    let highlight: WeReadHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlight.markText)
                .font(.body)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: highlight.styleColor.rawValue).opacity(0.25))
                .cornerRadius(8)

            HStack {
                if let chapter = highlight.chapterTitle {
                    Text(chapter)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(highlight.createdDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .contextMenu {
            Button("复制划线", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = highlight.markText
            }
        }
    }
}

// MARK: - 笔记行

struct NoteRow: View {
    let note: WeReadNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let abstract = note.abstract {
                Text(abstract)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
            }

            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .frame(width: 3)
                    .foregroundColor(.blue)
                    .cornerRadius(2)
                Text(note.content)
                    .font(.body)
            }

            Text(note.createdDate, style: .date)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
            Spacer()
            Text("\(count) 条")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title).fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 书籍分析 Sheet

struct BookAnalysisSheet: View {
    let book: WeReadBook
    @ObservedObject var analyzer: ClaudeWeReadAnalyzer
    @Binding var selectedType: WeReadAnalysisType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // 分析类型选择
                Picker("分析类型", selection: $selectedType) {
                    ForEach([WeReadAnalysisType.keyInsights,
                             .notesOrganize,
                             .themeAnalysis], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if analyzer.isAnalyzing {
                    StreamingPreview(content: analyzer.streamingContent)
                } else if let result = analyzer.analysisResult {
                    ScrollView {
                        Text(result.content)
                            .padding()
                            .textSelection(.enabled)
                    }
                } else {
                    Spacer()
                    Button {
                        Task { await analyzer.analyzeBook(book, type: selectedType) }
                    } label: {
                        Label("开始分析《\(book.title)》", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                    Spacer()
                }
            }
            .navigationTitle("AI 分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
