import AVFoundation
import ChessMeCore
import XCTest
@testable import ChessMe

final class BoardSoundTests: XCTestCase {
    func testMoveCaptureAndCheckHaveDistinctCues() throws {
        let start = ChessPosition.initial
        let e4 = try start.applying(ChessMove(uci: "e2e4"))
        XCTAssertEqual(BoardSound.transition(from: start, to: e4), .move)
        let d5 = try e4.applying(ChessMove(uci: "d7d5"))
        let capture = try d5.applying(ChessMove(uci: "e4d5"))
        XCTAssertEqual(BoardSound.transition(from: d5, to: capture), .capture)
        let check = try ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
        XCTAssertEqual(BoardSound.transition(from: check, to: try check.applying(ChessMove(uci: "a1a8"))), .check)
    }

    func testCaptureWithCheckKeepsBothIdentitiesInOneCue() throws {
        let board = try ChessPosition(fen: "r3k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
        XCTAssertEqual(BoardSound.transition(from: board, to: try board.applying(ChessMove(uci: "a1a8"))), .captureCheck)
    }

    func testEnPassantIsACaptureDespiteTheEmptyDestination() throws {
        let board = try ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")
        XCTAssertEqual(BoardSound.transition(from: board, to: try board.applying(ChessMove(uci: "e5d6"))), .capture)
    }

    func testCastlingAndPromotionAreSingleEvents() throws {
        let castle = try ChessPosition(fen: "4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        XCTAssertEqual(BoardSound.transition(from: castle, to: try castle.applying(ChessMove(uci: "e1g1"))), .move)
        let promotion = try ChessPosition(fen: "7k/P7/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(BoardSound.transition(from: promotion, to: try promotion.applying(ChessMove(uci: "a7a8q"))), .check)
    }

    func testIdenticalBoardsAndMultiMoveSeeksStaySilent() throws {
        let start = ChessPosition.initial
        let jumped = try ["e2e4", "e7e5", "g1f3"].reduce(start) { try $0.applying(ChessMove(uci: $1)) }
        XCTAssertNil(BoardSound.transition(from: start, to: start))
        XCTAssertNil(BoardSound.transition(from: start, to: jumped))
        XCTAssertNil(BoardSound.transition(from: jumped, to: start))
    }

    func testBackwardsStepDoesNotAnnounceANewCapture() throws {
        let board = try ChessPosition(fen: "r3k3/8/8/8/8/8/8/R3K3 w Q - 0 1")
        let next = try board.applying(ChessMove(uci: "a1a8"))
        XCTAssertEqual(BoardSound.transition(from: next, to: board), .move)
    }

    @MainActor func testEveryBundledCueDecodesAsShortMonoPCM() throws {
        for name in BoardSound.allCases.flatMap(\.resourceNames) {
            let url = try XCTUnwrap(BoardSoundPlayer.resourceURL(name), "Missing sound: \(name)")
            let file = try AVAudioFile(forReading: url)
            XCTAssertEqual(file.fileFormat.channelCount, 1, name)
            XCTAssertEqual(file.fileFormat.sampleRate, 48_000, name)
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.1, name)
            XCTAssertLessThan(player.duration, 0.3, name)
            XCTAssertTrue(player.prepareToPlay(), name)
        }
    }
}
