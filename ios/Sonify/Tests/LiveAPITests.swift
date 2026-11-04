import Foundation
import XCTest
@testable import Sonify

/// Интеграционные тесты iOS-клиента против живого HTTP.
/// - В CI бэкенд запущен на 127.0.0.1:8080 (см. .github/workflows/ios.yml).
/// - Локально без бэкенда тесты, которым он нужен, пропускаются (XCTSkip), а не падают.
final class LiveAPITests: XCTestCase {
    private let liveBaseURL = URL(string: "http://127.0.0.1:8080/api/v1")!

    private func backendIsUp() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8080/health")!)
        request.timeoutInterval = 2
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func testHealthEndpoint() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:8080/health")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        struct Health: Decodable { let status: String; let db: String }
        let health = try JSONDecoder().decode(Health.self, from: data)
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.db, "ok")
    }

    func testTracksPageFromLiveBackend() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let page = try await client.tracks(limit: 5, cursor: nil)
        XCTAssertFalse(page.items.isEmpty, "seed data expected")
        XCTAssertTrue(page.items.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })
        XCTAssertTrue(page.items.allSatisfy { $0.duration > 0 || $0.sourceKind == .soundcloud })
    }

    func testCursorPaginationFromLiveBackend() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let first = try await client.tracks(limit: 2, cursor: nil)
        guard let cursor = first.nextCursor else { throw XCTSkip("not enough seed tracks for pagination") }
        let second = try await client.tracks(limit: 2, cursor: cursor)
        let firstIDs = Set(first.items.map(\.id))
        XCTAssertFalse(second.items.isEmpty)
        XCTAssertTrue(Set(second.items.map(\.id)).isDisjoint(with: firstIDs))
    }

    func testDirectStreamDescriptorFromLiveBackend() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let page = try await client.tracks(limit: 20, cursor: nil)
        guard let local = page.items.first(where: { $0.canPlayNatively }) else {
            throw XCTSkip("no native-playable seed track")
        }
        let descriptor = try await client.streamDescriptor(track: local)
        XCTAssertEqual(descriptor.kind, .direct)
        XCTAssertEqual(descriptor.url?.scheme, "http")

        // Аудиофайл реально отдаётся и кэшируется на диск.
        let cache = AudioCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("sonify-live-\(UUID().uuidString)"))
        let file = try await cache.store(remote: XCTUnwrap(descriptor.url), trackID: local.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertGreaterThan((attributes[.size] as? Int) ?? 0, 10_000)
        let cached = await cache.cachedURL(for: local.id)
        XCTAssertEqual(cached, file)
        await cache.clear()
    }

    /// AVAudioFile читает файл как локальный: важно, что бэкенд отдаёт HTTP Range.
    func testAudioSupportsRangeRequests() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let page = try await client.tracks(limit: 20, cursor: nil)
        guard let local = page.items.first(where: { $0.canPlayNatively }),
              let descriptor = try? await client.streamDescriptor(track: local),
              let audioURL = descriptor.url else {
            throw XCTSkip("no native-playable seed track")
        }

        var request = URLRequest(url: audioURL)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 206, "Range request should return 206 Partial Content")
        XCTAssertEqual(data.count, 1024)
    }

    func testLyricsFromLiveBackend() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let page = try await client.tracks(limit: 20, cursor: nil)
        var found = false
        for track in page.items where track.sourceKind == .local {
            if let lyrics = try await client.lyrics(trackID: track.id), !lyrics.isEmpty {
                found = true
                XCTAssertFalse(lyrics.trackID.isEmpty)
                break
            }
        }
        XCTAssertTrue(found, "seed data should contain lyrics for at least one track")
    }

    func testSoundCloudEmbedDescriptor() async throws {
        try XCTSkipUnless(await backendIsUp(), "backend is not running on 127.0.0.1:8080")
        let client = APIClient(baseURL: liveBaseURL)
        let page = try await client.tracks(limit: 50, cursor: nil)
        guard let sc = page.items.first(where: { $0.sourceKind == .soundcloud }) else {
            throw XCTSkip("no soundcloud seed track")
        }
        let descriptor = try await client.streamDescriptor(track: sc)
        XCTAssertEqual(descriptor.kind, .embed)
        XCTAssertEqual(descriptor.embedURL?.host, "w.soundcloud.com")
    }
}
