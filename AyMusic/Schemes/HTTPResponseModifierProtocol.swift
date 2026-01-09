//
//  HTTPResponseModifierProtocol.swift
//  AyMusic
//
//  Created by Shiyukine on 1/2/26.
//

import Foundation
import WebKit

/// Custom NSURLProtocol to intercept and modify HTTP/HTTPS responses
/// This mimics the Android behavior of removing security headers and modifying cookies
class HTTPResponseModifierProtocol: URLProtocol {
    
    private var dataTask: URLSessionDataTask?
    private var urlSession: URLSession?
    private var receivedData: Data = Data()
    private var originalResponse: URLResponse?
    private var needCredentialsHeader: String = "false"
    
    // Cache for storing POST body data before WKWebView consumes the stream
    public static var bodyDataCache: [String: Data] = [:]
    public static let cacheLock = NSLock()

    public static var overrideResponses: [[String:Any]] = []
    
    public static var blockedUrls: [[String:Any]] = []
    
    // Client tokens storage
    private static var debounceSpotify = false
    
    // MARK: - URLProtocol Overrides
    
    override class func canInit(with request: URLRequest) -> Bool {
        
        // Only intercept http/https requests
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        
        // Avoid infinite loops by checking if we've already processed this request
        /*if URLProtocol.property(forKey: "HTTPResponseModifierProtocol", in: request) != nil {
            return false
        }*/
        
        return scheme == "http" || scheme == "https"
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "HTTPResponseModifierProtocol", code: -1, userInfo: nil))
            return
        }
        
        // block certain URLs
        if let urlString = request.url?.absoluteString {
            for blockRule in HTTPResponseModifierProtocol.blockedUrls {
                guard let pattern = blockRule["url"] as? String,
                        let includes = blockRule["includes"] as? Bool else {
                    continue
                }
                let isMatch = includes ? urlString.contains(pattern) : urlString == pattern
                if isMatch {
                    print("🚫 [Protocol] Blocking request to URL: \(urlString)")
                    let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled, userInfo: nil)
                    client?.urlProtocol(self, didFailWithError: error)
                    return
                }
            }
        }
        
        // Check if credentials are needed by looking at URL query parameter
        if let url = request.url, 
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           queryItems.contains(where: { $0.name == "__credentials" && $0.value == "true" }) {
            self.needCredentialsHeader = "true"
            
            // Remove the marker from URL before making actual request
            var newComponents = components
            newComponents.queryItems = queryItems.filter { $0.name != "__credentials" }
            if let cleanUrl = newComponents.url {
                mutableRequest.url = cleanUrl
            }
            
            // CRITICAL: Manually add Cookie header from HTTPCookieStorage
            // This ensures cookies are sent even when fetch() doesn't include credentials
            if let url = request.url {
                let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
                if !cookies.isEmpty {
                    // Format all cookies into a single Cookie header: "name1=value1; name2=value2"
                    let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                    mutableRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                    print("🍪 [Protocol] Added Cookie header with \(cookies.count) cookie(s): \(cookieHeader)")
                } else {
                    print("⚠️ [Protocol] No cookies found for URL: \(url.absoluteString)")
                }
            }
        }
        
        // Preserve HTTP method and body for POST/PUT requests
        if let httpMethod = request.httpMethod {
            mutableRequest.httpMethod = httpMethod
            
            // Extract X-Body-Data and X-Body-Encoding from headers
            let cachedBodyString = mutableRequest.value(forHTTPHeaderField: "X-Body-Data") ?? nil
            var cachedBody: Data? = nil
            if cachedBodyString == nil {
                HTTPResponseModifierProtocol.cacheLock.lock()
                let bodyId = request.url?.absoluteString
                cachedBody = bodyId.flatMap { HTTPResponseModifierProtocol.bodyDataCache[$0] }
                if httpMethod != "OPTIONS", let id = bodyId {
                    HTTPResponseModifierProtocol.bodyDataCache.removeValue(forKey: id) // Clean up
                }
                HTTPResponseModifierProtocol.cacheLock.unlock()
            }
            if cachedBodyString != nil {
                cachedBody = Data(cachedBodyString!.utf8)
            }
            let bodyEncoding = mutableRequest.value(forHTTPHeaderField: "X-Body-Encoding") ?? "none"
            
            // Remove custom headers from the request (will be re-added to response headers)
            mutableRequest.setValue(nil, forHTTPHeaderField: "X-Body-Data")
            mutableRequest.setValue(nil, forHTTPHeaderField: "X-Body-Encoding")
            
            if var bodyData = cachedBody {
                // Decode base64 if necessary
                if bodyEncoding == "base64", let base64String = String(data: bodyData, encoding: .utf8) {
                    if let decodedData = Data(base64Encoded: base64String) {
                        bodyData = decodedData
                    }
                }
                mutableRequest.httpBody = bodyData
            }
        }
        
        // Extract authentication tokens (Android equivalent)
        if let url = request.url {
            let urlString = url.absoluteString
            
            // Soundcloud client_id extraction
            if urlString.contains("api-auth.soundcloud.com/oauth/authorize") ||
               (urlString.contains("api-v2.soundcloud.com") && urlString.contains("client_id=")) {
                
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let queryItems = components.queryItems,
                   let clientId = queryItems.first(where: { $0.name == "client_id" })?.value {
                    
                    WebView.clientTokens["Soundcloud"] = clientId
                    print("🎵 [Soundcloud] Extracted client_id: \(clientId)")
                }
            }
            
            // Spotify Bearer token extraction
            if urlString.contains("spotify.com") {
                if let authHeader = request.value(forHTTPHeaderField: "Authorization") ?? 
                                   request.value(forHTTPHeaderField: "authorization") {
                    
                    if authHeader.lowercased().hasPrefix("bearer ") {
                        let token = String(authHeader.dropFirst("bearer ".count))
                        if urlString.contains("api-partner.spotify.com/pathfinder") && 
                           HTTPResponseModifierProtocol.debounceSpotify {
                            
                            HTTPResponseModifierProtocol.debounceSpotify = false
                            WebView.clientTokens["Spotify"] = token
                        }
                        HTTPResponseModifierProtocol.debounceSpotify = true
                    }
                }
            }
        }
        
        // Mark this request as processed to avoid infinite loops
        // URLProtocol.setProperty(true, forKey: "HTTPResponseModifierProtocol", in: mutableRequest)
        
        // Create URL session with proper configuration for SSL bypass
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData // Disable ALL caching
        config.urlCache = nil // Disable URL cache completely
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpAdditionalHeaders = mutableRequest.allHTTPHeaderFields
        config.httpCookieAcceptPolicy = .always
        
        #if DEBUG
        // Allow self-signed certificates by using ephemeral configuration
        // This ensures our delegate methods are called for SSL challenges
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        #endif
        
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.urlSession = session
        
        let task = session.dataTask(with: mutableRequest as URLRequest)
        self.dataTask = task
        task.resume()
        
        // print("[Protocol] Started loading: \(mutableRequest.httpMethod ?? "GET") \(mutableRequest.url?.absoluteString ?? "unknown")")
    }
    
    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        receivedData = Data()
        originalResponse = nil
    }
    
    // MARK: - Override Response Helper
    
    /// Check if request matches override rules and return search/replace map
    private class func haveOverrideResponseForRequest(url: String, headers: [String: String], method: String) -> [[String: String]]? {
        for overrideRule in overrideResponses {
            guard let urlPattern = overrideRule["url"] as? [String: Any],
                  let patternUrl = urlPattern["url"] as? String,
                  let includesUrl = urlPattern["includes"] as? Bool,
                  let ruleMethod = overrideRule["method"] as? String,
                  let overrides = overrideRule["overrides"] as? [[String: String]] else {
                continue
            }
            
            // Check method
            if method != ruleMethod {
                continue
            }
            
            // Check URL pattern
            let urlMatches = includesUrl ? url.contains(patternUrl) : url == patternUrl
            if !urlMatches {
                continue
            }
            
            // Check headers if specified
            if let headerRules = overrideRule["headers"] as? [[String: Any]], !headerRules.isEmpty {
                var headersMatch = false
                
                for headerRule in headerRules {
                    guard let headerName = headerRule["name"] as? String,
                          let headerValue = headerRule["value"] as? String,
                          let headerIncludes = headerRule["includes"] as? Bool else {
                        continue
                    }
                    
                    // Check if request has this header
                    if let requestHeaderValue = headers[headerName.lowercased()] {
                        let valueMatches = headerIncludes ? requestHeaderValue.contains(headerValue) : requestHeaderValue == headerValue
                        if valueMatches {
                            headersMatch = true
                            break
                        }
                    }
                }
                
                if !headersMatch {
                    continue
                }
            }
            
            // Match found - return overrides
            return overrides
        }
        
        return nil
    }
}

// MARK: - URLSessionDataDelegate
extension HTTPResponseModifierProtocol: URLSessionDataDelegate, URLSessionTaskDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
        // Modify response headers (similar to Android code)
        if let httpResponse = response as? HTTPURLResponse,
           let url = httpResponse.url {
            
            var modifiedHeaders = httpResponse.allHeaderFields as? [String: String] ?? [:]
            
            // Remove security headers that block iframes (Android equivalent)
            let headersToRemove = [
                "x-frame-options",
                "content-security-policy",
                "content-security-policy-report-only",
                "cross-origin-opener-policy-report-only",
                "Cross-Origin-Resource-Policy",
                "Cross-Origin-Embedder-Policy",
                "permissions-policy",
                "report-to",
                "access-control-allow-origin",
                "Access-Control-Allow-Headers"
            ]
            
            let headersToGet = [
                "Access-Control-Allow-Headers"
            ]
            
            var headersContent: [String: String] = [:]
            
            for header in headersToGet {
                for key in modifiedHeaders.keys {
                    if key.lowercased() == header.lowercased() {
                        headersContent[key.lowercased()] = modifiedHeaders[key]
                    }
                }
            }
            
            for header in headersToRemove {
                for key in modifiedHeaders.keys {
                    if key.lowercased() == header.lowercased() {
                        modifiedHeaders.removeValue(forKey: key)
                    }
                }
            }
            
            // Extract ALL cookies from the original response (handles multiple Set-Cookie headers)
            // CRITICAL: Must use the ORIGINAL allHeaderFields, not the dictionary conversion
            // because HTTPURLResponse can have multiple headers with the same name (Set-Cookie)
            // but [String: String] dictionary only keeps one!
            let allCookies = HTTPCookie.cookies(
                withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:],
                for: url
            )
            
            // Store and sync each cookie
            for cookie in allCookies {
                // Debug: Log cookie attributes
                // print("🍪 [Cookie Set] \(cookie.name) = \(cookie.value)")
                
                HTTPCookieStorage.shared.setCookie(cookie)
                
                // CRITICAL: Also notify WKWebView to sync to its cookie store
                // This makes cookies accessible to JavaScript (document.cookie)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SyncCookieToWebView"),
                        object: cookie
                    )
                }
            }
            
            // Set CORS headers based on credentials requirement
            if needCredentialsHeader == "true" {
                modifiedHeaders["Access-Control-Allow-Credentials"] = "true"
                let requestOrigin = request.value(forHTTPHeaderField: "Origin") ?? "*"
                modifiedHeaders["Access-Control-Allow-Origin"] = requestOrigin
            } else {
                modifiedHeaders["Access-Control-Allow-Origin"] = "*"
            }
            let currentAllowedHeaders = headersContent["Access-Control-Allow-Headers".lowercased()] ?? "*"
            modifiedHeaders["Access-Control-Allow-Headers"] = currentAllowedHeaders + ", X-Body-Data, X-Body-Encoding, Content-Type"
            modifiedHeaders["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, HEAD, PATCH"
            
            // Create modified response
            if let modifiedResponse = HTTPURLResponse(
                url: url,
                statusCode: httpResponse.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: modifiedHeaders
            ) {
                client?.urlProtocol(self, didReceive: modifiedResponse, cacheStoragePolicy: .notAllowed)
                originalResponse = modifiedResponse
            } else {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                originalResponse = response
            }
        } else {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            originalResponse = response
        }
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Accumulate data for potential override
        receivedData.append(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ [Protocol] Request failed: \(error.localizedDescription)")
            print("   URL: \(task.originalRequest?.url?.absoluteString ?? "unknown")")
            print("   Error code: \((error as NSError).code)")
            print("   Error domain: \((error as NSError).domain)")
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            // Check for response overrides
            if let httpResponse = originalResponse as? HTTPURLResponse,
               let url = httpResponse.url?.absoluteString,
               let method = task.originalRequest?.httpMethod {
                
                // Convert headers to lowercase keys for case-insensitive matching
                var lowercaseHeaders: [String: String] = [:]
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyStr = key as? String, let valueStr = value as? String {
                        lowercaseHeaders[keyStr.lowercased()] = valueStr
                    }
                }
                
                // Check if we have override rules for this request
                if let overrides = HTTPResponseModifierProtocol.haveOverrideResponseForRequest(
                    url: url,
                    headers: lowercaseHeaders,
                    method: method
                ) {
                    // Apply overrides to response data
                    if var responseString = String(data: receivedData, encoding: .utf8) {
                        print("🔄 [Override] Applying \(overrides.count) override(s) to response from: \(url)")
                        
                        for override in overrides {
                            if let search = override["search"], let replace = override["replace"] {
                                responseString = responseString.replacingOccurrences(of: search, with: replace)
                            }
                        }
                        
                        // Send modified data
                        if let modifiedData = responseString.data(using: .utf8) {
                            client?.urlProtocol(self, didLoad: modifiedData)
                            print("✅ [Override] Applied overrides, sent \(modifiedData.count) bytes")
                        } else {
                            // Fallback to original data if encoding fails
                            client?.urlProtocol(self, didLoad: receivedData)
                        }
                    } else {
                        // Not a text response, send as-is
                        client?.urlProtocol(self, didLoad: receivedData)
                    }
                } else {
                    // No overrides - send original data
                    client?.urlProtocol(self, didLoad: receivedData)
                }
            } else {
                // No HTTP response - send original data
                client?.urlProtocol(self, didLoad: receivedData)
            }
            
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Handle redirects and extract cookies
        if let url = response.url,
        let headers = response.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("SyncCookieToWebView"),
                        object: cookie
                    )
                }
            }
        }
        
        // Create mutable redirect request
        guard var mutableRedirect = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            completionHandler(nil)
            return
        }
        
        // If original request needed credentials, add marker to redirect URL
        if needCredentialsHeader == "true", let redirectUrl = request.url {
            var components = URLComponents(url: redirectUrl, resolvingAgainstBaseURL: false)
            if var queryItems = components?.queryItems {
                queryItems.append(URLQueryItem(name: "__credentials", value: "true"))
                components?.queryItems = queryItems
            } else {
                components?.queryItems = [URLQueryItem(name: "__credentials", value: "true")]
            }
            
            if let modifiedUrl = components?.url {
                mutableRedirect.url = modifiedUrl
            }
        }
        
        // Modify the redirect response to include CORS headers
        var modifiedHeaders = response.allHeaderFields as? [String: String] ?? [:]
        
        // Add CORS headers to the redirect response
        if needCredentialsHeader == "true" {
            modifiedHeaders["Access-Control-Allow-Credentials"] = "true"
            let requestOrigin = self.request.value(forHTTPHeaderField: "Origin") ?? "*"
            modifiedHeaders["Access-Control-Allow-Origin"] = requestOrigin
        } else {
            modifiedHeaders["Access-Control-Allow-Origin"] = "*"
        }
        
        // Create modified redirect response with CORS headers
        if let modifiedRedirectResponse = HTTPURLResponse(
            url: response.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: modifiedHeaders
        ) {
            client?.urlProtocol(self, wasRedirectedTo: mutableRedirect as URLRequest, redirectResponse: modifiedRedirectResponse)
        } else {
            client?.urlProtocol(self, wasRedirectedTo: mutableRedirect as URLRequest, redirectResponse: response)
        }
        
        // Return nil - let WKWebView handle the redirect navigation
        completionHandler(nil)
    }
    
    // Session-level SSL challenge handler (handles redirects and new connections)
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                #if DEBUG
                // Accept ALL certificates for local development (including self-signed)
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
                #else
                // Production: use default handling
                completionHandler(.performDefaultHandling, nil)
                return
                #endif
            }
        }
        
        // For other auth methods
        completionHandler(.performDefaultHandling, nil)
    }
    
    // Task-level SSL challenge handler (called first, before session-level)
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        
        print("🔐 [Protocol] Received task-level challenge for: \(challenge.protectionSpace.host)")
        print("   Auth method: \(challenge.protectionSpace.authenticationMethod)")
        
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                #if DEBUG
                // Accept ALL certificates for local development (including self-signed)
                let credential = URLCredential(trust: serverTrust)
                print("🔓 [Protocol SSL Bypass - Task] ✅ Accepting self-signed cert for: \(challenge.protectionSpace.host)")
                completionHandler(.useCredential, credential)
                return
                #else
                // Production: use default handling
                completionHandler(.performDefaultHandling, nil)
                return
                #endif
            }
        }
        
        // For other auth methods
        completionHandler(.performDefaultHandling, nil)
    }
}
