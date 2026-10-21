import XCTest
import ChessMeCore
@testable import ChessMe

final class ReviewPlaybackTests: XCTestCase {
    @MainActor func testASeekDuringLinePreparationKeepsTheRequestedBoard() async throws {
        let playback = ReviewLinePlayback()
        let moves = ["e2e4", "e7e5", "g1f3"]
        let loading = Task { await playback.load(fen: ChessPosition.initial.fen, moves: moves) }
        await Task.yield()
        playback.seek(2)
        await loading.value
        XCTAssertEqual(playback.cursor, 2)
        XCTAssertEqual(playback.proof?.positions[2], try ChessPosition.initial.applying(ChessMove(uci: "e2e4")).applying(ChessMove(uci: "e7e5")))
    }

    @MainActor func testAnOldPlaybackCannotMoveANewlySelectedLine() async throws {
        let playback = ReviewLinePlayback()
        await playback.load(fen: ChessPosition.initial.fen, moves: ["e2e4", "e7e5"])
        playback.play(reduceMotion: false)
        XCTAssertTrue(playback.isPlaying)
        await playback.load(fen: ChessPosition.initial.fen, moves: ["d2d4", "d7d5"], at: 1)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(playback.cursor, 1)
        XCTAssertEqual(playback.proof?.moves, ["d2d4", "d7d5"])
    }

    @MainActor func testReappearingOnTheSameLinePreservesTheInspectedPosition() async {
        let playback = ReviewLinePlayback()
        let moves = ["e2e4", "e7e5", "g1f3"]
        await playback.load(fen: ChessPosition.initial.fen, moves: moves, at: 0)
        playback.seek(2)
        await playback.load(fen: ChessPosition.initial.fen, moves: moves, at: 0)
        XCTAssertEqual(playback.cursor, 2)
        playback.seek(1)
        XCTAssertEqual(playback.cursor, 1, "An explicit plan selection can still seek within the same line")
    }

    @MainActor func testPausingPlaybackKeepsTheBoardAndCancelsTheNextMove() async throws {
        let playback = ReviewLinePlayback()
        await playback.load(fen: ChessPosition.initial.fen, moves: ["e2e4", "e7e5"], at: 1)
        playback.play(reduceMotion: false)
        playback.stop()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(playback.cursor, 1)
        XCTAssertFalse(playback.isPlaying)
    }

    @MainActor func testEnteringSampleFlushesThePendingRealBookmarkBeforeReplacingTheLibrary() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try LocalLibrary(url: directory.appendingPathComponent("library.json"))
        let game = try XCTUnwrap(DemoContent.games().first)
        try storage.save(LibrarySnapshot(games: [game]))
        let model = AppModel(libraryStorage: storage)
        defer { model.deviceAnalysis.clear() }
        let bookmark = ReviewBookmark(gameID: game.id, revision: "saved", place: .moment,
                                      momentID: "real-moment", step: 1, visited: ["real-moment"])
        model.saveBookmark(bookmark)
        XCTAssertEqual(model.reviewState.bookmarks, [bookmark])
        XCTAssertNil(try storage.load().review?.bookmarks.first, "The navigation write is still pending")
        model.loadDemo() // No yield: the debounce has not run yet.
        let restored = try storage.load()
        XCTAssertFalse(restored.isDemo)
        XCTAssertEqual(restored.review?.bookmarks, [bookmark])
        model.pauseAnalysis()
        let deadline = Date().addingTimeInterval(2)
        while model.isBusy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.isBusy)
        model.exitDemo()
        XCTAssertEqual(model.reviewState.bookmarks, [bookmark])
    }

    @MainActor func testFailedFlushKeepsTheRealLibraryOpenAndRetriesBeforeEnteringSample() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try LocalLibrary(url: directory.appendingPathComponent("library.json"))
        let game = try XCTUnwrap(DemoContent.games().first)
        try storage.save(LibrarySnapshot(games: [game]))
        let model = AppModel(libraryStorage: storage)
        defer { model.deviceAnalysis.clear() }
        let bookmark = ReviewBookmark(gameID: game.id, revision: "saved", place: .moment,
                                      momentID: "retained-moment", step: 1, visited: ["retained-moment"])
        model.saveBookmark(bookmark)
        try FileManager.default.removeItem(at: directory)
        model.loadDemo()
        XCTAssertFalse(model.isDemo, "A failed real-data write must keep the real library open")
        XCTAssertEqual(model.reviewState.bookmarks, [bookmark])
        XCTAssertNotNil(model.reviewSaveError)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.loadDemo()
        XCTAssertTrue(model.isDemo)
        XCTAssertNil(model.reviewSaveError)
        XCTAssertEqual(try storage.load().review?.bookmarks, [bookmark])
        model.pauseAnalysis()
    }

    func testQueuedNavigationCannotOverwriteANewerExplicitSaveOrRecreateDeletedData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try LocalLibrary(url: directory.appendingPathComponent("library.json"))
        var older = LibrarySnapshot(); older.coverageNote = "older navigation"
        var newer = LibrarySnapshot(); newer.coverageNote = "explicit save"
        storage.saveInBackground(older) { result in if case .failure(let error) = result { XCTFail(error.localizedDescription) } }
        try storage.save(newer)
        XCTAssertEqual(try storage.load().coverageNote, "explicit save")
        storage.saveInBackground(older) { result in if case .failure(let error) = result { XCTFail(error.localizedDescription) } }
        try storage.delete()
        XCTAssertTrue(try storage.load().games.isEmpty)
        XCTAssertNil(try storage.load().coverageNote)
    }

    func testBackgroundWriteFailureIsReportedAndTheWriterCanRecover() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try LocalLibrary(url: directory.appendingPathComponent("library.json"))
        let failed = expectation(description: "The failed navigation save is reported")
        storage.saveInBackground(LibrarySnapshot()) { result in
            if case .failure = result { failed.fulfill() } else { XCTFail("Missing directory should fail the write") }
        }
        await fulfillment(of: [failed], timeout: 3)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var value = LibrarySnapshot(); value.coverageNote = "recovered"
        try storage.save(value)
        XCTAssertEqual(try storage.load().coverageNote, "recovered")
    }
}
