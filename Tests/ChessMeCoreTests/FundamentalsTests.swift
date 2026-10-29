import Testing
@testable import ChessMeCore

struct FundamentalsTests {
    @Test func catalogueHasLegalNonterminalPositionsAndVerifiedExamples() throws {
        #expect(Set(FundamentalsLesson.all.map(\.id)).count == 6)
        for lesson in FundamentalsLesson.all {
            let position = try ChessPosition(fen: lesson.fen)
            #expect(!position.isInCheck(position.sideToMove.opposite))
            #expect(position.outcome() == .ongoing)
            let example = try ChessMove(uci: lesson.exampleUCI)
            #expect(position.legalMoves().contains(example))
            #expect(lesson.accepts(example))
            #expect(!lesson.accepts(try ChessMove(uci: "a1a1")))
            switch lesson.goal {
            case .mateInOne:
                for move in position.legalMoves() {
                    let next = try position.applying(move)
                    #expect(lesson.accepts(move) == (next.outcome() == .checkmate(winner: position.sideToMove)))
                }
            case .safePromotion:
                let rookUCI = String(lesson.exampleUCI.prefix(4)) + "r"
                #expect(lesson.accepts(try ChessMove(uci: rookUCI)))
                for kind in ["b", "n"] {
                    #expect(!lesson.accepts(try ChessMove(uci: String(lesson.exampleUCI.prefix(4)) + kind)))
                }
            }
        }
    }

    @Test func differentLegalMatesBothCount() throws {
        let lesson = FundamentalsLesson(id: "alternatives", title: "", introduction: "", hint: "",
            fen: "7k/5K2/4Q3/8/8/8/8/8 w - - 0 1", exampleUCI: "e6h3", goal: .mateInOne)
        #expect(lesson.accepts(try ChessMove(uci: "e6h3")))
        #expect(lesson.accepts(try ChessMove(uci: "e6h6")))
        #expect(!lesson.accepts(try ChessMove(uci: "e6e8")))
    }

    @Test func promotionRejectsImmediateCaptureAndStalemate() throws {
        // A rook on c1 can capture an unprotected promotion along the c-file.
        let rookCapture = FundamentalsLesson(id: "rook-capture", title: "", introduction: "", hint: "",
            fen: "7k/2P5/K7/8/8/8/8/2r5 w - - 0 1", exampleUCI: "c7c8q", goal: .safePromotion)
        #expect(!rookCapture.accepts(try ChessMove(uci: "c7c8q")))
        let stalemate = FundamentalsLesson(id: "stalemate", title: "", introduction: "", hint: "",
            fen: "8/k1P5/2K5/8/8/8/8/8 w - - 0 1", exampleUCI: "c7c8q", goal: .safePromotion)
        #expect(!stalemate.accepts(try ChessMove(uci: "c7c8q")))
    }

    @Test func wrongMovesStayVisibleAndGuidedCompletionIsDistinct() throws {
        for lesson in FundamentalsLesson.all {
            var attempt = FundamentalsAttempt(lesson: lesson)
            let start = attempt.position
            let wrong = try #require(start.legalMoves().first { !lesson.accepts($0) })
            attempt.play(wrong)
            #expect(!attempt.completed)
            #expect(attempt.position == start)
            #expect(attempt.feedback.contains("does not meet this task"))
            attempt.hint()
            #expect(attempt.guided)
            attempt.reveal()
            #expect(!attempt.completed)
            #expect(attempt.position == start)
            attempt.play(try ChessMove(uci: lesson.exampleUCI))
            #expect(attempt.completed && attempt.guided)
            #expect(attempt.feedback.contains("Guided"))
            attempt = FundamentalsAttempt(lesson: lesson)
            attempt.play(try ChessMove(uci: lesson.exampleUCI))
            #expect(attempt.completed && !attempt.guided)
        }
    }
}
