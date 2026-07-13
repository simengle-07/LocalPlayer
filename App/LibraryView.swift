import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Song.importedAt, order: .reverse)
    private var songs: [Song]

    @State private var isShowingImporter = false
    @State private var isImporting = false
    @State private var importErrorMessage: String?

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
                    List(songs, id: \.id) { song in
                        HStack(spacing: 12) {
                            Image(systemName: "music.note")
                                .foregroundStyle(.tint)
                                .frame(width: 24)

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
                        }
                        .accessibilityElement(children: .combine)
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
                importErrorMessage = "无法打开文件选择器：\(error.localizedDescription)"
            }
        }
        .alert(
            "导入未完全完成",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        importErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                importErrorMessage = nil
            }
        } message: {
            Text(importErrorMessage ?? "")
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
                    importer.removeStoredMP3(named: song.storageFileName)
                    throw error
                }

                knownHashes.insert(song.contentHash)
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }

        if !failures.isEmpty {
            importErrorMessage = failures.joined(separator: "\n")
        }
    }

    private func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
