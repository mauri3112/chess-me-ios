import Foundation

public enum ChessError: Error, Equatable, LocalizedError {
    case invalidFEN(String)
    case invalidMove(String)
    case invalidSAN(String)
    case invalidPGN(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidFEN(let reason): return "Invalid chess position: \(reason)"
        case .invalidMove(let move): return "Illegal move: \(move)"
        case .invalidSAN(let move): return "Could not replay move: \(move)"
        case .invalidPGN(let reason): return "Could not read game: \(reason)"
        case .cancelled: return "Analysis was paused."
        }
    }
}

public enum Side: String, Codable, CaseIterable, Sendable {
    case white, black
    public var opposite: Side { self == .white ? .black : .white }
    public var title: String { rawValue.capitalized }
}

public enum PieceKind: String, Codable, CaseIterable, Sendable {
    case pawn, knight, bishop, rook, queen, king
    public var sanSymbol: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
    public var value: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }
    fileprivate var fenLetter: String { self == .pawn ? "p" : sanSymbol.lowercased() }
}

public struct Piece: Codable, Equatable, Hashable, Sendable {
    public let kind: PieceKind
    public let side: Side
    public init(kind: PieceKind, side: Side) { self.kind = kind; self.side = side }
    public var symbol: String {
        switch (kind, side) {
        case (.king, .white): return "♔"
        case (.queen, .white): return "♕"
        case (.rook, .white): return "♖"
        case (.bishop, .white): return "♗"
        case (.knight, .white): return "♘"
        case (.pawn, .white): return "♙"
        case (.king, .black): return "♚"
        case (.queen, .black): return "♛"
        case (.rook, .black): return "♜"
        case (.bishop, .black): return "♝"
        case (.knight, .black): return "♞"
        case (.pawn, .black): return "♟"
        }
    }
}

public struct ChessMove: Codable, Equatable, Hashable, Sendable {
    /// Squares use a1 = 0, h1 = 7, a8 = 56, h8 = 63.
    public let from: Int
    public let to: Int
    public let promotion: PieceKind?
    public init(from: Int, to: Int, promotion: PieceKind? = nil) {
        self.from = from; self.to = to; self.promotion = promotion
    }
    public init(uci: String) throws {
        let chars = Array(uci.lowercased())
        guard chars.count == 4 || chars.count == 5,
              let from = Self.square(String(chars[0...1])),
              let to = Self.square(String(chars[2...3])) else { throw ChessError.invalidMove(uci) }
        var promotion: PieceKind?
        if chars.count == 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: throw ChessError.invalidMove(uci)
            }
        }
        self.init(from: from, to: to, promotion: promotion)
    }
    public var uci: String {
        Self.squareName(from) + Self.squareName(to) + (promotion?.fenLetter ?? "")
    }
    public static func square(_ name: String) -> Int? {
        let bytes = Array(name.utf8)
        guard bytes.count == 2, (97...104).contains(bytes[0]), (49...56).contains(bytes[1]) else { return nil }
        return Int(bytes[0] - 97) + Int(bytes[1] - 49) * 8
    }
    public static func squareName(_ square: Int) -> String {
        guard (0..<64).contains(square) else { return "?" }
        return String(UnicodeScalar(97 + square % 8)!) + String(square / 8 + 1)
    }
}

public enum PositionOutcome: Equatable, Sendable {
    case ongoing
    case checkmate(winner: Side)
    case stalemate
    case insufficientMaterial
    case fiftyMoveDraw
    case repetitionDraw
}

public struct ChessPosition: Equatable, Sendable {
    public private(set) var squares: [Piece?]
    public private(set) var sideToMove: Side
    public private(set) var castlingRights: String
    public private(set) var enPassantSquare: Int?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    public static let initial = try! ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    public init(fen: String) throws {
        let fields = fen.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 6 else { throw ChessError.invalidFEN("expected six fields") }
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { throw ChessError.invalidFEN("expected eight ranks") }
        var board = [Piece?](repeating: nil, count: 64)
        for (rankIndex, row) in rows.enumerated() {
            var file = 0
            for char in row {
                if let gap = char.wholeNumberValue, (1...8).contains(gap) { file += gap }
                else {
                    let kind: PieceKind
                    switch char.lowercased() {
                    case "p": kind = .pawn
                    case "n": kind = .knight
                    case "b": kind = .bishop
                    case "r": kind = .rook
                    case "q": kind = .queen
                    case "k": kind = .king
                    default: throw ChessError.invalidFEN("unknown piece")
                    }
                    guard file < 8 else { throw ChessError.invalidFEN("rank too long") }
                    guard kind != .pawn || (rankIndex != 0 && rankIndex != 7) else {
                        throw ChessError.invalidFEN("pawn on promotion rank")
                    }
                    board[(7 - rankIndex) * 8 + file] = Piece(kind: kind, side: char.isUppercase ? .white : .black)
                    file += 1
                }
                guard file <= 8 else { throw ChessError.invalidFEN("rank too long") }
            }
            guard file == 8 else { throw ChessError.invalidFEN("rank too short") }
        }
        guard fields[1] == "w" || fields[1] == "b" else { throw ChessError.invalidFEN("invalid side") }
        let rights = fields[2] == "-" ? "" : fields[2]
        guard rights.allSatisfy({ "KQkq".contains($0) }), Set(rights).count == rights.count else {
            throw ChessError.invalidFEN("invalid castling rights")
        }
        guard let half = Int(fields[4]), half >= 0, let full = Int(fields[5]), full > 0 else {
            throw ChessError.invalidFEN("invalid move counters")
        }
        let ep = fields[3] == "-" ? nil : ChessMove.square(fields[3])
        let side: Side = fields[1] == "w" ? .white : .black
        if fields[3] != "-" {
            guard let ep, ep / 8 == (side == .white ? 5 : 2), board[ep] == nil,
                  board[ep + (side == .white ? -8 : 8)] == Piece(kind: .pawn, side: side.opposite) else {
                throw ChessError.invalidFEN("invalid en passant square")
            }
        }
        for kingSide in Side.allCases {
            guard board.filter({ $0 == Piece(kind: .king, side: kingSide) }).count == 1 else {
                throw ChessError.invalidFEN("expected one king per side")
            }
        }
        self.squares = board
        self.sideToMove = side
        self.castlingRights = "KQkq".filter { rights.contains($0) }
        self.enPassantSquare = ep
        self.halfmoveClock = half
        self.fullmoveNumber = full
        guard !isInCheck(side.opposite) else { throw ChessError.invalidFEN("side that just moved is in check") }
        for (symbol, kingSquare, rookSquare, kingSide) in [
            (Character("K"), 4, 7, Side.white), (Character("Q"), 4, 0, Side.white),
            (Character("k"), 60, 63, Side.black), (Character("q"), 60, 56, Side.black)
        ] where castlingRights.contains(symbol) {
            guard squares[kingSquare] == Piece(kind: .king, side: kingSide),
                  squares[rookSquare] == Piece(kind: .rook, side: kingSide) else {
                throw ChessError.invalidFEN("castling pieces missing")
            }
        }
    }

    public var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = "", empty = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row += piece.side == .white ? piece.kind.fenLetter.uppercased() : piece.kind.fenLetter
                } else { empty += 1 }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        return rows.joined(separator: "/") + " \(sideToMove == .white ? "w" : "b") \(castlingRights.isEmpty ? "-" : castlingRights) \(enPassantSquare.map(ChessMove.squareName) ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Repetition ignores an en passant target unless a legal capture actually exists.
    public var repetitionKey: String {
        var fields = fen.split(separator: " ").prefix(4).map(String.init)
        if let ep = enPassantSquare,
           !legalMoves().contains(where: { $0.to == ep && squares[$0.from]?.kind == .pawn && $0.from % 8 != ep % 8 }) {
            fields[3] = "-"
        }
        return fields.joined(separator: " ")
    }

    public var isInCheck: Bool { isInCheck(sideToMove) }
    public func isInCheck(_ side: Side) -> Bool {
        guard let square = squares.firstIndex(of: Piece(kind: .king, side: side)) else { return true }
        return isAttacked(square, by: side.opposite)
    }

    public func isAttacked(_ square: Int, by side: Side) -> Bool {
        let rank = square / 8, file = square % 8
        let pawnRank = rank + (side == .white ? -1 : 1)
        for pawnFile in [file - 1, file + 1] where (0..<8).contains(pawnFile) && (0..<8).contains(pawnRank) {
            if squares[pawnRank * 8 + pawnFile] == Piece(kind: .pawn, side: side) { return true }
        }
        for (df, dr) in Self.knightSteps {
            if let target = Self.offset(square, df, dr), squares[target] == Piece(kind: .knight, side: side) { return true }
        }
        for (df, dr) in Self.kingSteps {
            if let target = Self.offset(square, df, dr), squares[target] == Piece(kind: .king, side: side) { return true }
        }
        for (df, dr) in Self.kingSteps {
            var target = Self.offset(square, df, dr)
            while let current = target {
                if let piece = squares[current] {
                    if piece.side == side && (piece.kind == .queen || (df == 0 || dr == 0 ? piece.kind == .rook : piece.kind == .bishop)) { return true }
                    break
                }
                target = Self.offset(current, df, dr)
            }
        }
        return false
    }

    public func legalMoves() -> [ChessMove] {
        pseudoLegalMoves().filter { !applyingUnchecked($0).isInCheck(sideToMove) }
    }

    public func applying(_ move: ChessMove) throws -> ChessPosition {
        guard legalMoves().contains(move) else { throw ChessError.invalidMove(move.uci) }
        return applyingUnchecked(move)
    }

    func applyingUnchecked(_ move: ChessMove) -> ChessPosition {
        var next = self
        let piece = squares[move.from]!
        let isCapture = squares[move.to] != nil || (piece.kind == .pawn && move.to == enPassantSquare)
        next.squares[move.from] = nil
        if piece.kind == .pawn && move.to == enPassantSquare && squares[move.to] == nil {
            next.squares[move.to + (piece.side == .white ? -8 : 8)] = nil
        }
        next.squares[move.to] = Piece(kind: move.promotion ?? piece.kind, side: piece.side)
        if piece.kind == .king && abs(move.to - move.from) == 2 {
            let rookFrom = move.to > move.from ? move.from + 3 : move.from - 4
            let rookTo = move.to > move.from ? move.from + 1 : move.from - 1
            next.squares[rookTo] = next.squares[rookFrom]
            next.squares[rookFrom] = nil
        }
        if piece.kind == .king {
            next.castlingRights.removeAll { piece.side == .white ? "KQ".contains($0) : "kq".contains($0) }
        }
        // Moving a rook or capturing it at its initial square removes the corresponding right.
        for (square, symbol) in [(0, Character("Q")), (7, Character("K")), (56, Character("q")), (63, Character("k"))] {
            if move.from == square || move.to == square { next.castlingRights.removeAll { $0 == symbol } }
        }
        next.enPassantSquare = piece.kind == .pawn && abs(move.to - move.from) == 16 ? (move.to + move.from) / 2 : nil
        next.halfmoveClock = piece.kind == .pawn || isCapture ? 0 : halfmoveClock + 1
        next.fullmoveNumber = fullmoveNumber + (sideToMove == .black ? 1 : 0)
        next.sideToMove = sideToMove.opposite
        return next
    }

    public func san(_ move: ChessMove) throws -> String {
        try san(move, legal: legalMoves())
    }

    private func san(_ move: ChessMove, legal: [ChessMove]) throws -> String {
        guard legal.contains(move), let piece = squares[move.from] else { throw ChessError.invalidMove(move.uci) }
        var result: String
        if piece.kind == .king && abs(move.to - move.from) == 2 { result = move.to > move.from ? "O-O" : "O-O-O" }
        else {
            let capture = squares[move.to] != nil || (piece.kind == .pawn && move.to == enPassantSquare)
            result = piece.kind.sanSymbol
            if piece.kind != .pawn {
                let peers = legal.filter { $0.to == move.to && $0.from != move.from && squares[$0.from]?.kind == piece.kind }
                if !peers.isEmpty {
                    let name = Array(ChessMove.squareName(move.from))
                    if !peers.contains(where: { $0.from % 8 == move.from % 8 }) { result += String(name[0]) }
                    else if !peers.contains(where: { $0.from / 8 == move.from / 8 }) { result += String(name[1]) }
                    else { result += String(name) }
                }
            } else if capture { result += String(Array(ChessMove.squareName(move.from))[0]) }
            if capture { result += "x" }
            result += ChessMove.squareName(move.to)
            if let promotion = move.promotion { result += "=" + promotion.sanSymbol }
        }
        let next = applyingUnchecked(move)
        if next.isInCheck { result += next.legalMoves().isEmpty ? "#" : "+" }
        return result
    }

    public func move(san token: String) throws -> ChessMove {
        let normalized = Self.normalizeSAN(token)
        let legal = legalMoves()
        if let uci = try? ChessMove(uci: normalized.lowercased()), legal.contains(uci) { return uci }
        let matches = try legal.filter { Self.normalizeSAN(try san($0, legal: legal)) == normalized }
        guard matches.count == 1, let move = matches.first else { throw ChessError.invalidSAN(token) }
        return move
    }

    public var hasInsufficientMaterial: Bool {
        let pieces = squares.enumerated().compactMap { index, piece -> (Int, Piece)? in
            guard let piece, piece.kind != .king else { return nil }; return (index, piece)
        }
        if pieces.isEmpty { return true }
        if pieces.count == 1 { return pieces[0].1.kind == .bishop || pieces[0].1.kind == .knight }
        // Any number of bishops on the same square color cannot produce mate.
        if pieces.allSatisfy({ $0.1.kind == .bishop }) {
            return Set(pieces.map { ($0.0 / 8 + $0.0 % 8) % 2 }).count == 1
        }
        return false
    }

    /// The caller supplies the count for this repetition key from its game history.
    /// Fifty-move and threefold draws are claimable; the app treats a valid claim as drawn.
    public func outcome(repetitionCount: Int = 1) -> PositionOutcome {
        if legalMoves().isEmpty { return isInCheck ? .checkmate(winner: sideToMove.opposite) : .stalemate }
        if hasInsufficientMaterial { return .insufficientMaterial }
        if halfmoveClock >= 100 { return .fiftyMoveDraw }
        if repetitionCount >= 3 { return .repetitionDraw }
        return .ongoing
    }

    func isCapture(_ move: ChessMove) -> Bool {
        squares[move.to] != nil || (squares[move.from]?.kind == .pawn && move.to == enPassantSquare)
    }

    private func pseudoLegalMoves() -> [ChessMove] {
        var moves: [ChessMove] = []
        func add(_ from: Int, _ to: Int) {
            if squares[from]?.kind == .pawn && (to / 8 == 0 || to / 8 == 7) {
                for kind in [PieceKind.queen, .rook, .bishop, .knight] { moves.append(ChessMove(from: from, to: to, promotion: kind)) }
            } else { moves.append(ChessMove(from: from, to: to)) }
        }
        for from in 0..<64 {
            guard let piece = squares[from], piece.side == sideToMove else { continue }
            switch piece.kind {
            case .pawn:
                let dr = piece.side == .white ? 1 : -1
                if let to = Self.offset(from, 0, dr), squares[to] == nil {
                    add(from, to)
                    if from / 8 == (piece.side == .white ? 1 : 6), let two = Self.offset(from, 0, dr * 2), squares[two] == nil { add(from, two) }
                }
                for df in [-1, 1] {
                    guard let to = Self.offset(from, df, dr) else { continue }
                    if let target = squares[to], target.side != piece.side, target.kind != .king { add(from, to) }
                    else if to == enPassantSquare { add(from, to) }
                }
            case .knight, .king:
                for (df, dr) in piece.kind == .knight ? Self.knightSteps : Self.kingSteps {
                    guard let to = Self.offset(from, df, dr), squares[to]?.side != piece.side, squares[to]?.kind != .king else { continue }
                    add(from, to)
                }
                if piece.kind == .king { moves += castlingMoves(from: from) }
            case .bishop, .rook, .queen:
                let directions = Self.kingSteps.filter { piece.kind == .queen || (piece.kind == .rook ? $0.0 == 0 || $0.1 == 0 : $0.0 != 0 && $0.1 != 0) }
                for (df, dr) in directions {
                    var to = Self.offset(from, df, dr)
                    while let current = to {
                        if let target = squares[current] {
                            if target.side != piece.side && target.kind != .king { add(from, current) }
                            break
                        }
                        add(from, current); to = Self.offset(current, df, dr)
                    }
                }
            }
        }
        return moves
    }

    private func castlingMoves(from: Int) -> [ChessMove] {
        guard from == (sideToMove == .white ? 4 : 60), !isInCheck else { return [] }
        let base = sideToMove == .white ? 0 : 56
        var moves: [ChessMove] = []
        for kingSide in [true, false] {
            let symbol: Character = sideToMove == .white ? (kingSide ? "K" : "Q") : (kingSide ? "k" : "q")
            let rook = base + (kingSide ? 7 : 0)
            let between = kingSide ? [base + 5, base + 6] : [base + 1, base + 2, base + 3]
            let travel = kingSide ? [base + 5, base + 6] : [base + 3, base + 2]
            guard castlingRights.contains(symbol), squares[rook] == Piece(kind: .rook, side: sideToMove),
                  between.allSatisfy({ squares[$0] == nil }), travel.allSatisfy({ !isAttacked($0, by: sideToMove.opposite) }) else { continue }
            moves.append(ChessMove(from: from, to: base + (kingSide ? 6 : 2)))
        }
        return moves
    }

    private static func offset(_ square: Int, _ df: Int, _ dr: Int) -> Int? {
        let file = square % 8 + df, rank = square / 8 + dr
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return rank * 8 + file
    }
    private static let knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static func normalizeSAN(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0", with: "O")
            .replacingOccurrences(of: "e.p.", with: "")
            .replacingOccurrences(of: "=", with: "")
            .filter { $0 != "+" && $0 != "#" && $0 != "!" && $0 != "?" && !$0.isWhitespace }
    }
}

public struct PGNDocument: Sendable {
    public let headers: [String: String]
    public let moves: [String]
    public let result: String?
    public let remainingClockCentiseconds: [Int?]
    public var initialFEN: String? { headers["FEN"] }
    public var clockData: GameClockData? {
        guard remainingClockCentiseconds.contains(where: { $0 != nil }) else { return nil }
        let control = (headers["TimeControl"] ?? "").split(separator: "+", omittingEmptySubsequences: false)
        let initial = control.count <= 2 ? control.first.flatMap { Int($0) } : nil
        let increment = initial == nil ? nil : (control.count == 1 ? 0 : Int(control[1]))
        let source: GameClockData.Source = URL(string: headers["Site"] ?? "")?.host == "lichess.org" ? .lichess : .pgn
        return GameClockData(initialSeconds: initial, incrementSeconds: increment, remainingCentiseconds: remainingClockCentiseconds, source: source)
    }
    public init(_ text: String) throws {
        let headerPattern = #"(?m)^\s*\[([A-Za-z0-9_]+)\s+"((?:\\.|[^"\\])*)"\]\s*$"#
        let expression = try NSRegularExpression(pattern: headerPattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var headers: [String: String] = [:]
        for match in expression.matches(in: text, range: range) {
            if let keyRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text) {
                headers[String(text[keyRange])] = String(text[valueRange]).replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\\"#, with: #"\"#)
            }
        }
        let body = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        var clean = "", variationDepth = 0, commentDepth = 0, lineComment = false
        var comment = "", clockComments: [Int] = []
        for character in body {
            if lineComment {
                if character.isNewline { lineComment = false; clean += " " }
                continue
            }
            if commentDepth > 0 {
                if character == "}" {
                    commentDepth -= 1; clean += " "
                    if commentDepth == 0, variationDepth == 0, let clock = GameClockData.parseClockComment(comment) {
                        clockComments.append(clock)
                        clean += " __chessme_clock_\(clockComments.count - 1)__ "
                    }
                }
                else if character == "{" { commentDepth += 1 }
                else { comment.append(character) }
                continue
            }
            if character == ";" { lineComment = true; continue }
            if character == "{" { commentDepth += 1; comment = ""; continue }
            if character == "}" { throw ChessError.invalidPGN("unmatched comment") }
            if character == "(" { variationDepth += 1; clean += " "; continue }
            if character == ")" {
                guard variationDepth > 0 else { throw ChessError.invalidPGN("unmatched variation") }
                variationDepth -= 1; clean += " "; continue
            }
            if variationDepth == 0 { clean.append(character) }
        }
        guard commentDepth == 0, variationDepth == 0 else { throw ChessError.invalidPGN("unfinished comment or variation") }
        let numberExpression = try NSRegularExpression(pattern: #"\d+\.(?:\.\.)?"#)
        clean = numberExpression.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..<clean.endIndex, in: clean), withTemplate: " ")
        let nagExpression = try NSRegularExpression(pattern: #"\$\d+"#)
        clean = nagExpression.stringByReplacingMatches(in: clean, range: NSRange(clean.startIndex..<clean.endIndex, in: clean), withTemplate: " ")
        let tokens = clean.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let results = ["1-0", "0-1", "1/2-1/2", "*"]
        var moves: [String] = [], result: String?, clocks: [Int?] = []
        for token in tokens {
            if token.hasPrefix("__chessme_clock_"), token.hasSuffix("__"),
               let index = Int(token.dropFirst(16).dropLast(2)), clockComments.indices.contains(index) {
                if !clocks.isEmpty { clocks[clocks.count - 1] = clockComments[index] }
                continue
            }
            if token.hasPrefix("$") || token == "e.p." || token == "..." { continue }
            if results.contains(token) { result = token; continue }
            guard result == nil else { throw ChessError.invalidPGN("moves after result") }
            guard !token.contains("[") && !token.contains("]") else { throw ChessError.invalidPGN("malformed header") }
            moves.append(token)
            clocks.append(nil)
        }
        self.headers = headers; self.moves = moves; self.result = result
        self.remainingClockCentiseconds = clocks
    }

    public func replay() throws -> [ChessPosition] {
        var position = try initialFEN.map(ChessPosition.init(fen:)) ?? .initial
        var positions = [position]
        for token in moves {
            position = try position.applying(position.move(san: token))
            positions.append(position)
        }
        return positions
    }
}
