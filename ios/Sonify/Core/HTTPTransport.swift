import Foundation

/// Транспорт: URLSession + async/await, маппинг ошибок, простой ретрай.
protocol HTTPTransportProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct HTTPTransport: HTTPTransportProtocol {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var lastError: Error?

        while attempt <= AppConfig.maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AppError.unknown("Некорректный ответ сети")
                }
                if Self.isRetryable(status: http.statusCode), attempt < AppConfig.maxRetries {
                    attempt += 1
                    try await Task.sleep(nanoseconds: Self.backoff(attempt))
                    continue
                }
                try Self.validate(http: http, data: data)
                return (data, http)
            } catch let error as URLError {
                lastError = error
                guard Self.isTransient(error), attempt < AppConfig.maxRetries else {
                    throw Self.mapURLError(error)
                }
                attempt += 1
                try await Task.sleep(nanoseconds: Self.backoff(attempt))
            }
        }
        throw lastError.map(Self.mapURLError) ?? AppError.unknown("Неизвестная сетевая ошибка")
    }

    private static func isRetryable(status: Int) -> Bool {
        status == 408 || status == 429 || (500..<600).contains(status)
    }

    private static func isTransient(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            true
        default:
            false
        }
    }

    private static func backoff(_ attempt: Int) -> UInt64 {
        let base = UInt64(200_000_000) * UInt64(attempt)
        let jitter = UInt64.random(in: 0...80_000_000)
        return base + jitter
    }

    private static func mapURLError(_ error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost:
            .offline
        case .timedOut:
            .unknown("Сервер не ответил вовремя")
        default:
            .unknown(error.localizedDescription)
        }
    }

    private static func validate(http: HTTPURLResponse, data: Data) throws {
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw AppError.unauthorized
        case 404:
            throw AppError.notFound
        default:
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error.message
            throw AppError.server(status: http.statusCode, message: message)
        }
    }
}

struct ErrorEnvelope: Decodable {
    struct Body: Decodable { let code: String; let message: String }
    let error: Body
}
