import SwiftUI
import ChessMeCore

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var player = ""
    @StateObject private var reports = InsightsReportController()
    @State private var refreshID = UUID()
    private struct Request: Equatable {
        let input: InsightsReportInput
        let refreshID: UUID
    }
    private var input: InsightsReportInput {
        InsightsReportInput(games: model.library.games,
                            analyses: model.library.analyses + (model.library.analysisHistory ?? []),
                            review: model.reviewState, username: player.isEmpty ? nil : player)
    }
    private var players: [String] {
        var names: [String: String] = [:]
        for game in model.library.games where !game.id.hasPrefix("demo-") {
            names[game.username.lowercased()] = game.username
        }
        return names.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your progress").font(ChessMeStyle.title(28))
                Text("Results and practice from the games saved on this device.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                if !players.isEmpty {
                    Picker("Player", selection: $player) {
                        Text("Latest saved game's player").tag("")
                        ForEach(players, id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier("insights.player")
                }
                if let report = reports.report(for: input) {
                    if report.results.games == 0 {
                        ContentUnavailableView("No personal games yet", systemImage: "chart.bar",
                                               description: Text("Import completed games to see their results. Sample games do not count."))
                    } else {
                        resultsCard(report)
                        breakdown("By color", rows: report.colors)
                        breakdown("By time control", rows: report.speeds)
                        breakdown("Openings in saved games", rows: report.openings)
                        estimates(report)
                        practice(report)
                    }
                } else { ProgressView("Reading saved games…") }
                if let note = model.library.coverageNote {
                    Text(note).font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
                Button("Refresh insights") { refreshID = UUID() }
                    .frame(minHeight: 44).accessibilityIdentifier("insights.refresh")
            }.padding(24)
        }.background(ChessMeStyle.paper)
            .navigationTitle("Insights").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task(id: Request(input: input, refreshID: refreshID)) { await reports.refresh(input) }
            .onDisappear { reports.cancel() }
            .accessibilityIdentifier("insights.scroll")
    }

    private func resultsCard(_ report: LearningInsights) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(report.username ?? "Saved games").font(ChessMeStyle.title(23))
                Text("\(report.results.games) unique finished games saved").font(.subheadline)
                Text(resultText(report.results)).font(.headline)
                Text("\(report.results.known) known outcomes; \(report.results.unknown) unknown. Unknown outcomes are excluded from result totals.")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
                if report.excludedGames > 0 {
                    Text("\(report.excludedGames) saved games belong to other players.").font(.caption)
                }
            }
        }.accessibilityIdentifier("insights.results")
    }

    private func breakdown(_ title: String, rows: [LearningInsights.Breakdown]) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(ChessMeStyle.title(22))
                ForEach(Array(rows.prefix(12))) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Text("\(row.results.games) games · \(resultText(row.results))")
                            .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        if row.results.unknown > 0 { Text("\(row.results.unknown) unknown outcomes").font(.caption) }
                    }.accessibilityElement(children: .combine)
                }
                if rows.count > 12 {
                    Text("Showing the 12 most frequent groups of \(rows.count). All groups count in the totals above.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                }
            }
        }
    }

    private func estimates(_ report: LearningInsights) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reviewed decisions").font(ChessMeStyle.title(22))
                if report.estimates.isEmpty {
                    Text("Review games to build a sample of assessed decisions.").font(.subheadline)
                }
                ForEach(report.estimates) { estimate in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(estimate.source == "device" ? "On-device estimates" : "Cloud estimates").font(.headline)
                        Text("\(estimate.decisions) assessed decisions in \(estimate.games) games; \(estimate.completeGames) complete reviews.")
                        Text("\(estimate.mistakes) mistakes · \(estimate.blunders) blunders")
                        Text("\(estimate.openingDecisions) decisions in moves 1–10; \(estimate.laterDecisions) after move 10.")
                    }.font(.subheadline)
                }
                Text("Each source uses its latest saved review per game. Partial reviews contribute only validated player decisions. The same game can appear under both sources. Move labels are engine estimates, not an accuracy rating.")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }
        }.accessibilityIdentifier("insights.estimates")
    }

    private func practice(_ report: LearningInsights) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Practice evidence").font(ChessMeStyle.title(22))
                Text("\(report.dueLessons) lessons ready now").font(.headline)
                Text("\(report.practiceAttempts) recorded attempts")
                Text("\(report.unaidedCompletions) completed without new help")
                Text("\(report.assistedCompletions) completed after help or retries")
                Text("\(report.revealedAttempts) answers revealed · \(report.otherAttempts) other or unfinished attempts")
                Text("Includes attempts linked to this player. Previously seen or topic-cued exercises can count as completed without new help. This is practice history, not a measure of improvement.")
                    .font(.caption).foregroundStyle(ChessMeStyle.muted)
            }.font(.subheadline)
        }.accessibilityIdentifier("insights.practice")
    }

    private func resultText(_ results: LearningInsights.Results) -> String {
        "\(results.wins) won · \(results.draws) drawn · \(results.losses) lost"
    }

}
