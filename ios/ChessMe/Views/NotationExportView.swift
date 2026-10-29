import SwiftUI
import UniformTypeIdentifiers
import ChessMeCore

private extension UTType {
    static let chessMePGN = UTType(exportedAs: "com.chessme.pgn", conformingTo: .plainText)
}

private struct PGNExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.chessMePGN, .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Preparation is tied to the retained source and current library generation.
struct NotationExportView: View {
    @EnvironmentObject private var model: AppModel
    let game: ChessGame
    var study: GameReplay? = nil
    var savedLine: SavedReviewLine? = nil
    var snapshotID: String? = nil
    @State private var notation: String?
    @State private var preparedRequest: NotationExportRequest?
    @State private var error: String?
    @State private var exporting = false
    @State private var copied = false
    private var isStudy: Bool { study != nil || savedLine != nil }
    private var source: NotationExportRequest.Source {
        if let id = savedLine?.id ?? snapshotID { return .savedLine(id) }
        return .game(game.id)
    }
    private var request: NotationExportRequest? {
        guard source.isRetained(games: model.library.games, lines: model.reviewState.savedLines) else { return nil }
        return NotationExportRequest(source: source, generation: model.reviewGeneration)
    }
    private var currentNotation: String? {
        guard let request, preparedRequest == request else { return nil }
        return notation
    }
    private var filename: String { isStudy ? "ChessMe-study.pgn" : "ChessMe-game.pgn" }
    private var explanation: String {
        if savedLine != nil { return "This PGN contains your saved variation and its original lead-in. It is an unfinished study, marked with *." }
        if study != nil { return "This PGN contains the source moves up to your selected position and your temporary continuation. It is an unfinished study, marked with *." }
        return "PGN contains the legal mainline, game details and known result. Original comments and branches are omitted."
    }

    var body: some View {
        ScrollView {
            if request == nil {
                ContentUnavailableView("Export unavailable", systemImage: "doc",
                    description: Text("The source game or saved line is no longer in your library."))
                    .accessibilityIdentifier("export.unavailable")
            } else {
            VStack(alignment: .leading, spacing: 18) {
                Text(isStudy ? "Share your study line" : "Share this game's mainline")
                    .font(ChessMeStyle.title(26))
                Text(explanation)
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                if modelIsSample {
                    Label("Sample game", systemImage: "eye").font(.caption)
                }
                if let notation = currentNotation {
                    ShareLink(item: notation) { Label("Share PGN text", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44).accessibilityIdentifier("export.share")
                    Button { if currentNotation != nil { exporting = true } } label: { Label("Save PGN file", systemImage: "doc.badge.arrow.up") }
                        .frame(minHeight: 44).accessibilityIdentifier("export.file")
                    Button {
                        guard let notation = currentNotation else { return }
                        UIPasteboard.general.string = notation; copied = true
                    } label: { Label(copied ? "Copied PGN" : "Copy PGN", systemImage: "doc.on.doc") }
                        .frame(minHeight: 44).accessibilityIdentifier("export.copy")
                    Text(notation).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("export.notation")
                } else if error == nil { ProgressView("Preparing notation…") }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }.padding(24)
            }
        }.background(ChessMeStyle.paper)
            .navigationTitle("PGN export").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .fileExporter(isPresented: Binding(get: { exporting && currentNotation != nil }, set: { exporting = $0 }),
                          document: PGNExportDocument(text: currentNotation ?? ""),
                          contentType: .chessMePGN, defaultFilename: filename) { result in
                if request != nil, case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .onChange(of: request) { _, _ in clearPreparedExport() }
            .task(id: request) {
                clearPreparedExport()
                guard let request else { return }
                let game = game, study = study, savedLine = savedLine
                let work = Task.detached(priority: .utility) {
                    if let savedLine {
                        let replay = try GameReplay(game: savedLine.replayGame())
                        return try GameNotationExport.line(position: replay.positions[0], moves: replay.moves,
                            headers: ["White": game.white, "Black": game.black, "Event": savedLine.title])
                    }
                    if let study {
                        return try GameNotationExport.line(position: study.positions[0],
                            moves: Array(study.moves.prefix(study.index)) + study.variationMoves,
                            headers: ["White": game.white, "Black": game.black, "Event": "ChessMe explored line"])
                    }
                    return try GameNotationExport.game(game)
                }
                do {
                    let text = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                    guard !Task.isCancelled,
                          request.isCurrent(generation: model.reviewGeneration, games: model.library.games,
                                            lines: model.reviewState.savedLines) else { return }
                    preparedRequest = request; notation = text
                } catch is CancellationError {} catch {
                    guard !Task.isCancelled,
                          request.isCurrent(generation: model.reviewGeneration, games: model.library.games,
                                            lines: model.reviewState.savedLines) else { return }
                    self.error = error.localizedDescription
                }
            }
    }

    private func clearPreparedExport() {
        notation = nil; preparedRequest = nil; exporting = false; copied = false; error = nil
    }

    private var modelIsSample: Bool { game.id.hasPrefix("demo-") }
}
