import Foundation
import MediaPlayer
import Testing
import UIKit

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
        #expect(song.categoryName == nil)
    }

    @Test
    func renamesSongWithTrimmedTitleAndRejectsBlankTitle() {
        let song = Self.makeSong(title: "Original")

        #expect(song.rename(to: "  Renamed Song  "))
        #expect(song.title == "Renamed Song")

        #expect(!song.rename(to: "   "))
        #expect(song.title == "Renamed Song")
    }

    @Test
    func movesSongToAnExistingCategoryWithoutCreatingCaseVariant() {
        let song = Self.makeSong(title: "Song")

        song.move(toCategory: "  rock  ", existingCategoryNames: ["Rock"])
        #expect(song.categoryName == "Rock")

        song.move(toCategory: nil, existingCategoryNames: ["Rock"])
        #expect(song.categoryName == nil)
    }

    @Test
    func listsUniqueNormalizedCategoryNames() {
        let rock = Self.makeSong(title: "Rock")
        rock.categoryName = "Rock"
        let duplicateRock = Self.makeSong(title: "Duplicate rock")
        duplicateRock.categoryName = " rock "
        let jazz = Self.makeSong(title: "Jazz")
        jazz.categoryName = "Jazz"

        #expect(Song.categoryNames(in: [rock, duplicateRock, jazz]) == ["Jazz", "Rock"])
    }

    @Test
    func renamesAndRemovesCategoriesForMatchingSongs() {
        let first = Self.makeSong(title: "First")
        first.categoryName = "Rock"
        let second = Self.makeSong(title: "Second")
        second.categoryName = "rock"
        let unaffected = Self.makeSong(title: "Unaffected")
        unaffected.categoryName = "Jazz"

        let renamedCategory = Song.renameCategory(
            named: "ROCK",
            to: "  Indie  ",
            in: [first, second, unaffected]
        )

        #expect(renamedCategory == "Indie")
        #expect(first.categoryName == "Indie")
        #expect(second.categoryName == "Indie")
        #expect(unaffected.categoryName == "Jazz")

        #expect(Song.removeCategory(named: "indie", from: [first, second, unaffected]))
        #expect(first.categoryName == nil)
        #expect(second.categoryName == nil)
        #expect(unaffected.categoryName == "Jazz")
    }

    @Test
    func movesSongsIntoCanonicalTwoLevelCategories() {
        let song = Self.makeSong(title: "First")
        let existingSong = Self.makeSong(title: "Existing")
        existingSong.categoryName = "日语音乐"
        existingSong.subcategoryName = "动画歌曲"

        song.move(
            toCategory: "  日语音乐  ",
            subcategory: "  动画歌曲  ",
            existingCategoryPaths: Song.categoryPaths(in: [existingSong])
        )

        #expect(song.categoryName == "日语音乐")
        #expect(song.subcategoryName == "动画歌曲")
    }

    @Test
    func deletesSubcategoryBackToItsParentWithoutAffectingOtherPaths() {
        let animeSong = Self.makeSong(title: "Anime")
        animeSong.categoryName = "日语音乐"
        animeSong.subcategoryName = "动画歌曲"
        let gameSong = Self.makeSong(title: "Game")
        gameSong.categoryName = "日语音乐"
        gameSong.subcategoryName = "游戏原声"

        #expect(
            Song.removeSubcategory(
                named: "动画歌曲",
                fromCategory: "日语音乐",
                in: [animeSong, gameSong]
            )
        )
        #expect(animeSong.categoryName == "日语音乐")
        #expect(animeSong.subcategoryName == nil)
        #expect(gameSong.subcategoryName == "游戏原声")
    }

    @Test
    func removesChildrenWhenRemovingTheirParentCategory() {
        let song = Self.makeSong(title: "Anime")
        song.categoryName = "日语音乐"
        song.subcategoryName = "动画歌曲"

        #expect(Song.removeCategory(named: "日语音乐", from: [song]))
        #expect(song.categoryName == nil)
        #expect(song.subcategoryName == nil)
    }

    @Test
    func renamesSubcategoryOnlyWithinItsParentCategory() {
        let japaneseSong = Self.makeSong(title: "Japanese")
        japaneseSong.categoryName = "日语音乐"
        japaneseSong.subcategoryName = "原声"
        let gameSong = Self.makeSong(title: "Game")
        gameSong.categoryName = "游戏音乐"
        gameSong.subcategoryName = "原声"

        let renamedSubcategory = Song.renameSubcategory(
            named: "原声",
            fromCategory: "日语音乐",
            to: "动画原声",
            in: [japaneseSong, gameSong]
        )

        #expect(renamedSubcategory == "动画原声")
        #expect(japaneseSong.subcategoryName == "动画原声")
        #expect(gameSong.subcategoryName == "原声")
    }

    @Test
    func replacesAndRemovesArtworkWithoutAcceptingInvalidImageData() {
        let song = Self.makeSong(title: "Artwork")
        let validArtworkData = Self.makeArtworkData()

        #expect(song.replaceArtwork(with: validArtworkData))
        #expect(song.artworkData == validArtworkData)

        #expect(!song.replaceArtwork(with: Data("not-an-image".utf8)))
        #expect(song.artworkData == validArtworkData)

        song.removeArtwork()
        #expect(song.artworkData == nil)
    }

    @Test
    func appliesBatchEditToOnlyTheSelectedSongsAndCanRestoreThem() {
        let first = Self.makeSong(title: "First")
        first.categoryName = "旧分类"
        let firstArtwork = Self.makeArtworkData()
        first.artworkData = firstArtwork
        let second = Self.makeSong(title: "Second")
        let untouched = Self.makeSong(title: "Untouched")
        untouched.categoryName = "保留分类"
        let untouchedArtwork = Self.makeArtworkData()
        untouched.artworkData = untouchedArtwork
        let replacementArtwork = Self.makeArtworkData()
        let request = BatchSongEditRequest(
            categoryChange: .move(
                categoryName: "  日语音乐  ",
                subcategoryName: "  动画歌曲  "
            ),
            artworkChange: .replace(replacementArtwork)
        )

        let snapshot: BatchSongEditSnapshot

        do {
            snapshot = try request.apply(
                to: [first, second],
                existingCategoryPaths: Song.categoryPaths(in: [untouched])
            )
        } catch {
            Issue.record("Expected the batch edit to apply, got \(error).")
            return
        }

        #expect(first.categoryName == "日语音乐")
        #expect(first.subcategoryName == "动画歌曲")
        #expect(first.artworkData == replacementArtwork)
        #expect(second.categoryName == "日语音乐")
        #expect(second.subcategoryName == "动画歌曲")
        #expect(second.artworkData == replacementArtwork)
        #expect(untouched.categoryName == "保留分类")
        #expect(untouched.artworkData == untouchedArtwork)

        snapshot.restore()

        #expect(first.categoryName == "旧分类")
        #expect(first.subcategoryName == nil)
        #expect(first.artworkData == firstArtwork)
        #expect(second.categoryName == nil)
        #expect(second.subcategoryName == nil)
        #expect(second.artworkData == nil)
    }

    @Test
    func clearsSelectedCategoryAndArtworkWithoutChangingUnrequestedFields() {
        let song = Self.makeSong(title: "Selected")
        song.categoryName = "日语音乐"
        song.subcategoryName = "动画歌曲"
        song.artworkData = Self.makeArtworkData()
        let request = BatchSongEditRequest(
            categoryChange: .move(categoryName: nil, subcategoryName: nil),
            artworkChange: .remove
        )

        do {
            _ = try request.apply(
                to: [song],
                existingCategoryPaths: Song.categoryPaths(in: [song])
            )
        } catch {
            Issue.record("Expected the batch edit to apply, got \(error).")
            return
        }

        #expect(song.categoryName == nil)
        #expect(song.subcategoryName == nil)
        #expect(song.artworkData == nil)
    }

    @Test
    func rejectsInvalidBatchArtworkWithoutMutatingAnySelectedSong() {
        let song = Self.makeSong(title: "Selected")
        song.categoryName = "原分类"
        let originalArtwork = Self.makeArtworkData()
        song.artworkData = originalArtwork
        let request = BatchSongEditRequest(
            categoryChange: .move(categoryName: "新分类", subcategoryName: nil),
            artworkChange: .replace(Data("not-an-image".utf8))
        )

        do {
            _ = try request.apply(
                to: [song],
                existingCategoryPaths: Song.categoryPaths(in: [song])
            )
            Issue.record("Expected an invalid artwork error.")
        } catch BatchSongEditError.invalidArtwork {
            // Expected outcome.
        } catch {
            Issue.record("Expected invalidArtwork, got \(error).")
        }

        #expect(song.categoryName == "原分类")
        #expect(song.subcategoryName == nil)
        #expect(song.artworkData == originalArtwork)
    }

    @Test
    func identifiesBatchEditsThatRequireNowPlayingArtworkRefresh() {
        let unchangedRequest = BatchSongEditRequest(
            categoryChange: .move(categoryName: "日语音乐", subcategoryName: nil),
            artworkChange: .unchanged
        )
        let replacementRequest = BatchSongEditRequest(
            categoryChange: .unchanged,
            artworkChange: .replace(Self.makeArtworkData())
        )
        let removalRequest = BatchSongEditRequest(
            categoryChange: .unchanged,
            artworkChange: .remove
        )

        #expect(!unchangedRequest.changesArtwork)
        #expect(replacementRequest.changesArtwork)
        #expect(removalRequest.changesArtwork)
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
    func continuesToTheNextQueuedSongOnlyAfterSuccessfulCompletion() async {
        await MainActor.run {
            let first = Self.makeSong(title: "First")
            let second = Self.makeSong(title: "Second")
            let songs = [first, second]

            #expect(
                AudioPlayerService.songForAutomaticContinuation(
                    in: songs,
                    after: first.id,
                    finishedSuccessfully: true
                )?.id == second.id
            )
            #expect(
                AudioPlayerService.songForAutomaticContinuation(
                    in: songs,
                    after: second.id,
                    finishedSuccessfully: true
                ) == nil
            )
            #expect(
                AudioPlayerService.songForAutomaticContinuation(
                    in: songs,
                    after: first.id,
                    finishedSuccessfully: false
                ) == nil
            )
        }
    }

    @Test
    func stopsAtTheEndInSequentialMode() {
        let first = Self.makeSong(title: "First")
        let second = Self.makeSong(title: "Second")

        #expect(
            AudioPlayerService.nextSong(
                in: [first, second],
                relativeTo: first.id,
                mode: .sequential,
                reason: .manual
            )?.id == second.id
        )
        #expect(
            AudioPlayerService.nextSong(
                in: [first, second],
                relativeTo: second.id,
                mode: .sequential,
                reason: .automatic
            ) == nil
        )
    }

    @Test
    func wrapsToTheFirstSongInRepeatAllMode() {
        let first = Self.makeSong(title: "First")
        let second = Self.makeSong(title: "Second")

        #expect(
            AudioPlayerService.nextSong(
                in: [first, second],
                relativeTo: second.id,
                mode: .repeatAll,
                reason: .automatic
            )?.id == first.id
        )
    }

    @Test
    func repeatsOnlyAfterAutomaticCompletionInRepeatOneMode() {
        let first = Self.makeSong(title: "First")
        let second = Self.makeSong(title: "Second")

        #expect(
            AudioPlayerService.nextSong(
                in: [first, second],
                relativeTo: first.id,
                mode: .repeatOne,
                reason: .automatic
            )?.id == first.id
        )
        #expect(
            AudioPlayerService.nextSong(
                in: [first, second],
                relativeTo: first.id,
                mode: .repeatOne,
                reason: .manual
            )?.id == second.id
        )
    }

    @Test
    func choosesAnotherSongInShuffleModeAndStopsForOneSong() {
        let first = Self.makeSong(title: "First")
        let second = Self.makeSong(title: "Second")
        let third = Self.makeSong(title: "Third")

        let shuffledSong = AudioPlayerService.nextSong(
            in: [first, second, third],
            relativeTo: first.id,
            mode: .shuffle,
            reason: .manual,
            randomIndex: { _ in 1 }
        )

        #expect(shuffledSong?.id == third.id)
        #expect(shuffledSong?.id != first.id)
        #expect(
            AudioPlayerService.nextSong(
                in: [first],
                relativeTo: first.id,
                mode: .shuffle,
                reason: .automatic,
                randomIndex: { _ in 0 }
            ) == nil
        )
    }

    @Test
    func persistsTheSelectedPlaybackMode() async {
        let suiteName = "LocalPlayerTests.PlaybackMode.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Expected an isolated UserDefaults suite.")
            return
        }

        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        await MainActor.run {
            let player = AudioPlayerService(userDefaults: defaults)
            #expect(player.playbackMode == .sequential)

            player.setPlaybackMode(.repeatAll)

            let restoredPlayer = AudioPlayerService(userDefaults: defaults)
            #expect(restoredPlayer.playbackMode == .repeatAll)
        }
    }

    @Test
    func reportsTrackCommandAvailabilityFromThePlaybackQueue() async {
        await MainActor.run {
            let first = Self.makeSong(title: "First")
            let second = Self.makeSong(title: "Second")
            let songs = [first, second]

            let firstAvailability = AudioPlayerService.trackCommandAvailability(
                in: songs,
                relativeTo: first.id
            )
            let secondAvailability = AudioPlayerService.trackCommandAvailability(
                in: songs,
                relativeTo: second.id
            )

            #expect(!firstAvailability.previous)
            #expect(firstAvailability.next)
            #expect(secondAvailability.previous)
            #expect(!secondAvailability.next)
        }
    }

    @Test
    func reportsNextCommandAvailabilityForEachPlaybackMode() {
        let first = Self.makeSong(title: "First")
        let second = Self.makeSong(title: "Second")

        let repeatAllAvailability = AudioPlayerService.trackCommandAvailability(
            in: [first, second],
            relativeTo: second.id,
            mode: .repeatAll
        )
        let repeatOneAvailability = AudioPlayerService.trackCommandAvailability(
            in: [first, second],
            relativeTo: second.id,
            mode: .repeatOne
        )
        let singleShuffleAvailability = AudioPlayerService.trackCommandAvailability(
            in: [first],
            relativeTo: first.id,
            mode: .shuffle
        )

        #expect(repeatAllAvailability.next)
        #expect(!repeatOneAvailability.next)
        #expect(!singleShuffleAvailability.next)
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

    private static func makeArtworkData() -> Data {
        let size = CGSize(width: 2, height: 2)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.pngData { context in
            context.cgContext.setFillColor(UIColor.systemBlue.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }
}
