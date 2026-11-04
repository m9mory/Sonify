import Foundation

/// Контракт библиотеки треков для слоя UI. Реализация — Data/TrackRepository.
protocol TrackRepositoryProtocol: Sendable {
    func fetchTracks(limit: Int, cursor: String?) async throws -> Page<Track>
    func search(query: String) async throws -> [Track]
    func track(id: String) async throws -> Track
    func streamDescriptor(for track: Track) async throws -> StreamDescriptor
    func lyrics(for track: Track) async throws -> Lyrics?
}

extension TrackRepositoryProtocol {
    func fetchTracks() async throws -> Page<Track> {
        try await fetchTracks(limit: 20, cursor: nil)
    }
}
