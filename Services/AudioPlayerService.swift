import AVFoundation
import Combine
import Foundation

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

    init(
        fileManager: FileManager = .default,
        musicDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.musicDirectoryURL = musicDirectoryURL
    }

    func togglePlayback(of song: Song) throws {
        if currentSongID == song.id, let audioPlayer {
            if audioPlayer.isPlaying {
                audioPlayer.pause()
                isPlaying = false
                currentTime = audioPlayer.currentTime
                stopProgressUpdates()
            } else {
                guard audioPlayer.play() else {
                    throw AudioPlayerError.cannotStartPlayback
                }

                isPlaying = true
                startProgressUpdates()
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

            guard audioPlayer.play() else {
                throw AudioPlayerError.cannotStartPlayback
            }

            isPlaying = true
            startProgressUpdates()
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
            currentSongID = song.id
            isPlaying = true
            currentTime = player.currentTime
            duration = player.duration
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
    }

    func setVolume(_ newVolume: Float) {
        let clampedVolume = min(max(newVolume, 0), 1)
        volume = clampedVolume
        audioPlayer?.volume = clampedVolume
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentSongID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopProgressUpdates()
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        player.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopProgressUpdates()
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
}
