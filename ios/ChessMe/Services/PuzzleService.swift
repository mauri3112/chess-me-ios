import Foundation
import ChessMeCore

struct PuzzleMatch: Codable, Equatable, Sendable {
    let puzzle: TrainingPuzzle
    let matchedThemes: [String]
}

struct PuzzleRecommendationSet: Codable, Equatable, Identifiable, Sendable {
    var id: String { gameID }
    let gameID: String
    let analysisSignature: String
    let rating: Int
    let matches: [PuzzleMatch]
    let matchedAt: Date
}

struct PuzzleService: Sendable {
    private let baseURL: URL?
    private let session: URLSession
    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = Self.configuredURL(), session: URLSession? = nil) {
        self.baseURL = baseURL.flatMap(CloudAnalysisService.validatedURL)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        self.session = session ?? URLSession(configuration: configuration)
    }
    static func configuredURL() -> URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ChessMePuzzleBaseURL") as? String else { return nil }
        return URL(string: value).flatMap(CloudAnalysisService.validatedURL)
    }
    func matches(themes: [String: Double], rating: Int, excluding: [String]) async throws -> [PuzzleMatch] {
        guard let baseURL else { throw CloudError.unconfigured }
        struct Query: Encodable { let themes: [String: Double]; let rating: Int; let limit: Int; let exclude: [String] }
        struct Response: Decodable { let matches: [PuzzleMatch]; let requested: Int; let source: String; let license: String }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/puzzles/recommendations"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Query(themes: themes, rating: min(3000, max(400, rating)), limit: 3, exclude: Array(excluding.suffix(100))))
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 100_000 else { throw CloudError.invalidResponse }
            data.append(byte)
        }
        guard let response = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        if response.statusCode == 429 { throw PuzzleServiceError.busy }
        guard response.statusCode == 200 else { throw PuzzleServiceError.unavailable }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.source == "lichess", result.license == "CC0", result.requested == 3, result.matches.count <= 3,
              Set(result.matches.map { $0.puzzle.id }).count == result.matches.count else { throw CloudError.invalidResponse }
        for match in result.matches {
            let puzzle = match.puzzle
            guard puzzle.source == "lichess", puzzle.license == "CC0", (400...3000).contains(puzzle.rating),
                  puzzle.id.range(of: "^[A-Za-z0-9]{5,12}$", options: .regularExpression) != nil,
                  puzzle.url.absoluteString == "https://lichess.org/training/\(puzzle.id)",
                  !excluding.contains(puzzle.id), !match.matchedThemes.isEmpty,
                  match.matchedThemes.allSatisfy({ themes[$0] != nil && puzzle.themes.contains($0) }) else { throw CloudError.invalidResponse }
            _ = try PuzzlePlaythrough(puzzle: puzzle)
        }
        return result.matches
    }
}

enum PuzzleServiceError: LocalizedError {
    case unavailable, busy
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Puzzle matching is unavailable. Your saved puzzles and lessons still work offline."
        case .busy: return "Puzzle matching is busy. Try again in a minute."
        }
    }
}
