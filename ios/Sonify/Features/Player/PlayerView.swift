import SwiftUI

struct PlayerView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var showEqualizer = false
    @State private var scrubPosition: Double?

    var body: some View {
        let track = player.currentTrack

        ScrollView {
            VStack(spacing: 22) {
                cover(track: track)
                titleBlock(track: track)

                if let track, track.canPlayNatively {
                    nativePlayerControls
                } else if let track, let embed = track.embedURL {
                    embedSection(embed: embed)
                } else {
                    Text("Трек недоступен для воспроизведения")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let failure = failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .navigationTitle("Сейчас играет")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.down") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showEqualizer = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(!(track?.canPlayNatively ?? false))
            }
        }
        .sheet(isPresented: $showEqualizer) {
            EqualizerView()
                .presentationDetents([.medium, .large])
        }
    }

    private var failureMessage: String? {
        if case let .failed(message) = player.state { return message }
        return nil
    }

    // MARK: - Sections

    private func cover(track: Track?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(
                    colors: [.indigo, .purple.opacity(0.8), .blue.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Image(systemName: track?.sourceKind == .soundcloud ? "cloud.fill" : "waveform.circle.fill")
                .font(.system(size: 84, weight: .thin))
                .foregroundStyle(.white.opacity(0.85))
                .symbolEffect(.pulse.byLayer, isActive: player.state == .playing)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 320)
        .shadow(color: .indigo.opacity(0.25), radius: 24, y: 10)
    }

    private func titleBlock(track: Track?) -> some View {
        VStack(spacing: 6) {
            Text(track?.title ?? "Ничего не играет")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(track?.artist.name ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let track {
                HStack(spacing: 8) {
                    Tag(text: track.sourceKind == .soundcloud ? "SoundCloud" : "Sonify",
                        tint: track.sourceKind == .soundcloud ? .orange : .indigo)
                    if let genre = track.genre { Tag(text: genre, tint: .secondary) }
                }
            }
        }
    }

    private var nativePlayerControls: some View {
        VStack(spacing: 16) {
            Slider(
                value: Binding(
                    get: { scrubPosition ?? player.position },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let value = scrubPosition {
                        player.seek(to: value)
                        scrubPosition = nil
                    }
                }
            )
            .tint(.indigo)

            HStack {
                Text(timeText(scrubPosition ?? player.position))
                Spacer()
                Text(timeText(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 34) {
                Button { player.isShuffleEnabled.toggle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(player.isShuffleEnabled ? Color.indigo : .secondary)
                }
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        if case .loading = player.state {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 30))
                                .offset(x: player.state == .playing ? 0 : 2)
                        }
                    }
                    .frame(width: 74, height: 74)
                    .background(Color.indigo, in: Circle())
                    .foregroundStyle(.white)
                }
                .disabled(player.isBuffering)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                Button { player.repeatMode = player.repeatMode.next } label: {
                    Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                        .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.indigo)
                }
            }
            .font(.title3)
            .padding(.vertical, 4)
        }
    }

    private func embedSection(embed: URL) -> some View {
        VStack(spacing: 10) {
            SoundCloudEmbedView(url: embed)
                .frame(height: 166)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("Играет через официальный плеер SoundCloud. Эквалайзер и оффлайн для этого источника недоступны.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func timeText(_ value: TimeInterval) -> String {
        guard value.isFinite, value > 0 else { return "0:00" }
        let total = Int(value)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct Tag: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}
