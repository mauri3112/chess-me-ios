import Foundation

/// Search metadata without reparsing an archive's moves on each keystroke.
public struct GameArchiveEntry: Identifiable, Sendable {
    public var id: String { game.id }
    public let game: ChessGame
    public let opening: String?
    public let eco: String?
    public let outcome: PlayerGameOutcome?
    private let searchableText: String

    public init(game: ChessGame, opening: OpeningVariation? = nil) {
        self.game = game
        let headers = game.pgn.flatMap { try? PGNDocument($0).headers } ?? [:]
        self.opening = opening?.name ?? headers["Opening"]
        self.eco = opening?.eco ?? headers["ECO"]
        outcome = game.finishedResult?.outcome(for: game.playerSide)
        searchableText = ([game.white, game.black, game.username, game.id,
                           self.opening ?? "", self.eco ?? "", headers["Variation"] ?? "",
                           headers["Event"] ?? "", game.timeControl.title,
                           outcome?.rawValue ?? "", game.finishedResult?.rawValue ?? ""])
            .joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    public func matches(_ query: String, side: Side? = nil, result: PlayerGameOutcome? = nil) -> Bool {
        guard side == nil || game.playerSide == side, result == nil || outcome == result else { return false }
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { $0.isWhitespace })
        return words.allSatisfy { searchableText.contains($0) }
    }
}

/// Portable mainline export. Study lines deliberately have no finished-game result.
public enum GameNotationExport {
    public static func game(_ game: ChessGame) throws -> String {
        let replay = try GameReplay(game: game)
        var headers = game.pgn.flatMap { try? PGNDocument($0).headers } ?? [:]
        headers["Event"] = headers["Event"] ?? "?"
        headers["White"] = game.white
        headers["Black"] = game.black
        if headers["Date"] == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy.MM.dd"
            headers["Date"] = formatter.string(from: game.playedAt)
        }
        if headers["Site"] == nil { headers["Site"] = game.url?.absoluteString ?? "?" }
        let result = game.finishedResult?.rawValue ?? "*"
        return try render(position: replay.positions[0], moves: replay.moves, headers: headers, result: result)
    }

    public static func line(position: ChessPosition, moves: [ChessMove], headers: [String: String] = [:]) throws -> String {
        try render(position: position, moves: moves, headers: headers, result: "*")
    }

    private static func render(position: ChessPosition, moves: [ChessMove], headers original: [String: String], result: String) throws -> String {
        guard moves.count <= 20_000 else { throw ChessError.invalidPGN("This line is too long to export.") }
        var headers = original
        headers["Event"] = headers["Event"] ?? "ChessMe study"
        headers["Site"] = headers["Site"] ?? "?"
        headers["Date"] = headers["Date"] ?? "????.??.??"
        headers["Round"] = headers["Round"] ?? "?"
        headers["White"] = headers["White"] ?? "White"
        headers["Black"] = headers["Black"] ?? "Black"
        headers["Result"] = result
        if position == .initial {
            headers.removeValue(forKey: "SetUp"); headers.removeValue(forKey: "FEN")
        } else {
            headers["SetUp"] = "1"; headers["FEN"] = position.fen
        }
        let firstTags = ["Event", "Site", "Date", "Round", "White", "Black", "Result"]
        let tags = firstTags + headers.keys.filter { !firstTags.contains($0) }.sorted()
        let tagText = tags.compactMap { key -> String? in
            guard key.range(of: "^[A-Za-z][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                  let value = headers[key] else { return nil }
            let clean = value.components(separatedBy: .controlCharacters).joined(separator: " ")
                .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "[\(key) \"\(clean)\"]"
        }.joined(separator: "\n")
        var board = position
        var tokens: [String] = []
        for (index, move) in moves.enumerated() {
            try Task.checkCancellation()
            if board.sideToMove == .white { tokens.append("\(board.fullmoveNumber).") }
            else if index == 0 { tokens.append("\(board.fullmoveNumber)...") }
            tokens.append(try board.san(move))
            board = try board.applying(move)
        }
        tokens.append(result)
        var rows: [String] = [], row = ""
        for token in tokens {
            if !row.isEmpty && row.count + token.count + 1 > 80 { rows.append(row); row = "" }
            row += (row.isEmpty ? "" : " ") + token
        }
        if !row.isEmpty { rows.append(row) }
        return tagText + "\n\n" + rows.joined(separator: "\n") + "\n"
    }
}
