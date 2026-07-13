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

    private let fileManager: FileManager
    private let musicDirectoryURL: URL?
    private var audioPlayer: AVAudioPlayer?

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
            } else {
                guard audioPlayer.play() else {
                    throw AudioPlayerError.cannotStartPlayback
                }

                isPlaying = true
            }

            return
        }

        let fileURL = try storedFileURL(for: song)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)

            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self

            guard player.play() else {
                throw AudioPlayerError.cannotStartPlayback
            }

            audioPlayer = player
            currentSongID = song.id
            isPlaying = true
        } catch let error as AudioPlayerError {
            throw error
        } catch {
            throw AudioPlayerError.cannotStartPlayback
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        currentSongID = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        player.currentTime = 0
        isPlaying = false
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
}
