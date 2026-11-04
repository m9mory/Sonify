import Foundation
import XCTest
@testable import Sonify

/// Тесты контракта: декодирование ответов бэкенда в доменные модели.
/// Запуск: xcodebuild test -scheme Sonify -destination 'platform=iOS Simulator,name=iPhone 16'
final class APIContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decoder.decode(type, from: Data(json.utf8))
    }

    func testTracksPageDecoding() throws {
        let json = """
        {
          "items": [
            {
              "id": "trk_1",
              "title": "Neon Drift",
              "artist": {"id": "art_1", "name": "Lumen", "avatarUrl": null},
              "artworkUrl": null,
              "durationSeconds": 214,
              "genre": "synthwave",
              "sourceKind": "local",
              "streamType": "direct",
              "playable": true,
              "likeCount": 12,
              "createdAt": "2026-11-04T17:46:02Z"
            }
          ],
          "nextCursor": "o:20"
        }
        """
        let page: PageDTO<TrackDTO> = try decode(PageDTO<TrackDTO>.self, json)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.nextCursor, "o:20")

        let track = page.items[0].toDomain()
        XCTAssertEqual(track.title, "Neon Drift")
        XCTAssertEqual(track.artist.name, "Lumen")
        XCTAssertEqual(track.duration, 214)
        XCTAssertEqual(track.sourceKind, .local)
        XCTAssertEqual(track.streamType, .direct)
        XCTAssertTrue(track.canPlayNatively)
        XCTAssertEqual(track.durationText, "3:34")
    }

    func testUnknownEnumsDoNotCrashDecoding() throws {
        let json = """
        {
          "id": "trk_2",
          "title": "Future",
          "artist": {"id": "art_2", "name": "X", "avatarUrl": null},
          "artworkUrl": null,
          "durationSeconds": 0,
          "genre": null,
          "sourceKind": "apple_music",
          "streamType": "hls",
          "playable": true,
          "likeCount": 0,
          "createdAt": "2026-11-04T17:46:02Z"
        }
        """
        let dto: TrackDTO = try decode(TrackDTO.self, json)
        XCTAssertEqual(dto.sourceKind, .unknown)
        XCTAssertEqual(dto.streamType, .unknown)
        XCTAssertFalse(dto.toDomain().canPlayNatively)
    }

    func testSoundCloudEmbedTrack() throws {
        let json = """
        {
          "id": "trk_3",
          "title": "SC track",
          "artist": {"id": "art_3", "name": "SC", "avatarUrl": null},
          "artworkUrl": null,
          "durationSeconds": 0,
          "genre": null,
          "sourceKind": "soundcloud",
          "streamType": "embed",
          "playable": true,
          "likeCount": 1,
          "createdAt": "2026-11-04T17:46:02Z",
          "embedUrl": "https://w.soundcloud.com/player/?url=https%3A%2F%2Fsoundcloud.com%2Fforss%2Fflickermood"
        }
        """
        let track = try decode(TrackDTO.self, json).toDomain()
        XCTAssertEqual(track.sourceKind, .soundcloud)
        XCTAssertEqual(track.streamType, .embed)
        XCTAssertFalse(track.canPlayNatively)
        XCTAssertNotNil(track.embedURL)
    }

    func testLyricsDecoding() throws {
        let json = """
        {"trackId":"trk_1","plain":"line one","synced":[{"t":0.0,"line":"line one"},{"t":8.5,"line":"line two"}]}
        """
        let lyrics = try decode(LyricsDTO.self, json).toDomain()
        XCTAssertEqual(lyrics.synced?.count, 2)
        XCTAssertEqual(lyrics.synced?[1].time, 8.5)
        XCTAssertEqual(lyrics.synced?[1].line, "line two")
        XCTAssertFalse(lyrics.isEmpty)
    }

    func testStreamDescriptorDecoding() throws {
        let embed = try decode(StreamDTO.self, """
        {"type":"embed","embedUrl":"https://w.soundcloud.com/player/?url=x"}
        """)
        XCTAssertEqual(embed.type, .embed)
        XCTAssertNotNil(embed.embedUrl)
    }

    func testErrorEnvelopeDecoding() throws {
        let envelope = try decode(ErrorEnvelope.self, """
        {"error":{"code":"not_found","message":"track not found"}}
        """)
        XCTAssertEqual(envelope.error.code, "not_found")
    }

    func testEqualizerPresetsAreValid() {
        let bands = EqualizerPreset.bandFrequencies.count
        XCTAssertEqual(bands, 10)
        for preset in EqualizerPreset.all {
            XCTAssertEqual(preset.gains.count, bands, "preset \(preset.name) must have \(bands) bands")
            XCTAssertTrue(preset.gains.allSatisfy { $0 >= -12 && $0 <= 12 }, "preset \(preset.name) out of range")
        }
        XCTAssertEqual(EqualizerPreset.bandFrequencies, EqualizerPreset.bandFrequencies.sorted())
    }

    func testAudioCacheFileNames() async {
        let cache = AudioCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("sonify-test-\(UUID().uuidString)"), byteLimit: 1024)
        let cached = await cache.cachedURL(for: "trk_123")
        XCTAssertNil(cached)
        await cache.clear()
    }
}
