import Foundation
@testable import Sonify

/// Заглушка репозитория для юнит-тестов ViewModel (без сети).
actor StubRepository: TrackRepositoryProtocol {
    private(set) var requestedCursors: [String?] = []
    var page = Page<Track>(items: [], nextCursor: nil)
    var searchResults: [Track] = []
    var streamResult = StreamDescriptor(kind: .unavailable, url: nil, embedURL: nil)
    var error: AppError?
    var lyricsResult: Lyrics?

    func configure(page: Page<Track>? = nil, search: [Track]? = nil, error: AppError? = nil) {
        if let page { self.page = page }
        if let search { self.searchResults = search }
        self.error = error
    }

    func fetchTracks(limit: Int, cursor: String?) async throws -> Page<Track> {
        requestedCursors.append(cursor)
        if let error { throw error }
        return page
    }

    func search(query: String) async throws -> [Track] {
        if let error { throw error }
        return searchResults
    }

    func track(id: String) async throws -> Track {
        if let error { throw error }
        guard let found = page.items.first(where: { $0.id == id }) else { throw AppError.notFound }
        return found
    }

    func streamDescriptor(for track: Track) async throws -> StreamDescriptor {
        if let error { throw error }
        return streamResult
    }

    func lyrics(for track: Track) async throws -> Lyrics? {
        if let error { throw error }
        return lyricsResult
    }
}

func makeTrack(
    id: String = "trk_1",
    title: String = "Neon Drift",
    artist: String = "Lumen",
    sourceKind: SourceKind = .local,
    streamType: StreamType = .direct
) -> Track {
    Track(
        id: id,
        title: title,
        artist: Artist(id: "art_1", name: artist, avatarURL: nil),
        artworkURL: nil,
        duration: 214,
        genre: "synthwave",
        sourceKind: sourceKind,
        streamType: streamType,
        isPlayable: true,
        likeCount: 10,
        createdAt: Date(timeIntervalSince1970: 1_760_000_000),
        embedURL: streamType == .embed ? URL(string: "https://w.soundcloud.com/player/?url=x") : nil
    )
}
