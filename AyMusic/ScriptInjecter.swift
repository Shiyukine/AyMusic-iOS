//
//  ScriptInjecter.swift
//  AyMusic
//
//  Created on 12/31/25.
//

import Foundation

class ScriptInjecter {
    // Singleton instance
    static let shared = ScriptInjecter()
    
    // Storage for URL patterns and their scripts
    private var scriptsMap: [String: String] = [:]
    private var urlsLoaded: [String: Int] = [:] // 0: not loaded, 1: loaded, 2: failed
    
    private init() {}
    
    // MARK: - Script Management
    
    func addScript(url: String, script: String) {
        scriptsMap[url] = script
        urlsLoaded[url] = 0
    }
    
    func getUrlStatus(url: String) -> Int {
        return urlsLoaded[url] ?? 0
    }
    
    func setUrlLoaded(url: String, status: Int) {
        urlsLoaded[url] = status
    }
    
    func resetUrlsLoaded() {
        for key in urlsLoaded.keys {
            urlsLoaded[key] = 0
        }
    }
    
    func clearAllScripts() {
        scriptsMap.removeAll()
        urlsLoaded.removeAll()
    }
    
    // MARK: - URL Matching
    
    func haveScriptForUrl(_ url: String) -> Bool {
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return false
        }
        
        for (pattern, _) in scriptsMap {
            guard let encodedPattern = pattern.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                continue
            }
            
            if encodedUrl.contains(encodedPattern) {
                return true
            }
        }
        
        return false
    }
    
    func getScriptsForUrl(_ url: String) -> [String] {
        var scripts: [String] = []
        
        guard let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return scripts
        }
        
        for (pattern, script) in scriptsMap {
            guard let encodedPattern = pattern.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                continue
            }
            
            if encodedUrl.contains(encodedPattern) {
                scripts.append(script)
            }
        }
        
        return scripts
    }
    
    // MARK: - HTML Injection
    
    func injectScriptsIntoHTML(_ html: String, forUrl url: String) -> String {
        let scripts = getScriptsForUrl(url)
        
        guard !scripts.isEmpty else {
            return html
        }
        
        // Combine all scripts
        let combinedScript = scripts.joined(separator: "\n")
        let scriptTag = "<script>\n\(combinedScript)\n</script>"
        
        // Inject after <head> tag
        if let range = html.range(of: "<head>", options: .caseInsensitive) {
            var modifiedHTML = html
            let insertPosition = range.upperBound
            modifiedHTML.insert(contentsOf: scriptTag, at: insertPosition)
            return modifiedHTML
        }
        
        // If no <head> found, try after <html>
        if let range = html.range(of: "<html>", options: .caseInsensitive) {
            var modifiedHTML = html
            let insertPosition = range.upperBound
            modifiedHTML.insert(contentsOf: scriptTag, at: insertPosition)
            return modifiedHTML
        }
        
        // If neither found, prepend to document
        return scriptTag + html
    }
}
