import SwiftUI
import ChessMeCore

struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = "All"
    private var targets: [ReviewLearningTarget] {
        model.reviewState.targets.filter { target in
            guard model.isDemo == target.finding.gameID.hasPrefix("demo-") else { return false }
            switch filter {
            case "Ready": return target.ready(at: Date())
            case "Later": return !target.dismissed && !target.ready(at: Date())
            case "Dismissed": return target.dismissed
            default: return !target.dismissed
            }
        }.sorted { $0.suggestedAt < $1.suggestedAt }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                BrandHeader(title: "Practice", tab: .practice)
                SampleNotice()
                PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("From your reviews").font(ChessMeStyle.title(24))
                        let count = model.suggestedReviewTargets.count
                        Text("\(model.readyReviewTargets.count) lessons ready")
                            .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                        if model.hasResumableReview {
                            PrimaryButton(title: "Resume practice", symbol: "play.fill") { model.resumeReviewSession() }
                                .accessibilityIdentifier("practice.resume")
                        }
                        else if count > 0 || model.isDemo && !model.allPuzzles.isEmpty {
                            PrimaryButton(title: "Start short practice", symbol: "play.fill") { model.startSession(allSaved: true) }
                                .accessibilityIdentifier("practice.start")
                        } else {
                            Text("Review a game to find your next lesson.").font(.subheadline)
                            Button("View games") { model.selectedTab = AppTab.games.rawValue }.frame(minHeight: 44)
                        }
                    }
                }
                NavigationLink { PuzzleTrainingView() } label: {
                    destination("Puzzles", detail: "Choose a theme or retry saved puzzles", symbol: "puzzlepiece.extension")
                }.accessibilityIdentifier("practice.puzzles")
                NavigationLink { FundamentalsView() } label: {
                    destination("Fundamentals", detail: "Checkmate patterns and promotion", symbol: "graduationcap")
                }.accessibilityIdentifier("practice.fundamentals")
                NavigationLink { FavoritesView() } label: {
                    destination("Saved positions", detail: "Lessons and puzzles you've kept", symbol: "heart")
                }.accessibilityIdentifier("practice.saved")
                NavigationLink { OpeningCoachView() } label: {
                    destination("Opening practice", detail: "Learn from repeated early decisions", symbol: "flag.checkered")
                }.accessibilityIdentifier("openings.open")
                NavigationLink { SavedReviewLinesView() } label: {
                    destination("Rehearse saved lines", detail: "Recall your chosen variations", symbol: "arrow.triangle.branch")
                }.accessibilityIdentifier("practice.lines")
                NavigationLink { AnalysisWorkspaceView() } label: {
                    destination("Analysis board", detail: "Explore moves or paste a position", symbol: "square.grid.3x3")
                }.accessibilityIdentifier("practice.analysis")
                Text("Your lessons").font(ChessMeStyle.title(22))
                Picker("Lesson status", selection: $filter) {
                    ForEach(["All", "Ready", "Later", "Dismissed"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                if targets.isEmpty { Text("No lessons in this group.").font(.subheadline).foregroundStyle(ChessMeStyle.muted) }
                ForEach(targets) { target in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink { ReviewTargetHistoryView(targetID: target.id) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                ChessBoardView(position: (try? ChessPosition(fen: target.finding.positionFEN)) ?? .initial)
                                    .frame(width: 64, height: 64).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(target.finding.theme).font(.subheadline.weight(.semibold))
                                    Text(target.finding.gameLabel).font(.caption)
                                    Text(target.invalidated ? "Source analysis changed" : target.dismissed ? "Dismissed" :
                                         target.ready(at: Date()) ? target.reason : "Suggested \(target.suggestedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                                }
                                Spacer(); Image(systemName: "chevron.right").font(.caption)
                            }.foregroundStyle(ChessMeStyle.ink)
                        }
                        HStack {
                            if !target.invalidated {
                                Button("Practise now") { model.openLesson(target.finding) }.accessibilityIdentifier("practice.lesson.\(target.id)")
                            }
                            Spacer()
                            Menu("Manage lesson") {
                                Button(target.kept ? "Kept for practice" : "Keep for practice") { model.updateTarget(target.id, action: .keep) }
                                Button("Defer for 3 days") { model.updateTarget(target.id, action: .deferUntil(Date().addingTimeInterval(259_200))) }
                                if target.dismissed { Button("Restore") { model.updateTarget(target.id, action: .restore) } }
                                else { Button("Dismiss suggestion") { model.updateTarget(target.id, action: .dismiss) } }
                            }
                        }.font(.caption).frame(minHeight: 44)
                    }
                    Divider()
                }
                ReviewSaveNotice()
            }.padding(24)
        }.background(ChessMeStyle.paper).toolbar(.hidden, for: .navigationBar).accessibilityIdentifier("practice.scroll")
    }
    private func destination(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(ChessMeStyle.muted)
            }
            Spacer(); Image(systemName: "chevron.right").font(.caption)
        }.foregroundStyle(ChessMeStyle.ink).padding(.vertical, 8).frame(minHeight: 56)
    }
}
