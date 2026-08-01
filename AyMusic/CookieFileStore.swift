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

    static func save(_ cookies: [HTTPCookie]) {
        let sessionCookies = cookies.filter { $0.isSessionOnly }
        guard !sessionCookies.isEmpty else { return }

        guard let data = try? JSONEncoder().encode(sessionCookies.map { PersistedCookie(from: $0) }) else { return }

        let url = fileURL

        do {
            try data.write(
                to: url,
                options: [
                    .atomic,
                    // Encrypts file with device hardware key + user passcode.
                    // File is inaccessible when device is locked.
                    // Same underlying mechanism as the Keychain.
                    .completeFileProtection
                ]
            )

            // Exclude from iCloud, iTunes, and Finder backups
            var resourceURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try resourceURL.setResourceValues(resourceValues)

        } catch {
            print("[CookieFileStore] Save failed: \(error)")
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
            return records.compactMap { $0.toHTTPCookie() }
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
