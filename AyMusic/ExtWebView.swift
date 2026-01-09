//
//  WebView.swift
//  AyMusic
//
//  Created by Shiyukine on 12/21/25.
//

import SwiftUI
import WebKit

struct ExtWebView: UIViewRepresentable {
    let url: String
    let closeUrl: String
    let filterByInclude: Bool
    var willClose: Bool = false
    
    init(baseUrl: String = "", closeUrl: String = "", filterByInclude: Bool = true) {
        self.url = baseUrl
        self.closeUrl = closeUrl
        self.filterByInclude = filterByInclude
    }
    
    func makeUIView(context: Context) -> WKWebView {
        guard let resourcePath = Bundle.main.resourcePath else {
            return WKWebView()
        }
        
        let baseDirectory = resourcePath
        let configuration = WKWebViewConfiguration()
        
        // Modern way to enable JavaScript (iOS 14+)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // Enable other useful features
        configuration.allowsInlineMediaPlayback = true
        
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        configuration.limitsNavigationsToAppBoundDomains = true
        
        // Enable developer extras for debugging
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Enable cookies for all domains including iframes and local IPs
        // This is crucial for local development with IP addresses like 192.168.0.33
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
        
        // Use default (persistent) data store for cookies
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Disable incremental rendering to ensure cookies are set before page loads
        configuration.suppressesIncrementalRendering = false
        
        // Configure cookie handling to accept third-party cookies (for iframes)
        if #available(iOS 14.0, *) {
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        
        // Setup JavaScript bridge - inject boundobject
        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        // Inject the boundobject JavaScript interface
        guard let data2 = try? Data(contentsOf: URL(fileURLWithPath: "\(baseDirectory)/overrides.js")) else {
            print("❌ Cannot read overrides.js")
            return WKWebView(frame: .zero, configuration: configuration)
        }
        
        let overridesScript = String(data: data2, encoding: .utf8) ?? ""
        
        // Inject boundobject in the PAGE world so webpage can access it
        if #available(iOS 14.0, *) {
            let injectorScript = WKUserScript(
                source: overridesScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,  // Run in ALL frames including iframes
                in: .page
            )
            userContentController.addUserScript(injectorScript)
        } else {
            // Add iframe script injection loader
            let injectorScript = WKUserScript(source: overridesScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(injectorScript)
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let userAgent = webView.value(forKey: "userAgent") as? String ?? ""
        print(userAgent)
        // Extract iOS version (e.g., 18_6)
        let iosVersionPattern = [#"iPhone OS ([\d_]+)"#, #"iPad OS ([\d_]+)"#, #"CPU OS ([\d_]+)"#]
        let iosVersion: String = {
            for pattern in iosVersionPattern {
                let regex = try? NSRegularExpression(pattern: pattern)
                let nsString = userAgent as NSString
                if let match = regex?.firstMatch(in: userAgent, range: NSRange(location: 0, length: nsString.length)),
                   match.numberOfRanges > 1 {
                    return nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: "_", with: ".")
                }
            }
            return "0.0"
        }()
        
        // Extract AppleWebKit version (e.g., 605.1.15)
        let webkitPattern = #"AppleWebKit/([\d\.]+)"#
        let webkitVersion: String = {
            let regex = try? NSRegularExpression(pattern: webkitPattern)
            let nsString = userAgent as NSString
            if let match = regex?.firstMatch(in: userAgent, range: NSRange(location: 0, length: nsString.length)),
            match.numberOfRanges > 1 {
                return nsString.substring(with: match.range(at: 1))
            }
            return "0.0.0"
        }()
        
        // Build new user agent
        let macDevice = "(Macintosh; Intel Mac OS X 10_15_7)"
        var newUA = userAgent
            .replacingOccurrences(of: #"\(iPhone; CPU iPhone OS [^)]*\)"#, with: macDevice, options: .regularExpression)
            .replacingOccurrences(of: #"\(iPhone; CPU OS [^)]*\)"#, with: macDevice, options: .regularExpression)
            .replacingOccurrences(of: #"\(iPad; CPU OS [^)]*\)"#, with: macDevice, options: .regularExpression)
            .replacingOccurrences(of: #"\(iPad; CPU iPad OS [^)]*\)"#, with: macDevice, options: .regularExpression)
            .replacingOccurrences(of: #" Mobile/[\w\d]+"#, with: "", options: .regularExpression)
        
        // Remove any existing Version/xxx and Safari/xxx
        newUA = newUA.replacingOccurrences(of: #" Version/[\d\.]+ Safari/[\d\.]+"#, with: "", options: .regularExpression)
        
        // Append Version/18_6 Safari/605.1.15 (or extracted values)
        newUA = newUA.trimmingCharacters(in: .whitespaces)
        newUA += " Version/\(iosVersion) Safari/\(webkitVersion)"
        
        // Set custom user agent
        webView.customUserAgent = newUA
        
        // Add cookie observer to watch for cookie changes
        // This is the NATIVE way to capture cookies from iframe redirects
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        
        // Restore cookies from HTTPCookieStorage to WKWebView on startup
        // This ensures cookies persist across app restarts
        if let cookies = HTTPCookieStorage.shared.cookies {
            print("🔄 Restoring \(cookies.count) cookies from HTTPCookieStorage to WKWebView")
            for cookie in cookies {
                configuration.websiteDataStore.httpCookieStore.setCookie(cookie) 
            }
        }
        
        // Enable inspection (Safari Web Inspector)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: url)!
        webView.load(URLRequest(url: url))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        var parent: ExtWebView
        weak var webView: WKWebView?
        
        init(_ parent: ExtWebView) {
            self.parent = parent
            
            super.init()
            
            // Listen for cookie sync notifications from URLProtocol
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(syncCookieFromProtocol(_:)),
                name: NSNotification.Name("SyncCookieToWebView"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc private func syncCookieFromProtocol(_ notification: Notification) {
            guard let cookie = notification.object as? HTTPCookie,
                  let webView = webView else {
                return
            }
            
            // Sync cookie to WKWebView's cookie store so JavaScript can access it
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                // Debug: Verify cookie is accessible
                print("✅ [Cookie Sync] Synced to ExtWKWebView: \(cookie.name)")
            }
        }
        
        // MARK: - WKHTTPCookieStoreObserver
        // This is called whenever cookies are added or changed in the cookie store
        // This is the NATIVE solution to capture cookies from iframe POST redirects!
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { cookies in
                // print("🍪 [Native Observer] Cookie store changed! Total cookies: \(cookies.count)")
                
                // Sync all cookies to HTTPCookieStorage for persistence across app restarts
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Debug: Check all cookies after navigation completes
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                if cookies.isEmpty {
                    print("⚠️ [didFinish] No cookies found in WKHTTPCookieStore")
                }
            }
            if(parent.willClose){
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CloseSecondWebView"),
                        object: nil
                    )
                }
                /*DispatchQueue.main.async {
                     if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                         windowScene.windows.first?.rootViewController?.dismiss(animated: true, completion: nil)
                     }
                 }*/
            }
        }
        
        // MARK: - Request Interception (Native Level)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            HTTPResponseModifierProtocol.bodyDataCache[navigationAction.request.url?.absoluteString ?? ""] = navigationAction.request.httpBody
            decisionHandler(.allow)
        }
        
        // Handle navigation responses to ensure cookies are processed
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            // CRITICAL: Manually handle cookies from redirect responses (302, 301, etc.)
            // WKWebView doesn't automatically set cookies from redirect responses
            if let httpResponse = navigationResponse.response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                let url = httpResponse.url?.absoluteString ?? "unknown"
                let frameType = navigationResponse.isForMainFrame ? "[Main Frame]" : "[iFrame]"
                
                // Handle Set-Cookie headers, especially important for redirects
                if let allHeaders = httpResponse.allHeaderFields as? [String: String],
                   let responseUrl = httpResponse.url {
                    
                    // Extract cookies from the response headers
                    let cookies = HTTPCookie.cookies(withResponseHeaderFields: allHeaders, for: responseUrl)
                    
                    if !cookies.isEmpty {
                        // print("   🍪 Found \(cookies.count) cookie(s) from response (status: \(statusCode))")
                        
                        // Manually set each cookie in the WKWebView's cookie store
                        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
                        for cookie in cookies {
                            
                            cookieStore.setCookie(cookie)
                            
                            // Also set in shared HTTPCookieStorage for consistency
                            HTTPCookieStorage.shared.setCookie(cookie)
                        }
                    }
                    
                    // Debug logging for redirects
                    if statusCode >= 300 && statusCode < 400 {
                        print("   🔄 Redirect (\(statusCode)) detected")
                        if let location = allHeaders["Location"] {
                            print("   → Redirecting to: \(location)")
                        }
                    }
                }
            }
            var test = parent.closeUrl == navigationResponse.response.url?.absoluteString
            if parent.filterByInclude {
                test = navigationResponse.response.url?.absoluteString.contains(parent.closeUrl) ?? false
            }
            if test {
                parent.willClose = true
            }
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
#if DEBUG
            // Accept self-signed certificates for local development (FALLBACK ONLY)
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if let serverTrust = challenge.protectionSpace.serverTrust {
                    let credential = URLCredential(trust: serverTrust)
                    print("🔓 [SSL Bypass] Accepting self-signed cert for: \(challenge.protectionSpace.host)")
                    completionHandler(.useCredential, credential)
                    return
                }
            }
#endif
            
            // Default behavior for production or non-SSL challenges
            completionHandler(.performDefaultHandling, nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed provisional navigation: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helper Extension
extension ExtWebView {
    static func showWebView(baseUrl: String, closeUrl: String, filterByInclude: Bool) -> ExtWebView {
        return ExtWebView(baseUrl: baseUrl, closeUrl: closeUrl, filterByInclude: filterByInclude)
    }
}
