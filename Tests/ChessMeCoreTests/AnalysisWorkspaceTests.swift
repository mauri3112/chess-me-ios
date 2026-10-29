import Testing
@testable import ChessMeCore

struct AnalysisWorkspaceTests {
    @Test func initialStudyUndoResetAndIllegalMove() throws {
        var study = AnalysisWorkspace()
        #expect(study.position == .initial)
        #expect(throws: ChessError.self) { try study.play(ChessMove(uci: "e2e5")) }
        #expect(study.moves.isEmpty)
        try study.play(ChessMove(uci: "e2e4"))
        try study.play(ChessMove(uci: "e7e5"))
        #expect(study.notations == ["e4", "e5"])
        #expect(study.repetitionHistory.count == 2)
        study.undo()
        #expect(study.position.sideToMove == .black)
        #expect(study.repetitionHistory == [ChessPosition.initial.repetitionKey])
        study.reset()
        study.undo()
        #expect(study.position == .initial)
        #expect(study.moves.isEmpty)
        #expect(study.repetitionHistory.isEmpty)
    }

    @Test func blackRootRetainsMoveNumberAndPGNSetup() throws {
        let fen = "4k2r/8/8/8/8/8/8/R3K3 b - - 0 23"
        var study = try AnalysisWorkspace(fen: fen)
        try study.play(ChessMove(uci: "h8h7"))
        try study.play(ChessMove(uci: "a1a2"))
        #expect(study.pgn.contains("[FEN \"\(fen)\"]"))
        #expect(study.pgn.contains("23... Rh7 24. Ra2 *"))
        study.reset()
        #expect(study.position.fen == fen)
    }

    @Test func promotionAndHistoryAreLegalAndUndoable() throws {
        var study = try AnalysisWorkspace(fen: "7k/P7/8/8/8/8/8/4K3 w - - 0 1")
        let root = study.position
        #expect(study.position.legalMoves().filter { $0.from == 48 && $0.to == 56 }.count == 4)
        #expect(throws: ChessError.self) { try study.play(ChessMove(uci: "a7a8")) }
        try study.play(ChessMove(uci: "a7a8n"))
        #expect(study.position.squares[56] == Piece(kind: .knight, side: .white))
        #expect(study.notations == ["a8=N"])
        #expect(study.repetitionHistory == [root.repetitionKey])
        study.undo()
        #expect(study.position == root)
    }

    @Test func repetitionStopsAtThirdOccurrence() throws {
        var study = AnalysisWorkspace()
        for uci in ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"] {
            try study.play(ChessMove(uci: uci))
        }
        #expect(study.outcome == .repetitionDraw)
        #expect(throws: ChessError.self) { try study.play(ChessMove(uci: "e2e4")) }
        study.undo()
        #expect(study.outcome == .ongoing)
    }

    @Test func rejectsMalformedAndImpossiblePositions() {
        let invalid = [
            "", "8/8/8/8/8/8/8/8 w - - 0 1",
            "4k3/44/8/8/8/8/8/4K3 w - - 0 1",
            "4k3/4K3/8/8/8/8/8/8 w - - 0 1",
            "4k3/8/8/8/8/8/8/4K2R w KQ - 0 1",
            "4k3/8/8/8/8/8/8/4R1K1 w - - 0 1",
            "4k3/8/8/8/8/8/PPPPPPPP/QQ2K3 w - - 0 1",
            "4k3/3p4/8/3p4/8/8/8/4K3 w - d6 0 1",
            "4k3/8/8/3p4/8/8/8/4K3 w - d6 1 1",
            "4k3/8/8/8/8/8/8/4K3 w - - 0 9223372036854775807",
            "4k3/8/8/8/8/8/8/4K3 w - - -1 1",
            String(repeating: "8", count: 300),
            "4k3/8/8/8/8/8/8/4K3 w - - ٠ 1"
        ]
        for fen in invalid {
            #expect(throws: ChessError.self) { try AnalysisWorkspace(fen: fen) }
        }
    }

    @Test func validUncapturableEnPassantAndCheckAreAccepted() throws {
        let ep = try AnalysisWorkspace(fen: "4k3/8/8/3p4/8/8/8/4K3 w - d6 0 2")
        #expect(ep.position.enPassantSquare == 43)
        let check = try AnalysisWorkspace(fen: "4k3/8/8/8/8/8/8/4R1K1 b - - 0 1")
        #expect(check.position.isInCheck)
    }
}
