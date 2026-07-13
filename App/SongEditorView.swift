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
    let categoryPaths: [SongCategoryPath]
    let onSave: (String, String?, String?, SongArtworkChange) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedCategoryName: String?
    @State private var newCategoryName = ""
    @State private var selectedSubcategoryName: String?
    @State private var newSubcategoryName = ""
    @State private var artworkData: Data?
    @State private var didChangeArtwork = false
    @State private var isLoadingArtwork = false
    @State private var validationMessage: String?

    init(
        song: Song,
        categoryNames: [String],
        categoryPaths: [SongCategoryPath],
        onSave: @escaping (String, String?, String?, SongArtworkChange) -> Bool
    ) {
        self.song = song
        self.categoryNames = categoryNames
        self.categoryPaths = categoryPaths
        self.onSave = onSave
        _title = State(initialValue: song.title)
        _selectedCategoryName = State(initialValue: song.categoryName)
        _selectedSubcategoryName = State(initialValue: song.subcategoryName)
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
                    Picker("一级分类", selection: $selectedCategoryName) {
                        Text("未分类")
                            .tag(String?.none)

                        ForEach(categoryNames, id: \.self) { categoryName in
                            Text(categoryName)
                                .tag(categoryName as String?)
                        }
                    }

                    TextField("或输入新一级分类", text: $newCategoryName)
                        .textInputAutocapitalization(.words)

                    if let effectiveCategoryName {
                        Picker("二级分类", selection: $selectedSubcategoryName) {
                            Text("仅一级分类")
                                .tag(String?.none)

                            ForEach(subcategoryNames, id: \.self) { subcategoryName in
                                Text(subcategoryName)
                                    .tag(subcategoryName as String?)
                            }
                        }

                        TextField("或输入新二级分类", text: $newSubcategoryName)
                            .textInputAutocapitalization(.words)

                        Text("当前一级分类：\(effectiveCategoryName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("先选择或输入一级分类，才能设置二级分类。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: effectiveCategoryName) { oldValue, newValue in
                    guard !Song.hasSameOptionalCategoryName(oldValue, newValue) else {
                        return
                    }

                    selectedSubcategoryName = nil
                    newSubcategoryName = ""
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

    private var effectiveCategoryName: String? {
        Song.normalizedCategoryName(from: newCategoryName) ?? selectedCategoryName
    }

    private var subcategoryNames: [String] {
        Song.subcategoryNames(
            for: effectiveCategoryName,
            in: categoryPaths
        )
    }

    private func save() {
        guard Song.normalizedTitle(from: title) != nil else {
            validationMessage = "歌曲名称不能为空。"
            return
        }

        let requestedSubcategoryName = effectiveCategoryName.flatMap { _ in
            Song.normalizedCategoryName(from: newSubcategoryName)
                ?? selectedSubcategoryName
        }
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

        if onSave(
            title,
            effectiveCategoryName,
            requestedSubcategoryName,
            artworkChange
        ) {
            dismiss()
        }
    }
}
