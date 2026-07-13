import Foundation
import SwiftUI

struct NowPlayingView: View {
    let librarySongs: [Song]
    let playbackQueue: [Song]

    @Binding var operationErrorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var audioPlayer: AudioPlayerService

    @State private var isSeeking = false
    @State private var seekTime: TimeInterval = 0

    var body: some View {
        NavigationStack {
            Group {
                if let currentSong {
                    ScrollView {
                        VStack(spacing: 28) {
                            ArtworkThumbnail(
                                artworkData: currentSong.artworkData,
                                size: 260
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)

                            VStack(spacing: 6) {
                                Text(currentSong.title)
                                    .font(.title2.weight(.semibold))
                                    .multilineTextAlignment(.center)

                                Text(currentSong.artist)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            VStack(spacing: 6) {
                                Slider(
                                    value: playbackPosition,
                                    in: 0...playbackDuration,
                                    onEditingChanged: updateSeeking
                                )
                                .accessibilityLabel("播放进度")
                                .accessibilityValue(
                                    "\(formattedDuration(displayedPlaybackTime))，共 \(formattedDuration(playbackDuration))"
                                )

                                HStack {
                                    Text(formattedDuration(displayedPlaybackTime))
                                    Spacer()
                                    Text(formattedDuration(playbackDuration))
                                }
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 36) {
                                Button(action: playPrevious) {
                                    Image(systemName: "backward.fill")
                                        .font(.title2)
                                }
                                .disabled(!audioPlayer.hasPrevious(in: playbackQueue))
                                .accessibilityLabel("上一首")

                                Button(action: { togglePlayback(for: currentSong) }) {
                                    Image(
                                        systemName: audioPlayer.isPlaying
                                            ? "pause.fill"
                                            : "play.fill"
                                    )
                                    .font(.title2)
                                    .frame(width: 52, height: 52)
                                }
                                .buttonStyle(.borderedProminent)
                                .clipShape(Circle())
                                .accessibilityLabel(audioPlayer.isPlaying ? "暂停" : "播放")

                                Button(action: playNext) {
                                    Image(systemName: "forward.fill")
                                        .font(.title2)
                                }
                                .disabled(!audioPlayer.hasNext(in: playbackQueue))
                                .accessibilityLabel("下一首")
                            }

                            HStack(spacing: 12) {
                                Image(systemName: "speaker.fill")
                                    .foregroundStyle(.secondary)

                                Slider(value: volume, in: 0...1)
                                    .accessibilityLabel("音量")
                                    .accessibilityValue("\(Int(audioPlayer.volume * 100))%")

                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                } else {
                    ContentUnavailableView(
                        "没有正在播放的歌曲",
                        systemImage: "music.note"
                    )
                }
            }
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            seekTime = boundedCurrentTime
        }
        .onChange(of: audioPlayer.currentTime) { _, newValue in
            if !isSeeking {
                seekTime = min(newValue, playbackDuration)
            }
        }
    }

    private var currentSong: Song? {
        guard let currentSongID = audioPlayer.currentSongID else {
            return nil
        }

        return librarySongs.first(where: { $0.id == currentSongID })
    }

    private var playbackDuration: TimeInterval {
        max(audioPlayer.duration, 1)
    }

    private var boundedCurrentTime: TimeInterval {
        min(audioPlayer.currentTime, playbackDuration)
    }

    private var displayedPlaybackTime: TimeInterval {
        isSeeking ? seekTime : boundedCurrentTime
    }

    private var playbackPosition: Binding<TimeInterval> {
        Binding(
            get: { displayedPlaybackTime },
            set: { seekTime = $0 }
        )
    }

    private var volume: Binding<Double> {
        Binding(
            get: { Double(audioPlayer.volume) },
            set: { audioPlayer.setVolume(Float($0)) }
        )
    }

    private func updateSeeking(_ editing: Bool) {
        isSeeking = editing

        if !editing {
            audioPlayer.seek(to: seekTime)
        }
    }

    private func togglePlayback(for song: Song) {
        performPlaybackAction {
            try audioPlayer.togglePlayback(of: song)
        }
    }

    private func playPrevious() {
        performPlaybackAction {
            try audioPlayer.playPrevious(in: playbackQueue)
        }
    }

    private func playNext() {
        performPlaybackAction {
            try audioPlayer.playNext(in: playbackQueue)
        }
    }

    private func performPlaybackAction(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            let title = currentSong?.title ?? "歌曲"
            operationErrorMessage = "无法播放 \(title)：\(error.localizedDescription)"
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
