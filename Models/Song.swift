import Foundation
import SwiftData
import UIKit

struct SongCategoryPath: Hashable {
    let categoryName: String
    let subcategoryName: String?

    var displayName: String {
        guard let subcategoryName else {
            return categoryName
        }

        return "\(categoryName) / \(subcategoryName)"
    }
}

enum LocalPlayerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [Song.self]
    }

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
        var subcategoryName: String?

        init(
            contentHash: String,
            storageFileName: String,
            title: String,
            artist: String,
            durationSeconds: Double,
            artworkData: Data?,
            importedAt: Date,
            categoryName: String? = nil,
            subcategoryName: String? = nil
        ) {
            self.id = UUID()
            self.contentHash = contentHash
            self.storageFileName = storageFileName
            self.title = title
            self.artist = artist
            self.durationSeconds = durationSeconds
            self.artworkData = artworkData
            self.importedAt = importedAt

            let path = Self.resolvedCategoryPath(
                categoryName: categoryName,
                subcategoryName: subcategoryName,
                existingCategoryPaths: []
            )
            self.categoryName = path?.categoryName
            self.subcategoryName = path?.subcategoryName
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
            subcategory rawSubcategoryName: String?,
            existingCategoryPaths: [SongCategoryPath]
        ) {
            let path = Self.resolvedCategoryPath(
                categoryName: rawCategoryName,
                subcategoryName: rawSubcategoryName,
                existingCategoryPaths: existingCategoryPaths
            )
            categoryName = path?.categoryName
            subcategoryName = path?.subcategoryName
        }

        func move(
            toCategory rawCategoryName: String?,
            existingCategoryNames: [String]
        ) {
            categoryName = Self.resolvedCategoryName(
                from: rawCategoryName,
                existingCategoryNames: existingCategoryNames
            )
            subcategoryName = nil
        }

        @discardableResult
        func replaceArtwork(with newArtworkData: Data) -> Bool {
            guard Self.isValidArtworkData(newArtworkData) else {
                return false
            }

            artworkData = newArtworkData
            return true
        }

        func removeArtwork() {
            artworkData = nil
        }

        static func normalizedTitle(from rawTitle: String) -> String? {
            normalizedText(from: rawTitle)
        }

        static func isValidArtworkData(_ artworkData: Data) -> Bool {
            UIImage(data: artworkData) != nil
        }

        static func normalizedCategoryName(from rawCategoryName: String?) -> String? {
            guard let rawCategoryName else {
                return nil
            }

            return normalizedText(from: rawCategoryName)
        }

        static func categoryNames(in songs: [Song]) -> [String] {
            var canonicalNames = [String: String]()

            for path in categoryPaths(in: songs) {
                let key = comparisonKey(path.categoryName)

                if canonicalNames[key] == nil {
                    canonicalNames[key] = path.categoryName
                }
            }

            return canonicalNames.values.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }

        static func categoryPaths(in songs: [Song]) -> [SongCategoryPath] {
            var canonicalPaths = [String: SongCategoryPath]()

            for song in songs {
                guard let categoryName = normalizedCategoryName(from: song.categoryName) else {
                    continue
                }

                let subcategoryName = normalizedCategoryName(
                    from: song.subcategoryName
                )
                let path = SongCategoryPath(
                    categoryName: categoryName,
                    subcategoryName: subcategoryName
                )
                let key = categoryPathKey(for: path)

                if canonicalPaths[key] == nil {
                    canonicalPaths[key] = path
                }
            }

            return canonicalPaths.values.sorted { lhs, rhs in
                let primaryOrder = lhs.categoryName.localizedStandardCompare(rhs.categoryName)

                if primaryOrder != .orderedSame {
                    return primaryOrder == .orderedAscending
                }

                switch (lhs.subcategoryName, rhs.subcategoryName) {
                case (nil, nil):
                    return false
                case (nil, _):
                    return true
                case (_, nil):
                    return false
                case let (lhsSubcategoryName?, rhsSubcategoryName?):
                    return lhsSubcategoryName.localizedStandardCompare(rhsSubcategoryName)
                        == .orderedAscending
                }
            }
        }

        static func subcategoryNames(
            for rawCategoryName: String?,
            in categoryPaths: [SongCategoryPath]
        ) -> [String] {
            guard let categoryName = normalizedCategoryName(from: rawCategoryName) else {
                return []
            }

            var canonicalNames = [String: String]()

            for path in categoryPaths where hasSameCategoryName(
                path.categoryName,
                categoryName
            ) {
                guard let subcategoryName = path.subcategoryName else {
                    continue
                }

                let key = comparisonKey(subcategoryName)

                if canonicalNames[key] == nil {
                    canonicalNames[key] = subcategoryName
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
                hasSameCategoryName($0.categoryName, existingCategoryName)
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

        static func renameSubcategory(
            named rawExistingSubcategoryName: String,
            fromCategory rawCategoryName: String,
            to rawNewSubcategoryName: String,
            in songs: [Song]
        ) -> String? {
            guard let categoryName = normalizedCategoryName(from: rawCategoryName),
                  let existingSubcategoryName = normalizedCategoryName(
                    from: rawExistingSubcategoryName
                  ),
                  let newSubcategoryName = normalizedCategoryName(
                    from: rawNewSubcategoryName
                  ) else {
                return nil
            }

            let matchingSongs = songs.filter {
                hasSameCategoryPath(
                    categoryName: $0.categoryName,
                    subcategoryName: $0.subcategoryName,
                    categoryName,
                    existingSubcategoryName
                )
            }

            guard !matchingSongs.isEmpty else {
                return nil
            }

            let otherSubcategoryNames = subcategoryNames(
                for: categoryName,
                in: categoryPaths(in: songs)
            ).filter {
                !hasSameCategoryName($0, existingSubcategoryName)
            }
            let resolvedNewSubcategoryName = resolvedCategoryName(
                from: newSubcategoryName,
                existingCategoryNames: otherSubcategoryNames
            ) ?? newSubcategoryName

            for song in matchingSongs {
                song.subcategoryName = resolvedNewSubcategoryName
            }

            return resolvedNewSubcategoryName
        }

        @discardableResult
        static func removeCategory(named rawCategoryName: String, from songs: [Song]) -> Bool {
            guard let categoryName = normalizedCategoryName(from: rawCategoryName) else {
                return false
            }

            var didRemoveCategory = false

            for song in songs where hasSameCategoryName(song.categoryName, categoryName) {
                song.categoryName = nil
                song.subcategoryName = nil
                didRemoveCategory = true
            }

            return didRemoveCategory
        }

        @discardableResult
        static func removeSubcategory(
            named rawSubcategoryName: String,
            fromCategory rawCategoryName: String,
            in songs: [Song]
        ) -> Bool {
            guard let categoryName = normalizedCategoryName(from: rawCategoryName),
                  let subcategoryName = normalizedCategoryName(
                    from: rawSubcategoryName
                  ) else {
                return false
            }

            var didRemoveSubcategory = false

            for song in songs where hasSameCategoryPath(
                categoryName: song.categoryName,
                subcategoryName: song.subcategoryName,
                categoryName,
                subcategoryName
            ) {
                song.subcategoryName = nil
                didRemoveSubcategory = true
            }

            return didRemoveSubcategory
        }

        static func hasSameCategoryName(_ lhs: String?, _ rhs: String) -> Bool {
            guard let normalizedLeft = normalizedCategoryName(from: lhs),
                  let normalizedRight = normalizedCategoryName(from: rhs) else {
                return false
            }

            return normalizedLeft.caseInsensitiveCompare(normalizedRight) == .orderedSame
        }

        static func hasSameOptionalCategoryName(
            _ lhs: String?,
            _ rhs: String?
        ) -> Bool {
            switch (
                normalizedCategoryName(from: lhs),
                normalizedCategoryName(from: rhs)
            ) {
            case (nil, nil):
                return true
            case let (left?, right?):
                return left.caseInsensitiveCompare(right) == .orderedSame
            default:
                return false
            }
        }

        static func hasSameCategoryPath(
            categoryName lhsCategoryName: String?,
            subcategoryName lhsSubcategoryName: String?,
            _ rhsCategoryName: String,
            _ rhsSubcategoryName: String
        ) -> Bool {
            hasSameCategoryName(lhsCategoryName, rhsCategoryName)
                && hasSameCategoryName(lhsSubcategoryName, rhsSubcategoryName)
        }

        private static func resolvedCategoryPath(
            categoryName rawCategoryName: String?,
            subcategoryName rawSubcategoryName: String?,
            existingCategoryPaths: [SongCategoryPath]
        ) -> SongCategoryPath? {
            guard let normalizedCategoryName = Self.normalizedCategoryName(
                from: rawCategoryName
            ) else {
                return nil
            }

            let resolvedCategoryName = existingCategoryPaths.first {
                hasSameCategoryName($0.categoryName, normalizedCategoryName)
            }?.categoryName ?? normalizedCategoryName

            guard let normalizedSubcategoryName = Self.normalizedCategoryName(
                from: rawSubcategoryName
            ) else {
                return SongCategoryPath(
                    categoryName: resolvedCategoryName,
                    subcategoryName: nil
                )
            }

            let resolvedSubcategoryName = existingCategoryPaths.first {
                hasSameCategoryPath(
                    categoryName: $0.categoryName,
                    subcategoryName: $0.subcategoryName,
                    resolvedCategoryName,
                    normalizedSubcategoryName
                )
            }?.subcategoryName ?? normalizedSubcategoryName

            return SongCategoryPath(
                categoryName: resolvedCategoryName,
                subcategoryName: resolvedSubcategoryName
            )
        }

        private static func categoryPathKey(for path: SongCategoryPath) -> String {
            let subcategoryKey = path.subcategoryName.map {
                comparisonKey($0)
            } ?? ""
            return "\(comparisonKey(path.categoryName))\u{1F}\(subcategoryKey)"
        }

        private static func comparisonKey(_ categoryName: String) -> String {
            categoryName.folding(options: [.caseInsensitive], locale: .current)
        }

        private static func normalizedText(from rawText: String) -> String? {
            let normalizedText = rawText.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return normalizedText.isEmpty ? nil : normalizedText
        }
    }
}

typealias Song = LocalPlayerSchemaV2.Song
