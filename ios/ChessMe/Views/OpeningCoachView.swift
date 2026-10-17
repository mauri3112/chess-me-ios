import SwiftUI
import ChessMeCore

struct OpeningCoachView: View {
    @EnvironmentObject private var model: AppModel
    @State private var report: OpeningReport?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Improve your openings").font(ChessMeStyle.title(30))
                Text("Find the repeated early decision that costs you the most.").font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                if let report {
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(report.reviewedGames) / \(report.requiredGames) openings reviewed").font(.subheadline.weight(.semibold))
                                .accessibilityIdentifier("openings.coverage")
                            ProgressView(value: Double(min(report.reviewedGames, report.requiredGames)), total: Double(report.requiredGames))
                            Text("\(report.eligibleGames) standard games saved. Advice starts after \(report.requiredGames) games have their first \(OpeningCoach.lastOpeningMove) moves reviewed at depth two or more. Short finished games count when every early decision is reviewed.")
                                .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        }
                    }
                    if !report.isReady {
                        Text("Review \(report.requiredGames - report.reviewedGames) more openings to build a useful sample. Import and review coverage still apply.")
                            .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    } else if report.opportunities.isEmpty {
                        Text("No repeated costly opening decision meets the evidence threshold yet. Keep reviewing games.")
                            .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                    }
                    ForEach(Array(report.opportunities.enumerated()), id: \.element.id) { index, opportunity in
                        PaperCard {
                            VStack(alignment: .leading, spacing: 13) {
                                Eyebrow(text: index == 0 ? "Largest repeated loss" : "Another repeated decision")
                                Text("Move \(opportunity.moveNumber): try \(opportunity.suggestedSAN)").font(ChessMeStyle.title(23))
                                Text("You reached this position in \(opportunity.visits) games. \(opportunity.mistakes) moves lost at least one pawn by the engine estimate.")
                                    .font(.subheadline)
                                ChessBoardView(position: (try? ChessPosition(fen: opportunity.positionFEN)) ?? .initial,
                                               perspective: (try? ChessPosition(fen: opportunity.positionFEN).sideToMove) ?? .white)
                                Text("Compare \(opportunity.playedSAN) with \(opportunity.suggestedSAN). Average estimated loss across all visits: \(String(format: "%.1f", opportunity.averageLoss / 100)) pawns.")
                                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                                if let game = model.library.games.first(where: { $0.id == opportunity.sampleGameID }) {
                                    NavigationLink { ReviewCardView(finding: finding(opportunity, game: game)) } label: { Label("Explore this decision", systemImage: "arrow.right") }
                                }
                                Text("\(opportunity.source.capitalized) estimates. At least five games at this position, three costly decisions and 60% agreement on the suggested move.")
                                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                            }
                        }
                    }
                } else { ProgressView("Checking your opening decisions…") }
            }.padding(24)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Openings").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task {
                let games = model.library.games, analyses = model.library.analyses + (model.library.analysisHistory ?? [])
                let username = model.authentication.account?.username ?? (model.publicUsername.isEmpty ? nil : model.publicUsername)
                report = await Task.detached(priority: .utility) { OpeningCoach.report(games: games, analyses: analyses, username: username) }.value
            }
    }
    private func finding(_ opportunity: OpeningOpportunity, game: ChessGame) -> MoveFinding {
        MoveFinding(id: "opening-\(opportunity.id)", gameID: game.id, gameLabel: game.label,
                    positionFEN: opportunity.positionFEN, playedMove: opportunity.playedMove,
                    bestMove: opportunity.suggestedMove, acceptedMoves: [opportunity.suggestedMove], continuation: [opportunity.suggestedMove],
                    centipawnLoss: Double(opportunity.sampleLoss), theme: "Opening decision", explanation: "Compare the suggested move with your earlier choice. This advice comes from repeated engine estimates in your saved games.",
                    hint: "Compare development, king safety and immediate threats.", moveNumber: opportunity.moveNumber,
                    source: opportunity.source, isPuzzle: false)
    }
}
