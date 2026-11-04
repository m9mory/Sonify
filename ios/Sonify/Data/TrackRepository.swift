import Foundation

struct TrackRepository: TrackRepositoryProtocol {
    let client: APIClient
    let cache: AudioCache

    init(client: APIClient = APIClient(), cache: AudioCache = AudioCache()) {
        self.client = client
        self.cache = cache
    }

    func fetchTracks(limit: Int, cursor: String?) async throws -> Page<Track> {
        try await client.tracks(limit: limit, cursor: cursor)
    }

    func search(query: String) async throws -> [Track] {
        try await client.search(query: query)
    }

    func track(id: String) async throws -> Track {
        try await client.track(id: id)
    }

    func streamDescriptor(for track: Track) async throws -> StreamDescriptor {
        try await client.streamDescriptor(track: track)
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        try await client.lyrics(trackID: track.id)
    }

    /// Локальный файл для нативного плеера: из кэша или скачанный.
    func localFile(for track: Track, remote: URL) async throws -> URL {
        try await cache.store(remote: remote, trackID: track.id)
    }
}
