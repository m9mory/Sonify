import Foundation

/// Кэш аудио на диске: LRU по суммарному размеру.
/// Плеер сначала ищет файл здесь, иначе скачивает и сохраняет.
actor AudioCache {
    private let directory: URL
    private let byteLimit: Int
    private let fileManager = FileManager.default
    private var inFlight: [String: Task<URL, Error>] = [:]

    init(directory: URL? = nil, byteLimit: Int = 500 * 1024 * 1024) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        self.directory = base
        self.byteLimit = byteLimit
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func cachedURL(for trackID: String) -> URL? {
        let url = directory.appendingPathComponent(Self.fileName(for: trackID))
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func makeRoomIfNeeded() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        let stats: [(url: URL, size: Int, date: Date)] = entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            guard let size = values?.fileSize, let date = values?.contentModificationDate else { return nil }
            return (url, size, date)
        }

        var total = stats.reduce(0) { $0 + $1.size }
        guard total > byteLimit else { return }
        for entry in stats.sorted(by: { $0.date < $1.date }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= byteLimit / 2 { break }
        }
    }

    func store(remote: URL, trackID: String) async throws -> URL {
        if let cached = cachedURL(for: trackID) { return cached }
        if let task = inFlight[trackID] { return try await task.value }

        let task = Task<URL, Error> {
            let (tempURL, response) = try await URLSession.shared.download(from: remote)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AppError.audioForbidden
            }
            let destination = self.directory.appendingPathComponent(Self.fileName(for: trackID))
            try? self.fileManager.removeItem(at: destination)
            try self.fileManager.moveItem(at: tempURL, to: destination)
            self.makeRoomIfNeeded()
            return destination
        }
        inFlight[trackID] = task
        defer { inFlight[trackID] = nil }
        return try await task.value
    }

    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func fileName(for trackID: String) -> String {
        let safe = trackID.replacingOccurrences(of: "/", with: "_")
        return "\(safe).audio"
    }
}
