import Foundation

/// Реализация API-клиента поверх HTTPTransport.
final class APIClient: @unchecked Sendable {
    private let baseURL: URL
    private let transport: HTTPTransportProtocol
    private let session: URLSession

    init(baseURL: URL = AppConfig.apiBaseURL, transport: HTTPTransportProtocol? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConfig.requestTimeout
        configuration.waitsForConnectivity = false
        let urlSession = URLSession(configuration: configuration)
        self.baseURL = baseURL
        self.session = urlSession
        self.transport = transport ?? HTTPTransport(session: urlSession)
    }

    func tracks(limit: Int, cursor: String?) async throws -> Page<Track> {
        var components = URLComponents(url: endpoint("tracks"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        components.queryItems = query
        let dto: PageDTO<TrackDTO> = try await get(components.url!)
        return Page(items: dto.items.map { $0.toDomain() }, nextCursor: dto.nextCursor)
    }

    func search(query: String) async throws -> [Track] {
        var components = URLComponents(url: endpoint("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let dto: SearchResponseDTO = try await get(components.url!)
        return dto.items.map { $0.track.toDomain() }
    }

    func track(id: String) async throws -> Track {
        let dto: TrackDTO = try await get(endpoint("tracks/\(id)"))
        return dto.toDomain()
    }

    func lyrics(trackID: String) async throws -> Lyrics? {
        do {
            let dto: LyricsDTO = try await get(endpoint("tracks/\(trackID)/lyrics"))
            return dto.toDomain()
        } catch AppError.notFound {
            return nil
        }
    }

    /// `/stream` отвечает 302 на прямой URL или JSON для embed.
    func streamDescriptor(track: Track) async throws -> StreamDescriptor {
        if track.embedURL != nil || track.sourceKind == .soundcloud {
            // Для embed-треков берём URL виджета сразу из трека, не дёргая редирект.
            let dto: StreamDTO? = try? await get(endpoint("tracks/\(track.id)/stream"))
            return StreamDescriptor(kind: .embed, url: nil, embedURL: dto?.embedUrl.flatMap(URL.init(string:)) ?? track.embedURL)
        }
        let url = endpoint("tracks/\(track.id)/stream")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, http) = try await transport.data(for: request)
        guard let finalURL = http.url, finalURL != url else {
            if let data = try? await (transport.data(for: request)).0,
               let dto = try? JSONCoding.decoder.decode(StreamDTO.self, from: data) {
                return StreamDescriptor(kind: .embed, url: nil, embedURL: dto.embedUrl.flatMap(URL.init(string:)))
            }
            throw AppError.audioForbidden
        }
        return StreamDescriptor(kind: .direct, url: finalURL, embedURL: nil)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await transport.data(for: request)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw AppError.decoding(String(describing: error))
        }
    }
}
