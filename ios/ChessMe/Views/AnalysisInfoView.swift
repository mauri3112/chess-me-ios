import SwiftUI
import ChessMeCore

struct AnalysisInfoView: View {
    var body: some View {
        List {
            Section("On your device") {
                Text("Stockfish 19 and Arasan 26 are bundled with their neural networks for offline analysis. ChessMe Tactical and Material are lighter alternatives. Overnight Stockfish reviews save decisions and can resume while charging.")
                Text("Scores, move labels and brilliant candidates are estimates. More time can change the result. The evaluation bar shows an advantage in pawns, rather than a win probability.")
            }
            Section("Practice") {
                Text("Lessons start without engine suggestions. Asking for a hint, opening analysis or exploring marks that solve as guided. Guided solves return sooner; unaided solves extend your practice streak.")
            }
            Section("Cloud") {
                Text("Cloud Stockfish runs on a separately configured server. Cloud reviews require a verified subscription and remaining allowance. Live board analysis always uses your selected device engine.")
            }
            Section("Related puzzles and openings") {
                Text("Lichess puzzles come from its CC0 database. Matching uses estimated tactical themes, your puzzle level and failed attempts. Solve the whole line; asking for help keeps the attempt guided.")
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
                Text("Stockfish 19").font(ChessMeStyle.title(26))
                Text("Copyright 2004–2026 The Stockfish developers. Licensed under GNU GPLv3 or later. No warranty.").font(.subheadline)
                Link("Stockfish upstream source", destination: StockfishEngine.sourceURL)
                Text(StockfishEngine.license).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                Text("Arasan 26").font(ChessMeStyle.title(26))
                Text("Engine and neural network by Jon Dart.").font(.subheadline)
                Link("Arasan source", destination: URL(string: "https://github.com/jdart1/arasan-chess/tree/v26.0")!)
                Text(ArasanEngine.license).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
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
