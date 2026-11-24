//
//  CookieFileStore.swift
//  AyMusic
//
//  Created by Shiyukine on 02/07/2026.
//


import Foundation

struct CookieFileStore {

    // MARK: - File URL

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )

        return appSupport.appendingPathComponent(".session_cookies")
    }

    // MARK: - Save

    /// `cookies` comes from WKHTTPCookieStore. It is merged with HTTPCookieStorage.shared, where the native request
    /// proxy puts the cookies it receives (the login's session cookie lands there first, and only reaches the
    /// WKHTTPCookieStore if a web view is around to receive the sync notification).
    static func save(_ cookies: [HTTPCookie]) {
        var merged: [String: HTTPCookie] = [:]
        for cookie in cookies { merged["\(cookie.name)|\(cookie.domain)|\(cookie.path)"] = cookie }
        for cookie in HTTPCookieStorage.shared.cookies ?? [] { merged["\(cookie.name)|\(cookie.domain)|\(cookie.path)"] = cookie }
        let cookies = Array(merged.values)

        // Persist ALL cookies (not only session-only ones): WebKit / HTTPCookieStorage flush persistent
        // cookies lazily, so a kill right after login (e.g. Xcode rebuild) could otherwise lose the session.
        guard !cookies.isEmpty else { return }

        guard let data = try? JSONEncoder().encode(cookies.map { PersistedCookie(from: $0) }) else { return }

        let url = fileURL

        do {
            try data.write(
                to: url,
                options: [
                    .atomic,
                    // Encrypted at rest, but readable/writable once the device was unlocked after boot.
                    // `.completeFileProtection` made the write fail when the app went to background because
                    // the screen was locked, and made the read fail on a background launch while locked.
                    .completeFileProtectionUntilFirstUserAuthentication
                ]
            )

            // Exclude from iCloud, iTunes, and Finder backups
            var resourceURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try resourceURL.setResourceValues(resourceValues)

            print("[CookieFileStore] Saved \(cookies.count) cookie(s); PHPSESSID: \(cookies.filter { $0.name == "PHPSESSID" }.map { "\($0.domain) session=\($0.isSessionOnly)" })")
        } catch {
            print("[CookieFileStore] Save failed: \(error)")
        }
    }

    // MARK: - Debounced save (called on every cookie change)

    private static var pendingSave: DispatchWorkItem?
    private static var lastWKCookies: [HTTPCookie] = []

    /// Pass the WKHTTPCookieStore cookies when you have them, or [] to just re-save (HTTPCookieStorage.shared is always read).
    static func saveDebounced(_ cookies: [HTTPCookie]) {
        DispatchQueue.main.async {
            if !cookies.isEmpty { lastWKCookies = cookies }
            pendingSave?.cancel()
            let item = DispatchWorkItem { save(lastWKCookies) }
            pendingSave = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
        }
    }

    // MARK: - Load

    static func load() -> [HTTPCookie] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[CookieFileStore] Load failed: no storage file")
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([PersistedCookie].self, from: data)
            let cookies = records.compactMap { $0.toHTTPCookie() }
            print("[CookieFileStore] Loaded \(cookies.count) cookie(s)")
            return cookies
        } catch {
            print("[CookieFileStore] Load failed: \(error)")
            return []
        }
    }

    // MARK: - Delete

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
