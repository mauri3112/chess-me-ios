import SwiftUI
import ChessMeCore

struct AnalysisInfoView: View {
    var body: some View {
        List {
            Section("On your device") {
                Text("Arasan 26 and its neural network provide offline device analysis. Overnight reviews save completed decisions and can resume while charging.")
                Text("Scores, move labels and brilliant candidates are estimates. More time can change the result. The evaluation bar shows an advantage in pawns, rather than a win probability.")
            }
            Section("Practice") {
                Text("Exercises start without engine suggestions. Hints, mistakes, retries and revealed lines remain in the attempt history. Follow-up timing adapts to that evidence. Later recall and new related-position results are shown separately.")
            }
            Section("Cloud") {
                Text("Cloud Stockfish runs on a separately configured server. Cloud reviews require a verified subscription and remaining allowance. Live board analysis uses the selected device engine. Stockfish is not bundled in the native app.")
            }
            Section("Related puzzles and openings") {
                Text("Book moves follow the offline Lichess catalogue of \(OpeningBook.shared.openingCount.formatted()) opening lines and variations. Theory ends at the recorded length of each line. Known positions also recognize transpositions. Ordinary book moves do not become mistake lessons; verified blunders remain visible.")
                Text("Lichess puzzles come from its CC0 database. Broad catalogue suggestions use themes and estimated level. A lesson-specific invitation additionally verifies a shared board mechanism in the legal lines. Related puzzles are optional; asking for help remains visible in the attempt history.")
                Text("Opening advice starts after 30 sufficiently reviewed standard games. It requires repeated losses at the same position and agreement on a suggested move. These are engine estimates.")
            }
            Section("Supported games") {
                Text("Only finished standard games are supported. A partial import or review keeps its progress and coverage label.")
            }
        }
        .font(.subheadline)
        .navigationTitle("About analysis").navigationBarTitleDisplayMode(.inline)
    }
}

struct OpenSourceLicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ChessMe app and shared core").font(ChessMeStyle.title(26))
                Text("Copyright 2026 ChessMe contributors. Licensed under GNU GPL version 3. You can use, study, modify and share this software under that licence. There is no warranty.").font(.subheadline)
                Link("Corresponding source for this build", destination: URL(string: Bundle.main.object(forInfoDictionaryKey: "ChessMeSourceCodeURL") as? String ?? "https://github.com/mauri3112/chess-me-ios")!)
                Text("The published client source includes the app, shared core, native engine adapters, exact neural networks and build files. The cloud backend is a separate service.").font(.footnote)
                Text("Stockfish · cloud and host tools").font(ChessMeStyle.title(26))
                Text("Copyright 2004–2026 The Stockfish developers. Licensed under GNU GPLv3 or later. No warranty.").font(.subheadline)
                Link("Stockfish upstream source", destination: StockfishEngine.sourceURL)
                Text(StockfishEngine.license).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("Arasan 26").font(ChessMeStyle.title(26))
                Text("Engine and neural network by Jon Dart.").font(.subheadline)
                Link("Arasan source", destination: URL(string: "https://github.com/jdart1/arasan-chess/tree/v26.0")!)
                Text(ArasanEngine.license).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("Lichess openings").font(ChessMeStyle.title(26))
                Text("The complete opening-name catalogue and its variations are released under Creative Commons CC0. The offline index includes all five ECO volumes.").font(.subheadline)
                Link("Lichess opening catalogue", destination: URL(string: "https://github.com/lichess-org/chess-openings")!)
                Text((try? OpeningBook.licenseText()) ?? "Creative Commons CC0 1.0 Universal")
                    .font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("Lichess puzzles").font(ChessMeStyle.title(26))
                Text("Puzzle data is released under Creative Commons CC0. The original puzzle and database links remain available in the app.").font(.subheadline)
                Link("Lichess open database", destination: URL(string: "https://database.lichess.org/#puzzles")!)
                Link("CC0 dedication", destination: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
        }
        .navigationTitle("Open Source Licenses").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("analysis.licenses")
    }
}
