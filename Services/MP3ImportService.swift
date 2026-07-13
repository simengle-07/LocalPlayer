import AVFoundation
import CryptoKit
import Foundation

enum MP3ImportError: LocalizedError {
    case unsupportedFileType
    case cannotAccessFile
    case duplicateFile
    case invalidAudioFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFileType:
            return "只能导入 MP3 文件。"
        case .cannotAccessFile:
            return "无法读取所选文件。"
        case .duplicateFile:
            return "这首音乐已经在资料库中。"
        case .invalidAudioFile:
            return "所选文件不是可播放的 MP3 音频。"
        }
    }
}

struct MP3ImportService {
    private let fileManager: FileManager
    private let musicDirectoryURL: URL?

    init(
        fileManager: FileManager = .default,
        musicDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.musicDirectoryURL = musicDirectoryURL
    }

    func importMP3(
        from sourceURL: URL,
        existingContentHashes: Set<String>
    ) async throws -> Song {
        guard sourceURL.pathExtension.lowercased() == "mp3" else {
            throw MP3ImportError.unsupportedFileType
        }

        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw MP3ImportError.cannotAccessFile
        }

        defer {
            sourceURL.stopAccessingSecurityScopedResource()
        }

        let contentHash = try sha256(of: sourceURL)

        guard !existingContentHashes.contains(contentHash) else {
            throw MP3ImportError.duplicateFile
        }

        let metadata: SongMetadata
        do {
            metadata = try await readMetadata(from: sourceURL)
        } catch {
            throw MP3ImportError.invalidAudioFile
        }

        let directory = try musicDirectory()
        let storageFileName = "\(contentHash).mp3"
        let destinationURL = directory.appendingPathComponent(storageFileName)

        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            throw MP3ImportError.duplicateFile
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return Song(
            contentHash: contentHash,
            storageFileName: storageFileName,
            title: metadata.title,
            artist: metadata.artist,
            durationSeconds: metadata.durationSeconds,
            artworkData: metadata.artworkData,
            importedAt: Date()
        )
    }

    func removeStoredMP3(named storageFileName: String) throws {
        guard storageFileName == URL(fileURLWithPath: storageFileName).lastPathComponent,
              URL(fileURLWithPath: storageFileName).pathExtension.lowercased() == "mp3"
        else {
            return
        }

        let directory = try musicDirectory()
        let fileURL = directory.appendingPathComponent(storageFileName)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func musicDirectory() throws -> URL {
        let directory = musicDirectoryURL ?? URL.documentsDirectory
            .appendingPathComponent("Music", isDirectory: true)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()

        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()

            guard !data.isEmpty else {
                break
            }

            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func readMetadata(from fileURL: URL) async throws -> SongMetadata {
        let asset = AVURLAsset(url: fileURL)
        let (duration, commonMetadata) = try await asset.load(
            .duration,
            .commonMetadata
        )
        let durationSeconds = CMTimeGetSeconds(duration)

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw MP3ImportError.invalidAudioFile
        }

        let title = normalizedText(
            try? await stringValue(for: .commonKeyTitle, in: commonMetadata)
        ) ?? fileURL.deletingPathExtension().lastPathComponent

        let artist = normalizedText(
            try? await stringValue(for: .commonKeyArtist, in: commonMetadata)
        ) ?? "未知歌手"

        let artworkData = try? await dataValue(
            for: .commonKeyArtwork,
            in: commonMetadata
        )

        return SongMetadata(
            title: title,
            artist: artist,
            durationSeconds: durationSeconds,
            artworkData: artworkData
        )
    }

    private func stringValue(
        for key: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) async throws -> String? {
        guard let item = metadata.first(where: { $0.commonKey == key }) else {
            return nil
        }

        return try await item.load(.stringValue)
    }

    private func dataValue(
        for key: AVMetadataKey,
        in metadata: [AVMetadataItem]
    ) async throws -> Data? {
        guard let item = metadata.first(where: { $0.commonKey == key }) else {
            return nil
        }

        return try await item.load(.dataValue)
    }

    private func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct SongMetadata {
    let title: String
    let artist: String
    let durationSeconds: Double
    let artworkData: Data?
}
