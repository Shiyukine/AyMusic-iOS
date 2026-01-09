//
//  LocalFilesURLSchemeHandler.swift
//  AyMusic
//
//  Created by Shiyukine on 12/28/25.
//

import SwiftUI
import WebKit

class LocalFilesURLSchemeHandler: NSObject, WKURLSchemeHandler {
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "LocalFilesSchemeHandler", code: -1, userInfo: nil))
            return
        }
        
        // Get documents directory
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("⚠️ Cannot access documents directory")
            urlSchemeTask.didFailWithError(NSError(domain: "LocalFilesSchemeHandler", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot access documents directory"]))
            return
        }
        
        // Get the path from the URL (e.g., app://localfiles/myfile.json -> myfile.json)
        var path = url.path
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }
        
        if path.isEmpty {
            print("⚠️ Empty path in localfiles request")
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        
        // Construct the full file path
        let fileURL = documentsDir.appendingPathComponent(path)
        
        guard let data = try? Data(contentsOf: fileURL) else {
            print("❌ Local file not found: \(fileURL.path)")
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
                "Cache-Control": "no-cache"
            ]
        )!
        
        print("✅ Loaded from documents: \(path)")
        
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
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
