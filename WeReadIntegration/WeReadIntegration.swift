// WeReadIntegration.swift
// 微信读书集成模块主入口
//
// 使用方式：
//   在 iOS Claude App 的相关界面中添加：
//   WeReadIntegrationView()
//
// 集成到已有 App：
//   在 AppDelegate 或 SceneDelegate 中调用：
//   WeReadIntegration.setup()

import SwiftUI

// MARK: - 集成入口视图

/// 微信读书集成功能入口 View
/// 可直接嵌入到 Claude App 的任意导航栈中
public struct WeReadIntegrationView: View {
    public init() {}

    public var body: some View {
        WeReadDashboardView()
    }
}

// MARK: - 集成配置

public enum WeReadIntegration {

    /// App 启动时调用，恢复上次登录会话
    public static func setup() {
        Task { @MainActor in
            let authManager = WeReadAuthManager.shared
            if authManager.isAuthenticated {
                _ = await authManager.validateSession()
            }
        }
    }

    /// 当前是否已授权连接微信读书
    public static var isConnected: Bool {
        WeReadAuthManager.shared.isAuthenticated
    }

    /// 断开微信读书连接
    public static func disconnect() {
        WeReadAuthManager.shared.logout()
    }

    /// 获取用户已读书籍数量（快速访问）
    public static func quickFetchBookCount() async throws -> Int {
        let books = try await WeReadAPIClient.shared.fetchShelf()
        return books.count
    }
}

// MARK: - Claude App 集成扩展点

/// 在 Claude App 消息输入框中添加「附加微信读书数据」按钮
/// 实现：用户可将当前阅读的书籍划线直接附加到对话中
public struct WeReadAttachButton: View {
    let onAttach: (String) -> Void

    @State private var showBookPicker = false
    @State private var books: [WeReadBook] = []
    @State private var isLoading = false

    public init(onAttach: @escaping (String) -> Void) {
        self.onAttach = onAttach
    }

    public var body: some View {
        Button {
            loadAndShowBooks()
        } label: {
            Image(systemName: "books.vertical.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        }
        .sheet(isPresented: $showBookPicker) {
            BookPickerSheet(books: books, onSelect: { book in
                attachBookData(book)
            })
        }
    }

    private func loadAndShowBooks() {
        guard WeReadAuthManager.shared.isAuthenticated else {
            // 未登录时不显示
            return
        }
        isLoading = true
        Task {
            books = (try? await WeReadAPIClient.shared.fetchShelf()) ?? []
            isLoading = false
            showBookPicker = true
        }
    }

    private func attachBookData(_ book: WeReadBook) {
        Task {
            let highlights = (try? await WeReadAPIClient.shared.fetchHighlights(bookId: book.bookId)) ?? []
            var text = "【微信读书数据】《\(book.title)》by \(book.author)\n"
            text += "阅读进度：\(book.readPercentText)\n\n"
            if !highlights.isEmpty {
                text += "我的划线：\n"
                for h in highlights.prefix(20) {
                    text += "• \(h.markText)\n"
                }
            }
            await MainActor.run { onAttach(text) }
        }
    }
}

// MARK: - 书籍选择器

struct BookPickerSheet: View {
    let books: [WeReadBook]
    let onSelect: (WeReadBook) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button {
                    onSelect(book)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: URL(string: book.cover)) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 40, height: 54)
                        .cornerRadius(4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title).font(.subheadline.bold()).foregroundColor(.primary)
                            Text(book.author).font(.caption).foregroundColor(.secondary)
                            Text(book.readPercentText).font(.caption2).foregroundColor(.green)
                        }
                    }
                }
            }
            .navigationTitle("选择书籍附加到对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
