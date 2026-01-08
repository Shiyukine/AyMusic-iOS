//
//  WebViewTest.swift
//  AyMusic
//
//  Created by Shiyukine on 1/4/26.
//

import SwiftUI
import WebKit

struct WebViewTest: UIViewRepresentable {
    let url: String
    
    init(baseUrl: String = "") {
        self.url = baseUrl
    }
    
    func makeUIView(context: Context) -> WKWebView {
        guard let resourcePath = Bundle.main.resourcePath else {
            return WKWebView()
        }
        
        let baseDirectory = resourcePath
        let configuration = WKWebViewConfiguration()

        // ⚠️ PRIVATE API: Register http/https schemes with NSURLProtocol
        // This allows us to intercept and modify response headers like Android
        // registerPrivateAPIForHTTPInterception()
        
        // Modern way to enable JavaScript (iOS 14+)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // Enable other useful features
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // For testing: Allow unrestricted navigation
        configuration.limitsNavigationsToAppBoundDomains = false
        
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
        userContentController.add(context.coordinator as! WKScriptMessageHandler, name: "boundobject")
        configuration.userContentController = userContentController
        
        // Inject the boundobject JavaScript interface
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(baseDirectory)/boundobject.js")) else {
            print("❌ Cannot read boundobject.js")
            return WKWebView(frame: .zero, configuration: configuration)
        }
        
        let boundObjectScript = String(data: data, encoding: .utf8) ?? ""

        // Inject the boundobject JavaScript interface
        guard let data2 = try? Data(contentsOf: URL(fileURLWithPath: "\(baseDirectory)/overrides.js")) else {
            print("❌ Cannot read overrides.js")
            return WKWebView(frame: .zero, configuration: configuration)
        }
        
        let overridesScript = String(data: data2, encoding: .utf8) ?? ""
        
        // Inject boundobject in the PAGE world so webpage can access it
        if #available(iOS 14.0, *) {
            let script = WKUserScript(
                source: boundObjectScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page  // Runs in the same world as webpage JavaScript
            )
            userContentController.addUserScript(script)
            
            // Add iframe script injection loader
            let injectorScript = WKUserScript(
                source: overridesScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,  // Run in ALL frames including iframes
                in: .page
            )
            //userContentController.addUserScript(injectorScript)
        } else {
            // Fallback for iOS 13 and earlier
            let script = WKUserScript(source: boundObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(script)
            
            // Add iframe script injection loader
            let injectorScript = WKUserScript(source: overridesScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            //userContentController.addUserScript(injectorScript)
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        
        // For testing: Allow mixed content (HTTP resources on HTTPS pages)
        if #available(iOS 14.0, *) {
            webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        
        context.coordinator.webView = webView

        let userAgent = webView.value(forKey: "userAgent") as? String ?? ""
        // Extract iOS version (e.g., 18_6)
        let iosVersionPattern = #"iPhone OS ([\d_]+)"#
        let iosVersion: String = {
            let regex = try? NSRegularExpression(pattern: iosVersionPattern)
            let nsString = userAgent as NSString
            if let match = regex?.firstMatch(in: userAgent, range: NSRange(location: 0, length: nsString.length)),
            match.numberOfRanges > 1 {
                return nsString.substring(with: match.range(at: 1)).replacingOccurrences(of: "_", with: ".")
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
            .replacingOccurrences(of: #" Mobile/[\w\d]+"#, with: "", options: .regularExpression)
        
        // Remove any existing Version/xxx and Safari/xxx
        newUA = newUA.replacingOccurrences(of: #" Version/[\d\.]+ Safari/[\d\.]+"#, with: "", options: .regularExpression)
        
        // Append Version/18_6 Safari/605.1.15 (or extracted values)
        newUA = newUA.trimmingCharacters(in: .whitespaces)
        newUA += " Version/\(iosVersion) Safari/\(webkitVersion)"
        
        // Set custom user agent
        //webView.customUserAgent = newUA
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
        
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

    // MARK: - Private API Registration
    
    /// PRIVATE API: Register http/https schemes with NSURLProtocol
    /// This enables intercepting and modifying HTTP/HTTPS response headers
    private func registerPrivateAPIForHTTPInterception() {
        // Register our custom protocol handler
        URLProtocol.registerClass(HTTPResponseModifierProtocol.self)
        
        // Use private API to make WKWebView use NSURLProtocol for http/https
        guard let contextControllerClass = NSClassFromString("WKBrowsingContextController") as? NSObject.Type,
              let registerSchemeSelector = NSSelectorFromString("registerSchemeForCustomProtocol:") as? Selector else {
            print("⚠️ [Private API] Failed to load WKBrowsingContextController")
            return
        }
        
        if contextControllerClass.responds(to: registerSchemeSelector) {
            _ = contextControllerClass.perform(registerSchemeSelector, with: "http")
            _ = contextControllerClass.perform(registerSchemeSelector, with: "https")
            print("✅ [Private API] Registered http/https schemes with NSURLProtocol")
        } else {
            print("⚠️ [Private API] WKBrowsingContextController doesn't respond to registerSchemeForCustomProtocol:")
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
        var parent: WebViewTest
        weak var webView: WKWebView?
        
        init(_ parent: WebViewTest) {
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
                print("✅ [Cookie Sync] Synced to TestWKWebView: \(cookie.name)")
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
        }
        
        // MARK: - Request Interception (Native Level)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            HTTPResponseModifierProtocol.bodyDataCache[navigationAction.request.url?.absoluteString ?? ""] = navigationAction.request.httpBody
            decisionHandler(.allow)
        }
        
        // Handle navigation responses to ensure cookies are processed
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed provisional navigation: \(error.localizedDescription)")
        }
        
        // MARK: - Helper Methods
                
        /// Execute JavaScript in a specific frame only
        private func executeJavaScript(_ script: String, in frameInfo: WKFrameInfo?, webView: WKWebView?, completion: ((Result<Any?, Error>) -> Void)? = nil) {
            guard let webView = webView else {
                completion?(.failure(NSError(domain: "WebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "WebView is nil"])))
                return
            }
            
            if #available(iOS 14.0, *) {
                webView.evaluateJavaScript(script, in: frameInfo, in: .page) { result in
                    switch result {
                    case .success(let value):
                        completion?(.success(value))
                    case .failure(let error):
                        print("❌ JS execution error: \(error)")
                        completion?(.failure(error))
                    }
                }
            } else {
                // Fallback for iOS 13 - only main frame
                webView.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        completion?(.failure(error))
                    } else {
                        completion?(.success(result))
                    }
                }
            }
        }
        
        // MARK: - JavaScript Bridge Handler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            
            // print("📨 Received message from JS: \(message.name)")
            // print("   Body: \(body)")
            
            // Handle different message types
            switch message.name {
            case "boundobject":
                handleBoundObjectCall(body: body, webView: message.webView, iframeInfo: message.frameInfo)
            default:
                print("⚠️ Unknown message name: \(message.name)")
            }
        }

        private func handleBoundObjectCall(body: [String: Any], webView: WKWebView?, iframeInfo: WKFrameInfo? = nil) {
            guard let method = body["method"] as? String else {
                print("⚠️ No method specified")
                return
            }
            
            let params = body["params"] as? [String: Any] ?? [:]
            let callId = body["callId"] as? String ?? "cb_-1"
            
            // Handle different native methods
            switch method {
            case "cacheRequestBody":
                // Cache POST/PUT/PATCH body data before fetch request is sent
                let url = params["url"] as? String ?? ""
                let body = params["body"] as? String ?? ""
                
                if !url.isEmpty, !body.isEmpty {
                    HTTPResponseModifierProtocol.cacheLock.lock()
                    HTTPResponseModifierProtocol.bodyDataCache[url] = body.data(using: .utf8)
                    HTTPResponseModifierProtocol.cacheLock.unlock()
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)',true); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                    print("✅ Cached body data for URL: \(url) (length: \(body.count))")
                }

            default:
                print("⚠️ Unknown method: \(method)")
            }
        }
    }
}

// MARK: - Helper Extension
extension WebViewTest {
    static func showWebView(baseUrl: String) -> WebViewTest {
        return WebViewTest(baseUrl: baseUrl)
    }
}
