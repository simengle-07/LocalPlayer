import Foundation
import SwiftUI

enum SongArtworkChange {
    case unchanged
    case replace(Data)
    case remove
}

struct SongEditorView: View {
    let song: Song
    let categoryNames: [String]
    let onSave: (String, String?, SongArtworkChange) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedCategoryName: String?
    @State private var newCategoryName = ""
    @State private var artworkData: Data?
    @State private var didChangeArtwork = false
    @State private var isLoadingArtwork = false
    @State private var validationMessage: String?

    init(
        song: Song,
        categoryNames: [String],
        onSave: @escaping (String, String?, SongArtworkChange) -> Bool
    ) {
        self.song = song
        self.categoryNames = categoryNames
        self.onSave = onSave
        _title = State(initialValue: song.title)
        _selectedCategoryName = State(initialValue: song.categoryName)
        _artworkData = State(initialValue: song.artworkData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("歌曲名称") {
                    TextField("显示名称", text: $title)
                        .textInputAutocapitalization(.words)
                }

                Section("分类") {
                    Picker("现有分类", selection: $selectedCategoryName) {
                        Text("未分类")
                            .tag(String?.none)

                        ForEach(categoryNames, id: \.self) { categoryName in
                            Text(categoryName)
                                .tag(categoryName as String?)
                        }
                    }

                    TextField("或输入新分类", text: $newCategoryName)
                        .textInputAutocapitalization(.words)

                    Text("填写新分类时，会优先使用它。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ArtworkEditorSection(
                    artworkData: $artworkData,
                    didChangeArtwork: $didChangeArtwork,
                    errorMessage: $validationMessage,
                    isLoadingArtwork: $isLoadingArtwork
                )
            }
            .navigationTitle("编辑歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(isLoadingArtwork)
                }
            }
            .alert(
                "操作未完成",
                isPresented: Binding(
                    get: { validationMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            validationMessage = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {
                    validationMessage = nil
                }
            } message: {
                Text(validationMessage ?? "")
            }
        }
    }

    private func save() {
        guard Song.normalizedTitle(from: title) != nil else {
            validationMessage = "歌曲名称不能为空。"
            return
        }

        let requestedCategoryName = Song.normalizedCategoryName(from: newCategoryName)
            ?? selectedCategoryName
        let artworkChange: SongArtworkChange

        if didChangeArtwork {
            if let artworkData {
                artworkChange = .replace(artworkData)
            } else {
                artworkChange = .remove
            }
        } else {
            artworkChange = .unchanged
        }

        if onSave(title, requestedCategoryName, artworkChange) {
            dismiss()
        }
    }
}
