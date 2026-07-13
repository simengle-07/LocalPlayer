import SwiftUI

struct SongEditorView: View {
    let song: Song
    let categoryNames: [String]
    let onSave: (String, String?) -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var selectedCategoryName: String?
    @State private var newCategoryName = ""
    @State private var validationMessage: String?

    init(
        song: Song,
        categoryNames: [String],
        onSave: @escaping (String, String?) -> Bool
    ) {
        self.song = song
        self.categoryNames = categoryNames
        self.onSave = onSave
        _title = State(initialValue: song.title)
        _selectedCategoryName = State(initialValue: song.categoryName)
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
                }
            }
            .alert(
                "无法保存",
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

        if onSave(title, requestedCategoryName) {
            dismiss()
        }
    }
}
