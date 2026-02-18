// WeReadLoginView.swift
// 微信读书登录视图（二维码扫码 + WKWebView）

import SwiftUI
import WebKit

// MARK: - 登录入口视图

struct WeReadLoginView: View {
    @ObservedObject private var authManager = WeReadAuthManager.shared
    @State private var showWebLogin = false
    @State private var isValidating = false
    @Environment(\.dismiss) private var dismiss

    var onLoginSuccess: (() -> Void)?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo 区域
            VStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)

                Text("连接微信读书")
                    .font(.title.bold())

                Text("授权后 Claude 可读取您的书架、划线和笔记，为您提供个性化阅读分析")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // 功能说明卡片
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "bookmark.fill", color: .orange,
                           title: "划线同步", desc: "读取您的所有书籍划线")
                FeatureRow(icon: "note.text", color: .blue,
                           title: "笔记整理", desc: "同步书籍笔记和想法")
                FeatureRow(icon: "chart.bar.fill", color: .purple,
                           title: "阅读统计", desc: "分析您的阅读习惯与偏好")
                FeatureRow(icon: "sparkles", color: .pink,
                           title: "AI 分析", desc: "Claude 为您生成个性化书单与洞见")
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            // 隐私说明
            Text("数据仅在您的设备上处理，不会上传至第三方服务器")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // 登录按钮
            Button {
                showWebLogin = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text("扫码登录微信读书")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.green)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .sheet(isPresented: $showWebLogin) {
            WeReadWebLoginSheet(onSuccess: {
                showWebLogin = false
                onLoginSuccess?()
                dismiss()
            })
        }
    }
}

// MARK: - 功能行组件

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - WebView 登录 Sheet

struct WeReadWebLoginSheet: View {
    @ObservedObject private var authManager = WeReadAuthManager.shared
    @State private var isLoading = true
    var onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WeReadWebView(isLoading: $isLoading, onLoginSuccess: onSuccess)
                    .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在加载登录页面...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .navigationTitle("微信读书登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onSuccess() // 即使取消也关闭 sheet（用户可选择不登录）
                    }
                }
            }
        }
    }
}

// MARK: - WKWebView 包装

struct WeReadWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    var onLoginSuccess: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        let request = URLRequest(url: URL(string: "https://weread.qq.com/#login")!)
        webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading, onLoginSuccess: onLoginSuccess)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoading: Bool
        var onLoginSuccess: () -> Void

        init(isLoading: Binding<Bool>, onLoginSuccess: @escaping () -> Void) {
            self._isLoading = isLoading
            self.onLoginSuccess = onLoginSuccess
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            guard let url = webView.url?.absoluteString else { return }

            // 登录成功检测：URL 不再包含 #login 且在 weread.qq.com 域
            if url.contains("weread.qq.com") && !url.contains("#login") {
                Task { @MainActor in
                    await WeReadAuthManager.shared.extractAuthCookiesPublic(from: webView)
                    if WeReadAuthManager.shared.isAuthenticated {
                        self.onLoginSuccess()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}
