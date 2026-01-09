//
//  WebView.swift
//  AyMusic
//
//  Created by Shiyukine on 12/21/25.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let fileName: String
    
    // Store iframe URL patterns and their injection code
    static var codeInjecter: [[String: String]] = []
    static var interceptRequests: [[String: Any]] = []
    static var clientTokens: [String: String] = [:]
    
    init(fileName: String = "index.html") {
        self.fileName = fileName
    }
    
    func makeUIView(context: Context) -> WKWebView {
        guard let resourcePath = Bundle.main.resourcePath else {
            return WKWebView()
        }
        
        let baseDirectory = resourcePath
        let configuration = WKWebViewConfiguration()
        
        // ⚠️ PRIVATE API: Register http/https schemes with NSURLProtocol
        // This allows us to intercept and modify response headers like Android
        registerPrivateAPIForHTTPInterception()
        
        // Share process pool to enable cookie sharing across all webviews
        let pool = WKProcessPool()
        let selector = NSSelectorFromString("_registerURLSchemeAsSecure:")
        pool.perform(selector, with: NSString(string: "app"))
        configuration.processPool = pool
        
        // Register app:// scheme for root (bundle), cache, and localfiles access
        let appSchemeHandler = AppURLSchemeHandler(baseDirectory: baseDirectory)
        configuration.setURLSchemeHandler(appSchemeHandler, forURLScheme: "app")
        
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
        userContentController.add(context.coordinator, name: "boundobject")
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

            let script2 = WKUserScript(
                source: overridesScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page  // Runs in the same world as webpage JavaScript
            )
            userContentController.addUserScript(script2)
            
            // Add iframe script injection loader
            let iframeInjectionScript = createIframeScriptInjector()
            let injectorScript = WKUserScript(
                source: iframeInjectionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,  // Run in ALL frames including iframes
                in: .page
            )
            userContentController.addUserScript(injectorScript)
        } else {
            // Fallback for iOS 13 and earlier
            let script = WKUserScript(source: boundObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(script)
            
            let script2 = WKUserScript(source: overridesScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(script2)
            
            // Add iframe script injection loader
            let iframeInjectionScript = createIframeScriptInjector()
            let injectorScript = WKUserScript(source: iframeInjectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
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
        
        // Disable safe area insets for the scroll view
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        
        // Ensure the webView fills the entire space
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Disable scrolling
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        
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
        let url = URL(string: "app://root/\(fileName)")!
        webView.load(URLRequest(url: url))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Iframe Script Injection
    
    private func createIframeScriptInjector() -> String {
        // Build the injector with all registered scripts
        var scriptMappings = "["
        for (index, item) in WebView.codeInjecter.enumerated() {
            if index > 0 { scriptMappings += "," }
            let url = item["url"] ?? ""
            let code = item["code"] ?? ""
            
            // Escape for JSON
            let escapedUrl = url
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            let escapedCode = code
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            scriptMappings += "{\"url\":\"\(escapedUrl)\",\"code\":\"\(escapedCode)\"}"
        }
        scriptMappings += "]"
        
        return """
        (function() {
            'use strict';
            
            const currentUrl = window.location.href;
            const scriptMappings = \(scriptMappings);
            
            // Function to inject matching scripts
            function injectScripts() {
                try {
                    // Encode URL for comparison
                    const encodedUrl = encodeURIComponent(decodeURIComponent(currentUrl));
                    
                    for (const mapping of scriptMappings) {
                        const encodedPattern = encodeURIComponent(decodeURIComponent(mapping.url));
                        
                        if (encodedUrl.includes(encodedPattern)) {
                            // console.log('[IframeInjector] Matched pattern:', mapping.url, 'for URL:', currentUrl);
                            
                            // Create and inject script element
                            const scriptElement = document.createElement('script');
                            scriptElement.textContent = mapping.code;
                            
                            if (document.head) {
                                document.head.insertBefore(scriptElement, document.head.firstChild);
                            }
                        }
                    }
                } catch (e) {
                    console.error('[IframeInjector] Error injecting scripts:', e);
                }
            }
            
            // Wait for document to be ready
            if (document.head && document.body) {
                injectScripts();
            } else {
                const observer = new MutationObserver(() => {
                    if (document.head && document.body) {
                        observer.disconnect();
                        injectScripts();
                    }
                });
                observer.observe(document, {
                    childList: true,
                    subtree: true
                });
            }
        })();
        """
    }
    
    // Helper method to rebuild user scripts when scripts are registered
    func rebuildUserScripts(webView: WKWebView) {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        
        let userContentController = webView.configuration.userContentController
        userContentController.removeAllUserScripts()
        
        // Re-add boundobject script
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "\(resourcePath)/boundobject.js")),
              let boundObjectScript = String(data: data, encoding: .utf8) else {
            print("❌ Cannot read boundobject.js")
            return
        }
        
        guard let data2 = try? Data(contentsOf: URL(fileURLWithPath: "\(resourcePath)/overrides.js")),
              let overridesScript = String(data: data2, encoding: .utf8) else {
            print("❌ Cannot read overrides.js")
            return
        }
        
        if #available(iOS 14.0, *) {
            let script = WKUserScript(
                source: boundObjectScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            )
            userContentController.addUserScript(script)
            
            let script2 = WKUserScript(
                source: overridesScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            )
            userContentController.addUserScript(script2)
            
            // Add updated iframe script injection loader
            let iframeInjectionScript = createIframeScriptInjector()
            let injectorScript = WKUserScript(
                source: iframeInjectionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            )
            userContentController.addUserScript(injectorScript)
        } else {
            let script = WKUserScript(source: boundObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(script)
            
            let script2 = WKUserScript(source: overridesScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(script2)
            
            let iframeInjectionScript = createIframeScriptInjector()
            let injectorScript = WKUserScript(source: iframeInjectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userContentController.addUserScript(injectorScript)
        }
        
        // print("Rebuilt user scripts with \(WebView.codeInjecter.count) iframe injection(s)")
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
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver, UIDocumentPickerDelegate {
        var parent: WebView
        weak var webView: WKWebView?
        var filePickerCallbackId: String?
        var filePickerFrameInfo: WKFrameInfo?
        
        init(_ parent: WebView) {
            self.parent = parent
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
            // Get version info from app bundle
            let versionName = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
            let versionCode = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            
            // Check if this is a debug or release build
            #if DEBUG
            let isPackaged = "false"
            #else
            let isPackaged = "true"
            #endif
            
            let script = """
            var intev = setInterval(() => {
                if(!loaded) {
                    console.log('Attempt registerClient')
                    if(typeof app != 'undefined' && app) {
                        app.registerClient('iOS', 'v\(versionName)', \(versionCode), window.boundobject, \(isPackaged))
                        clearInterval(intev)
                    }
                }
                else {
                    clearInterval(intev)
                }
            }, 100)
            """
            
            webView.evaluateJavaScript(script, completionHandler: nil)
            
            // Debug: Check all cookies after navigation completes
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                if cookies.isEmpty {
                    print("⚠️ [didFinish] No cookies found in WKHTTPCookieStore")
                }
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
            case "getSettings":
                // use UserDefaults
                let settingFileName = params["fileName"] as? String ?? "default"
                
                // Try to get value as either array or dictionary
                var settingsValue: Any? = nil
                
                if let array = UserDefaults.standard.array(forKey: settingFileName) {
                    settingsValue = array
                } else if let dict = UserDefaults.standard.dictionary(forKey: settingFileName) {
                    settingsValue = dict
                }
                
                if let value = settingsValue {
                    // Check if empty
                    let isEmpty = (value as? [Any])?.isEmpty ?? (value as? [String: Any])?.isEmpty ?? false
                    if isEmpty {
                        // Key exists but empty - return null
                        let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)', null); }"
                        executeJavaScript(script, in: iframeInfo, webView: webView)
                        return
                    }
                    
                    // Return the settings as JSON string
                    if let jsonData = try? JSONSerialization.data(withJSONObject: value),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(jsonString)'); }"
                        executeJavaScript(script, in: iframeInfo, webView: webView)
                    }
                } else {
                    // Key doesn't exist - return null
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)', null); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                }

            case "setSettings":
                // use UserDefaults
                let settingFileName = params["fileName"] as? String ?? "default"
                
                // Parse content - it might be a JSON string (array or object) or already parsed
                var settingsValue: Any? = nil
                if let contentString = params["content"] as? String {
                    // Parse JSON string - could be array or object
                    if let jsonData = contentString.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: jsonData) {
                        settingsValue = parsed
                    }
                } else {
                    // Already parsed (could be dict or array)
                    settingsValue = params["content"]
                }
                
                if let value = settingsValue {
                    UserDefaults.standard.setValue(value, forKey: settingFileName)
                    UserDefaults.standard.synchronize()
                    
                    if let dict = value as? [String: Any] {
                        print("💾 Saved settings '\(settingFileName)' with \(dict.count) keys")
                    } else if let array = value as? [Any] {
                        print("💾 Saved settings '\(settingFileName)' with \(array.count) items")
                    } else {
                        print("💾 Saved settings '\(settingFileName)'")
                    }
                } else {
                    print("⚠️ Failed to parse settings for '\(settingFileName)'")
                }

            case "httpRequestGET":
                let url = params["url"] as? String ?? ""
                let headers = params["headers"] as? [String: String] ?? [:]
                let timeout = params["timeout"] as? TimeInterval ?? 30

                // Perform the GET request
                Utils.performGETRequest(url: url, headers: headers, timeout: timeout) { [weak self] result in
                    switch result {
                    case .success(let responseText):
                        // Escape the string for JavaScript and pass it as a string literal
                        let escapedText = responseText
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
                        let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(escapedText)'); }"
                        DispatchQueue.main.async {
                            self?.executeJavaScript(script, in: iframeInfo, webView: webView)
                        }
                    case .failure(let error):
                        print("⚠️ HTTP GET request failed: \(error.localizedDescription)")
                    }
                }

            case "httpRequestPOST":
                let url = params["url"] as? String ?? ""
                let headers = params["headers"] as? [String: String] ?? [:]
                let timeout = params["timeout"] as? TimeInterval ?? 30
                let body = params["body"] as? [String: Any] ?? [:]

                // Perform the POST request
                Utils.performPOSTRequest(url: url, headers: headers, body: body, timeout: timeout) { [weak self] result in
                    switch result {
                    case .success(let responseText):
                        // Escape the string for JavaScript and pass it as a string literal
                        let escapedText = responseText
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                            .replacingOccurrences(of: "\n", with: "\\n")
                            .replacingOccurrences(of: "\r", with: "\\r")
                        let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(escapedText)'); }"
                        DispatchQueue.main.async {
                            self?.executeJavaScript(script, in: iframeInfo, webView: webView)
                        }
                    case .failure(let error):
                        print("⚠️ HTTP POST request failed: \(error.localizedDescription)")
                    }
                }

            case "changeServerURL":
                let newURL = params["url"] as? String ?? ""
                print("Change server URL to: \(newURL)")
                UpdateManager.serverUrl = newURL

            case "openWebsiteInNewWindow":
                let baseUrl = params["baseUrl"] as? String ?? ""
                let closeUrl = params["closeUrl"] as? String ?? ""
                let filterByInclude = params["filterByInclude"] as? Bool ?? true
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenSecondWebView"),
                        object: [   
                            "baseUrl": baseUrl,
                            "closeUrl": closeUrl,
                            "filterByInclude": filterByInclude
                        ]
                    )
                }
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)

            case "saveCache":
                let content = params["content"] as? String ?? ""
                let fileName = params["fileName"] as? String ?? "default_cache"
                
                guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    print("⚠️ Cannot access cache directory")
                    return
                }
                
                let fileURL = cacheDir.appendingPathComponent(fileName)
                
                // Create parent directories if they don't exist
                let parentDir = fileURL.deletingLastPathComponent()
                do {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    // print("Saved to cache: \(fileURL.path)")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } catch {
                    print("⚠️ Failed to save cache: \(error.localizedDescription)")
                }

            case "saveData":
                let content = params["content"] as? String ?? ""
                let fileName = params["fileName"] as? String ?? "default_data"
                
                guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("⚠️ Cannot access documents directory")
                    return
                }
                
                let fileURL = documentsDir.appendingPathComponent(fileName)
                
                // Create parent directories if they don't exist
                let parentDir = fileURL.deletingLastPathComponent()
                do {
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ Saved to documents: \(fileURL.path)")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } catch {
                    print("⚠️ Failed to save data: \(error.localizedDescription)")
                }

            case "removeCache":
                let fileName = params["fileName"] as? String ?? "default_cache"
                
                guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    print("⚠️ Cannot access cache directory")
                    return
                }
                
                let fileURL = cacheDir.appendingPathComponent(fileName)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("✅ Removed from cache: \(fileURL.path)")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } catch {
                    print("⚠️ Failed to remove cache: \(error.localizedDescription)")
                }

            case "removeData":
                let fileName = params["fileName"] as? String ?? "default_data"
                
                guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    print("⚠️ Cannot access documents directory")
                    return
                }
                
                let fileURL = documentsDir.appendingPathComponent(fileName)
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("✅ Removed from documents: \(fileURL.path)")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } catch {
                    print("⚠️ Failed to remove data: \(error.localizedDescription)")
                }

            case "registerIframeUrl":
                let url = params["url"] as? String ?? ""
                let code = params["code"] as? String ?? ""
                
                // Remove existing entry with the same URL if it exists
                WebView.codeInjecter.removeAll { item in
                    item["url"] == url
                }
                
                // Add the new entry
                WebView.codeInjecter.append(["url": url, "code": code])
                
                // Also update ScriptInjecter singleton (it will replace if exists)
                ScriptInjecter.shared.addScript(url: url, script: code)
                
                print("Registered iframe URL pattern: \(url)")
                
                // Rebuild user scripts with updated injector
                if let webView = self.webView {
                    self.parent.rebuildUserScripts(webView: webView)
                }
                
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)
            
            case "getCodeInjecters":
                // Return the list of code injecters as JSON to the requesting frame
                let jsonData = try? JSONSerialization.data(withJSONObject: WebView.codeInjecter)
                if let jsonString = jsonData.flatMap({ String(data: $0, encoding: .utf8) }) {
                    let escapedJSON = jsonString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                        .replacingOccurrences(of: "\n", with: "\\n")
                        .replacingOccurrences(of: "\r", with: "\\r")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(escapedJSON)'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } else {
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','[]'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                }
            
            case "clearCodeInjecters":
                WebView.codeInjecter.removeAll()
                
                // Also clear ScriptInjecter singleton
                ScriptInjecter.shared.clearAllScripts()
                
                // Rebuild user scripts (now empty)
                if let webView = self.webView {
                    self.parent.rebuildUserScripts(webView: webView)
                }
                
                print("✅ Cleared all code injecters and user scripts")
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)

            case "interceptRequest":
                let url = params["url"] as? String ?? ""
                let intercept = params["includes"] as? Bool ?? false
                
                // Add to the interceptRequests array
                WebView.interceptRequests.append(["url": url, "includes": intercept])
                print("✅ Registered request interception for URL pattern: \(url), intercept: \(intercept)")
                
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','success'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)

            case "haveCookie":
                let name = params["name"] as? String ?? ""
                let url = params["url"] as? String ?? ""

                let cookieStore = webView?.configuration.websiteDataStore.httpCookieStore
                cookieStore?.getAllCookies { [weak self] cookies in
                    let exists = cookies.contains { $0.name == name && url.contains($0.domain) }
                    let content = exists ? cookies.first { $0.name == name && url.contains($0.domain) }?.value ?? "" : ""
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(content)'); }"
                    self?.executeJavaScript(script, in: iframeInfo, webView: webView)
                }
                
            case "getWindowInsets":
                // For iOS, we can return safe area insets as window insets
                let insets = webView?.safeAreaInsets ?? UIEdgeInsets.zero
                let insetsDict: [String: CGFloat] = [
                    "top": insets.top,
                    "left": insets.left,
                    "bottom": insets.bottom,
                    "right": insets.right
                ]
                let jsonData = try? JSONSerialization.data(withJSONObject: insetsDict)
                if let jsonString = jsonData.flatMap({ String(data: $0, encoding: .utf8) }) {
                    let escapedJSON = jsonString
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                        .replacingOccurrences(of: "\n", with: "\\n")
                        .replacingOccurrences(of: "\r", with: "\\r")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(escapedJSON)'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                }

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
                }

            case "registerOverrideResponse":
                let response = params["response"] as? String ?? ""
                print(response)
                var responseDictArray: [[String: Any]] = []
                if let jsonData = response.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
                    responseDictArray = parsed
                }
                
                if !responseDictArray.isEmpty {
                    // Add all override rules from the array
                    for responseDict in responseDictArray {
                        let platforms = responseDict["platforms"] as? [String] ?? []
                        if !platforms.isEmpty && platforms.contains("iOS") {
                            HTTPResponseModifierProtocol.overrideResponses.append(responseDict)
                        }
                    }
                    
                    print("✅ Registered \(responseDictArray.count) override response rule(s)")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(responseDictArray.count)'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                } else {
                    print("⚠️ No override responses to register")
                    let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','0'); }"
                    executeJavaScript(script, in: iframeInfo, webView: webView)
                }

            case "clearOverrideResponses":
                HTTPResponseModifierProtocol.overrideResponses.removeAll()
                print("🗑️ Cleared all override responses")
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','cleared'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)
                
            case "removeClientToken":
                let platform = params["platform"] as? String ?? "none"
                WebView.clientTokens.removeValue(forKey: platform)
                
            case "getClientToken":
                let platform = params["platform"] as? String ?? "none"
                let token = WebView.clientTokens[platform] ?? ""
                let script = "if(window.boundobject.__manager) { window.boundobject.__manager.callbackNative('\(callId)','\(token)'); }"
                executeJavaScript(script, in: iframeInfo, webView: webView)

            case "clearWebViewCache":
                // Clear all WKWebView cache and website data
                let dataStore = webView?.configuration.websiteDataStore
                let dataTypes = Set([
                    WKWebsiteDataTypeDiskCache,
                    WKWebsiteDataTypeMemoryCache
                ])
                let sinceDate = Date(timeIntervalSince1970: 0)
                
                dataStore?.removeData(ofTypes: dataTypes, modifiedSince: sinceDate, completionHandler: {
                    print("✅ Cleared WKWebView cache and website data")
                })

                URLCache.shared.removeAllCachedResponses()
                print("✅ [Cache] Cleared URLSession cache")
                webView?.reload()
                
            case "addBadUrl":
                let url: String = params["url"] as? String ?? ""
                let includes: Bool = params["includes"] as? Bool ?? false
                HTTPResponseModifierProtocol.blockedUrls.append(["url": url, "includes": includes])

            case "pickUpMusic":
                // Present document picker on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, let webView = self.webView else { return }
                    
                    // Store callback info for later use
                    self.filePickerCallbackId = callId
                    self.filePickerFrameInfo = iframeInfo
                    
                    // Get the root view controller
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let rootViewController = windowScene.windows.first?.rootViewController else {
                        print("⚠️ Cannot get root view controller")
                        let script = "if(window.listeners && window.listeners.filePickerCallback) { window.listeners.filePickerCallback([]); }"
                        self.executeJavaScript(script, in: iframeInfo, webView: webView)
                        return
                    }
                    
                    // Create document picker for audio files
                    let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio])
                    documentPicker.delegate = self
                    documentPicker.allowsMultipleSelection = false
                    
                    // Present the picker
                    rootViewController.present(documentPicker, animated: true, completion: nil)
                }
                
            case "openLink":
                let urlString = params["url"] as? String ?? ""
                if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                } else {
                    print("⚠️ Cannot open URL: \(urlString)")
                }
                
            case "restartApp":
                webView?.reload()

            default:
                print("⚠️ Unknown method: \(method)")
            }
        }
        
        // MARK: - UIDocumentPickerDelegate
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else {
                // User cancelled or no file selected
                callFilePickerCallback(with: [])
                return
            }
            
            print("📁 User selected file: \(selectedURL.lastPathComponent)")
            
            // Start accessing the security-scoped resource
            guard selectedURL.startAccessingSecurityScopedResource() else {
                print("⚠️ Cannot access security-scoped resource")
                callFilePickerCallback(with: [])
                return
            }
            
            defer {
                selectedURL.stopAccessingSecurityScopedResource()
            }
            
            // Get documents directory
            guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("⚠️ Cannot access documents directory")
                callFilePickerCallback(with: [])
                return
            }
            
            // Create a subdirectory for music if it doesn't exist
            let musicDir = documentsDir.appendingPathComponent("music", isDirectory: true)
            try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
            
            // Generate destination path
            let fileName = selectedURL.lastPathComponent
            let destinationURL = musicDir.appendingPathComponent(fileName)
            
            // If file already exists, generate unique name
            var finalDestinationURL = destinationURL
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                let baseName = (fileName as NSString).deletingPathExtension
                let ext = (fileName as NSString).pathExtension
                var counter = 1
                
                repeat {
                    let newName = "\(baseName)_\(counter).\(ext)"
                    finalDestinationURL = musicDir.appendingPathComponent(newName)
                    counter += 1
                } while FileManager.default.fileExists(atPath: finalDestinationURL.path)
            }
            
            // Copy the file to documents directory
            do {
                try FileManager.default.copyItem(at: selectedURL, to: finalDestinationURL)
                print("✅ File copied to: \(finalDestinationURL.path)")
                
                // Get the relative path from documents directory and URL-encode it
                let fileName = finalDestinationURL.lastPathComponent
                let displayName = fileName
                
                // URL-encode the filename for the app://localfiles URL
                guard let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                    print("❌ Failed to encode filename: \(fileName)")
                    callFilePickerCallback(with: [])
                    return
                }
                
                // Build app://localfiles URL with encoded path
                let appURL = "music/\(encodedFileName)"
                
                // Call back to JavaScript with file info
                // Format: [["url", "displayName"]]
                callFilePickerCallback(with: [[appURL, displayName]])
                
            } catch {
                print("❌ Error copying file: \(error.localizedDescription)")
                callFilePickerCallback(with: [])
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            print("📱 User cancelled document picker")
            callFilePickerCallback(with: [])
        }
        
        private func callFilePickerCallback(with files: [[String]]) {
            // Convert array to JSON string
            var jsonString = "[]"
            if !files.isEmpty {
                // Build: [["url", "name"]]
                let items = files.map { file in
                    let url = file[0].replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'") 
                    let name = file[1].replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "'", with: "\\'")
                    return "['\(url)','\(name)']"
                }.joined(separator: ",")
                jsonString = "[\(items)]"
            }
            
            let script = "if(window.listeners && window.listeners.filePickerCallback) { window.listeners.filePickerCallback(\(jsonString)); }"
            
            DispatchQueue.main.async { [weak self] in
                self?.executeJavaScript(script, in: self?.filePickerFrameInfo, webView: self?.webView)
            }
            
            // Clear callback info
            filePickerCallbackId = nil
            filePickerFrameInfo = nil
        }
    }
}

// MARK: - Helper Extension
extension WebView {
    static func fromLocalFile(named fileName: String) -> WebView {
        return WebView(fileName: fileName)
    }
}
