import SwiftUI

struct LibraryView: View {
    @Environment(PlayerService.self) private var player
    @State private var viewModel = LibraryViewModel()

    let onPlay: (Track, [Track]) -> Void

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.tracks.isEmpty {
                ProgressView("Загружаем треки…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.tracks.isEmpty {
                ContentUnavailableView {
                    Label("Не удалось загрузить", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Повторить") { Task { await viewModel.reload() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if viewModel.displayed.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            } else {
                trackList
            }
        }
        .navigationTitle("Sonify")
        .searchable(text: Binding(
            get: { viewModel.searchQuery },
            set: { viewModel.search($0) }
        ), prompt: "Трек или артист")
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.reload() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("beta")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private var trackList: some View {
        List {
            Section {
                ForEach(viewModel.displayed) { track in
                    TrackRowView(track: track, isCurrent: player.currentTrack?.id == track.id,
                                 isPlaying: player.currentTrack?.id == track.id && player.state == .playing)
                        .contentShape(Rectangle())
                        .onTapGesture { onPlay(track, viewModel.displayed) }
                        .task { await viewModel.loadMoreIfNeeded(currentItem: track) }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                Text(viewModel.searchQuery.isEmpty ? "Лента" : "Результаты поиска")
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .listStyle(.plain)
        .animation(.default, value: viewModel.displayed.map(\.id))
    }
}

struct TrackRowView: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.indigo : .primary)
                HStack(spacing: 6) {
                    Text(track.artist.name)
                    if let genre = track.genre {
                        Text("· \(genre)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if track.sourceKind == .soundcloud {
                    Text("SC")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
                Text(track.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isCurrent {
                Image(systemName: isPlaying ? "waveform" : "pause.circle")
                    .foregroundStyle(.indigo)
                    .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            }
        }
        .padding(.vertical, 2)
    }

    private var artwork: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(
                    colors: [.indigo.opacity(0.85), .purple.opacity(0.6), .blue.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 52, height: 52)
                .overlay {
                    Image(systemName: track.canPlayNatively ? "music.note" : "cloud")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
        }
    }
}
