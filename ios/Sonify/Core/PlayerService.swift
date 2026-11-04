import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Состояние и управление воспроизведением.
///
/// `direct`-треки играют нативно: аудиофайл скачивается в `AudioCache`, затем
/// воспроизводится через `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitEQ`
/// (это даёт эквалайзер). `embed`-треки SoundCloud открываются официальным
/// виджетом в WKWebView (см. `SoundCloudEmbedView`) — для них нативный EQ,
/// фоновое воспроизведение и оффлайн недоступны, что UI честно показывает.
@MainActor
@Observable
final class PlayerService {
    enum State: Equatable {
        case idle
        case loading(Track? = nil)
        case playing
        case paused
        case failed(String)
    }

    var currentTrack: Track?
    var state: State = .idle
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering = false
    var queue: [Track] = []
    var queueIndex: Int = 0
    var repeatMode: RepeatMode = .off
    var isShuffleEnabled = false

    private let repository: TrackRepository
    let equalizer: EqualizerController
    private var audioFile: AVAudioFile?
    private var timer: Task<Void, Never>?
    private var startOffset: TimeInterval = 0
    private var startTicks: UInt64 = 0
    private var observerTasks: [Task<Void, Never>] = []
    private var wasPlayingBeforeInterruption = false

    enum RepeatMode: String, CaseIterable, Sendable {
        case off, one, all
        var next: RepeatMode {
            switch self {
            case .off: .all
            case .all: .one
            case .one: .off
            }
        }
    }

    init(repository: TrackRepository = TrackRepository(), equalizer: EqualizerController = EqualizerController()) {
        self.repository = repository
        self.equalizer = equalizer
        equalizer.apply(preset: .flat)
        observeNotifications()
        setupRemoteCommands()
    }

    // MARK: - Public

    func play(track: Track, queue: [Track]? = nil) async {
        if let queue, !queue.isEmpty {
            self.queue = queue
            self.queueIndex = queue.firstIndex(of: track) ?? 0
        } else if self.queue.isEmpty {
            self.queue = [track]
            self.queueIndex = 0
        }
        await load(track, autoPlay: true)
    }

    func togglePlayPause() {
        guard let track = currentTrack else { return }
        if track.canPlayNatively {
            switch state {
            case .playing: pause()
            case .paused, .failed, .idle: resume()
            case .loading: break
            }
        }
    }

    func pause() {
        guard case .playing = state else { return }
        equalizer.playerNode.pause()
        state = .paused
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack?.canPlayNatively == true else { return }
        if audioFile == nil {
            Task { await load(currentTrack!, autoPlay: true) }
            return
        }
        try? AudioSessionController.activate()
        if !equalizer.engine.isRunning {
            try? equalizer.engine.start()
        }
        equalizer.playerNode.play()
        state = .playing
        startTimer()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard currentTrack?.canPlayNatively == true, let file = audioFile else { return }
        let clamped = max(0, min(time, duration))
        let sampleRate = file.processingFormat.sampleRate
        let frame = AVAudioFramePosition(clamped * sampleRate)
        let remaining = file.length - frame
        guard remaining > 0 else { return }
        let wasPlaying = state == .playing
        let completion: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.handleTrackFinished() }
        }
        equalizer.playerNode.stop()
        equalizer.playerNode.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionHandler: completion
        )
        startOffset = clamped
        startTicks = 0
        position = clamped
        if wasPlaying {
            equalizer.playerNode.play()
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        queueIndex = isShuffleEnabled ? Int.random(in: 0..<queue.count) : (queueIndex + 1) % queue.count
        let track = queue[queueIndex]
        Task { await load(track, autoPlay: true) }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 {
            seek(to: 0)
            return
        }
        queueIndex = queueIndex > 0 ? queueIndex - 1 : queue.count - 1
        let track = queue[queueIndex]
        Task { await load(track, autoPlay: true) }
    }

    func stop() {
        equalizer.playerNode.stop()
        timer?.cancel()
        audioFile = nil
        state = .idle
        position = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Loading

    private func load(_ track: Track, autoPlay: Bool) async {
        state = .loading(track)
        currentTrack = track
        position = 0
        duration = track.duration
        equalizer.playerNode.stop()
        audioFile = nil
        stopTimer()

        guard track.canPlayNatively else {
            state = .paused
            updateNowPlaying()
            return
        }

        do {
            try AudioSessionController.activate()
            isBuffering = true
            let descriptor = try await repository.streamDescriptor(for: track)
            guard let remote = descriptor.url, descriptor.kind == .direct else {
                throw AppError.audioForbidden
            }
            let local = try await repository.localFile(for: track, remote: remote)
            let file = try AVAudioFile(forReading: local)
            audioFile = file
            duration = Double(file.length) / file.processingFormat.sampleRate
            isBuffering = false
            schedule(file: file)
            if autoPlay {
                state = .playing
                startTimer()
            } else {
                state = .paused
            }
            updateNowPlaying()
        } catch {
            isBuffering = false
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func schedule(file: AVAudioFile) {
        equalizer.playerNode.scheduleFile(file, at: nil) { [weak self] in
            Task { @MainActor in self?.handleTrackFinished() }
        }
        if !equalizer.engine.isRunning {
            do {
                try equalizer.engine.start()
            } catch {
                state = .failed("Не удалось запустить аудиодвижок: \(error.localizedDescription)")
                return
            }
        }
        equalizer.playerNode.play()
        startOffset = 0
        startTicks = 0
        refreshClock()
    }

    private func handleTrackFinished() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else if repeatMode == .off && queueIndex >= queue.count - 1 {
            state = .paused
            position = duration
            stopTimer()
            updateNowPlaying()
        } else {
            next()
        }
    }

    // MARK: - Clock

    private func startTimer() {
        stopTimer()
        refreshClock()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                self.refreshClock()
            }
        }
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    private func refreshClock() {
        guard let nodeTime = equalizer.playerNode.lastRenderTime,
              let playerTime = equalizer.playerNode.playerTime(forNodeTime: nodeTime) else { return }
        if startTicks == 0 { startTicks = playerTime.sampleTime }
        let delta = Double(playerTime.sampleTime - startTicks) / playerTime.sampleRate
        position = min(duration, max(0, startOffset + delta))
        if position > 0, position.truncatingRemainder(dividingBy: 5) < 0.3 {
            updateNowPlaying()
        }
    }

    // MARK: - Remote / Now Playing

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if track.sourceKind == .soundcloud {
            info[MPMediaItemPropertyAlbumTitle] = "SoundCloud"
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Notifications

    private func observeNotifications() {
        let center = NotificationCenter.default
        observerTasks.append(Task { [weak self] in
            for await notification in center.notifications(named: AVAudioSession.interruptionNotification) {
                await MainActor.run { self?.handleInterruption(notification) }
            }
        })
        observerTasks.append(Task { [weak self] in
            for await notification in center.notifications(named: AVAudioSession.routeChangeNotification) {
                await MainActor.run { self?.handleRouteChange(notification) }
            }
        })
    }

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = state == .playing
            pause()
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            if wasPlayingBeforeInterruption, options.contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let reasonRaw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        if reason == .oldDeviceUnavailable, state == .playing {
            pause()
        }
    }
}
