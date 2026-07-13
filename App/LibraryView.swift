import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

private enum LibraryCategoryFilter: Hashable {
    case all
    case uncategorized
    case category(String)
    case subcategory(SongCategoryPath)

    var displayName: String {
        switch self {
        case .all:
            return "全部音乐"
        case .uncategorized:
            return "未分类"
        case .category(let categoryName):
            return categoryName
        case .subcategory(let path):
            return path.displayName
        }
    }
}

private struct PendingBatchSongEdit: Identifiable {
    let id = UUID()
    let songIDs: Set<UUID>
    let request: BatchSongEditRequest
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var audioPlayer: AudioPlayerService
    @Environment(\.editMode) private var editMode

    @Query(sort: \Song.title, order: .forward)
    private var songs: [Song]

    @State private var isShowingImporter = false
    @State private var isShowingNowPlaying = false
    @State private var isShowingSongEditor = false
    @State private var isShowingBatchSongEditor = false
    @State private var isImporting = false
    @State private var selectedCategoryFilter = LibraryCategoryFilter.all
    @State private var selectedSongIDs = Set<UUID>()
    @State private var songBeingEdited: Song?
    @State private var pendingBatchSongEdit: PendingBatchSongEdit?
    @State private var categoryNameBeingRenamed: String?
    @State private var renamedCategoryName = ""
    @State private var categoryNamePendingDeletion: String?
    @State private var subcategoryPathBeingRenamed: SongCategoryPath?
    @State private var subcategoryPathPendingDeletion: SongCategoryPath?
    @State private var operationErrorMessage: String?

    private let importer = MP3ImportService()

    var body: some View {
        lifecycleContent
    }

    private var navigationContent: some View {
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
                    List(selection: $selectedSongIDs) {
                        ForEach(filteredSongs, id: \.id) { song in
                            songRow(song)
                                .tag(song.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !isEditing {
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
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(isEditing ? "已选择 \(selectedSongIDs.count) 首" : "本地音乐")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    categoryFilterMenu
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        Button("批量编辑", systemImage: "slider.horizontal.3") {
                            isShowingBatchSongEditor = true
                        }
                        .disabled(selectedSongIDs.isEmpty)
                    } else if isImporting {
                        ProgressView()
                            .accessibilityLabel("正在导入音乐")
                    } else {
                        Button("导入 MP3", systemImage: "plus") {
                            isShowingImporter = true
                        }
                    }

                    EditButton()
                }
            }
        }
    }

    private var playerInsetContent: some View {
        navigationContent
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
    }

    private var sheetContent: some View {
        playerInsetContent
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
                    categoryPaths: categoryPaths,
                    onSave: { title, categoryName, subcategoryName, artworkChange in
                        saveSongEdits(
                            for: songBeingEdited,
                            title: title,
                            categoryName: categoryName,
                            subcategoryName: subcategoryName,
                            artworkChange: artworkChange
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingBatchSongEditor) {
            BatchSongEditorView(
                selectedSongCount: selectedBatchSongs.count,
                categoryNames: categoryNames,
                categoryPaths: categoryPaths,
                onSubmit: { request in
                    guard !selectedBatchSongs.isEmpty else {
                        return
                    }

                    pendingBatchSongEdit = PendingBatchSongEdit(
                        songIDs: selectedSongIDs,
                        request: request
                    )
                }
            )
        }
    }

    private var importerContent: some View {
        sheetContent
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
    }

    private var categoryDialogContent: some View {
        importerContent
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
    }

    private var subcategoryDialogContent: some View {
        categoryDialogContent
        .alert(
            "重命名二级分类",
            isPresented: Binding(
                get: { subcategoryPathBeingRenamed != nil },
                set: { isPresented in
                    if !isPresented {
                        subcategoryPathBeingRenamed = nil
                    }
                }
            )
        ) {
            TextField("二级分类名称", text: $renamedCategoryName)

            Button("保存") {
                renameSubcategory()
            }

            Button("取消", role: .cancel) {
                subcategoryPathBeingRenamed = nil
            }
        }
        .confirmationDialog(
            "删除二级分类",
            isPresented: Binding(
                get: { subcategoryPathPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        subcategoryPathPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("删除并移回一级分类", role: .destructive) {
                deleteSubcategory()
            }
        } message: {
            Text(
                "删除“\(subcategoryPathPendingDeletion?.displayName ?? "")”后，其中的歌曲会保留在一级分类。"
            )
        }
    }

    private var errorDialogContent: some View {
        subcategoryDialogContent
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
        .confirmationDialog(
            "确认批量编辑",
            isPresented: Binding(
                get: { pendingBatchSongEdit != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingBatchSongEdit = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let pendingEdit = pendingBatchSongEdit {
                Button("应用到 \(pendingEdit.songIDs.count) 首歌曲") {
                    applyBatchEdit(pendingEdit)
                }
            }

            Button("取消", role: .cancel) {
                pendingBatchSongEdit = nil
            }
        } message: {
            Text(
                pendingBatchSongEdit.map { batchEditSummary(for: $0) }
                    ?? ""
            )
        }
    }

    private var lifecycleContent: some View {
        errorDialogContent
        .onAppear {
            synchronizePlaybackQueue()
        }
        .onChange(of: selectedCategoryFilter) { _, _ in
            clearBatchSelection()
            synchronizePlaybackQueue()
        }
        .onChange(of: isEditing) { _, isEditing in
            if !isEditing {
                clearBatchSelection()
            }
        }
        .onChange(of: filteredSongs.map(\.id)) { _, _ in
            synchronizePlaybackQueue()
        }
        .onChange(of: categoryPaths) { _, _ in
            synchronizeSelectedCategoryFilter()
        }
    }

    private var categoryFilterMenu: some View {
        Menu {
            Button {
                selectedCategoryFilter = .all
            } label: {
                Label("全部音乐", systemImage: "music.note.list")
            }

            Button {
                selectedCategoryFilter = .uncategorized
            } label: {
                Label("未分类", systemImage: "tray")
            }

            ForEach(categoryNames, id: \.self) { categoryName in
                Menu(categoryName) {
                    Button("全部 \(categoryName)") {
                        selectedCategoryFilter = .category(categoryName)
                    }

                    let subcategoryNames = subcategoryNames(for: categoryName)

                    if !subcategoryNames.isEmpty {
                        Divider()

                        ForEach(subcategoryNames, id: \.self) { subcategoryName in
                            Button(subcategoryName) {
                                selectedCategoryFilter = .subcategory(
                                    SongCategoryPath(
                                        categoryName: categoryName,
                                        subcategoryName: subcategoryName
                                    )
                                )
                            }
                        }
                    }
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

                            let subcategoryNames = subcategoryNames(for: categoryName)

                            if !subcategoryNames.isEmpty {
                                Divider()

                                ForEach(subcategoryNames, id: \.self) { subcategoryName in
                                    Menu(subcategoryName) {
                                        Button("重命名", systemImage: "pencil") {
                                            subcategoryPathBeingRenamed = SongCategoryPath(
                                                categoryName: categoryName,
                                                subcategoryName: subcategoryName
                                            )
                                            renamedCategoryName = subcategoryName
                                        }

                                        Button(
                                            "删除",
                                            systemImage: "trash",
                                            role: .destructive
                                        ) {
                                            subcategoryPathPendingDeletion = SongCategoryPath(
                                                categoryName: categoryName,
                                                subcategoryName: subcategoryName
                                            )
                                        }
                                    }
                                }
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

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var selectedBatchSongs: [Song] {
        songs.filter { selectedSongIDs.contains($0.id) }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: 8) {
            if isEditing {
                songRowContent(song)
            } else {
                Button {
                    togglePlayback(of: song)
                } label: {
                    songRowContent(song)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityHint(
                    audioPlayer.currentSongID == song.id && audioPlayer.isPlaying
                        ? "暂停播放"
                        : "播放歌曲"
                )

                songManagementMenu(for: song)
            }
        }
    }

    private func songRowContent(_ song: Song) -> some View {
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

    private func songManagementMenu(for song: Song) -> some View {
        Menu {
            Button("重命名", systemImage: "pencil") {
                presentSongEditor(for: song)
            }

            Menu("移动到分类") {
                Button("未分类", systemImage: "tray") {
                    moveSong(song, toCategory: nil, subcategoryName: nil)
                }

                ForEach(categoryNames, id: \.self) { categoryName in
                    Menu(categoryName) {
                        Button("仅 \(categoryName)") {
                            moveSong(
                                song,
                                toCategory: categoryName,
                                subcategoryName: nil
                            )
                        }

                        let subcategoryNames = subcategoryNames(for: categoryName)

                        if !subcategoryNames.isEmpty {
                            Divider()

                            ForEach(subcategoryNames, id: \.self) { subcategoryName in
                                Button(subcategoryName) {
                                    moveSong(
                                        song,
                                        toCategory: categoryName,
                                        subcategoryName: subcategoryName
                                    )
                                }
                            }
                        }
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
        subcategoryName: String?,
        artworkChange: SongArtworkChange
    ) -> Bool {
        let originalTitle = song.title
        let originalCategoryName = song.categoryName
        let originalSubcategoryName = song.subcategoryName
        let originalArtworkData = song.artworkData

        guard song.rename(to: title) else {
            operationErrorMessage = "歌曲名称不能为空。"
            return false
        }

        song.move(
            toCategory: categoryName,
            subcategory: subcategoryName,
            existingCategoryPaths: categoryPaths
        )

        switch artworkChange {
        case .unchanged:
            break
        case .replace(let artworkData):
            guard song.replaceArtwork(with: artworkData) else {
                song.title = originalTitle
                song.categoryName = originalCategoryName
                song.subcategoryName = originalSubcategoryName
                operationErrorMessage = "所选封面不是可用的图片。"
                return false
            }
        case .remove:
            song.removeArtwork()
        }

        guard saveModelChanges(withFailureMessage: "保存歌曲编辑失败") else {
            song.title = originalTitle
            song.categoryName = originalCategoryName
            song.subcategoryName = originalSubcategoryName
            song.artworkData = originalArtworkData
            return false
        }

        return true
    }

    private func applyBatchEdit(_ pendingEdit: PendingBatchSongEdit) {
        let selectedSongs = songs.filter {
            pendingEdit.songIDs.contains($0.id)
        }

        guard selectedSongs.count == pendingEdit.songIDs.count else {
            operationErrorMessage = "部分已选择歌曲已不在资料库中，请重新选择。"
            clearBatchSelection()
            return
        }

        let snapshot: BatchSongEditSnapshot

        do {
            snapshot = try pendingEdit.request.apply(
                to: selectedSongs,
                existingCategoryPaths: categoryPaths
            )
        } catch {
            operationErrorMessage = "无法应用批量编辑：\(error.localizedDescription)"
            return
        }

        do {
            try modelContext.save()
        } catch {
            snapshot.restore()
            operationErrorMessage = "保存批量编辑失败：\(error.localizedDescription)"
            return
        }

        if pendingEdit.request.changesArtwork,
           let currentSongID = audioPlayer.currentSongID,
           pendingEdit.songIDs.contains(currentSongID) {
            audioPlayer.refreshNowPlayingInfo()
        }

        clearBatchSelection()
        editMode?.wrappedValue = .inactive
    }

    private func clearBatchSelection() {
        selectedSongIDs.removeAll()
        isShowingBatchSongEditor = false
        pendingBatchSongEdit = nil
    }

    private func batchEditSummary(for pendingEdit: PendingBatchSongEdit) -> String {
        var changes = [String]()

        switch pendingEdit.request.categoryChange {
        case .unchanged:
            break
        case let .move(categoryName?, subcategoryName?):
            changes.append("分类设为“\(categoryName) / \(subcategoryName)”")
        case let .move(categoryName?, nil):
            changes.append("分类设为“\(categoryName)”")
        case .move(nil, _):
            changes.append("设为未分类")
        }

        switch pendingEdit.request.artworkChange {
        case .unchanged:
            break
        case .replace(_):
            changes.append("设置同一张封面")
        case .remove:
            changes.append("移除封面")
        }

        return "将对 \(pendingEdit.songIDs.count) 首歌曲\(changes.joined(separator: "，"))。"
    }

    private func moveSong(
        _ song: Song,
        toCategory categoryName: String?,
        subcategoryName: String?
    ) {
        let originalCategoryName = song.categoryName
        let originalSubcategoryName = song.subcategoryName

        song.move(
            toCategory: categoryName,
            subcategory: subcategoryName,
            existingCategoryPaths: categoryPaths
        )

        guard saveModelChanges(withFailureMessage: "移动歌曲分类失败") else {
            song.categoryName = originalCategoryName
            song.subcategoryName = originalSubcategoryName
            return
        }
    }

    private func renameCategory() {
        guard let categoryNameBeingRenamed else {
            return
        }

        let originalCategories = songs.map {
            (
                song: $0,
                categoryName: $0.categoryName,
                subcategoryName: $0.subcategoryName
            )
        }

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

        switch selectedCategoryFilter {
        case .category(let selectedCategoryName) where Song.hasSameCategoryName(
            selectedCategoryName,
            categoryNameBeingRenamed
        ):
            selectedCategoryFilter = .category(resolvedCategoryName)
        case .subcategory(let path) where Song.hasSameCategoryName(
            path.categoryName,
            categoryNameBeingRenamed
        ):
            selectedCategoryFilter = .subcategory(
                SongCategoryPath(
                    categoryName: resolvedCategoryName,
                    subcategoryName: path.subcategoryName
                )
            )
        default:
            break
        }

        self.categoryNameBeingRenamed = nil
    }

    private func deleteCategory() {
        guard let categoryNamePendingDeletion else {
            return
        }

        let originalCategories = songs.map {
            (
                song: $0,
                categoryName: $0.categoryName,
                subcategoryName: $0.subcategoryName
            )
        }

        guard Song.removeCategory(named: categoryNamePendingDeletion, from: songs) else {
            return
        }

        guard saveModelChanges(withFailureMessage: "删除分类失败") else {
            restoreCategories(originalCategories)
            return
        }

        switch selectedCategoryFilter {
        case .category(let selectedCategoryName) where Song.hasSameCategoryName(
            selectedCategoryName,
            categoryNamePendingDeletion
        ):
            selectedCategoryFilter = .uncategorized
        case .subcategory(let path) where Song.hasSameCategoryName(
            path.categoryName,
            categoryNamePendingDeletion
        ):
            selectedCategoryFilter = .uncategorized
        default:
            break
        }

        self.categoryNamePendingDeletion = nil
    }

    private func renameSubcategory() {
        guard let path = subcategoryPathBeingRenamed,
              let subcategoryName = path.subcategoryName else {
            return
        }

        let originalCategories = songs.map {
            (
                song: $0,
                categoryName: $0.categoryName,
                subcategoryName: $0.subcategoryName
            )
        }
        guard let resolvedSubcategoryName = Song.renameSubcategory(
            named: subcategoryName,
            fromCategory: path.categoryName,
            to: renamedCategoryName,
            in: songs
        ) else {
            operationErrorMessage = "二级分类名称不能为空。"
            return
        }

        guard saveModelChanges(withFailureMessage: "重命名二级分类失败") else {
            restoreCategories(originalCategories)
            return
        }

        if case .subcategory(let selectedPath) = selectedCategoryFilter,
           Song.hasSameCategoryPath(
               categoryName: selectedPath.categoryName,
               subcategoryName: selectedPath.subcategoryName,
               path.categoryName,
               subcategoryName
           ) {
            selectedCategoryFilter = .subcategory(
                SongCategoryPath(
                    categoryName: path.categoryName,
                    subcategoryName: resolvedSubcategoryName
                )
            )
        }

        subcategoryPathBeingRenamed = nil
    }

    private func deleteSubcategory() {
        guard let path = subcategoryPathPendingDeletion,
              let subcategoryName = path.subcategoryName else {
            return
        }

        let originalCategories = songs.map {
            (
                song: $0,
                categoryName: $0.categoryName,
                subcategoryName: $0.subcategoryName
            )
        }
        guard Song.removeSubcategory(
            named: subcategoryName,
            fromCategory: path.categoryName,
            in: songs
        ) else {
            return
        }

        guard saveModelChanges(withFailureMessage: "删除二级分类失败") else {
            restoreCategories(originalCategories)
            return
        }

        if case .subcategory(let selectedPath) = selectedCategoryFilter,
           Song.hasSameCategoryPath(
               categoryName: selectedPath.categoryName,
               subcategoryName: selectedPath.subcategoryName,
               path.categoryName,
               subcategoryName
           ) {
            selectedCategoryFilter = .category(path.categoryName)
        }

        subcategoryPathPendingDeletion = nil
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

    private func restoreCategories(
        _ categories: [
            (song: Song, categoryName: String?, subcategoryName: String?)
        ]
    ) {
        for category in categories {
            category.song.categoryName = category.categoryName
            category.song.subcategoryName = category.subcategoryName
        }
    }

    private func synchronizePlaybackQueue() {
        audioPlayer.setPlaybackQueue(playbackQueue)
    }

    private var categoryNames: [String] {
        Song.categoryNames(in: songs)
    }

    private var categoryPaths: [SongCategoryPath] {
        Song.categoryPaths(in: songs)
    }

    private func subcategoryNames(for categoryName: String) -> [String] {
        Song.subcategoryNames(for: categoryName, in: categoryPaths)
    }

    private func synchronizeSelectedCategoryFilter() {
        switch selectedCategoryFilter {
        case .all, .uncategorized:
            return
        case .category(let categoryName):
            guard categoryNames.contains(where: {
                Song.hasSameCategoryName($0, categoryName)
            }) else {
                selectedCategoryFilter = .all
                return
            }
        case .subcategory(let path):
            guard categoryNames.contains(where: {
                Song.hasSameCategoryName($0, path.categoryName)
            }) else {
                selectedCategoryFilter = .all
                return
            }

            guard categoryPaths.contains(where: {
                Song.hasSameCategoryPath(
                    categoryName: $0.categoryName,
                    subcategoryName: $0.subcategoryName,
                    path.categoryName,
                    path.subcategoryName ?? ""
                )
            }) else {
                selectedCategoryFilter = .category(path.categoryName)
                return
            }
        }
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
        case .subcategory(let path):
            guard let subcategoryName = path.subcategoryName else {
                return []
            }

            return songs.filter {
                Song.hasSameCategoryPath(
                    categoryName: $0.categoryName,
                    subcategoryName: $0.subcategoryName,
                    path.categoryName,
                    subcategoryName
                )
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
