import SwiftUI
import ChessMeCore

@MainActor
final class ReviewLinePlayback: ObservableObject {
    @Published private(set) var proof: ReviewLineProof?
    @Published private(set) var cursor = 0
    @Published private(set) var isPlaying = false
    private var requestedCursor = 0
    private var generation = UUID()
    private var loadGeneration = UUID()
    private var playback: Task<Void, Never>?

    func load(fen: String, moves: [String], cached: ReviewLineProof? = nil, at index: Int = 0) async {
        // Navigation reappearance must keep the position the player inspected.
        // Plan selection has its own explicit seek in the view.
        if let proof, proof.rootFEN == fen, proof.moves == moves { return }
        stop()
        loadGeneration = UUID()
        let ticket = loadGeneration
        requestedCursor = index
        let result: ReviewLineProof?
        if let cached, cached.rootFEN == fen, cached.moves == moves { result = cached }
        else {
            let work = Task.detached(priority: .userInitiated) {
                (try? ChessPosition(fen: fen)).flatMap { ReviewLineProof(position: $0, moves: moves) }
            }
            result = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        }
        guard !Task.isCancelled, loadGeneration == ticket else { return }
        proof = result
        cursor = min(max(0, requestedCursor), result?.moves.count ?? 0)
    }

    func seek(_ index: Int) {
        stop()
        requestedCursor = index
        cursor = min(max(0, index), proof?.moves.count ?? 0)
    }

    func play(reduceMotion: Bool) {
        guard let proof else { return }
        if isPlaying { stop(); return }
        if reduceMotion { seek(proof.moves.count); return }
        if cursor == proof.moves.count { cursor = 0 }
        isPlaying = true
        let ticket = generation
        playback = Task {
            while cursor < proof.moves.count {
                do { try await Task.sleep(for: .milliseconds(550)) } catch { return }
                guard !Task.isCancelled, generation == ticket else { return }
                cursor += 1
            }
            if generation == ticket { isPlaying = false; playback = nil }
        }
    }

    func stop() {
        generation = UUID(); playback?.cancel(); playback = nil; isPlaying = false
    }
}
