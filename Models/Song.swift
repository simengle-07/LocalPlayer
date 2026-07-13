import Foundation
import SwiftData

@Model
final class Song {
    var id: UUID

    @Attribute(.unique)
    var contentHash: String

    var storageFileName: String
    var title: String
    var artist: String
    var durationSeconds: Double
    var artworkData: Data?
    var importedAt: Date
    var categoryName: String?

    init(
        contentHash: String,
        storageFileName: String,
        title: String,
        artist: String,
        durationSeconds: Double,
        artworkData: Data?,
        importedAt: Date,
        categoryName: String? = nil
    ) {
        self.id = UUID()
        self.contentHash = contentHash
        self.storageFileName = storageFileName
        self.title = title
        self.artist = artist
        self.durationSeconds = durationSeconds
        self.artworkData = artworkData
        self.importedAt = importedAt
        self.categoryName = Self.normalizedCategoryName(from: categoryName)
    }

    @discardableResult
    func rename(to rawTitle: String) -> Bool {
        guard let normalizedTitle = Self.normalizedTitle(from: rawTitle) else {
            return false
        }

        title = normalizedTitle
        return true
    }

    func move(
        toCategory rawCategoryName: String?,
        existingCategoryNames: [String]
    ) {
        categoryName = Self.resolvedCategoryName(
            from: rawCategoryName,
            existingCategoryNames: existingCategoryNames
        )
    }

    static func normalizedTitle(from rawTitle: String) -> String? {
        normalizedText(from: rawTitle)
    }

    static func normalizedCategoryName(from rawCategoryName: String?) -> String? {
        guard let rawCategoryName else {
            return nil
        }

        return normalizedText(from: rawCategoryName)
    }

    static func categoryNames(in songs: [Song]) -> [String] {
        var canonicalNames = [String: String]()

        for song in songs {
            guard let categoryName = normalizedCategoryName(from: song.categoryName) else {
                continue
            }

            let key = categoryName.folding(
                options: [.caseInsensitive],
                locale: .current
            )

            if canonicalNames[key] == nil {
                canonicalNames[key] = categoryName
            }
        }

        return canonicalNames.values.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func resolvedCategoryName(
        from rawCategoryName: String?,
        existingCategoryNames: [String]
    ) -> String? {
        guard let normalizedName = normalizedCategoryName(
            from: rawCategoryName
        ) else {
            return nil
        }

        return existingCategoryNames.first {
            hasSameCategoryName($0, normalizedName)
        } ?? normalizedName
    }

    static func renameCategory(
        named rawExistingCategoryName: String,
        to rawNewCategoryName: String,
        in songs: [Song]
    ) -> String? {
        guard let existingCategoryName = normalizedCategoryName(
            from: rawExistingCategoryName
        ), let newCategoryName = normalizedCategoryName(from: rawNewCategoryName) else {
            return nil
        }

        let matchingSongs = songs.filter {
            guard let songCategoryName = $0.categoryName else {
                return false
            }

            return hasSameCategoryName(songCategoryName, existingCategoryName)
        }

        guard !matchingSongs.isEmpty else {
            return nil
        }

        let otherCategoryNames = categoryNames(in: songs).filter {
            !hasSameCategoryName($0, existingCategoryName)
        }
        let resolvedNewCategoryName = resolvedCategoryName(
            from: newCategoryName,
            existingCategoryNames: otherCategoryNames
        ) ?? newCategoryName

        for song in matchingSongs {
            song.categoryName = resolvedNewCategoryName
        }

        return resolvedNewCategoryName
    }

    @discardableResult
    static func removeCategory(named rawCategoryName: String, from songs: [Song]) -> Bool {
        guard let categoryName = normalizedCategoryName(from: rawCategoryName) else {
            return false
        }

        var didRemoveCategory = false

        for song in songs where hasSameCategoryName(song.categoryName, categoryName) {
            song.categoryName = nil
            didRemoveCategory = true
        }

        return didRemoveCategory
    }

    static func hasSameCategoryName(_ lhs: String?, _ rhs: String) -> Bool {
        guard let normalizedLeft = normalizedCategoryName(from: lhs),
              let normalizedRight = normalizedCategoryName(from: rhs) else {
            return false
        }

        return normalizedLeft.caseInsensitiveCompare(normalizedRight) == .orderedSame
    }

    private static func normalizedText(from rawText: String) -> String? {
        let normalizedText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedText.isEmpty ? nil : normalizedText
    }
}
