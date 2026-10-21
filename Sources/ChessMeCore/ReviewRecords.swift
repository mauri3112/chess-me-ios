import Foundation

/// Stable local identity, not a cryptographic hash or an authentication token.
public enum ReviewIdentity {
    public static func make(_ values: [String]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in values.joined(separator: "\u{1f}").utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public struct ReviewBookmark: Codable, Equatable, Sendable, Identifiable {
    public enum Place: String, Codable, Sendable { case overview, moment, recap }
    public var id: String { gameID }
    public let gameID: String
    public var revision: String
    public var place: Place
    public var momentID: String?
    public var step: Int
    public var visited: [String]
    public var finished: Bool
    public init(gameID: String, revision: String, place: Place = .overview, momentID: String? = nil,
                step: Int = 0, visited: [String] = [], finished: Bool = false) {
        self.gameID = gameID; self.revision = revision; self.place = place
        self.momentID = momentID; self.step = step; self.visited = visited; self.finished = finished
    }
}

public struct SavedReviewLine: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let gameID: String
    public let gameLabel: String
    public let username: String
    public let playerSide: Side
    public let initialFEN: String
    public let prefix: [String]
    public let moves: [String]
    public let positionFEN: String
    public let repetitionHistory: [String]
    public let opening: String?
    public let openingFamily: String
    public let savedAt: Date
    public var title: String

    public init(game: ChessGame, replay: GameReplay, title: String? = nil, now: Date = Date()) throws {
        guard !replay.variationMoves.isEmpty else {
            throw ChessError.invalidMove("Play a variation before saving a line.")
        }
        self.gameID = game.id; self.gameLabel = game.label; self.username = game.username
        self.playerSide = game.playerSide
        self.initialFEN = replay.positions[0].fen
        self.prefix = replay.moves.prefix(replay.index).map(\.uci)
        self.moves = replay.variationMoves.map(\.uci)
        self.positionFEN = replay.positions[replay.index].fen
        self.repetitionHistory = replay.positions.prefix(replay.index).map(\.repetitionKey)
        self.opening = OpeningBook.shared.line(in: replay, includingVariation: true).opening?.name
        self.openingFamily = OpeningFamily.name(for: opening)
        self.savedAt = now
        self.id = ReviewIdentity.make([game.username.lowercased(), game.id, initialFEN,
                                       prefix.joined(separator: " "), moves.joined(separator: " ")])
        self.title = title ?? "\(opening ?? "Saved line") · move \(replay.positions[replay.index].fullmoveNumber)"
    }

    public func replayGame() -> ChessGame {
        ChessGame(id: gameID, username: username, white: playerSide == .white ? username : "Opponent",
                  black: playerSide == .black ? username : "Opponent", playedAt: savedAt, playerSide: playerSide,
                  moves: (prefix + moves).joined(separator: " "), initialFEN: initialFEN, status: "resign")
    }

    public func matches(search: String, side: Side?) -> Bool {
        (side == nil || side == playerSide) &&
        (search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
         [title, opening ?? "", openingFamily].joined(separator: " ").localizedCaseInsensitiveContains(search))
    }
}

public enum OpeningFamily {
    public static func name(for opening: String?) -> String {
        guard let opening, !opening.isEmpty else { return "Unclassified opening" }
        // The catalogue uses a colon for named variations. Preserve a recognized
        // name when there is no supported broader family instead of guessing ECO.
        let family = opening.split(separator: ":", maxSplits: 1).first.map(String.init) ?? opening
        return family.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ReviewExposureKind: String, Codable, Sendable {
    case idea, line, hint, counterline, solution, topicCue
    public var revealsAnswer: Bool { self != .idea && self != .topicCue }
}

public struct ReviewExposure: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let targetID: String
    public let kind: ReviewExposureKind
    public let date: Date
    public init(targetID: String, kind: ReviewExposureKind, date: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.targetID = targetID; self.kind = kind; self.date = date
    }
}

public struct ReviewDecision: Codable, Identifiable, Equatable, Sendable {
    public enum Grade: String, Codable, Sendable { case accepted, mistake, ungraded }
    public let id: String
    public let positionFEN: String
    public let move: String
    public let grade: Grade
    public let date: Date
    public init(positionFEN: String, move: String, grade: Grade, date: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.positionFEN = positionFEN; self.move = move; self.grade = grade; self.date = date
    }
}

public struct ReviewPracticeAttempt: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case game, relatedPuzzle }
    public enum Outcome: String, Codable, Sendable { case inProgress, completed, revealed, skipped, ungraded, interrupted }
    public let id: String
    public let targetID: String
    public let kind: Kind
    public let puzzleID: String?
    public let evidenceRevision: String
    public let startedAt: Date
    public var endedAt: Date?
    public var decisions: [ReviewDecision] = []
    public var help: [ReviewExposureKind] = []
    public var outcome: Outcome = .inProgress
    public var knownSeenBefore: Bool
    public var topicCued: Bool
    public var linkedLessonRevision: String?
    public var sourceGameID: String?
    public var sourceUsername: String?
    public var rootFEN: String
    public var line: [String] = []

    public init(targetID: String, kind: Kind = .game, puzzleID: String? = nil, evidenceRevision: String,
                rootFEN: String, knownSeenBefore: Bool = false, topicCued: Bool = false,
                now: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.targetID = targetID; self.kind = kind; self.puzzleID = puzzleID
        self.evidenceRevision = evidenceRevision; self.rootFEN = rootFEN; self.startedAt = now
        self.knownSeenBefore = knownSeenBefore; self.topicCued = topicCued
    }
    public var hasMistake: Bool { decisions.contains { $0.grade == .mistake } }
    public var assisted: Bool { !help.isEmpty || hasMistake || outcome == .revealed }
    public var cleanCompletion: Bool {
        outcome == .completed && !assisted && decisions.contains { $0.grade == .accepted }
    }
    public var summary: String {
        switch outcome {
        case .completed: return assisted ? "Completed after help or retries" : "Completed without new help"
        case .revealed: return "Answer reviewed"
        case .skipped: return "Skipped"
        case .ungraded: return "Not yet verified"
        case .interrupted: return "Unfinished"
        case .inProgress: return "In progress"
        }
    }
}

public struct ReviewLearningTarget: Codable, Equatable, Identifiable, Sendable {
    public var id: String { finding.id }
    public let username: String
    public let finding: MoveFinding
    public let revision: String
    public let history: [String]
    public let ideaKey: String?
    public let createdAt: Date
    public var dueAt: Date
    public var deferredUntil: Date?
    public var dismissed = false
    public var kept = false
    public var invalidated = false
    public var reason = "A useful idea from your review"
    public init(username: String, finding: MoveFinding, revision: String, history: [String], ideaKey: String?,
                now: Date = Date()) {
        self.username = username; self.finding = finding; self.revision = revision; self.history = history
        self.ideaKey = ideaKey; self.createdAt = now; self.dueAt = now.addingTimeInterval(86_400)
    }
    public func ready(at date: Date) -> Bool {
        !dismissed && !invalidated && max(dueAt, deferredUntil ?? .distantPast) <= date
    }
    public var suggestedAt: Date { max(dueAt, deferredUntil ?? .distantPast) }
}

public struct ReviewFollowUpSession: Codable, Equatable, Sendable, Identifiable {
    public enum Surface: String, Codable, Sendable { case exercise, recap }
    public let id: String
    public let targetIDs: [String]
    public let startedAt: Date
    public var index = 0
    public var finished = false
    public let originGameID: String?
    public var findings: [MoveFinding]?
    public var attemptIDs: [String] = []
    public var activeRelatedRunID: String?
    public var surface: Surface = .exercise
    public var canResume: Bool { !finished || activeRelatedRunID != nil }
    public init(targetIDs: [String], originGameID: String? = nil, findings: [MoveFinding]? = nil, now: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.targetIDs = targetIDs; self.originGameID = originGameID; self.startedAt = now
        self.findings = findings
    }
}

public struct ReviewStandalonePractice: Codable, Equatable, Sendable {
    public let runID: String
    public let parentRunID: String?
    public let returnGameID: String?
    public init(runID: String, parentRunID: String? = nil, returnGameID: String? = nil) {
        self.runID = runID; self.parentRunID = parentRunID; self.returnGameID = returnGameID
    }
}

public struct ReviewGameObservation: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case soundChoice, missedOpportunity }
    public let id: String
    public let targetID: String
    public let gameID: String
    public let username: String
    public let ply: Int
    public let kind: Kind
    public let positionFEN: String
    public let playedMove: String
    public let keyLine: [String]
    public let explanation: String
    public let playedAt: Date
    public let assessedAt: Date
    public let revision: String
    public var lessonRevision: String?
    public init(targetID: String, game: ChessGame, ply: Int, kind: Kind, positionFEN: String,
                playedMove: String, keyLine: [String], explanation: String, revision: String, lessonRevision: String? = nil, now: Date = Date()) {
        self.id = ReviewIdentity.make([targetID, game.username.lowercased(), game.id, String(ply), kind.rawValue])
        self.targetID = targetID; self.gameID = game.id; self.username = game.username; self.ply = ply
        self.kind = kind; self.positionFEN = positionFEN; self.playedMove = playedMove; self.keyLine = keyLine
        self.explanation = explanation; self.playedAt = game.playedAt; self.assessedAt = now; self.revision = revision
        self.lessonRevision = lessonRevision
    }
}

/// New records live alongside legacy counters. Missing legacy facts are never
/// reconstructed as successful attempts or as unseen-position evidence.
public struct ReviewLibrary: Codable, Sendable {
    public var bookmarks: [ReviewBookmark] = []
    public var savedLines: [SavedReviewLine] = []
    public var exposures: [ReviewExposure] = []
    public var targets: [ReviewLearningTarget] = []
    public var attempts: [ReviewPracticeAttempt] = []
    public var observations: [ReviewGameObservation] = []
    public var session: ReviewFollowUpSession?
    public var runs: [AdaptiveReviewRun] = []
    public var standalonePractice: ReviewStandalonePractice?
    public init() {}

    private enum CodingKeys: String, CodingKey { case bookmarks, savedLines, exposures, targets, attempts, observations, session, runs, standalonePractice }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bookmarks = try values.decodeIfPresent([ReviewBookmark].self, forKey: .bookmarks) ?? []
        savedLines = try values.decodeIfPresent([SavedReviewLine].self, forKey: .savedLines) ?? []
        exposures = try values.decodeIfPresent([ReviewExposure].self, forKey: .exposures) ?? []
        targets = try values.decodeIfPresent([ReviewLearningTarget].self, forKey: .targets) ?? []
        attempts = try values.decodeIfPresent([ReviewPracticeAttempt].self, forKey: .attempts) ?? []
        observations = try values.decodeIfPresent([ReviewGameObservation].self, forKey: .observations) ?? []
        session = try values.decodeIfPresent(ReviewFollowUpSession.self, forKey: .session)
        runs = try values.decodeIfPresent([AdaptiveReviewRun].self, forKey: .runs) ?? []
        standalonePractice = try values.decodeIfPresent(ReviewStandalonePractice.self, forKey: .standalonePractice)
    }

    public mutating func expose(_ targetID: String, kind: ReviewExposureKind, now: Date = Date()) {
        // Re-rendering a visible card is not a new exposure. A later visit is.
        if let last = exposures.last, last.targetID == targetID, last.kind == kind,
           now.timeIntervalSince(last.date) < 2 { return }
        exposures.append(ReviewExposure(targetID: targetID, kind: kind, date: now))
    }

    public mutating func save(_ line: SavedReviewLine) {
        guard !savedLines.contains(where: { $0.id == line.id }) else { return }
        savedLines.append(line)
    }

    public mutating func enroll(_ target: ReviewLearningTarget) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { targets.append(target); return }
        guard targets[index].revision != target.revision else { return }
        // A newly encountered revision establishes a new lesson exposure. Keep
        // manual controls; historical attempts retain their own pinned evidence.
        var replacement = target
        replacement.kept = targets[index].kept
        replacement.dismissed = targets[index].dismissed
        replacement.deferredUntil = targets[index].deferredUntil
        targets[index] = replacement
        observations.removeAll { $0.targetID == target.id && $0.lessonRevision != target.revision }
    }

    public mutating func record(_ attempt: ReviewPracticeAttempt) {
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) { attempts[index] = attempt }
        else { attempts.append(attempt) }
        reschedule(targetID: attempt.targetID)
    }

    public func qualifiesForRecall(_ attempt: ReviewPracticeAttempt) -> Bool {
        guard attempt.kind == .game, attempt.cleanCompletion, let end = attempt.endedAt,
              let target = targets.first(where: { $0.id == attempt.targetID }),
              target.revision == attempt.evidenceRevision, !target.invalidated else { return false }
        guard !exposures.contains(where: {
            $0.targetID == attempt.targetID && $0.kind.revealsAnswer && $0.date > attempt.startedAt && $0.date <= end
        }) else { return false }
        let seen = exposures.filter { $0.targetID == attempt.targetID && $0.date <= attempt.startedAt }
            .map(\.date).max() ?? target.createdAt
        let earlier = attempts.filter {
            $0.id != attempt.id && $0.targetID == attempt.targetID && $0.kind == .game &&
            ($0.outcome == .completed || $0.outcome == .revealed || $0.assisted || $0.decisions.contains { $0.grade == .accepted }) &&
            ($0.endedAt ?? .distantFuture) <= attempt.startedAt
        }.compactMap(\.endedAt).max() ?? target.createdAt
        return end >= attempt.startedAt && attempt.startedAt.timeIntervalSince(max(seen, earlier)) >= Self.recallDelay
    }

    public func qualifiesForRelatedEvidence(_ attempt: ReviewPracticeAttempt) -> Bool {
        guard attempt.kind == .relatedPuzzle, attempt.cleanCompletion, !attempt.knownSeenBefore,
              attempt.puzzleID != nil, let target = targets.first(where: { $0.id == attempt.targetID }),
              !target.invalidated, target.revision == attempt.linkedLessonRevision else { return false }
        return true
    }

    /// A 24-hour operational gate avoids calling a midnight date change or an
    /// immediate solution replay delayed recall. It is not a scientific score.
    public static let recallDelay: TimeInterval = 86_400
    public static let sessionSize = 3

    public mutating func reschedule(targetID: String) {
        guard let index = targets.firstIndex(where: { $0.id == targetID }) else { return }
        let relevant = attempts.filter { $0.targetID == targetID && $0.kind == .game && $0.evidenceRevision == targets[index].revision }
            .sorted { $0.startedAt < $1.startedAt }
        var successes = 0
        var due = targets[index].createdAt.addingTimeInterval(Self.recallDelay)
        var reason = "A useful idea from your review"
        let days = [3, 7, 14, 30, 60]
        for attempt in relevant {
            if attempt.hasMistake || !attempt.help.isEmpty || attempt.outcome == .revealed {
                let event = attempt.endedAt ?? attempt.decisions.last?.date ?? attempt.startedAt
                due = event.addingTimeInterval(Self.recallDelay)
                reason = attempt.hasMistake ? "A decision to reinforce" : "You used help last time"
                successes = 0
            } else if qualifiesForRecall(attempt), let end = attempt.endedAt {
                due = end.addingTimeInterval(Double(days[min(successes, days.count - 1)]) * Self.recallDelay)
                successes += 1
                reason = "You recalled this later without new help"
            }
        }
        targets[index].dueAt = due; targets[index].reason = reason
    }

    public func suggestedSet(now: Date = Date(), excluding: Set<String> = []) -> [ReviewLearningTarget] {
        let candidates = targets.filter { $0.ready(at: now) && !excluding.contains($0.id) }.sorted {
            if $0.kept != $1.kept { return $0.kept }
            if $0.suggestedAt != $1.suggestedAt { return $0.suggestedAt < $1.suggestedAt }
            return $0.id < $1.id
        }
        var usedIdeas = Set<String>()
        var chosen: [ReviewLearningTarget] = []
        for target in candidates {
            let key = target.ideaKey ?? target.id
            guard usedIdeas.insert(key).inserted else { continue }
            chosen.append(target)
            if chosen.count == Self.sessionSize { break }
        }
        return chosen
    }

    public mutating func removeAccount(_ username: String, gameIDs: Set<String>) {
        func belongsToAccount(_ attempt: ReviewPracticeAttempt) -> Bool {
            attempt.sourceUsername?.lowercased() == username.lowercased() ||
                attempt.sourceGameID.map { gameIDs.contains($0) } == true
        }
        var ids = Set(targets.filter { $0.username.lowercased() == username.lowercased() || gameIDs.contains($0.finding.gameID) }.map(\.id))
        ids.formUnion((session?.findings ?? []).filter { gameIDs.contains($0.gameID) }.map(\.id))
        ids.formUnion(attempts.filter(belongsToAccount).map(\.targetID))
        ids.formUnion(runs.filter { belongsToAccount($0.attempt) }.map(\.targetID))
        targets.removeAll { ids.contains($0.id) }
        attempts.removeAll { ids.contains($0.targetID) }
        exposures.removeAll { ids.contains($0.targetID) }
        runs.removeAll { ids.contains($0.targetID) }
        observations.removeAll { ids.contains($0.targetID) || gameIDs.contains($0.gameID) || $0.username.lowercased() == username.lowercased() }
        bookmarks.removeAll { gameIDs.contains($0.gameID) }
        if session?.targetIDs.contains(where: { ids.contains($0) }) == true ||
            session?.findings?.contains(where: { gameIDs.contains($0.gameID) }) == true { session = nil }
        if let context = standalonePractice, let gameID = context.returnGameID, gameIDs.contains(gameID) {
            let runIDs = Set([context.runID] + [context.parentRunID].compactMap { $0 })
            runs.removeAll { runIDs.contains($0.id) }; attempts.removeAll { runIDs.contains($0.id) }
            standalonePractice = nil
        }
        if let context = standalonePractice, !runs.contains(where: { $0.id == context.runID }) { standalonePractice = nil }
        // Explicit variations have their own deletion scope under P3-R9.
    }
}
