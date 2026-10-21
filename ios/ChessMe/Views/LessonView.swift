import SwiftUI
import ChessMeCore

struct LessonSessionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var returnGame: ChessGame?
    @State private var parentRun: AdaptiveReviewRun?
    @State private var parentReturnGameID: String?
    var body: some View {
        let originGameID = model.reviewState.session?.originGameID
        Group {
            if let returnGame {
                GameDetailView(game: returnGame, resumeSavedPlace: true)
            } else if let parentRun {
                ReviewPracticeView(finding: parentRun.sourceFinding, resumeRunID: parentRun.id, returnGameID: parentReturnGameID) {
                    if let parentReturnGameID, let game = model.library.games.first(where: { $0.id == parentReturnGameID }) { returnGame = game }
                    else { model.endSession() }
                }
            } else if let pending = model.reviewState.standalonePractice,
                      let run = model.reviewState.runs.first(where: { $0.id == pending.runID }), let puzzle = run.puzzleSnapshot {
                ReviewPracticeView(finding: run.sourceFinding, puzzle: puzzle, linkedTargetID: run.targetID,
                                   resumeRunID: run.id, returnGameID: pending.returnGameID, parentRunID: pending.parentRunID) {
                    if let id = pending.parentRunID, let parent = model.reviewState.runs.first(where: { $0.id == id }) {
                        parentRun = parent; parentReturnGameID = pending.returnGameID
                    } else if let id = pending.returnGameID, let game = model.library.games.first(where: { $0.id == id }) { returnGame = game }
                    else { model.endSession() }
                }
            } else {
                ReviewPracticeSetView(findings: model.session, originGameID: originGameID) {
                    if let originGameID, let game = model.library.games.first(where: { $0.id == originGameID }) { returnGame = game }
                    else { model.endSession() }
                }
            }
        }
    }
}
