import Foundation
import SwiftUI

struct MiniPlayerBar: View {
    let song: Song
    let songs: [Song]

    @Binding var operationErrorMessage: String?
    let onOpenPlayer: () -> Void

    @EnvironmentObject private var audioPlayer: AudioPlayerService

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(
                value: min(audioPlayer.currentTime, playbackDuration),
                total: playbackDuration
            )
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .accessibilityLabel("播放进度")
            .accessibilityValue(formattedDuration(audioPlayer.currentTime))

            HStack(spacing: 12) {
                Button(action: onOpenPlayer) {
                    HStack(spacing: 12) {
                        ArtworkThumbnail(artworkData: song.artworkData)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)

                            Text(song.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("打开正在播放页面")
                .accessibilityHint("查看完整播放控制")

                Button(action: playPrevious) {
                    Image(systemName: "backward.fill")
                }
                .disabled(!audioPlayer.hasPrevious(in: songs))
                .accessibilityLabel("上一首")

                Button(action: togglePlayback) {
                    Image(
                        systemName: audioPlayer.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                }
                .accessibilityLabel(audioPlayer.isPlaying ? "暂停" : "播放")

                Button(action: playNext) {
                    Image(systemName: "forward.fill")
                }
                .disabled(!audioPlayer.hasNext(in: songs))
                .accessibilityLabel("下一首")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var playbackDuration: TimeInterval {
        max(audioPlayer.duration, 1)
    }

    private func togglePlayback() {
        performPlaybackAction {
            try audioPlayer.togglePlayback(of: song)
        }
    }

    private func playPrevious() {
        performPlaybackAction {
            try audioPlayer.playPrevious(in: songs)
        }
    }

    private func playNext() {
        performPlaybackAction {
            try audioPlayer.playNext(in: songs)
        }
    }

    private func performPlaybackAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            operationErrorMessage = "无法播放 \(song.title)：\(error.localizedDescription)"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
