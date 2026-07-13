import Foundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ArtworkEditorSection: View {
    @Binding var artworkData: Data?
    @Binding var didChangeArtwork: Bool
    @Binding var errorMessage: String?
    @Binding var isLoadingArtwork: Bool
    var allowsRemoval = true
    var footerText = "封面更改会在保存歌曲时应用。"

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isShowingFileImporter = false

    var body: some View {
        Section("封面") {
            HStack {
                Spacer()

                ArtworkThumbnail(artworkData: artworkData, size: 104)

                Spacer()
            }

            if isLoadingArtwork {
                HStack {
                    ProgressView()
                    Text("正在读取照片…")
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("从照片选择", systemImage: "photo.on.rectangle")
            }

            Button("从文件选择", systemImage: "folder") {
                isShowingFileImporter = true
            }

            if allowsRemoval {
                Button("移除封面", systemImage: "trash", role: .destructive) {
                    artworkData = nil
                    didChangeArtwork = true
                }
                .disabled(artworkData == nil)
            }

            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else {
                return
            }

            Task {
                await loadArtwork(from: newItem)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case .success(let fileURL):
                loadArtworkFile(from: fileURL)
            case .failure(let error):
                errorMessage = "无法读取封面文件：\(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func loadArtwork(from photoItem: PhotosPickerItem) async {
        isLoadingArtwork = true
        defer {
            isLoadingArtwork = false
            selectedPhotoItem = nil
        }

        do {
            guard let imageData = try await photoItem.loadTransferable(type: Data.self) else {
                errorMessage = "无法读取所选照片。"
                return
            }

            useArtworkData(imageData)
        } catch {
            errorMessage = "无法读取所选照片：\(error.localizedDescription)"
        }
    }

    private func loadArtworkFile(from fileURL: URL) {
        guard fileURL.startAccessingSecurityScopedResource() else {
            errorMessage = "无法访问所选封面文件。"
            return
        }

        defer {
            fileURL.stopAccessingSecurityScopedResource()
        }

        do {
            useArtworkData(try Data(contentsOf: fileURL))
        } catch {
            errorMessage = "无法读取封面文件：\(error.localizedDescription)"
        }
    }

    private func useArtworkData(_ candidateData: Data) {
        guard Song.isValidArtworkData(candidateData) else {
            errorMessage = "所选文件不是可用的图片。"
            return
        }

        artworkData = candidateData
        didChangeArtwork = true
    }
}
