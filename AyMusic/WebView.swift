//
//  WebView.swift
//  AyMusic
//
//  Created by Shiyukine on 12/21/25.
//

import SwiftUI
import WebKit

class LocalFileURLSchemeHandler: NSObject, WKURLSchemeHandler {
    let baseDirectory: String
    
    init(baseDirectory: String) {
        self.baseDirectory = baseDirectory
        super.init()
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "WebView", code: -1, userInfo: nil))
            return
        }
        
        // Get the path from the URL (e.g., applocal://localhost/class/window.js -> class/window.js)
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        if path.isEmpty {
            path = "index.html"
        }
        
        // Since Xcode flattened all files to bundle root, extract just the filename
        // "class/window.js" -> "window.js"
        // "plugins/jsmediatags.js" -> "jsmediatags.js"
        let fileName = (path as NSString).lastPathComponent
        
        let filePath = "\(baseDirectory)/\(fileName)"
        
        guard FileManager.default.fileExists(atPath: filePath) else {
            print("❌ Not found: \(path) -> \(fileName)")
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            print("❌ Cannot read: \(fileName)")
            urlSchemeTask.didFailWithError(NSError(domain: "WebView", code: -2, userInfo: nil))
            return
        }
        
        let mimeType = getMimeType(for: fileName)
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
        
        print("✅ Loaded: \(path) -> \(fileName)")
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Task cancelled
    }
    
    private func getMimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js", "mjs": return "application/javascript"
        case "json": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
}

struct WebView: UIViewRepresentable {
    let fileName: String
    
    init(fileName: String = "index.html") {
        self.fileName = fileName
    }
    
    func makeUIView(context: Context) -> WKWebView {
        guard let resourcePath = Bundle.main.resourcePath else {
            return WKWebView()
        }
        
        let baseDirectory = resourcePath
        let configuration = WKWebViewConfiguration()
        
        // Register custom URL scheme handler for applocal://
        let schemeHandler = LocalFileURLSchemeHandler(baseDirectory: baseDirectory)
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "applocal")
        
        // Modern way to enable JavaScript (iOS 14+)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        
        // Enable other useful features
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Enable developer extras for debugging
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Setup JavaScript bridge - inject boundobject
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "boundobject")
        configuration.userContentController = userContentController
        
        // Inject the boundobject JavaScript interface
        let boundObjectScript = """
        window.boundobject = {
            callNative: function(method, params) {
                window.webkit.messageHandlers.boundobject.postMessage({
                    method: method,
                    params: params || {}
                });
            },
            
            // Example methods that call native iOS code
            showAlert: function(message) {
                this.callNative('showAlert', { message: message });
            },
            
            getDeviceInfo: function(callback) {
                window.deviceInfoCallback = callback;
                this.callNative('getDeviceInfo', {});
            },
            
            log: function(message) {
                this.callNative('log', { message: message });
            }
        };
        console.log('✅ boundobject initialized');
        """
        
        let script = WKUserScript(source: boundObjectScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(script)
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Enable inspection (Safari Web Inspector)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        
        print("📂 Base directory: \(baseDirectory)")
        print("✅ WebView configured with applocal:// scheme (secure context)")
        print("✅ JavaScript bridge 'boundobject' registered")
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let url = URL(string: "applocal://localhost/\(fileName)")!
        print("🌐 Loading: \(url)")
        webView.load(URLRequest(url: url))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ Page loaded successfully")
            
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
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ Failed provisional navigation: \(error.localizedDescription)")
        }
        
        // MARK: - JavaScript Bridge Handler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            
            print("📨 Received message from JS: \(message.name)")
            print("   Body: \(body)")
            
            // Handle different message types
            switch message.name {
            case "boundobject":
                handleBoundObjectCall(body: body, webView: message.webView)
            default:
                print("⚠️ Unknown message name: \(message.name)")
            }
        }
        
        private func handleBoundObjectCall(body: [String: Any], webView: WKWebView?) {
            guard let method = body["method"] as? String else {
                print("⚠️ No method specified")
                return
            }
            
            let params = body["params"] as? [String: Any] ?? [:]
            
            // Handle different native methods
            switch method {
            case "showAlert":
                // Example: Show a native alert
                let message = params["message"] as? String ?? "Hello from iOS!"
                DispatchQueue.main.async {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let viewController = windowScene.windows.first?.rootViewController {
                        let alert = UIAlertController(title: "iOS Native Alert", message: message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        viewController.present(alert, animated: true)
                    }
                }
                
            case "getDeviceInfo":
                // Example: Return device info to JavaScript
                let deviceInfo: [String: Any] = [
                    "model": UIDevice.current.model,
                    "systemVersion": UIDevice.current.systemVersion,
                    "name": UIDevice.current.name
                ]
                let jsonData = try? JSONSerialization.data(withJSONObject: deviceInfo)
                if let jsonString = jsonData.flatMap({ String(data: $0, encoding: .utf8) }) {
                    let script = "if(window.deviceInfoCallback) { window.deviceInfoCallback(\(jsonString)); }"
                    webView?.evaluateJavaScript(script, completionHandler: nil)
                }
                
            case "log":
                // Example: Native logging
                let logMessage = params["message"] as? String ?? ""
                print("📱 iOS Native Log: \(logMessage)")
                
            default:
                print("⚠️ Unknown method: \(method)")
            }
        }
    }
}

// MARK: - Helper Extension
extension WebView {
    static func fromLocalFile(named fileName: String) -> WebView {
        return WebView(fileName: fileName)
    }
}
