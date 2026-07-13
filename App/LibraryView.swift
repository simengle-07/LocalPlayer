import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @Query(sort: \Song.title, order: .forward)
    private var songs: [Song]

    @State private var isShowingImporter = false
    @State private var isShowingNowPlaying = false
    @State private var isImporting = false
    @State private var operationErrorMessage: String?

    private let importer = MP3ImportService()

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView(
                        "还没有音乐",
                        systemImage: "music.note.list",
                        description: Text("从“文件”中导入 MP3，建立你的本地音乐资料库。")
                    )
                } else {
                    List {
                        ForEach(songs, id: \.id) { song in
                            Button {
                                togglePlayback(of: song)
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkThumbnail(artworkData: song.artworkData)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(song.title)
                                            .lineLimit(1)

                                        Text(song.artist)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(formattedDuration(song.durationSeconds))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)

                                    let isCurrentSong = audioPlayer.currentSongID == song.id

                                    Image(
                                        systemName: isCurrentSong && audioPlayer.isPlaying
                                            ? "speaker.wave.2.fill"
                                            : "play.fill"
                                    )
                                    .foregroundStyle(
                                        isCurrentSong ? Color.accentColor : Color.secondary
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(
                                audioPlayer.currentSongID == song.id && audioPlayer.isPlaying
                                    ? "暂停播放"
                                    : "播放歌曲"
                            )
                        }
                        .onDelete(perform: deleteSongs)
                    }
                }
            }
            .navigationTitle("本地音乐")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isImporting {
                        ProgressView()
                            .accessibilityLabel("正在导入音乐")
                    } else {
                        Button("导入 MP3", systemImage: "plus") {
                            isShowingImporter = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let currentSong {
                MiniPlayerBar(
                    song: currentSong,
                    songs: songs,
                    operationErrorMessage: $operationErrorMessage,
                    onOpenPlayer: {
                        isShowingNowPlaying = true
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView(
                songs: songs,
                operationErrorMessage: $operationErrorMessage
            )
            .environmentObject(audioPlayer)
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.mp3],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { @MainActor in
                    await importFiles(urls)
                }
            case .failure(let error):
                operationErrorMessage = "无法打开文件选择器：\(error.localizedDescription)"
            }
        }
        .alert(
            "操作未完全完成",
            isPresented: Binding(
                get: { operationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        operationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
        .onAppear {
            audioPlayer.setPlaybackQueue(songs)
        }
        .onChange(of: songs.map(\.id)) { _, _ in
            audioPlayer.setPlaybackQueue(songs)
        }
    }

    @MainActor
    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        var knownHashes = Set(songs.map(\.contentHash))
        var failures = [String]()

        for url in urls {
            do {
                let song = try await importer.importMP3(
                    from: url,
                    existingContentHashes: knownHashes
                )

                modelContext.insert(song)

                do {
                    try modelContext.save()
                } catch {
                    modelContext.delete(song)
                    try? importer.removeStoredMP3(named: song.storageFileName)
                    throw error
                }

                knownHashes.insert(song.contentHash)
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            operationErrorMessage = failures.joined(separator: "\n")
        }
    }

    private func deleteSongs(at offsets: IndexSet) {
        let songsToDelete = offsets.map { songs[$0] }

        if songsToDelete.contains(where: { $0.id == audioPlayer.currentSongID }) {
            audioPlayer.stopPlayback()
        }

        for song in songsToDelete {
            modelContext.delete(song)
        }

        do {
            try modelContext.save()
        } catch {
            operationErrorMessage = "删除资料库记录失败：\(error.localizedDescription)"
            return
        }

        var failedFiles = [String]()

        for song in songsToDelete {
            do {
                try importer.removeStoredMP3(named: song.storageFileName)
            } catch {
                failedFiles.append(song.title)
            }
        }

        if !failedFiles.isEmpty {
            operationErrorMessage = "已从资料库移除，但未能清理文件：\(failedFiles.joined(separator: "、"))"
        }
    }

    private func togglePlayback(of song: Song) {
        do {
            try audioPlayer.togglePlayback(of: song)
        } catch {
            operationErrorMessage = "无法播放 \(song.title)：\(error.localizedDescription)"
        }
    }

    private var currentSong: Song? {
        guard let currentSongID = audioPlayer.currentSongID else {
            return nil
        }

        return songs.first(where: { $0.id == currentSongID })
    }

    private func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct ArtworkThumbnail: View {
    let artworkData: Data?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let artworkData,
               let image = UIImage(data: artworkData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
