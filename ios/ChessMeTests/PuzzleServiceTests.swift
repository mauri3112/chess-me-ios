import XCTest
import ChessMeCore
@testable import ChessMe

final class PuzzleServiceTests: XCTestCase {
    @MainActor
    func testProviderLevelPreservesLocalProgressAndRespectsManualChoice() {
        let model = AppModel(previewLibrary: LibrarySnapshot())
        let previousRating = model.puzzleTargetRating
        let previousAutomatic = model.automaticPuzzleLevel
        defer { model.automaticPuzzleLevel = previousAutomatic; model.puzzleTargetRating = previousRating }
        model.automaticPuzzleLevel = true
        let account = LichessAccount(id: "learner", username: "Learner", perfs: ["puzzle": .init(rating: 1800, games: 50)])
        model.adoptPuzzleLevel(from: account)
        XCTAssertEqual(model.puzzleTargetRating, 1800)
        model.recordPuzzle(DemoContent.puzzleExamples[0], correct: true, assisted: false)
        XCTAssertEqual(model.puzzleTargetRating, 1825)
        model.adoptPuzzleLevel(from: account)
        XCTAssertEqual(model.puzzleTargetRating, 1825, "An unchanged provider rating must preserve progress on this device")
        model.automaticPuzzleLevel = false
        model.puzzleTargetRating = 1400
        model.adoptPuzzleLevel(from: account, force: true)
        XCTAssertEqual(model.puzzleTargetRating, 1400)
        model.recordPuzzle(DemoContent.puzzleExamples[0], correct: true, assisted: false)
        XCTAssertEqual(model.puzzleTargetRating, 1400)
        model.automaticPuzzleLevel = true
        XCTAssertEqual(model.puzzleTargetRating, 1800, "Automatic level should resume from the saved public profile too")
        model.adoptPuzzleLevel(from: LichessAccount(id: "newlearner", username: "NewLearner", perfs: [:]))
        XCTAssertEqual(model.puzzleTargetRating, 1200, "A new account with no ratings must not inherit another player's difficulty")
    }

    func testServiceOnlySendsThemesLevelAndPublicPuzzleIDsAndValidatesEveryPly() async throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        PuzzleProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/chessme/v1/puzzles/recommendations")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            var bodyData = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    bodyData.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
            XCTAssertEqual(Set(body.keys), ["themes", "rating", "limit", "exclude"])
            XCTAssertEqual(body["limit"] as? Int, 3)
            let result: [String: Any] = ["matches": [["puzzle": try JSONSerialization.jsonObject(with: JSONEncoder().encode(puzzle)), "matchedThemes": ["mate"]]], "requested": 3, "source": "lichess", "license": "CC0"]
            return try JSONSerialization.data(withJSONObject: result)
        }
        let service = service()
        let matches = try await service.matches(themes: ["mate": 1], rating: 1700, excluding: [])
        XCTAssertEqual(matches.first?.puzzle, puzzle)
        var attempt = try PuzzlePlaythrough(puzzle: try XCTUnwrap(matches.first?.puzzle))
        XCTAssertTrue(try attempt.play(ChessMove(uci: "a2e6")))
        XCTAssertFalse(attempt.isComplete)
    }

    func testMalformedPuzzleAndUnrelatedThemeAreRejected() async throws {
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        for malformed in [true, false] {
            PuzzleProtocol.handler = { _ in
                var value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(puzzle)) as! [String: Any]
                if malformed { value["solution"] = ["a2e6", "d7h1", "f7f8"] }
                let result: [String: Any] = ["matches": [["puzzle": value, "matchedThemes": [malformed ? "mate" : "fork"]]], "requested": 3, "source": "lichess", "license": "CC0"]
                return try JSONSerialization.data(withJSONObject: result)
            }
            do {
                _ = try await service().matches(themes: ["mate": 1], rating: 1700, excluding: [])
                XCTFail("Invalid server data must not become a playable puzzle")
            } catch { }
        }
    }

    @MainActor
    func testReviewedGameMatchesAreStoredAndReusedWithoutSendingTheGame() async throws {
        let original = DemoContent.games()[0]
        let game = ChessGame(id: "pgn-native-fixture", username: "Fixture", white: "Fixture", black: "Partner", playedAt: Date(), playerSide: .white, moves: original.moves, status: "resign")
        let analysis = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, nodesPerMove: 800)).analyze(game: game)
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        var requests = 0
        PuzzleProtocol.handler = { _ in
            requests += 1
            let value: [String: Any] = ["matches": [["puzzle": try JSONSerialization.jsonObject(with: JSONEncoder().encode(puzzle)), "matchedThemes": ["mate"]]], "requested": 3, "source": "lichess", "license": "CC0"]
            return try JSONSerialization.data(withJSONObject: value)
        }
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], analyses: [analysis]), puzzleService: service())
        let originalRating = model.puzzleTargetRating
        defer { model.puzzleTargetRating = originalRating }
        await model.refreshPuzzleMatches()
        XCTAssertEqual(model.recommendedPuzzles, [puzzle])
        XCTAssertEqual(model.puzzleMatchCoverage.checked, 1)
        XCTAssertEqual(model.library.puzzleRecommendations?.first?.gameID, game.id)
        await model.refreshPuzzleMatches()
        XCTAssertEqual(requests, 1, "A saved match set for the same review should be reused")
        model.puzzleTargetRating += 200
        await model.refreshPuzzleMatches()
        XCTAssertEqual(requests, 2, "Difficulty changes must replace matches at the old level")
        let saved = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(model.library))
        XCTAssertEqual(saved.puzzleRecommendations?.first?.matches.first?.puzzle, puzzle)
    }

    @MainActor
    func testFavoritesAndPuzzlePracticeSurviveSnapshotCodingAndLegacyLibrariesLoad() throws {
        let game = DemoContent.games()[0]
        let puzzle = try XCTUnwrap(DemoContent.puzzleExamples.first)
        let model = AppModel(previewLibrary: LibrarySnapshot(games: [game], isDemo: true))
        model.toggleFavorite(game); model.toggleFavorite(puzzle)
        model.recordPuzzle(puzzle, correct: true, assisted: true)
        let saved = try JSONDecoder().decode(LibrarySnapshot.self, from: JSONEncoder().encode(model.library))
        XCTAssertEqual(saved.favoriteGameIDs, [game.id])
        XCTAssertEqual(saved.favoritePuzzles?.first, puzzle)
        XCTAssertEqual(saved.practice.first?.correctCount, 0)
        XCTAssertEqual(saved.practice.first?.assistedCount, 1)
        XCTAssertEqual(saved.practice.first?.streak, 0)
        let legacy = Data("{\"games\":[],\"analyses\":[],\"practice\":[],\"isDemo\":false,\"skippedGames\":0}".utf8)
        XCTAssertNil(try JSONDecoder().decode(LibrarySnapshot.self, from: legacy).favoritePuzzles)
        model.toggleFavorite(game); model.toggleFavorite(puzzle)
        XCTAssertTrue(model.favoriteGames.isEmpty && model.favoritePuzzles.isEmpty)
    }

    private func service() -> PuzzleService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PuzzleProtocol.self]
        return PuzzleService(baseURL: URL(string: "https://example.com/chessme")!, session: URLSession(configuration: configuration))
    }
}

private final class PuzzleProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
