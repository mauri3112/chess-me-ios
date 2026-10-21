import Foundation

public struct OpeningVariation: Codable, Equatable, Sendable {
    public let eco: String
    public let name: String
    public let linePlies: Int
}

public struct OpeningMove: Equatable, Sendable {
    public let ply: Int
    public let positionKey: String
    public let move: String
    public let opening: OpeningVariation?
}

/// Recognized moves in the actual game. A named opening never exempts the whole game.
public struct OpeningLine: Equatable, Sendable {
    public let moves: [Int: OpeningMove]
    public let namedPositions: [Int: OpeningVariation]
    public var opening: OpeningVariation? { opening(at: Int.max) }
    public func opening(at positionIndex: Int) -> OpeningVariation? {
        namedPositions.keys.filter { $0 <= positionIndex }.max().flatMap { namedPositions[$0] }
    }

    public func recognizes(_ assessment: MoveAssessment) -> Bool {
        guard let book = moves[assessment.ply], book.move == assessment.playedMove,
              let position = try? ChessPosition(fen: assessment.positionFEN) else { return false }
        return position.repetitionKey == book.positionKey
    }
    public func recognizes(_ finding: MoveFinding) -> Bool {
        guard let position = try? ChessPosition(fen: finding.positionFEN), position.fullmoveNumber == finding.moveNumber else { return false }
        let ply = (finding.moveNumber - 1) * 2 + (position.sideToMove == .white ? 0 : 1)
        guard let book = moves[ply] else { return false }
        return finding.playedMove == book.move && position.repetitionKey == book.positionKey
    }

    /// Keep scores, search depth, progress, provenance and completion time intact.
    /// Named traps also appear in the catalogue; verified mate losses remain blunders.
    public func annotating(_ original: GameAnalysis) -> GameAnalysis {
        let analysis = ReviewMovePolicy.normalizing(original)
        var protected = Set((analysis.moveAssessments ?? []).filter {
            ($0.engineQuality ?? $0.quality) == .blunder
        }.map(\.ply))
        for finding in analysis.findings where recognizes(finding) && finding.quality == .blunder {
            if let position = try? ChessPosition(fen: finding.positionFEN) {
                protected.insert((finding.moveNumber - 1) * 2 + (position.sideToMove == .white ? 0 : 1))
            }
        }
        let findings = analysis.findings.filter { finding in
            guard recognizes(finding), let position = try? ChessPosition(fen: finding.positionFEN) else { return true }
            let ply = (finding.moveNumber - 1) * 2 + (position.sideToMove == .white ? 0 : 1)
            return protected.contains(ply)
        }
        let assessments = analysis.moveAssessments?.map { value -> MoveAssessment in
            guard recognizes(value), !protected.contains(value.ply) else { return value }
            return MoveAssessment(ply: value.ply, positionFEN: value.positionFEN, playedMove: value.playedMove,
                                  bestMove: value.bestMove, quality: .book, centipawnLoss: value.centipawnLoss,
                                  whiteScore: value.whiteScore, completedDepth: value.completedDepth, isProvisional: value.isProvisional,
                                  opening: moves[value.ply]?.opening, engineQuality: value.engineQuality ?? value.quality, bestWhiteScore: value.bestWhiteScore)
        }
        guard findings != analysis.findings || assessments != analysis.moveAssessments else { return analysis }
        return GameAnalysis(gameID: analysis.gameID, findings: findings, analyzedPlies: analysis.analyzedPlies,
                            totalPlies: analysis.totalPlies, source: analysis.source, completedAt: analysis.completedAt,
                            engineVersion: analysis.engineVersion, configurationID: analysis.configurationID, moveAssessments: assessments)
    }
}

/// Full CC0 Lichess ECO A00–E99 catalogue, with every legal prefix and move indexed offline.
public struct OpeningBook: Sendable {
    private struct Record: Decodable, Sendable {
        let moves: [String: Int]
        let opening: OpeningVariation?
    }
    private struct Index: Decodable, Sendable {
        let schema: Int
        let sourceCommit: String
        let openingCount: Int
        let maximumPly: Int
        let positions: [String: Record]
    }
    public static let shared = OpeningBook()
    private let index: Index?
    private init() {
        let url = CoreResources.url(forResource: "OpeningBook", withExtension: "json", subdirectory: "Resources")
        index = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Index.self, from: $0) }
    }
    public var openingCount: Int { index?.openingCount ?? 0 }
    public var maximumPly: Int { index?.maximumPly ?? 0 }
    public var sourceCommit: String? { index?.sourceCommit }
    public var isAvailable: Bool { index?.schema == 1 && openingCount > 0 }

    public func line(in replay: GameReplay, includingVariation: Bool = false) -> OpeningLine {
        if includingVariation, replay.isVariation {
            return line(positions: Array(replay.positions.prefix(replay.index + 1)) + replay.variationPositions,
                        moves: Array(replay.moves.prefix(replay.index)) + replay.variationMoves)
        }
        return line(positions: replay.positions, moves: replay.moves)
    }
    public func line(positions: [ChessPosition], moves: [ChessMove]) -> OpeningLine {
        guard isAvailable, positions.count == moves.count + 1,
              positions.first == ChessPosition.initial else { return OpeningLine(moves: [:], namedPositions: [:]) }
        var recognized: [Int: OpeningMove] = [:], names: [Int: OpeningVariation] = [:]
        var seen = Set<String>(), lastOpening: OpeningVariation?
        for ply in moves.indices.prefix(maximumPly) {
            let key = positions[ply].repetitionKey
            // Repetitions later in a game must not restart its opening classification.
            guard seen.insert(key).inserted else { break }
            let next = positions[ply + 1].repetitionKey
            if let opening = index?.positions[next]?.opening {
                lastOpening = opening
                names[ply + 1] = opening
            }
            if let lastPly = index?.positions[key]?.moves[moves[ply].uci], ply <= lastPly {
                recognized[ply] = OpeningMove(ply: ply, positionKey: key, move: moves[ply].uci, opening: lastOpening)
            }
        }
        return OpeningLine(moves: recognized, namedPositions: names)
    }

    public static func licenseText() throws -> String {
        guard let url = CoreResources.url(forResource: "LichessOpeningsLicense", withExtension: "txt", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
