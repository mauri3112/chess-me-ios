import Foundation

/// Provider clocks are the mover's remaining time after each mainline ply, in centiseconds.
/// Missing entries stay missing; an older clock must never masquerade as a new reading.
public struct GameClockData: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case lichess, pgn }
    public let initialSeconds: Int?
    public let incrementSeconds: Int?
    public let remainingCentiseconds: [Int?]
    public let source: Source

    public init(initialSeconds: Int?, incrementSeconds: Int?, remainingCentiseconds: [Int?], source: Source = .lichess) {
        self.initialSeconds = initialSeconds.flatMap { (0...604_800).contains($0) ? $0 : nil }
        self.incrementSeconds = incrementSeconds.flatMap { (0...86_400).contains($0) ? $0 : nil }
        self.remainingCentiseconds = remainingCentiseconds.map { $0.flatMap { (0...60_480_000).contains($0) ? $0 : nil } }
        self.source = source
    }

    public var timeControl: String? {
        guard let initialSeconds, let incrementSeconds else { return nil }
        let base = initialSeconds % 60 == 0 ? "\(initialSeconds / 60) min" : "\(initialSeconds)s"
        return "\(base) + \(incrementSeconds)s"
    }

    public static func clockLabel(_ centiseconds: Int?) -> String {
        guard let centiseconds else { return "—" }
        let seconds = centiseconds / 100
        if seconds >= 3_600 { return String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60) }
        if seconds < 10 { return String(format: "0:%02d.%d", seconds, centiseconds / 10 % 10) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    public static func durationLabel(_ centiseconds: Int) -> String {
        centiseconds < 6_000 ? String(format: "%.1fs", Double(centiseconds) / 100) : clockLabel(centiseconds)
    }

    static func parseClockComment(_ comment: String) -> Int? {
        guard let range = comment.range(of: #"\[%clk\s+\d+:\d{2}:\d{2}(?:\.\d+)?\s*\]"#, options: .regularExpression) else { return nil }
        let value = comment[range].dropFirst(5).dropLast().trimmingCharacters(in: .whitespaces)
        let fields = value.split(separator: ":")
        guard fields.count == 3, let hours = Int(fields[0]), let minutes = Int(fields[1]), let seconds = Double(fields[2]),
              hours <= 168, minutes < 60, seconds < 60 else { return nil }
        return Int(((Double(hours * 3_600 + minutes * 60) + seconds) * 100).rounded())
    }
}

public struct GameClockSnapshot: Equatable, Sendable {
    public let white: Int?
    public let black: Int?
    public func remaining(for side: Side) -> Int? { side == .white ? white : black }
}

public struct GameMoveTiming: Equatable, Sendable {
    public let side: Side
    public let before: Int?
    public let after: Int?
    /// Clock difference plus increment. Lichess compensates network lag and permits added time,
    /// so this is an estimate, not a measurement of wall-clock thinking time.
    public let estimatedSpent: Int?
    public let firstMoveUntimed: Bool
}

/// Built once from the replay, with an O(1) lookup for every selected board position.
public struct GameClockTimeline: Sendable {
    public let snapshots: [GameClockSnapshot]
    public let moves: [GameMoveTiming]

    public init(data: GameClockData, positions: [ChessPosition], status: String) {
        guard let first = positions.first else { snapshots = []; moves = []; return }
        let plyCount = positions.count - 1
        let readings = data.remainingCentiseconds
        func startingClock(_ side: Side) -> Int? {
            // Lichess does not run either player's clock on their first move. This also
            // preserves berserk/zero-base starting clocks instead of assuming the base time.
            let firstPly = first.sideToMove == side ? 0 : 1
            if data.source == .lichess, firstPly < plyCount, readings.indices.contains(firstPly), let value = readings[firstPly] { return value }
            return data.initialSeconds.map { $0 * 100 }
        }
        var white = startingClock(.white), black = startingClock(.black)
        var snapshots = [GameClockSnapshot(white: white, black: black)]
        var moves: [GameMoveTiming] = []
        var seen = Set<Side>()
        let endedByMove = status == "mate" || status == "stalemate" || positions.last?.outcome() != .ongoing
        func incrementFor(_ side: Side) -> Int? {
            if data.source == .lichess, let initial = data.initialSeconds, initial > 0, (data.incrementSeconds ?? 0) > 0,
               let starting = startingClock(side), abs(starting - initial * 100) > 100 {
                // Exported clocks can reveal a modified starting clock (for example
                // berserk), but the export does not supply its per-player increment.
                // Keep the recorded clock and omit an unreliable thinking-time estimate.
                return nil
            }
            return data.incrementSeconds.map { $0 * 100 }
        }
        for ply in 0..<plyCount {
            let side = positions[ply].sideToMove
            let before = side == .white ? white : black
            let after = readings.indices.contains(ply) ? readings[ply] : nil
            let firstMoveUntimed = data.source == .lichess && !seen.contains(side)
            seen.insert(side)
            let increment = endedByMove && ply == plyCount - 1 ? 0 : incrementFor(side)
            var spent: Int?
            if !firstMoveUntimed, let before, let after, let increment {
                let difference = before + increment - after
                // A clock increase beyond the increment means time was added or data is incomplete.
                if difference >= 0 { spent = difference }
            }
            moves.append(GameMoveTiming(side: side, before: before, after: after, estimatedSpent: spent, firstMoveUntimed: firstMoveUntimed))
            if side == .white { white = after } else { black = after }
            snapshots.append(GameClockSnapshot(white: white, black: black))
        }
        self.snapshots = snapshots; self.moves = moves
    }
}
