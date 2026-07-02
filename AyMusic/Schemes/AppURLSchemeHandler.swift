//
//  AppURLSchemeHandler.swift
//  AyMusic
//
//  Created by Shiyukine on 12/28/25.
//

import SwiftUI
import WebKit

class AppURLSchemeHandler: NSObject, WKURLSchemeHandler {
    let baseDirectory: String
    
    init(baseDirectory: String) {
        self.baseDirectory = baseDirectory
        super.init()
    }
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "AppSchemeHandler", code: -1, userInfo: nil))
            return
        }
        
        // Handle CORS preflight (OPTIONS) requests
        if urlSchemeTask.request.httpMethod == "OPTIONS" {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 204,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
                    "Access-Control-Max-Age": "86400"
                ]
            )!
            
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didFinish()
            return
        }
        
        // Get the host to determine which directory to use
        // app://root/index.html -> host = "root" (bundle resources)
        // app://cache/file.json -> host = "cache"
        // app://localfiles/file.json -> host = "localfiles"
        guard let host = url.host else {
            print("No host in app:// URL: \(url.absoluteString)")
            urlSchemeTask.didFailWithError(NSError(domain: "AppSchemeHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid app:// URL format"]))
            return
        }
        
        // Get the path from the URL
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        
        if path.isEmpty && host != "root" {
            print("Empty path in app:// request")
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        
        // Handle root (bundle resources) differently
        if host == "root" {
            handleRootRequest(urlSchemeTask: urlSchemeTask, url: url, path: path)
            return
        }
        
        // Determine which directory to use based on host
        let baseDir: URL?
        switch host {
        case "cache":
            baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        case "localfiles", "data":
            baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        default:
            print("Unknown app:// host: \(host)")
            urlSchemeTask.didFailWithError(NSError(domain: "AppSchemeHandler", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unknown host: \(host)"]))
            return
        }
        
        guard let directory = baseDir else {
            print("Cannot access \(host) directory")
            urlSchemeTask.didFailWithError(NSError(domain: "AppSchemeHandler", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot access directory"]))
            return
        }
        
        // Construct the full file path
        let fileURL = directory.appendingPathComponent(path)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            print("File not found in \(host): \(fileURL.path)")
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        
        let mimeType = getMimeType(for: path)
        
        // Create HTTPURLResponse with status code 200
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ]
        )!
        
        print("Loaded from \(host): \(path)")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Task cancelled
    }
    
    // MARK: - Root (Bundle Resources) Handler
    private func handleRootRequest(urlSchemeTask: WKURLSchemeTask, url: URL, path: String) {
        var resourcePath = path
        if resourcePath.isEmpty {
            resourcePath = "index.html"
        }
        
        var fileURL: URL?
        var data: Data?
        
        // Extract file components
        let fileName = (resourcePath as NSString).deletingPathExtension
        let fileExtension = (resourcePath as NSString).pathExtension
        let subdirectory = (resourcePath as NSString).deletingLastPathComponent
        
        // Try Bundle.url with FULL subdirectory path (works with blue folder references)
        if !subdirectory.isEmpty {
            if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: "HTML/\(subdirectory)") {
                fileURL = bundleURL
                data = try? Data(contentsOf: bundleURL)
                print("Loaded (hierarchical): HTML/\(resourcePath)")
            }
        }
        
        // Try at HTML root (for files like index.html, main.css at top level)
        if data == nil {
            if let bundleURL = Bundle.main.url(forResource: fileName, withExtension: fileExtension, subdirectory: "HTML") {
                fileURL = bundleURL
                data = try? Data(contentsOf: bundleURL)
            }
        }
        
        guard let data = data, let _ = fileURL else {
            print("Not found: \(resourcePath)")
            print("Expected: HTML/\(subdirectory.isEmpty ? "" : "\(subdirectory)/")\(fileName).\(fileExtension)")
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        
        let mimeType = getMimeType(for: resourcePath)
        
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-cache",
                "Access-Control-Allow-Origin": "*"
            ]
        )!
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
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
        case "m4a", "aac": return "audio/mp4"
        case "ogg", "oga": return "audio/ogg"
        case "opus": return "audio/opus"
        case "flac": return "audio/flac"
        case "wav": return "audio/wav"
        case "mp4": return "video/mp4"
        case "webm": return "video/webm"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
