//
//  Utils.swift
//  AyMusic
//
//  Created by Shiyukine on 12/31/25.
//

import SwiftUI
import WebKit

struct Utils {
    static public func performGETRequest(url: String, headers: [String: String], timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        guard let requestURL = URL(string: url) else {
            completion(.failure(NSError(domain: "WebView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "WebView", code: 204, userInfo: [NSLocalizedDescriptionKey: "No Data"])))
                return
            }

            // Return raw string response
            if let text = String(data: data, encoding: .utf8) {
                completion(.success(text))
            } else {
                completion(.failure(NSError(domain: "WebView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to decode response as UTF-8"])))
            }
        }
        task.resume()
    }

    static public func performPOSTRequest(url: String, headers: [String: String], body: [String: Any], timeout: TimeInterval, completion: @escaping (Result<String, Error>) -> Void) {
        guard let requestURL = URL(string: url) else {
            completion(.failure(NSError(domain: "WebView", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "WebView", code: 204, userInfo: [NSLocalizedDescriptionKey: "No Data"])))
                return
            }

            // Return raw string response
            if let text = String(data: data, encoding: .utf8) {
                completion(.success(text))
            } else {
                completion(.failure(NSError(domain: "WebView", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unable to decode response as UTF-8"])))
            }
        }
        task.resume()
    }
}
