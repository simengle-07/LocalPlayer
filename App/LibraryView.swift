import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum LibraryCategoryFilter: Hashable {
    case all
    case uncategorized
    case category(String)

    var displayName: String {
        switch self {
        case .all:
            return "全部音乐"
        case .uncategorized:
            return "未分类"
        case .category(let categoryName):
            return categoryName
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @Query(sort: \Song.title, order: .forward)
    private var songs: [Song]

    @State private var isShowingImporter = false
    @State private var isShowingNowPlaying = false
    @State private var isShowingSongEditor = false
    @State private var isImporting = false
    @State private var selectedCategoryFilter = LibraryCategoryFilter.all
    @State private var songBeingEdited: Song?
    @State private var categoryNameBeingRenamed: String?
    @State private var renamedCategoryName = ""
    @State private var categoryNamePendingDeletion: String?
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
                } else if filteredSongs.isEmpty {
                    ContentUnavailableView(
                        "这个分类还没有音乐",
                        systemImage: "music.note.list",
                        description: Text("选择其他分类，或编辑歌曲以调整分类。")
                    )
                } else {
                    List {
                        ForEach(filteredSongs, id: \.id) { song in
                            songRow(song)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        presentSongEditor(for: song)
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
                                    .tint(.accentColor)

                                    Button(role: .destructive) {
                                        deleteSong(song)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                        .onDelete(perform: deleteSongs)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("本地音乐")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    categoryFilterMenu
                }

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
                    songs: playbackQueue,
                    operationErrorMessage: $operationErrorMessage,
                    onOpenPlayer: {
                        isShowingNowPlaying = true
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingNowPlaying) {
            NowPlayingView(
                librarySongs: songs,
                playbackQueue: playbackQueue,
                operationErrorMessage: $operationErrorMessage
            )
            .environmentObject(audioPlayer)
        }
        .sheet(
            isPresented: $isShowingSongEditor,
            onDismiss: { songBeingEdited = nil }
        ) {
            if let songBeingEdited {
                SongEditorView(
                    song: songBeingEdited,
                    categoryNames: categoryNames,
                    onSave: { title, categoryName, artworkChange in
                        saveSongEdits(
                            for: songBeingEdited,
                            title: title,
                            categoryName: categoryName,
                            artworkChange: artworkChange
                        )
                    }
                )
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
                operationErrorMessage = "无法打开文件选择器：\(error.localizedDescription)"
            }
        }
        .alert(
            "重命名分类",
            isPresented: Binding(
                get: { categoryNameBeingRenamed != nil },
                set: { isPresented in
                    if !isPresented {
                        categoryNameBeingRenamed = nil
                    }
                }
            )
        ) {
            TextField("分类名称", text: $renamedCategoryName)

            Button("保存") {
                renameCategory()
            }

            Button("取消", role: .cancel) {
                categoryNameBeingRenamed = nil
            }
        }
        .confirmationDialog(
            "删除分类",
            isPresented: Binding(
                get: { categoryNamePendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        categoryNamePendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除并设为未分类", role: .destructive) {
                deleteCategory()
            }
        } message: {
            Text("删除“\(categoryNamePendingDeletion ?? "")”后，其中的歌曲会变为未分类。")
        }
        .alert(
            "操作未完成",
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
            synchronizePlaybackQueue()
        }
        .onChange(of: selectedCategoryFilter) { _, _ in
            synchronizePlaybackQueue()
        }
        .onChange(of: filteredSongs.map(\.id)) { _, _ in
            synchronizePlaybackQueue()
        }
        .onChange(of: categoryNames) { _, updatedCategoryNames in
            guard case .category(let selectedCategoryName) = selectedCategoryFilter,
                  !updatedCategoryNames.contains(where: {
                      Song.hasSameCategoryName($0, selectedCategoryName)
                  }) else {
                return
            }

            selectedCategoryFilter = .all
        }
    }

    private var categoryFilterMenu: some View {
        Menu {
            Picker("显示", selection: $selectedCategoryFilter) {
                Label("全部音乐", systemImage: "music.note.list")
                    .tag(LibraryCategoryFilter.all)

                Label("未分类", systemImage: "tray")
                    .tag(LibraryCategoryFilter.uncategorized)

                ForEach(categoryNames, id: \.self) { categoryName in
                    Text(categoryName)
                        .tag(LibraryCategoryFilter.category(categoryName))
                }
            }

            if !categoryNames.isEmpty {
                Divider()

                Menu("管理分类") {
                    ForEach(categoryNames, id: \.self) { categoryName in
                        Menu(categoryName) {
                            Button("重命名", systemImage: "pencil") {
                                categoryNameBeingRenamed = categoryName
                                renamedCategoryName = categoryName
                            }

                            Button("删除", systemImage: "trash", role: .destructive) {
                                categoryNamePendingDeletion = categoryName
                            }
                        }
                    }
                }
            }
        } label: {
            Label(selectedCategoryFilter.displayName, systemImage: "line.3.horizontal.decrease.circle")
                .lineLimit(1)
        }
        .accessibilityLabel("筛选音乐分类")
        .accessibilityValue(selectedCategoryFilter.displayName)
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                audioPlayer.currentSongID == song.id && audioPlayer.isPlaying
                    ? "暂停播放"
                    : "播放歌曲"
            )

            Menu {
                Button("重命名", systemImage: "pencil") {
                    presentSongEditor(for: song)
                }

                Menu("移动到分类") {
                    Button("未分类", systemImage: "tray") {
                        moveSong(song, toCategory: nil)
                    }

                    ForEach(categoryNames, id: \.self) { categoryName in
                        Button(categoryName) {
                            moveSong(song, toCategory: categoryName)
                        }
                    }

                    Divider()

                    Button("新建分类…", systemImage: "plus") {
                        presentSongEditor(for: song)
                    }
                }

                Button("删除", systemImage: "trash", role: .destructive) {
                    deleteSong(song)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("管理 \(song.title)")
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

    private func presentSongEditor(for song: Song) {
        songBeingEdited = song
        isShowingSongEditor = true
    }

    private func saveSongEdits(
        for song: Song,
        title: String,
        categoryName: String?,
        artworkChange: SongArtworkChange
    ) -> Bool {
        let originalTitle = song.title
        let originalCategoryName = song.categoryName
        let originalArtworkData = song.artworkData

        guard song.rename(to: title) else {
            operationErrorMessage = "歌曲名称不能为空。"
            return false
        }

        song.move(
            toCategory: categoryName,
            existingCategoryNames: categoryNames
        )

        switch artworkChange {
        case .unchanged:
            break
        case .replace(let artworkData):
            guard song.replaceArtwork(with: artworkData) else {
                song.title = originalTitle
                song.categoryName = originalCategoryName
                operationErrorMessage = "所选封面不是可用的图片。"
                return false
            }
        case .remove:
            song.removeArtwork()
        }

        guard saveModelChanges(withFailureMessage: "保存歌曲编辑失败") else {
            song.title = originalTitle
            song.categoryName = originalCategoryName
            song.artworkData = originalArtworkData
            return false
        }

        return true
    }

    private func moveSong(_ song: Song, toCategory categoryName: String?) {
        let originalCategoryName = song.categoryName

        song.move(
            toCategory: categoryName,
            existingCategoryNames: categoryNames
        )

        guard saveModelChanges(withFailureMessage: "移动歌曲分类失败") else {
            song.categoryName = originalCategoryName
            return
        }
    }

    private func renameCategory() {
        guard let categoryNameBeingRenamed else {
            return
        }

        let originalCategories = songs.map { (song: $0, categoryName: $0.categoryName) }

        guard let resolvedCategoryName = Song.renameCategory(
            named: categoryNameBeingRenamed,
            to: renamedCategoryName,
            in: songs
        ) else {
            operationErrorMessage = "分类名称不能为空。"
            return
        }

        guard saveModelChanges(withFailureMessage: "重命名分类失败") else {
            restoreCategories(originalCategories)
            return
        }

        if case .category(let selectedCategoryName) = selectedCategoryFilter,
           Song.hasSameCategoryName(selectedCategoryName, categoryNameBeingRenamed) {
            selectedCategoryFilter = .category(resolvedCategoryName)
        }

        self.categoryNameBeingRenamed = nil
    }

    private func deleteCategory() {
        guard let categoryNamePendingDeletion else {
            return
        }

        let originalCategories = songs.map { (song: $0, categoryName: $0.categoryName) }

        guard Song.removeCategory(named: categoryNamePendingDeletion, from: songs) else {
            return
        }

        guard saveModelChanges(withFailureMessage: "删除分类失败") else {
            restoreCategories(originalCategories)
            return
        }

        if case .category(let selectedCategoryName) = selectedCategoryFilter,
           Song.hasSameCategoryName(selectedCategoryName, categoryNamePendingDeletion) {
            selectedCategoryFilter = .uncategorized
        }

        self.categoryNamePendingDeletion = nil
    }

    private func deleteSong(_ song: Song) {
        guard let index = filteredSongs.firstIndex(where: { $0.id == song.id }) else {
            return
        }

        deleteSongs(at: IndexSet(integer: index))
    }

    private func deleteSongs(at offsets: IndexSet) {
        let songsToDelete = offsets.map { filteredSongs[$0] }

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

    private func saveModelChanges(withFailureMessage failureMessage: String) -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            operationErrorMessage = "\(failureMessage)：\(error.localizedDescription)"
            return false
        }
    }

    private func restoreCategories(_ categories: [(song: Song, categoryName: String?)]) {
        for category in categories {
            category.song.categoryName = category.categoryName
        }
    }

    private func synchronizePlaybackQueue() {
        audioPlayer.setPlaybackQueue(playbackQueue)
    }

    private var categoryNames: [String] {
        Song.categoryNames(in: songs)
    }

    private var filteredSongs: [Song] {
        switch selectedCategoryFilter {
        case .all:
            return songs
        case .uncategorized:
            return songs.filter {
                Song.normalizedCategoryName(from: $0.categoryName) == nil
            }
        case .category(let categoryName):
            return songs.filter {
                Song.hasSameCategoryName($0.categoryName, categoryName)
            }
        }
    }

    private var playbackQueue: [Song] {
        filteredSongs
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
