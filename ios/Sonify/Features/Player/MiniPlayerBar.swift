import SwiftUI

struct MiniPlayerBar: View {
    @Environment(PlayerService.self) private var player
    let track: Track
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            progressLine
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "music.note").font(.caption).foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.footnote.weight(.semibold)).lineLimit(1)
                    Text(track.artist.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 30, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            let fraction = player.duration > 0 ? min(1, player.position / player.duration) : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.indigo.opacity(0.15))
                Rectangle().fill(Color.indigo).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 2)
    }
}
