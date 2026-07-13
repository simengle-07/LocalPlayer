import Foundation
import SwiftUI

private enum BatchCategoryAction: String, CaseIterable, Identifiable {
    case unchanged
    case set
    case clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged:
            return "保持不变"
        case .set:
            return "设置分类"
        case .clear:
            return "设为未分类"
        }
    }
}

private enum BatchArtworkAction: String, CaseIterable, Identifiable {
    case unchanged
    case replace
    case remove

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged:
            return "保持不变"
        case .replace:
            return "设置同一张封面"
        case .remove:
            return "移除封面"
        }
    }
}

struct BatchSongEditorView: View {
    let selectedSongCount: Int
    let categoryNames: [String]
    let categoryPaths: [SongCategoryPath]
    let onSubmit: (BatchSongEditRequest) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var categoryAction = BatchCategoryAction.unchanged
    @State private var selectedCategoryName: String?
    @State private var newCategoryName = ""
    @State private var selectedSubcategoryName: String?
    @State private var newSubcategoryName = ""
    @State private var artworkAction = BatchArtworkAction.unchanged
    @State private var artworkData: Data?
    @State private var didChangeArtwork = false
    @State private var isLoadingArtwork = false
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "已选择 \(selectedSongCount) 首歌曲",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.secondary)
                }

                Section("分类") {
                    Picker("分类操作", selection: $categoryAction) {
                        ForEach(BatchCategoryAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }

                    if categoryAction == .set {
                        categoryEditor
                    } else if categoryAction == .clear {
                        Text("会清除所选歌曲的一级和二级分类。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("封面") {
                    Picker("封面操作", selection: $artworkAction) {
                        ForEach(BatchArtworkAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }

                    if artworkAction == .remove {
                        Text("会移除所选歌曲的自定义封面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if artworkAction == .replace {
                    ArtworkEditorSection(
                        artworkData: $artworkData,
                        didChangeArtwork: $didChangeArtwork,
                        errorMessage: $validationMessage,
                        isLoadingArtwork: $isLoadingArtwork,
                        allowsRemoval: false,
                        footerText: "所选图片会应用到全部选中歌曲。"
                    )
                }
            }
            .navigationTitle("批量编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("下一步", action: submit)
                        .disabled(!canSubmit)
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
            .onChange(of: effectiveCategoryName) { oldValue, newValue in
                guard !Song.hasSameOptionalCategoryName(oldValue, newValue) else {
                    return
                }

                selectedSubcategoryName = nil
                newSubcategoryName = ""
            }
            .onChange(of: artworkAction) { _, newValue in
                guard newValue != .replace else {
                    return
                }

                artworkData = nil
                didChangeArtwork = false
            }
        }
    }

    @ViewBuilder
    private var categoryEditor: some View {
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

    private var effectiveCategoryName: String? {
        Song.normalizedCategoryName(from: newCategoryName) ?? selectedCategoryName
    }

    private var subcategoryNames: [String] {
        Song.subcategoryNames(
            for: effectiveCategoryName,
            in: categoryPaths
        )
    }

    private var requestedSubcategoryName: String? {
        effectiveCategoryName.flatMap { _ in
            Song.normalizedCategoryName(from: newSubcategoryName)
                ?? selectedSubcategoryName
        }
    }

    private var canSubmit: Bool {
        guard !isLoadingArtwork else {
            return false
        }

        guard categoryAction != .unchanged || artworkAction != .unchanged else {
            return false
        }

        if categoryAction == .set, effectiveCategoryName == nil {
            return false
        }

        if artworkAction == .replace, artworkData == nil {
            return false
        }

        return true
    }

    private func submit() {
        let categoryChange: BatchCategoryChange

        switch categoryAction {
        case .unchanged:
            categoryChange = .unchanged
        case .set:
            guard let effectiveCategoryName else {
                validationMessage = "请选择或输入一级分类。"
                return
            }
            categoryChange = .move(
                categoryName: effectiveCategoryName,
                subcategoryName: requestedSubcategoryName
            )
        case .clear:
            categoryChange = .move(categoryName: nil, subcategoryName: nil)
        }

        let artworkChange: BatchArtworkChange

        switch artworkAction {
        case .unchanged:
            artworkChange = .unchanged
        case .replace:
            guard let artworkData else {
                validationMessage = "请选择可用的封面图片。"
                return
            }
            artworkChange = .replace(artworkData)
        case .remove:
            artworkChange = .remove
        }

        onSubmit(
            BatchSongEditRequest(
                categoryChange: categoryChange,
                artworkChange: artworkChange
            )
        )
        dismiss()
    }
}
