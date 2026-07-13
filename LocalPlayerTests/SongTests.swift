import Foundation
import MediaPlayer
import Testing

@testable import LocalPlayer

struct SongTests {
    @Test
    func storesImportedSongMetadata() {
        let song = Song(
            contentHash: "abc123",
            storageFileName: "abc123.mp3",
            title: "Test Song",
            artist: "Test Artist",
            durationSeconds: 180.0,
            artworkData: nil,
            importedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(song.contentHash == "abc123")
        #expect(song.storageFileName == "abc123.mp3")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.durationSeconds == 180.0)
        #expect(song.artworkData == nil)
    }

    @Test
    func rejectsFilesThatAreNotMP3() async {
        let importer = MP3ImportService()
        let textFileURL = URL(fileURLWithPath: "/not-a-song.txt")

        do {
            _ = try await importer.importMP3(
                from: textFileURL,
                existingContentHashes: Set<String>()
            )
            Issue.record("Expected the importer to reject a non-MP3 file.")
        } catch MP3ImportError.unsupportedFileType {
            // Expected outcome.
        } catch {
            Issue.record("Expected unsupportedFileType, got \(error).")
        }
    }

    @Test
    func removesOnlyTheStoredMP3Copy() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("stored-song.mp3")

        defer {
            try? fileManager.removeItem(at: directory)
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data([0x00]).write(to: fileURL)

        let importer = MP3ImportService(
            fileManager: fileManager,
            musicDirectoryURL: directory
        )

        try importer.removeStoredMP3(named: "stored-song.mp3")

        #expect(!fileManager.fileExists(atPath: fileURL.path))
    }

    @Test
    func rejectsPlaybackWhenStoredFileIsMissing() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let player = AudioPlayerService(musicDirectoryURL: directory)
            let song = Song(
                contentHash: "missing-song",
                storageFileName: "missing-song.mp3",
                title: "Missing Song",
                artist: "Test Artist",
                durationSeconds: 1,
                artworkData: nil,
                importedAt: .now
            )

            do {
                try player.togglePlayback(of: song)
                Issue.record("Expected playback to reject a missing MP3 file.")
            } catch AudioPlayerError.missingStoredFile {
                // Expected outcome.
            } catch {
                Issue.record("Expected missingStoredFile, got \(error).")
            }
        }
    }

    @Test
    func keepsPlaybackVolumeWithinTheSupportedRange() async {
        await MainActor.run {
            let player = AudioPlayerService()

            player.setVolume(1.5)
            #expect(player.volume == 1)

            player.setVolume(-0.25)
            #expect(player.volume == 0)
        }
    }

    @Test
    func findsOnlySongsThatExistNextToTheCurrentSong() async {
        await MainActor.run {
            let first = Self.makeSong(title: "First")
            let second = Self.makeSong(title: "Second")
            let songs = [first, second]

            #expect(
                AudioPlayerService.adjacentSong(
                    in: songs,
                    relativeTo: first.id,
                    offset: 1
                )?.id == second.id
            )
            #expect(
                AudioPlayerService.adjacentSong(
                    in: songs,
                    relativeTo: second.id,
                    offset: 1
                ) == nil
            )
            #expect(
                AudioPlayerService.adjacentSong(
                    in: songs,
                    relativeTo: first.id,
                    offset: 2
                ) == nil
            )
        }
    }

    @Test
    func mapsCurrentSongToNowPlayingMetadata() async {
        await MainActor.run {
            let song = Self.makeSong(title: "Now Playing")
            let nowPlayingInfo = AudioPlayerService.nowPlayingInfo(
                for: song,
                elapsedTime: 30,
                duration: 120,
                isPlaying: true
            )

            #expect(nowPlayingInfo[MPMediaItemPropertyTitle] as? String == "Now Playing")
            #expect(nowPlayingInfo[MPMediaItemPropertyArtist] as? String == "Test Artist")
            #expect(nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] as? Double == 120)
            #expect(nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 30)
            #expect(nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        }
    }

    private static func makeSong(title: String) -> Song {
        Song(
            contentHash: UUID().uuidString,
            storageFileName: "test.mp3",
            title: title,
            artist: "Test Artist",
            durationSeconds: 1,
            artworkData: nil,
            importedAt: .now
        )
    }
}
