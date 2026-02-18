// WeReadAuthManagerPublic.swift
// 对 WeReadAuthManager 补充公开方法，供 Views 调用
// （避免在原文件中将私有方法公开导致架构混乱）

import Foundation
import WebKit

extension WeReadAuthManager {

    /// 公开的 Cookie 提取方法，供 WeReadWebView 的 Coordinator 调用
    func extractAuthCookiesPublic(from webView: WKWebView) async {
        let dataStore = webView.configuration.websiteDataStore
        let cookies = await dataStore.httpCookieStore.allCookies()

        let authCookies = cookies.filter { cookie in
            ["wr_vid", "wr_skey", "wr_name", "wr_avatar",
             "wr_gender", "wr_rt", "wr_localvid", "wr_pf"].contains(cookie.name)
        }

        guard !authCookies.isEmpty else { return }
        persistCookies(authCookies)

        if let vidCookie = authCookies.first(where: { $0.name == "wr_vid" }),
           let vid = Int(vidCookie.value) {
            authState = .authenticated(userVid: vid)
        }
    }
}
