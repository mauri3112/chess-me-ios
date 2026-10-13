import Testing
import Foundation
@testable import ChessMeCore

struct ChessTests {
    @Test
    func testStartingPositionPerftThroughThreePlies() {
        #expect(perft(.initial, depth: 1) == 20)
        #expect(perft(.initial, depth: 2) == 400)
        #expect(perft(.initial, depth: 3) == 8_902)
    }

    @Test
    func testKiwipeteCastlingAndPinsPerft() throws {
        let position = try ChessPosition(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        #expect(perft(position, depth: 1) == 48)
        #expect(perft(position, depth: 2) == 2_039)
    }

    @Test
    func testCastlingMovesRookAndRemovesRights() throws {
        let position = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let move = try position.move(san: "0-0")
        #expect(move.uci == "e1g1")
        let after = try position.applying(move)
        #expect(after.squares[5] == Piece(kind: .rook, side: .white))
        #expect(after.squares[6] == Piece(kind: .king, side: .white))
        #expect(after.squares[7] == nil)
        #expect(after.castlingRights == "kq")
        let attacked = try ChessPosition(fen: "k4r2/8/8/8/8/8/8/4K2R w K - 0 1")
        #expect(!(attacked.legalMoves().contains(try ChessMove(uci: "e1g1"))))
    }

    @Test
    func testEnPassantCapturesPawnAndRejectsDiscoveredCheck() throws {
        let position = try ChessPosition(fen: "7k/8/8/5pP1/8/8/8/7K w - f6 0 1")
        let move = try position.move(san: "gxf6 e.p.")
        let next = try position.applying(move)
        #expect(next.squares[37] == nil)
        #expect(next.squares[45] == Piece(kind: .pawn, side: .white))
        #expect(next.halfmoveClock == 0)
        let pinned = try ChessPosition(fen: "7k/8/8/r4pPK/8/8/8/8 w - f6 0 1")
        #expect(!(pinned.legalMoves().contains(try ChessMove(uci: "g5f6"))))
        #expect(pinned.repetitionKey.hasSuffix("-"))
    }

    @Test
    func testAllPromotionsAndSAN() throws {
        let position = try ChessPosition(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")
        let promotions = position.legalMoves().filter { $0.from == 48 }
        #expect(Set(promotions.compactMap(\.promotion)) == Set([.queen, .rook, .bishop, .knight]))
        let knight = try position.move(san: "a8=N")
        #expect(knight.uci == "a7a8n")
        #expect(try position.applying(knight).squares[56]?.kind == .knight)
        #expect(throws: ChessError.self) { try position.applying(ChessMove(from: 48, to: 56)) }
    }

    @Test
    func testSANDisambiguationAndIllegalMoves() throws {
        let position = try ChessPosition(fen: "7k/8/8/8/8/8/8/1N3N1K w - - 0 1")
        #expect(try position.move(san: "Nbd2").uci == "b1d2")
        #expect(try position.move(san: "Nfd2").uci == "f1d2")
        #expect(throws: ChessError.self) { try position.move(san: "Nd2") }
        #expect(throws: ChessError.self) { try ChessPosition.initial.move(san: "Qh5") }
        #expect(throws: ChessError.self) { try ChessMove(uci: "e9e4") }
        #expect(throws: ChessError.self) { try ChessMove(uci: "a7a8k") }
    }

    @Test
    func testPGNMainlineIgnoresNestedVariationsCommentsAndNAGs() throws {
        let pgn = """
        [Event "Practice"]
        [White "You"]
        [Result "0-1"]

        1.f3 {a comment} e5 2. g4 (2.e4 (2.d4) d5) $2 Qh4#! 0-1
        """
        let document = try PGNDocument(pgn)
        #expect(document.moves == ["f3", "e5", "g4", "Qh4#!"])
        #expect(document.headers["White"] == "You")
        let replay = try document.replay()
        #expect(replay.count == 5)
        #expect(replay.last?.outcome() == .checkmate(winner: .black))
        #expect(throws: ChessError.self) { try PGNDocument("1. e4 {unfinished") }
        #expect(throws: ChessError.self) { try PGNDocument("1. e4 (1.d4") }
        #expect(throws: ChessError.self) { try PGNDocument("1. e4 1-0 e5") }
        #expect(throws: ChessError.self) { try PGNDocument("1. e4 e6 2. e5 e5").replay() }
    }

    @Test
    func testFENRejectsInvalidBoardsAndRoundTrips() throws {
        #expect(try ChessPosition(fen: ChessPosition.initial.fen) == .initial)
        for fen in ["8/8/8/8/8/8/8/8 w - - 0 1", "8/8/8/8/8/8/8/K6k x - - 0 1",
                    "8/8/8/8/8/8/8/K6k w K - 0 1", "8/8/8/8/8/8/8/K6k w - e3 0 1",
                    "8/8/8/8/8/8/8/K5Pk w - - 0 1"] {
            #expect(throws: ChessError.self) { try ChessPosition(fen: fen) }
        }
    }

    @Test
    func testDrawsCheckmatePrecedenceAndRepetition() throws {
        let kings = try ChessPosition(fen: "7k/8/8/8/8/8/8/7K w - - 0 1")
        #expect(kings.outcome() == .insufficientMaterial)
        let stalemate = try ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        #expect(stalemate.outcome() == .stalemate)
        let mate = try ChessPosition(fen: "7k/6Q1/6K1/8/8/8/8/8 b - - 100 1")
        #expect(mate.outcome() == .checkmate(winner: .white))
        let fifty = try ChessPosition(fen: "7k/8/8/8/8/8/4R3/7K w - - 100 1")
        #expect(fifty.outcome() == .fiftyMoveDraw)
        #expect(ChessPosition.initial.outcome(repetitionCount: 3) == .repetitionDraw)
        var position = ChessPosition.initial
        var counts = [position.repetitionKey: 1]
        for token in ["Nf3", "Nf6", "Ng1", "Ng8", "Nf3", "Nf6", "Ng1", "Ng8"] {
            position = try position.applying(position.move(san: token))
            counts[position.repetitionKey, default: 0] += 1
        }
        #expect(position.outcome(repetitionCount: counts[position.repetitionKey]!) == .repetitionDraw)
    }

    private func perft(_ position: ChessPosition, depth: Int) -> Int {
        if depth == 0 { return 1 }
        return position.legalMoves().reduce(0) { $0 + perft(position.applyingUnchecked($1), depth: depth - 1) }
    }
}
