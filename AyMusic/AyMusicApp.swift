//
//  AyMusicApp.swift
//  AyMusic
//
//  Created by Shiyukine on 8/10/25.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct AyMusicApp: App {
    init() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
        } catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
