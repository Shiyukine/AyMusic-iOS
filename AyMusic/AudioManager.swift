//
//  AudioManager.swift
//  AyMusic
//
//  Created by Shiyukine on 01/07/2026.
//

import AVFoundation
import MediaPlayer

class AudioManager {
    static let shared = AudioManager()
    
    // 1. Swap AVAudioPlayer for the modern AVQueuePlayer and AVPlayerLooper
    private var queuePlayer: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    
    private init() {}

    func startSilentLoop() {
        configureAudioSession()
        /*setupRemoteTransportControls()
        
        guard let silentFileURL = createSilentWavFile() else { return }
        
        // 2. Create a Player Item from your micro-noise file
        let playerItem = AVPlayerItem(url: silentFileURL)
        
        // 3. Initialize the Queue Player
        queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        if let player = queuePlayer {
            // 4. Use AVPlayerLooper to seamlessly loop it at the system level
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
            
            player.volume = 1.0 // Keep at 1.0 since the file is microscopic noise
            
            UIApplication.shared.beginReceivingRemoteControlEvents()
            
            player.play()
            
            updateNowPlayingInfo()
            print("Modern AVQueuePlayer loop started safely!")
        } else {
            print("Could not instantiate AVQueuePlayer.")
        }*/
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set audio session: \(error)")
        }
    }
    
    private func updateNowPlayingInfo() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "System Active"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "My App"
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = 86400.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { _ in return .success }
        commandCenter.pauseCommand.addTarget { _ in return .success }
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
}
