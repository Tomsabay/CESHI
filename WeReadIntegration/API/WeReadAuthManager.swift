// WeReadAuthManager.swift
// 微信读书认证管理
// 通过 WKWebView 二维码扫码登录，持久化 Cookie 到 Keychain

import Foundation
import WebKit
import AuthenticationServices
import Security

// MARK: - 认证状态

enum WeReadAuthState: Equatable {
    case unauthenticated
    case qrCodePending(url: URL)     // 等待用户扫码
    case authenticated(userVid: Int)
    case sessionExpired
}

// MARK: - 认证管理器

@MainActor
final class WeReadAuthManager: NSObject, ObservableObject {

    static let shared = WeReadAuthManager()

    @Published var authState: WeReadAuthState = .unauthenticated
    @Published var userProfile: WeReadUserProfile?

    private let keychainService = "com.claudeapp.weread"
    private let keychainCookieKey = "weread_cookies"
    private let userDefaultsProfileKey = "weread_user_profile"

    // 微信读书登录 URL
    private let loginURL = URL(string: "https://weread.qq.com/#login")!

    // 存储会话 Cookie 的 HTTPCookieStorage
    private(set) var cookieStorage = HTTPCookieStorage()
    private var webView: WKWebView?
    private var loginContinuation: CheckedContinuation<Bool, Error>?

    override private init() {
        super.init()
        loadPersistedSession()
    }

    // MARK: - 公开接口

    /// 检查当前是否已认证
    var isAuthenticated: Bool {
        if case .authenticated = authState { return true }
        return false
    }

    /// 获取用于 API 请求的 Cookie 字符串
    var cookieHeader: String? {
        let cookies = loadCookiesFromKeychain()
        guard !cookies.isEmpty else { return nil }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// 发起二维码登录流程
    /// 返回可嵌入 SwiftUI 的 WKWebView（显示二维码页面）
    func startQRCodeLogin() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            self.loginContinuation = continuation
            DispatchQueue.main.async {
                self.setupLoginWebView()
            }
        }
    }

    /// 退出登录，清除所有凭证
    func logout() {
        authState = .unauthenticated
        userProfile = nil
        deleteCookiesFromKeychain()
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) {}
    }

    /// 验证当前 Session 是否仍然有效
    func validateSession() async -> Bool {
        guard cookieHeader != nil else { return false }
        // 尝试访问用户信息接口，验证 Cookie 是否仍有效
        do {
            let profile = try await fetchUserProfile()
            self.userProfile = profile
            if let vid = profile.userVid {
                self.authState = .authenticated(userVid: vid)
            }
            return true
        } catch WeReadError.sessionExpired {
            self.authState = .sessionExpired
            return false
        } catch {
            return false
        }
    }

    // MARK: - Cookie 持久化（Keychain）

    func persistCookies(_ cookies: [HTTPCookie]) {
        let cookieProps = cookies.compactMap { cookie -> [String: Any]? in
            return cookie.properties.map { props in
                var dict: [String: Any] = [:]
                props.forEach { dict[$0.key.rawValue] = $0.value }
                return dict
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: cookieProps) else { return }
        saveToKeychain(key: keychainCookieKey, data: data)
    }

    func loadCookiesFromKeychain() -> [HTTPCookie] {
        guard let data = loadFromKeychain(key: keychainCookieKey),
              let cookieProps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return cookieProps.compactMap { props -> HTTPCookie? in
            var httpProps: [HTTPCookiePropertyKey: Any] = [:]
            props.forEach { httpProps[HTTPCookiePropertyKey($0.key)] = $0.value }
            return HTTPCookie(properties: httpProps)
        }
    }

    // MARK: - 私有方法

    private func loadPersistedSession() {
        let cookies = loadCookiesFromKeychain()
        guard !cookies.isEmpty else { return }

        // 检查关键 Cookie（wr_vid 是微信读书的用户 ID Cookie）
        if let vidCookie = cookies.first(where: { $0.name == "wr_vid" }),
           let vid = Int(vidCookie.value) {
            authState = .authenticated(userVid: vid)
        }

        // 加载缓存的用户信息
        if let data = UserDefaults.standard.data(forKey: userDefaultsProfileKey),
           let profile = try? JSONDecoder().decode(WeReadUserProfile.self, from: data) {
            userProfile = profile
        }
    }

    private func setupLoginWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let request = URLRequest(url: loginURL)
        webView.load(request)
    }

    /// 从 WKWebView Cookie 存储中提取认证 Cookie
    private func extractAuthCookies(from webView: WKWebView) async {
        let dataStore = webView.configuration.websiteDataStore
        let cookies = await dataStore.httpCookieStore.allCookies()

        let authCookies = cookies.filter { cookie in
            // 微信读书关键 Cookie
            ["wr_vid", "wr_skey", "wr_name", "wr_avatar", "wr_gender",
             "wr_rt", "wr_localvid", "wr_pf"].contains(cookie.name)
        }

        guard !authCookies.isEmpty else { return }
        persistCookies(authCookies)

        if let vidCookie = authCookies.first(where: { $0.name == "wr_vid" }),
           let vid = Int(vidCookie.value) {
            authState = .authenticated(userVid: vid)
            loginContinuation?.resume(returning: true)
            loginContinuation = nil
        }
    }

    private func fetchUserProfile() async throws -> WeReadUserProfile {
        guard let cookieStr = cookieHeader else {
            throw WeReadError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://i.weread.qq.com/user/profile")!)
        request.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        request.setValue("https://weread.qq.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeReadError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw WeReadError.sessionExpired
        }
        guard httpResponse.statusCode == 200 else {
            throw WeReadError.apiError(httpResponse.statusCode, "获取用户信息失败")
        }

        let profile = try JSONDecoder().decode(WeReadUserProfile.self, from: data)

        // 缓存 profile
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsProfileKey)
        }
        return profile
    }

    // MARK: - Keychain 工具方法

    private func saveToKeychain(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func deleteCookiesFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainCookieKey
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: userDefaultsProfileKey)
    }
}

// MARK: - WKNavigationDelegate

extension WeReadAuthManager: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面加载完成后，检查 URL 判断是否已登录
        guard let url = webView.url else { return }

        let urlString = url.absoluteString
        // 登录成功后会跳转到主页，不再包含 #login
        if urlString.contains("weread.qq.com") && !urlString.contains("#login") {
            Task { @MainActor in
                await self.extractAuthCookies(from: webView)
            }
        }
    }
}
