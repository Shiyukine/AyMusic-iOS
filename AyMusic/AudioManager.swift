//
//  AudioManager.swift
//  AyMusic
//
//  Created by Shiyukine on 01/07/2026.
//

import AVFoundation
import MediaPlayer
import WebKit

extension AVPlayer {
    var isPlaying: Bool {
        return rate != 0 && error == nil
    }
}

class AudioManager {
    static let shared = AudioManager()
    
    // 1. Swap AVAudioPlayer for the modern AVQueuePlayer and AVPlayerLooper
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var nowPlayingInfo = [String: Any]()
    private var webView: WKWebView?
    
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    
    private init() {}

    func startSilentLoop() {
        configureAudioSession()
        //setupRemoteTransportControls()
        
        guard let silentFileURL = createSilentWavFile() else { return }
        
        // 2. Create a Player Item from your micro-noise file
        let playerItem = AVPlayerItem(url: silentFileURL)
        
        // 3. Initialize the Queue Player
        queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        if let player = queuePlayer {
            // 4. Use AVPlayerLooper to seamlessly loop it at the system level
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            
            player.volume = 1.0
            
            UIApplication.shared.beginReceivingRemoteControlEvents()
            
            player.play()
            
            updateNowPlayingInfo()
            print("Modern AVQueuePlayer loop started safely!")
        } else {
            print("Could not instantiate AVQueuePlayer.")
        }
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
    
    private func updateNowPlayingInfo() {
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Click to launch the app"
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "Required to listen to a music"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "AyMusic"
        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: CGSize(width: 100, height: 100)) { _ in
            // 1. Traverse the Info.plist dictionary to find the primary icon name
            guard let iconsDict = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                  let primaryIconsDict = iconsDict["CFBundlePrimaryIcon"] as? [String: Any],
                  let iconFiles = primaryIconsDict["CFBundleIconFiles"] as? [String],
                  let lastIconName = iconFiles.last else {
                return UIImage()
            }
            
            // 2. Load the image asset via its catalog name
            return UIImage(named: lastIconName) ?? UIImage()
        }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            if self.queuePlayer?.isPlaying == false {
                self.queuePlayer?.play()
            }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "MediaActionWebView") {
                // Called if we run out of time — must end the task
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
            self.webView?.evaluateJavaScript("window.listeners.player.play(); window.testAudio.play()") { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                }
                
                self.bgTask = .invalid
            }
            return .success
        }
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            if self.queuePlayer?.isPlaying == false {
                self.queuePlayer?.play()
            }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "MediaActionWebView") {
                // Called if we run out of time — must end the task
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
            self.webView?.evaluateJavaScript("window.listeners.player.play(); window.testAudio.play()") { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    UIApplication.shared.endBackgroundTask(self.bgTask)
                }
                
                self.bgTask = .invalid
            }
            return .success
        }
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { _ in
            self.webView?.evaluateJavaScript("window.listeners.player.next()", completionHandler: nil)
            return .success
        }
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            self.webView?.evaluateJavaScript("window.listeners.player.previous()", completionHandler: nil)
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let positionEvent = event as? MPChangePlaybackPositionCommandEvent {
                let newTime = positionEvent.positionTime
                self.webView?.evaluateJavaScript("window.listeners.player.seek(\(newTime))", completionHandler: nil)
                return .success
            }
            return .commandFailed
        }
    }
    
    private func createSilentWavFile() -> URL? {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        guard let cacheDir = urls.first else { return nil }
        let fileURL = cacheDir.appendingPathComponent("generated_micronoise.wav")
        
        if fileManager.fileExists(atPath: fileURL.path) { return fileURL }
        
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false) else { return nil }
        
        do {
            let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            let frameCount = AVAudioFrameCount(format.sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
            buffer.frameLength = frameCount
            
            if let channelData = buffer.floatChannelData?[0] {
                for i in 0..<Int(frameCount) {
                    channelData[i] = Float.random(in: -0.001...0.001)
                }
            }
            
            try audioFile.write(from: buffer)
            return fileURL
        } catch {
            print("Failed to generate micro-noise file: \(error)")
            return nil
        }
    }

    func sessionChangeMediaMetadata(_ title: String, _ album: String, _ artist: String, _ artworkUrl: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.nowPlayingInfo[MPMediaItemPropertyTitle] = title
            self.nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
            self.nowPlayingInfo[MPMediaItemPropertyArtist] = artist
            
            if let url = URL(string: artworkUrl), let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
            }
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
        }
    }

    func sessionChangePositionState(_ currentTime: Double, _ duration: Double, _ playbackRate: Double, _ isPlaying: Bool, _ shuffle: Bool, _ repeatMode: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            self.nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
            self.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
            
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }

    func sessionChangePlaying(_ isPlaying: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        }
    }
}
