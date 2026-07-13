import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

enum AudioPlayerError: LocalizedError {
    case invalidStoredFileName
    case missingStoredFile
    case cannotStartPlayback

    var errorDescription: String? {
        switch self {
        case .invalidStoredFileName:
            return "歌曲文件名无效。"
        case .missingStoredFile:
            return "找不到这首歌的本地 MP3 文件。"
        case .cannotStartPlayback:
            return "无法开始播放这首歌。"
        }
    }
}

@MainActor
final class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var currentSongID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var volume: Float = 1

    private let fileManager: FileManager
    private let musicDirectoryURL: URL?
    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?
    private var nowPlayingSong: Song?
    private var playbackQueue = [Song]()
    private var remoteCommandsConfigured = false

    init(
        fileManager: FileManager = .default,
        musicDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.musicDirectoryURL = musicDirectoryURL
    }

    func setPlaybackQueue(_ songs: [Song]) {
        playbackQueue = songs
        updateRemoteTrackCommandAvailability()
    }

    func togglePlayback(of song: Song) throws {
        if currentSongID == song.id, let audioPlayer {
            if audioPlayer.isPlaying {
                pausePlayback()
            } else {
                try resumePlayback()
            }

            return
        }

        try startPlayback(of: song)
    }

    func play(_ song: Song) throws {
        if currentSongID == song.id, let audioPlayer {
            guard !audioPlayer.isPlaying else {
                return
            }

            try resumePlayback()
            return
        }

        try startPlayback(of: song)
    }

    func playPrevious(in songs: [Song]) throws {
        guard let previousSong = Self.adjacentSong(
            in: songs,
            relativeTo: currentSongID,
            offset: -1
        ) else {
            return
        }

        try play(previousSong)
    }

    func hasPrevious(in songs: [Song]) -> Bool {
        Self.adjacentSong(
            in: songs,
            relativeTo: currentSongID,
            offset: -1
        ) != nil
    }

    func playNext(in songs: [Song]) throws {
        guard let nextSong = Self.adjacentSong(
            in: songs,
            relativeTo: currentSongID,
            offset: 1
        ) else {
            return
        }

        try play(nextSong)
    }

    func hasNext(in songs: [Song]) -> Bool {
        Self.adjacentSong(
            in: songs,
            relativeTo: currentSongID,
            offset: 1
        ) != nil
    }

    static func adjacentSong(
        in songs: [Song],
        relativeTo currentSongID: UUID?,
        offset: Int
    ) -> Song? {
        guard offset == -1 || offset == 1,
              let currentSongID,
              let currentIndex = songs.firstIndex(where: { $0.id == currentSongID }) else {
            return nil
        }

        let targetIndex = currentIndex + offset

        guard songs.indices.contains(targetIndex) else {
            return nil
        }

        return songs[targetIndex]
    }

    static func songForAutomaticContinuation(
        in songs: [Song],
        after currentSongID: UUID?,
        finishedSuccessfully: Bool
    ) -> Song? {
        guard finishedSuccessfully else {
            return nil
        }

        return adjacentSong(
            in: songs,
            relativeTo: currentSongID,
            offset: 1
        )
    }

    static func trackCommandAvailability(
        in songs: [Song],
        relativeTo currentSongID: UUID?
    ) -> (previous: Bool, next: Bool) {
        (
            previous: adjacentSong(
                in: songs,
                relativeTo: currentSongID,
                offset: -1
            ) != nil,
            next: adjacentSong(
                in: songs,
                relativeTo: currentSongID,
                offset: 1
            ) != nil
        )
    }

    private func startPlayback(of song: Song) throws {
        let fileURL = try storedFileURL(for: song)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.volume = volume

            guard player.prepareToPlay(), player.play() else {
                throw AudioPlayerError.cannotStartPlayback
            }

            audioPlayer?.stop()
            stopProgressUpdates()
            audioPlayer = player
            nowPlayingSong = song
            currentSongID = song.id
            isPlaying = true
            currentTime = player.currentTime
            duration = player.duration
            configureRemoteCommandsIfNeeded()
            updateRemoteTrackCommandAvailability()
            publishNowPlayingInfo()
            startProgressUpdates()
        } catch let error as AudioPlayerError {
            throw error
        } catch {
            throw AudioPlayerError.cannotStartPlayback
        }
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else {
            return
        }

        let targetTime = min(max(time, 0), audioPlayer.duration)
        audioPlayer.currentTime = targetTime
        currentTime = targetTime
        duration = audioPlayer.duration
        publishNowPlayingInfo()
    }

    func setVolume(_ newVolume: Float) {
        let clampedVolume = min(max(newVolume, 0), 1)
        volume = clampedVolume
        audioPlayer?.volume = clampedVolume
    }

    func refreshNowPlayingInfo() {
        publishNowPlayingInfo()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        nowPlayingSong = nil
        currentSongID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopProgressUpdates()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteTrackCommandAvailability()
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        guard player === audioPlayer else {
            return
        }

        if let nextSong = Self.songForAutomaticContinuation(
            in: playbackQueue,
            after: currentSongID,
            finishedSuccessfully: flag
        ) {
            do {
                try startPlayback(of: nextSong)
                return
            } catch {
                // Fall through to the completed state if the next local file is unavailable.
            }
        }

        player.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressUpdates()
        publishNowPlayingInfo()
    }

    static func nowPlayingInfo(
        for song: Song,
        elapsedTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) -> [String: Any] {
        let resolvedDuration = max(duration, 0)
        let resolvedElapsedTime = min(max(elapsedTime, 0), resolvedDuration)
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: resolvedDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: resolvedElapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: NSNumber(
                value: MPNowPlayingInfoMediaType.audio.rawValue
            )
        ]

        if let artworkData = song.artworkData,
           let artworkImage = UIImage(data: artworkData) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: artworkImage.size
            ) { _ in
                artworkImage
            }
        }

        return nowPlayingInfo
    }

    private func storedFileURL(for song: Song) throws -> URL {
        let fileNameURL = URL(fileURLWithPath: song.storageFileName)

        guard song.storageFileName == fileNameURL.lastPathComponent,
              fileNameURL.pathExtension.lowercased() == "mp3" else {
            throw AudioPlayerError.invalidStoredFileName
        }

        let directory = musicDirectoryURL ?? URL.documentsDirectory
            .appendingPathComponent("Music", isDirectory: true)
        let fileURL = directory.appendingPathComponent(song.storageFileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AudioPlayerError.missingStoredFile
        }

        return fileURL
    }

    private func startProgressUpdates() {
        stopProgressUpdates()

        progressTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25,
            repeats: true
        ) { [weak self] _ in
            self?.updatePlaybackProgress()
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updatePlaybackProgress() {
        guard let audioPlayer else {
            return
        }

        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
    }

    private func pausePlayback() {
        guard let audioPlayer else {
            return
        }

        audioPlayer.pause()
        isPlaying = false
        currentTime = audioPlayer.currentTime
        stopProgressUpdates()
        publishNowPlayingInfo()
    }

    private func resumePlayback() throws {
        guard let audioPlayer,
              audioPlayer.play() else {
            throw AudioPlayerError.cannotStartPlayback
        }

        isPlaying = true
        currentTime = audioPlayer.currentTime
        duration = audioPlayer.duration
        startProgressUpdates()
        publishNowPlayingInfo()
    }

    private func publishNowPlayingInfo() {
        guard let nowPlayingSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = Self.nowPlayingInfo(
            for: nowPlayingSong,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !remoteCommandsConfigured else {
            return
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handleRemotePlayCommand() ?? .noActionableNowPlayingItem
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handleRemotePauseCommand() ?? .noActionableNowPlayingItem
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handleRemoteToggleCommand() ?? .noActionableNowPlayingItem
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handleRemotePreviousTrackCommand() ?? .noActionableNowPlayingItem
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handleRemoteNextTrackCommand() ?? .noActionableNowPlayingItem
        }

        remoteCommandsConfigured = true
        updateRemoteTrackCommandAvailability()
    }

    private func handleRemotePlayCommand() -> MPRemoteCommandHandlerStatus {
        guard nowPlayingSong != nil else {
            return .noActionableNowPlayingItem
        }

        do {
            try resumePlayback()
            return .success
        } catch {
            return .commandFailed
        }
    }

    private func handleRemotePauseCommand() -> MPRemoteCommandHandlerStatus {
        guard audioPlayer != nil else {
            return .noActionableNowPlayingItem
        }

        pausePlayback()
        return .success
    }

    private func handleRemoteToggleCommand() -> MPRemoteCommandHandlerStatus {
        guard let audioPlayer else {
            return .noActionableNowPlayingItem
        }

        do {
            if audioPlayer.isPlaying {
                pausePlayback()
            } else {
                try resumePlayback()
            }

            return .success
        } catch {
            return .commandFailed
        }
    }

    private func handleRemotePreviousTrackCommand() -> MPRemoteCommandHandlerStatus {
        guard let currentSongID else {
            return .noActionableNowPlayingItem
        }

        guard let previousSong = Self.adjacentSong(
            in: playbackQueue,
            relativeTo: currentSongID,
            offset: -1
        ) else {
            return .noSuchContent
        }

        do {
            try play(previousSong)
            return .success
        } catch {
            return .commandFailed
        }
    }

    private func handleRemoteNextTrackCommand() -> MPRemoteCommandHandlerStatus {
        guard let currentSongID else {
            return .noActionableNowPlayingItem
        }

        guard let nextSong = Self.adjacentSong(
            in: playbackQueue,
            relativeTo: currentSongID,
            offset: 1
        ) else {
            return .noSuchContent
        }

        do {
            try play(nextSong)
            return .success
        } catch {
            return .commandFailed
        }
    }

    private func updateRemoteTrackCommandAvailability() {
        guard remoteCommandsConfigured else {
            return
        }

        let availability = Self.trackCommandAvailability(
            in: playbackQueue,
            relativeTo: currentSongID
        )
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.previousTrackCommand.isEnabled = availability.previous
        commandCenter.nextTrackCommand.isEnabled = availability.next
    }
}
