import SwiftUI
import UIKit
import ChessMeCore

struct AnalysisWorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var analysis = PositionAnalysisController()
    @State private var workspace = AnalysisWorkspace()
    @State private var fenInput = ""
    @State private var error: String?
    @State private var selected: Int?
    @State private var promotionMoves: [ChessMove] = []
    @State private var perspective: Side = .white
    @State private var lifecycle = AnalysisWorkspaceLifecycle()
    @FocusState private var fenFocused: Bool

    private var requestedAnalysis: Bool { lifecycle.requested }
    private var position: ChessPosition { workspace.position }
    private var controlLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
    }
    private var targets: Set<Int> {
        guard let selected, workspace.outcome == .ongoing else { return [] }
        return Set(position.legalMoves().filter { $0.from == selected }.map(\.to))
    }
    private var configuration: DeviceEngineConfiguration {
        model.engineConfiguration.bounded(
            forMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Explore a position").font(ChessMeStyle.title(28))
                Text("Play legal moves or load a FEN. This offline study stays separate from your imported games.")
                    .font(.subheadline).foregroundStyle(ChessMeStyle.muted)
                LiveAnalysis(controller: analysis, position: position) { evaluation in
                    AnalysisBoardView(position: position, perspective: perspective, selectedSquare: selected,
                                      targets: targets, evaluation: evaluation, evaluationPosition: position,
                                      topMoves: configuration.topMoves, showArrows: requestedAnalysis,
                                      onSquare: select)
                }
                Text(status).font(.subheadline.weight(.medium)).accessibilityIdentifier("workspace.status")
                controlLayout {
                    Button("Undo", systemImage: "arrow.uturn.backward") { workspace.undo(); changedPosition() }
                        .disabled(workspace.moves.isEmpty).accessibilityIdentifier("workspace.undo")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Button("Reset", systemImage: "arrow.counterclockwise") { workspace.reset(); changedPosition() }
                        .disabled(workspace.moves.isEmpty).accessibilityIdentifier("workspace.reset")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Button("Flip", systemImage: "arrow.up.arrow.down") { perspective = perspective.opposite }
                        .accessibilityIdentifier("workspace.flip")
                }.buttonStyle(.borderless)
                controlLayout {
                    Button(analysis.isCalculating || lifecycle.waitingForReview ? "Stop analysis" : "Analyze on device", systemImage: "cpu") {
                        if analysis.isCalculating || lifecycle.waitingForReview { updateLifecycle(.stopped) }
                        else { updateLifecycle(.requested) }
                    }.accessibilityIdentifier("workspace.analyze")
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    NavigationLink { EngineSettingsView() } label: {
                        if dynamicTypeSize.isAccessibilitySize {
                            Label("Engine settings", systemImage: "slider.horizontal.3")
                        } else {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                        .accessibilityLabel("Engine settings")
                }
                if lifecycle.waitingForReview {
                    Text("Position analysis is paused while your saved games are being reviewed. It resumes when the review finishes.")
                        .font(.caption).foregroundStyle(ChessMeStyle.muted)
                        .accessibilityIdentifier("workspace.analysisPaused")
                }
                if requestedAnalysis {
                    AnalysisPanel(position: position, controller: analysis, configuration: configuration)
                }
                if !workspace.notations.isEmpty {
                    Text(workspace.notations.joined(separator: " ")).font(.subheadline.monospaced())
                        .textSelection(.enabled).accessibilityIdentifier("workspace.line")
                }
                DisclosureGroup("Load a position with FEN") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Six-field FEN", text: $fenInput, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.caption.monospaced()).lineLimit(3...5)
                            .focused($fenFocused).submitLabel(.done).onSubmit(loadFEN)
                            .accessibilityIdentifier("workspace.fenInput")
                        Button("Load position") { loadFEN() }.accessibilityIdentifier("workspace.loadFEN")
                        Button("Use starting position") {
                            workspace = AnalysisWorkspace(); fenInput = ""; changedPosition()
                        }
                    }.padding(.top, 8)
                }.accessibilityIdentifier("workspace.fenDisclosure")
                if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("workspace.error") }
                Text(position.fen).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("workspace.currentFEN")
                controlLayout {
                    Button("Copy FEN", systemImage: "doc.on.doc") { UIPasteboard.general.string = position.fen }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    ShareLink(item: position.fen) { Text("Share FEN") }
                    ShareLink(item: workspace.pgn) { Text("Share PGN") }
                }.font(.subheadline)
            }.padding(24)
        }
        .background(ChessMeStyle.paper)
        .navigationTitle("Position study").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("workspace.scroll")
        .confirmationDialog("Promote pawn", isPresented: Binding(
            get: { !promotionMoves.isEmpty }, set: { if !$0 { promotionMoves = [] } }
        ), titleVisibility: .visible) {
            ForEach(promotionMoves, id: \.uci) { move in
                Button(move.promotion?.rawValue.capitalized ?? "Queen") { play(move) }
            }
            Button("Cancel", role: .cancel) { promotionMoves = [] }
        }
        .onChange(of: scenePhase) { _, phase in updateLifecycle(.activeChanged(phase == .active)) }
        .onChange(of: model.isAnalyzing) { _, busy in updateLifecycle(.reviewRunningChanged(busy)) }
        .onChange(of: configuration) { _, _ in updateLifecycle(.configurationChanged) }
        .onDisappear { updateLifecycle(.disappeared); analysis.stop() }
        .onAppear { updateLifecycle(.appeared(active: scenePhase == .active, reviewRunning: model.isAnalyzing)) }
    }

    private var status: String {
        switch workspace.outcome {
        case .ongoing: return "\(position.sideToMove.title) to move\(position.isInCheck ? " · check" : "")"
        case .checkmate(let winner): return "Checkmate · \(winner.title) wins"
        case .stalemate: return "Draw by stalemate"
        case .insufficientMaterial: return "Draw by insufficient material"
        case .fiftyMoveDraw: return "Draw by the fifty-move rule"
        case .repetitionDraw: return "Draw by repetition"
        }
    }
    private func select(_ square: Int) {
        guard workspace.outcome == .ongoing else { return }
        if let selected {
            let matches = position.legalMoves().filter { $0.from == selected && $0.to == square }
            if matches.count > 1 { promotionMoves = matches; return }
            if let move = matches.first { play(move); return }
        }
        selected = position.squares[square]?.side == position.sideToMove && selected != square ? square : nil
    }
    private func play(_ move: ChessMove) {
        do { try workspace.play(move); changedPosition() }
        catch { self.error = error.localizedDescription }
    }
    private func loadFEN() {
        fenFocused = false
        do {
            let loaded = try AnalysisWorkspace(fen: fenInput)
            workspace = loaded
            changedPosition()
        } catch { self.error = error.localizedDescription }
    }
    private func changedPosition() {
        selected = nil; promotionMoves = []; error = nil
        analysis.stop()
        updateLifecycle(.configurationChanged)
    }
    private func updateLifecycle(_ event: AnalysisWorkspaceLifecycle.Event) {
        switch lifecycle.handle(event) {
        case .none: break
        case .stop: analysis.stop()
        case .start:
            analysis.stop()
            analysis.start(position: position, history: workspace.repetitionHistory, configuration: configuration)
        }
    }
}
