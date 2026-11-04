import SwiftUI

@main
struct SonifyApp: App {
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .preferredColorScheme(nil)
                .tint(.indigo)
        }
    }
}

struct RootView: View {
    @Environment(PlayerService.self) private var player
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            LibraryView { track, queue in
                Task {
                    await player.play(track: track, queue: queue)
                    showPlayer = true
                }
            }
            .navigationDestination(isPresented: $showPlayer) {
                PlayerView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let track = player.currentTrack {
                MiniPlayerBar(track: track) { showPlayer = true }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
