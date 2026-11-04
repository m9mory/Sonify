import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var tracks: [Track] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var searchResults: [Track] = []
    var searchQuery: String = ""

    private let repository: TrackRepositoryProtocol
    private var nextCursor: String?
    private var currentTask: Task<Void, Never>?

    init(repository: TrackRepositoryProtocol = TrackRepository()) {
        self.repository = repository
    }

    var displayed: [Track] {
        searchQuery.isEmpty ? tracks : searchResults
    }

    var canLoadMore: Bool { nextCursor != nil && searchQuery.isEmpty }

    func loadIfNeeded() async {
        guard tracks.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repository.fetchTracks(limit: 20, cursor: nil)
            tracks = page.items
            nextCursor = page.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentItem: Track) async {
        guard canLoadMore, !isLoadingMore, let last = tracks.last, last.id == currentItem.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.fetchTracks(limit: 20, cursor: nextCursor)
            let known = Set(tracks.map(\.id))
            tracks += page.items.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Поиск с дебаунсом 300 мс, чтобы не дёргать API на каждый символ.
    func search(_ query: String) {
        searchQuery = query
        currentTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        currentTask = Task { [repository] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await repository.search(query: trimmed)
                guard !Task.isCancelled else { return }
                await MainActor.run { self.searchResults = results }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}
