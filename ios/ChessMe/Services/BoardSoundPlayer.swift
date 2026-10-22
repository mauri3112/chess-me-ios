import AVFoundation
import ChessMeCore

enum BoardSound: CaseIterable, Equatable {
    case move, capture, check, captureCheck

    var resourceNames: [String] {
        switch self {
        case .move: return (1...3).map { "walnut-move-\($0)" }
        case .capture: return (1...2).map { "walnut-capture-\($0)" }
        case .check: return ["walnut-check"]
        case .captureCheck: return ["walnut-capture-check"]
        }
    }

    /// Only adjacent, legal board transitions produce sound. Loading a board
    /// and jumping multiple plies through the move list stay quiet.
    static func transition(from before: ChessPosition, to after: ChessPosition) -> BoardSound? {
        if let move = connectingMove(from: before, to: after) {
            let capture = before.squares[move.to] != nil ||
                (before.squares[move.from]?.kind == .pawn && move.to == before.enPassantSquare)
            if after.isInCheck { return capture ? .captureCheck : .check }
            return capture ? .capture : .move
        }
        // A single step backwards is a quiet placement, never a new check or capture.
        return connectingMove(from: after, to: before) == nil ? nil : .move
    }

    private static func connectingMove(from before: ChessPosition, to after: ChessPosition) -> ChessMove? {
        guard before.sideToMove != after.sideToMove else { return nil }
        return before.legalMoves().first { move in
            before.squares[move.from] != after.squares[move.from] &&
            after.squares[move.to]?.side == before.sideToMove &&
            (try? before.applying(move)) == after
        }
    }
}

@MainActor
final class BoardSoundPlayer {
    static let shared = BoardSoundPlayer()
    static let preferenceKey = "audio.boardSounds"
    private var players: [String: AVAudioPlayer] = [:]
    private var lastResource: String?

    static func resourceURL(_ name: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds") ??
            bundle.url(forResource: name, withExtension: "wav")
    }

    func prepare() {
        guard players.isEmpty else { return }
        // Ambient audio follows the Ring/Silent switch and mixes with music.
        do { try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default) }
        catch { return }
        for name in BoardSound.allCases.flatMap(\.resourceNames) {
            guard let url = Self.resourceURL(name), let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[name] = player
        }
    }

    func play(_ sound: BoardSound) {
        guard UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true else { return }
        prepare()
        let options = sound.resourceNames.filter { $0 != lastResource }
        guard let name = (options.isEmpty ? sound.resourceNames : options).randomElement(),
              let player = players[name] else { return }
        lastResource = name
        player.currentTime = 0
        player.play()
    }
}
