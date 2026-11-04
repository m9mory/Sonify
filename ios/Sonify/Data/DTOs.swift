import Foundation

// DTO бэкенда (docs/API.md). Отделены от доменных моделей, чтобы изменения API
// не протекали в UI и чтобы покрываться unit-тестами декодирования.

struct PageDTO<Item: Decodable>: Decodable {
    let items: [Item]
    let nextCursor: String?
}

struct ArtistDTO: Decodable {
    let id: String
    let name: String
    let avatarUrl: String?
}

struct TrackDTO: Decodable {
    let id: String
    let title: String
    let artist: ArtistDTO
    let artworkUrl: String?
    let durationSeconds: Int
    let genre: String?
    let sourceKind: SourceKind
    let streamType: StreamType
    let playable: Bool
    let likeCount: Int
    let createdAt: Date
    let embedUrl: String?
}

struct LyricsDTO: Decodable {
    let trackId: String
    let plain: String?
    let synced: [LyricLine]?
}

struct StreamDTO: Decodable {
    let type: StreamType
    let url: String?
    let embedUrl: String?
    let mime: String?
}

struct SearchItemDTO: Decodable {
    let kind: String
    let track: TrackDTO
}

struct SearchResponseDTO: Decodable {
    let items: [SearchItemDTO]
    let nextCursor: String?
}

enum JSONCoding {
    /// ISO8601 с поддержкой дробных секунд (бэкенд отдаёт `...T17:46:02Z`).
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = formatter.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "bad date: \(raw)"))
        }
        return decoder
    }()
}

extension TrackDTO {
    func toDomain() -> Track {
        Track(
            id: id,
            title: title,
            artist: Artist(id: artist.id, name: artist.name, avatarURL: artist.avatarUrl.flatMap(URL.init(string:))),
            artworkURL: artworkUrl.flatMap(URL.init(string:)),
            duration: TimeInterval(durationSeconds),
            genre: genre,
            sourceKind: sourceKind,
            streamType: streamType,
            isPlayable: playable,
            likeCount: likeCount,
            createdAt: createdAt,
            embedURL: embedUrl.flatMap(URL.init(string:))
        )
    }
}

extension LyricsDTO {
    func toDomain() -> Lyrics {
        Lyrics(trackID: trackId, plain: plain, synced: synced)
    }
}
