import Foundation
import XCTest
@testable import Sonify

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testInitialLoadFillsTracksAndCursor() async {
        let repo = StubRepository()
        await repo.configure(page: Page(items: [makeTrack(id: "a"), makeTrack(id: "b")], nextCursor: "o:2"))
        let viewModel = LibraryViewModel(repository: repo)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.tracks.count, 2)
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertNil(viewModel.errorMessage)
        let cursors = await repo.requestedCursors
        XCTAssertEqual(cursors, [nil])
    }

    func testLoadMoreAppendsWithoutDuplicates() async {
        let repo = StubRepository()
        await repo.configure(page: Page(items: [makeTrack(id: "a"), makeTrack(id: "b")], nextCursor: "o:2"))
        let viewModel = LibraryViewModel(repository: repo)
        await viewModel.loadIfNeeded()

        await repo.configure(page: Page(items: [makeTrack(id: "b"), makeTrack(id: "c")], nextCursor: nil))
        await viewModel.loadMoreIfNeeded(currentItem: viewModel.tracks.last!)

        XCTAssertEqual(viewModel.tracks.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testLoadMoreIgnoredWhenNotLastItem() async {
        let repo = StubRepository()
        await repo.configure(page: Page(items: [makeTrack(id: "a"), makeTrack(id: "b")], nextCursor: "o:2"))
        let viewModel = LibraryViewModel(repository: repo)
        await viewModel.loadIfNeeded()

        await viewModel.loadMoreIfNeeded(currentItem: viewModel.tracks.first!)

        let cursors = await repo.requestedCursors
        XCTAssertEqual(cursors.count, 1, "no extra request for a non-last row")
    }

    func testNetworkErrorSurfacesMessage() async {
        let repo = StubRepository()
        await repo.configure(error: .offline)
        let viewModel = LibraryViewModel(repository: repo)

        await viewModel.reload()

        XCTAssertTrue(viewModel.tracks.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, AppError.offline.errorDescription)
    }

    func testSearchFiltersAndClears() async {
        let repo = StubRepository()
        await repo.configure(page: Page(items: [makeTrack(id: "a")], nextCursor: nil),
                             search: [makeTrack(id: "s1", title: "Static Bloom")])
        let viewModel = LibraryViewModel(repository: repo)
        await viewModel.loadIfNeeded()

        viewModel.search("static")
        try? await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(viewModel.displayed.map(\.id), ["s1"])

        viewModel.search("")
        XCTAssertEqual(viewModel.displayed.map(\.id), ["a"], "cleared query falls back to library")
    }
}
