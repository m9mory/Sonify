import Foundation

/// Источник трека. Значение приходит с бэкенда и определяет способ воспроизведения.
enum SourceKind: String, Codable, Sendable {
    case local
    case soundcloud
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SourceKind(rawValue: raw) ?? .unknown
    }
}

/// Как iOS будет играть трек: нативно через AVPlayer или официальным SoundCloud-эмбедом.
enum StreamType: String, Codable, Sendable {
    case direct
    case embed
    case unavailable
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StreamType(rawValue: raw) ?? .unknown
    }

    var isNativePlayable: Bool { self == .direct }
}

struct Artist: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let avatarURL: URL?
}

struct Track: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: Artist
    let artworkURL: URL?
    let duration: TimeInterval
    let genre: String?
    let sourceKind: SourceKind
    let streamType: StreamType
    let isPlayable: Bool
    let likeCount: Int
    let createdAt: Date
    /// Для треков SoundCloud — URL официального плеера-виджета.
    let embedURL: URL?

    var durationText: String {
        guard duration > 0 else { return "—:—" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var canPlayNatively: Bool { isPlayable && streamType.isNativePlayable }
}

struct Page<T: Sendable>: Sendable {
    let items: [T]
    let nextCursor: String?
}

struct LyricLine: Codable, Hashable, Sendable {
    let time: Double
    let line: String
    let endTime: Double?

    enum CodingKeys: String, CodingKey {
        case time = "t"
        case line
        case endTime
    }
}

struct Lyrics: Sendable {
    let trackID: String
    let plain: String?
    let synced: [LyricLine]?

    var isEmpty: Bool { (plain ?? "").isEmpty && (synced ?? []).isEmpty }
}

struct StreamDescriptor: Sendable {
    enum Kind: String, Sendable { case direct, embed, unavailable }
    let kind: Kind
    let url: URL?
    let embedURL: URL?
}

enum AppError: LocalizedError, Equatable {
    case offline
    case unauthorized
    case notFound
    case server(status: Int, message: String?)
    case decoding(String)
    case invalidURL
    case audioForbidden
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .offline: "Нет соединения. Проверьте интернет и локальную сеть."
        case .unauthorized: "Нужно войти в аккаунт."
        case .notFound: "Не найдено."
        case let .server(status, message): message ?? "Ошибка сервера (\(status))."
        case let .decoding(detail): "Не удалось разобрать ответ сервера: \(detail)"
        case .invalidURL: "Некорректный URL."
        case .audioForbidden: "Этот трек нельзя воспроизвести напрямую."
        case let .unknown(message): message
        }
    }
}
