import Foundation

enum BatchCategoryChange {
    case unchanged
    case move(categoryName: String?, subcategoryName: String?)
}

enum BatchArtworkChange {
    case unchanged
    case replace(Data)
    case remove
}

enum BatchSongEditError: LocalizedError {
    case invalidArtwork

    var errorDescription: String? {
        switch self {
        case .invalidArtwork:
            return "所选封面不是可用的图片。"
        }
    }
}

struct BatchSongEditSnapshot {
    private struct Entry {
        let song: Song
        let categoryName: String?
        let subcategoryName: String?
        let artworkData: Data?
    }

    private let entries: [Entry]

    init(songs: [Song]) {
        entries = songs.map {
            Entry(
                song: $0,
                categoryName: $0.categoryName,
                subcategoryName: $0.subcategoryName,
                artworkData: $0.artworkData
            )
        }
    }

    func restore() {
        for entry in entries {
            entry.song.categoryName = entry.categoryName
            entry.song.subcategoryName = entry.subcategoryName
            entry.song.artworkData = entry.artworkData
        }
    }
}

struct BatchSongEditRequest {
    let categoryChange: BatchCategoryChange
    let artworkChange: BatchArtworkChange

    var changesArtwork: Bool {
        switch artworkChange {
        case .unchanged:
            return false
        case .replace, .remove:
            return true
        }
    }

    func apply(
        to songs: [Song],
        existingCategoryPaths: [SongCategoryPath]
    ) throws -> BatchSongEditSnapshot {
        if case .replace(let artworkData) = artworkChange,
           !Song.isValidArtworkData(artworkData) {
            throw BatchSongEditError.invalidArtwork
        }

        let snapshot = BatchSongEditSnapshot(songs: songs)

        for song in songs {
            switch categoryChange {
            case .unchanged:
                break
            case let .move(categoryName, subcategoryName):
                song.move(
                    toCategory: categoryName,
                    subcategory: subcategoryName,
                    existingCategoryPaths: existingCategoryPaths
                )
            }

            switch artworkChange {
            case .unchanged:
                break
            case let .replace(artworkData):
                guard song.replaceArtwork(with: artworkData) else {
                    snapshot.restore()
                    throw BatchSongEditError.invalidArtwork
                }
            case .remove:
                song.removeArtwork()
            }
        }

        return snapshot
    }
}
