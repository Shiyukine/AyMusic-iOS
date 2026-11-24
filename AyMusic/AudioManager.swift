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
    
    // Keep-alive state: the silent loop is what keeps the *app* running in background,
    // so it must restart itself whenever iOS pauses it (call, Bluetooth disconnect, ...).
    private var isInterruptedFlag = false
    private var interruptionStartedAt = Date.distantPast
    /// An interruption whose `.ended` never arrives (seen in the logs) must not block restarts forever
    private var isInterrupted: Bool {
        get { isInterruptedFlag && Date().timeIntervalSince(interruptionStartedAt) < 8 }
        set { isInterruptedFlag = newValue; if newValue { interruptionStartedAt = Date() } }
    }
    private var observersInstalled = false
    private var statusObservation: NSKeyValueObservation?
    private var retryWork: DispatchWorkItem?
    private var retryCount = 0
    private let maxRetries = 20

    private init() {}

    func startSilentLoop() {
        // Calls before the cold-launch decision (setupAtLaunch decides after 0.6 s) wait for it; a cold launch from
        // Control Center holds the loop back (see setupAtLaunch). The loop must exist in every other session: a native
        // player outside the web view is what keeps AyMusic registered as a music app.
        if queuePlayer == nil && (Date().timeIntervalSince(initTime) < 0.6 || coldLaunchHold) { return }
        installObserversIfNeeded()

        // Called on every ContentView.onAppear: don't rebuild the player (and don't reset
        // the Now Playing info) if it already exists, just make sure it is running.
        if queuePlayer != nil {
            ensureSilentLoopPlaying(reason: "startSilentLoop (already created)")
            return
        }

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

            // iOS pauses the player on interruptions / route loss. Restart it ourselves,
            // otherwise nothing plays and iOS suspends the app (and the WKWebView JS with it).
            statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
                if p.timeControlStatus == .playing {
                    self?.retryCount = 0
                } else if p.timeControlStatus == .paused {
                    self?.scheduleRestart(reason: "timeControlStatus == paused")
                }
            }

            UIApplication.shared.beginReceivingRemoteControlEvents()

            player.play()

            updateNowPlayingInfo()
            print("Modern AVQueuePlayer loop started safely!")
        } else {
            print("Could not instantiate AVQueuePlayer.")
        }
    }

    // MARK: - Who owns the audio session
    
    // The native loop and WebKit's audio (the page's keep-alive <audio>, the music) are two non-mixable audio sessions:
    // whichever starts last interrupts the other, and an interrupted WebKit play() fails. The page reports whether it
    // is playing audio; the loop is only (re)started when it is not, and not right after the page became ready
    // (its keep-alive audio is starting).
    private var webAudioPlaying = false
    private var webAudioGraceUntil = Date.distantPast
    
    func setWebAudioPlaying(_ playing: Bool) {
        guard playing != webAudioPlaying else { return }
        webAudioPlaying = playing
        if !playing {
            if queuePlayer == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    guard let self, !self.webAudioPlaying else { return }
                    self.coldLaunchHold = false
                    self.startSilentLoop()
                }
            } else {
                scheduleRestart(reason: "web audio stopped", delay: 1.5)
            }
        }
    }
    
    // MARK: - Web process tether
    
    // WebKit holds a foreground activity on the web process while a runJavaScript call is pending (if the app can take
    // foreground assertions, i.e. it is playing audio). In background we keep one long async JS call pending at all
    // times, so the page keeps running instead of being suspended. A tick that returns late means it was frozen.
    private var tetherRunning = false
    
    func startWebTether() {
        guard !tetherRunning, webView != nil, UIApplication.shared.applicationState != .active else { return }
        tetherRunning = true
        runTether()
    }
    
    private func runTether() {
        guard let webView, UIApplication.shared.applicationState != .active else {
            tetherRunning = false
            return
        }
        let started = Date()
        webView.callAsyncJavaScript(
            "await new Promise(r => setTimeout(r, 20000)); return window.__webAudioActive ? (window.__webAudioActive() ? 'tick:1' : 'tick:0') : 'tick:?'",
            arguments: [:], in: nil, in: .page
        ) { [weak self] result in
            guard let self else { return }
            var failed = false
            if case .failure = result { failed = true }
            if case .success(let value) = result, let text = value as? String {
                if text == "tick:1" { self.setWebAudioPlaying(true) }
                else if text == "tick:0" { self.setWebAudioPlaying(false) }
            }
            if Date().timeIntervalSince(started) > 30 { self.setWebAudioPlaying(false) }
            DispatchQueue.main.asyncAfter(deadline: .now() + (failed ? 2 : 0)) { self.runTether() }
        }
    }
    
    // MARK: - Keep-alive / recovery

    private func log(_ message: String) {
        print("[AudioManager] \(message)")
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let nc = NotificationCenter.default

        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self,
                  let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.isInterrupted = true
                self.retryWork?.cancel()
            case .ended:
                self.isInterrupted = false
                self.retryCount = 0
                // The silent loop must always come back, whether or not the *music* should resume
                // (WebKit decides that on its own for the page's media).
                self.ensureSilentLoopPlaying(reason: "interruption ended")
            @unknown default:
                break
            }
        }

        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            guard let self,
                  let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable {
                self.retryCount = 0
                self.scheduleRestart(reason: "route change \(reason.rawValue)", delay: 0.3)
            }
        }

        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.statusObservation?.invalidate()
            self.statusObservation = nil
            self.playerLooper = nil
            self.queuePlayer = nil
            self.retryCount = 0
            self.startSilentLoop()
        }

        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.startWebTether()
        }
        
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.retryCount = 0
            // The user opened the app: no reason to hold the loop back any more
            if self?.queuePlayer == nil, !(self?.webAudioPlaying ?? false) {
                self?.coldLaunchHold = false
                self?.startSilentLoop()
            }
            self?.ensureSilentLoopPlaying(reason: "didBecomeActive")
        }
    }

    private func scheduleRestart(reason: String, delay: TimeInterval = 0.5) {
        DispatchQueue.main.async {
            guard !self.isInterrupted else { return }
            self.retryWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.ensureSilentLoopPlaying(reason: reason) }
            self.retryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func ensureSilentLoopPlaying(reason: String) {
        guard let player = queuePlayer, !isInterrupted else { return }

        if webAudioPlaying { return }
        let graceLeft = webAudioGraceUntil.timeIntervalSinceNow
        if graceLeft > 0 {
            scheduleRestart(reason: reason, delay: graceLeft + 0.3)
            return
        }

        retryCount += 1
        if retryCount > maxRetries {
            log("giving up restarting silent loop (\(reason))")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // Typically fails while a call is still active or if iOS refuses activation in background
            log("setActive failed (\(reason)): \(error), retry #\(retryCount)")
            scheduleRestart(reason: reason, delay: min(0.5 * Double(retryCount), 5))
            return
        }

        if player.timeControlStatus != .playing {
            player.play()
        }
        pokeWebKeepAlive()
    }
    
    /// Ask the page to restart its own silent <audio>. WebKit pauses it on interruptions, and without media playing
    /// in the page the web content process gets suspended even though the app is alive.
    private func pokeWebKeepAlive() {
        guard let webView else { return }
        
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "WebKeepAlive") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        
        webView.callAsyncJavaScript(
            "return window.listeners && window.listeners.keepAlive ? await window.listeners.keepAlive() : 'listeners.keepAlive missing'",
            arguments: [:], in: nil, in: .page
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }

    func setWebView(_ webView: WKWebView) {
        self.webView = webView
    }
    
    // MARK: - Play inside the platform iframe with a user gesture
    
    // The music plays in a cross-origin platform iframe. While the page is hidden WebKit denies audible playback
    // started without a user gesture *in that document*. A postMessage from the main page carries no gesture, but
    // evaluateJavaScript/callAsyncJavaScript force one in the frame they target.
    private var mediaFrame: (taskId: String, frame: WKFrameInfo)?
    
    func registerMediaFrame(taskId: String, frame: WKFrameInfo) {
        mediaFrame = (taskId, frame)
    }
    
    // Every frame (including cross-origin frames nested in the platform iframe, e.g. the Spotify SDK frame) reports
    // itself through boundobject.js: the audio element lives in the innermost one.
    private var knownFrames: [(url: String, frame: WKFrameInfo)] = []
    
    func registerFrame(url: String, frame: WKFrameInfo) {
        knownFrames.removeAll { $0.url == url }
        knownFrames.append((url, frame))
        if knownFrames.count > 30 { knownFrames.removeFirst() }
        // A frame that appears while the restore mute is on (the SDK frame) must start muted
        if restoreMute, !frame.isMainFrame, let webView {
            webView.callAsyncJavaScript("window.__aymSetMute && window.__aymSetMute(true)", arguments: [:], in: frame, in: .page) { _ in }
        }
    }
    
    /// Replays, inside a forced gesture, the media elements of every known frame that WebKit refused or swallowed.
    private func replayInAllFrames() {
        guard let webView else { return }
        var dead: [String] = []
        let group = DispatchGroup()
        for entry in knownFrames {
            group.enter()
            webView.callAsyncJavaScript(
                "return window.__aymusicRetryPlay ? await window.__aymusicRetryPlay() : ''",
                arguments: [:], in: entry.frame, in: .page
            ) { result in
                if case .failure = result { dead.append(entry.url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.knownFrames.removeAll { dead.contains($0.url) }
        }
    }
    
    /// A media element in `frame` called play() while the page is hidden: replay it inside a forced gesture a few times
    /// (the SDK's play() is often neither rejected nor completed in that state).
    private var replayGeneration: [String: Int] = [:]
    
    func replayPlayAttempts(in frame: WKFrameInfo) {
        guard let webView else { return }
        let key = frame.request.url?.host ?? "?"
        let generation = (replayGeneration[key] ?? 0) + 1
        replayGeneration[key] = generation
        
        for delay in [0.05, 0.6, 1.5, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // a newer play() call in the same frame restarts the sequence
                guard let self, self.replayGeneration[key] == generation else { return }
                webView.callAsyncJavaScript(
                    "return window.__aymusicRetryPlay ? await window.__aymusicRetryPlay() : ''",
                    arguments: [:], in: frame, in: .page
                ) { _ in }
            }
        }
    }
    
    /// Runs the platform's play script in the registered iframe. Completion gets "ok" or an error string.
    func playMediaFrame(taskId: String, completion: @escaping (String) -> Void) {
        guard let webView else { completion("no webview"); return }
        guard let entry = mediaFrame, entry.taskId == taskId else { completion("no media frame for task"); return }
        
        // Don't activate our own audio session here: it would interrupt WebKit's right before the SDK's play().
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "PlayMediaFrame") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        
        webView.callAsyncJavaScript(
            "return await (window.__aymusicPlay ? window.__aymusicPlay() : 'no __aymusicPlay in frame')",
            arguments: [:], in: entry.frame, in: .page
        ) { [weak self] result in
            let text: String
            switch result {
            case .success(let value): text = (value as? String) ?? "ok"
            case .failure(let error): text = "js error: \(error.localizedDescription)"
            }
            completion(text)
            
            // The actual start often comes from a server round trip (Spotify Web API -> SDK frame): replay whatever the
            // frames swallowed, inside a gesture, a few times over the next seconds.
            for delay in [0.0, 1.5, 3.0, 4.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.replayInAllFrames() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }
    
    // MARK: - Mute the SDK's priming blip
    
    // A song restored paused (autoplay=false) is still played once from 0:00 by the Spotify SDK for ~0.6 s. While the
    // flag is on, media elements in sub-frames are muted when they get their play(); the page clears it when the
    // music is really started, which unmutes them.
    private var restoreMute = false
    
    func setRestoreMute(_ mute: Bool) {
        guard mute != restoreMute else { return }
        restoreMute = mute
        guard let webView else { return }
        for entry in knownFrames where !entry.frame.isMainFrame {
            webView.callAsyncJavaScript("window.__aymSetMute && window.__aymSetMute(\(mute))", arguments: [:], in: entry.frame, in: .page) { _ in }
        }
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
    
    // MARK: - Launch / remote commands
    
    private let initTime = Date()
    private var coldLaunchHold = false
    
    /// Call once, as early as possible (AyMusicApp.init): when Control Center's play relaunches the closed app in
    /// background, iOS delivers the command as soon as a handler is registered.
    ///
    /// The native loop keeps AyMusic eligible as the music app, but it is a second audio session next to WebKit's:
    /// after a cold launch from Control Center it blocks WebKit's audio (the SDK's play() hangs). In that case it stays
    /// off until the page's audio has played and stopped, for at most 20 s, or until the user opens the app.
    func setupAtLaunch() {
        setupRemoteTransportControls()
        installObserversIfNeeded()
        // A Control Center play command is delivered within ~100 ms of launch; wait a bit to know whether it is one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            if self.coldLaunchHold {
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    guard let self, self.coldLaunchHold else { return }
                    self.releaseColdLaunchHold()
                }
            } else {
                self.startSilentLoop()
            }
        }
    }
    
    private func releaseColdLaunchHold() {
        guard coldLaunchHold else { return }
        coldLaunchHold = false
        // While the page's audio plays the loop stays off (it would interrupt it); it starts when that audio stops
        if !webAudioPlaying { startSilentLoop() }
    }
    
    // WebKit already registers next/previous/seek itself from the page's MediaSession handlers (listen.js).
    // Registering them natively too would run each command twice (skipping two tracks), so only play/pause are ours.
    private var remoteCommandsInstalled = false
    
    // Page readiness: a play request that arrives before the web app is loaded (cold launch) is kept and
    // executed as soon as the page reports it is ready.
    private var pageReady = false
    private var pendingResume = false
    
    func pageDidReload() {
        pageReady = false
    }
    
    func pageDidBecomeReady() {
        pageReady = true
        // Restart the page's silent <audio> with a gesture so the web process isn't suspended
        webAudioGraceUntil = Date().addingTimeInterval(4)
        pokeWebKeepAlive()
        startWebTether()
        if pendingResume {
            pendingResume = false
            runResumePlayback()
        }
    }
    
    private func requestResumePlayback() {
        if pageReady { runResumePlayback() } else { pendingResume = true }
    }
    
    private var resumeInFlight = false
    private var resumeStartedAt = Date.distantPast
    
    private func runResumePlayback() {
        resumeInFlight = true
        resumeStartedAt = Date()
        guard let webView else {
            pendingResume = true
            return
        }
        
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "ResumePlayback") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        
        webView.callAsyncJavaScript(
            "return window.listeners && window.listeners.resumePlayback ? await window.listeners.resumePlayback() : 'not ready'",
            arguments: [:], in: nil, in: .page
        ) { [weak self] result in
            if case .success(let value) = result, (value as? String) == "not ready" {
                self?.pageReady = false
                self?.pendingResume = true
            }
            self?.resumeInFlight = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }
    
    private func runPausePlayback() {
        guard let webView else { return }
        webView.callAsyncJavaScript(
            "return window.listeners && window.listeners.player ? (window.listeners.player.pause(), 'ok') : 'not ready'",
            arguments: [:], in: nil, in: .page
        ) { _ in }
    }
    
    private func setupRemoteTransportControls() {
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true
        
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.queuePlayer == nil && Date().timeIntervalSince(self.initTime) < 3 {
                self.coldLaunchHold = true
            }
            // Several presses in a row (nothing audible yet) restarted the sequence and broke the first start
            if self.resumeInFlight, Date().timeIntervalSince(self.resumeStartedAt) < 15 { return .success }
            // No audio session activation here: the page's audio takes over
            MPNowPlayingInfoCenter.default().playbackState = .playing
            self.requestResumePlayback()
            return .success
        }
        
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            MPNowPlayingInfoCenter.default().playbackState = .paused
            // A pause must not be replayed once the page loads
            self.pendingResume = false
            self.runPausePlayback()
            return .success
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
