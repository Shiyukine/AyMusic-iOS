//
//  AyMusicApp.swift
//  AyMusic
//
//  Created by Shiyukine on 8/10/25.
//

import SwiftUI
import SwiftData
import WebKit

@main
struct AyMusicApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    init() {
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                saveSessionCookiesWithBackgroundTask()
            }
        }
    }
    
    private func saveSessionCookiesWithBackgroundTask() {
        // Tell iOS: "give me a few extra seconds to finish this, even if backgrounded"
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "SaveSessionCookies") {
            // Called if we run out of time — must end the task
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }

        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            
            CookieFileStore.save(cookies)

            UIApplication.shared.endBackgroundTask(self.bgTask)
            print("[Cookies] Saved \(cookies.filter { $0.isSessionOnly }.count) session-only cookies")
            self.bgTask = .invalid
        }
    }
}
