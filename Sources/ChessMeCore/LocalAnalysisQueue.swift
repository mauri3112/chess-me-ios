import Foundation

public enum LocalAnalysisLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced, deep, maximum
    public var id: String { rawValue }
    public var title: String {
        switch self { case .balanced: return "Balanced"; case .deep: return "Deep"; case .maximum: return "Maximum" }
    }
    public var depth: Int {
        switch self { case .balanced: return 24; case .deep: return 28; case .maximum: return 32 }
    }
    public var secondsPerDecision: Int {
        switch self { case .balanced: return 15; case .deep: return 60; case .maximum: return 180 }
    }
    public var nodeLimit: Int {
        switch self { case .balanced: return 5_000_000; case .deep: return 20_000_000; case .maximum: return 100_000_000 }
    }
    public var memoryMB: Int {
        switch self { case .balanced: return 32; case .deep: return 64; case .maximum: return 128 }
    }
    public var requirement: String {
        "An iPhone or iPad running iOS 17 or later"
    }
}

/// Depth is a time/work preference. Device memory only bounds the search cache.
public struct LocalAnalysisHardware: Equatable, Sendable {
    public let modelIdentifier: String
    public let memoryMB: Int
    public let isSimulator: Bool
    public init(modelIdentifier: String, memoryMB: Int, isSimulator: Bool = false) {
        self.modelIdentifier = modelIdentifier; self.memoryMB = memoryMB; self.isSimulator = isSimulator
    }
    public var supportsOvernight: Bool {
        isSimulator || modelIdentifier.hasPrefix("iPhone") || modelIdentifier.hasPrefix("iPad")
    }
    public func supports(_ level: LocalAnalysisLevel) -> Bool {
        supportsOvernight
    }
    public func bounded(_ level: LocalAnalysisLevel) -> LocalAnalysisLevel {
        supportsOvernight ? level : .balanced
    }
    public func cacheMegabytes(for level: LocalAnalysisLevel) -> Int {
        min(level.memoryMB, memoryMB < 4_000 ? 32 : 128)
    }
    public var engineThreads: Int { memoryMB < 4_000 ? 1 : 2 }
}

public enum LocalAnalysisResourceError: LocalizedError {
    case insufficientMemory
    public var errorDescription: String? { "Waiting for device memory to recover. Completed decisions are saved." }
}

public enum LocalAnalysisMemoryPolicy {
    // Leave room for a cold NNUE load, search-thread state and the rest of the
    // app. This is an allocation reserve, not a measured total app footprint.
    public static let reserveMegabytes = 384
    public static func cacheMegabytes(requested: Int, availableToAppMB: Int?) -> Int? {
        let ceiling = min(128, max(8, requested))
        guard let availableToAppMB else { return ceiling }
        let budget = min(ceiling, max(0, availableToAppMB - reserveMegabytes))
        return [8, 16, 32, 64, 128].last { $0 <= budget }
    }
}

/// A complete review measured on this device. Partial or interrupted searches
/// must not make an opening-only sample look like a typical complete game.
public struct LocalAnalysisTiming: Codable, Equatable, Sendable {
    public let level: LocalAnalysisLevel
    public let configurationID: String
    public let engineVersion: String
    public let hardwareIdentifier: String
    public let decisions: Int
    public let seconds: Double
    public init(level: LocalAnalysisLevel, configurationID: String, engineVersion: String,
                hardwareIdentifier: String, decisions: Int, seconds: Double) {
        self.level = level; self.configurationID = configurationID; self.engineVersion = engineVersion
        self.hardwareIdentifier = hardwareIdentifier; self.decisions = decisions; self.seconds = seconds
    }
}

public struct LocalAnalysisNightEstimate: Equatable, Sendable {
    public let minimumGames: Int
    public let maximumGames: Int
    public let usesMeasuredSpeed: Bool
    public var summary: String {
        if maximumGames == 0 { return "A game may need more than one night" }
        if minimumGames == 0 { return "Up to \(maximumGames) \(maximumGames == 1 ? "game" : "games") per night" }
        if minimumGames == maximumGames { return "About \(maximumGames) \(maximumGames == 1 ? "game" : "games") per night" }
        return "About \(minimumGames)–\(maximumGames) games per night"
    }

    public init(configuration: DeviceEngineConfiguration, typicalDecisions: Double = 40,
                hardwareIdentifier: String, engineVersion: String, timings: [LocalAnalysisTiming] = []) {
        let matching = timings.filter {
            $0.configurationID == configuration.options.configurationID && $0.hardwareIdentifier == hardwareIdentifier &&
            $0.engineVersion == engineVersion && $0.decisions > 0 && $0.seconds.isFinite && $0.seconds > 0
        }.suffix(10)
        usesMeasuredSpeed = !matching.isEmpty
        let measured = matching.reduce(0.0) { $0 + $1.seconds } / Double(max(1, matching.reduce(0) { $0 + $1.decisions }))
        let secondsPerDecision = usesMeasuredSpeed ? max(0.25, measured) : Double(configuration.secondsPerPosition)
        let decisions = typicalDecisions.isFinite ? max(1, typicalDecisions) : 40
        let secondsPerGame = max(1, secondsPerDecision * decisions)
        // Capacity planning assumes three hours of opportunities. Leave 20–50%
        // for thermal throttling, startup, interruption and checkpoint work.
        // iOS does not promise that this processing time will be granted.
        let capacity = min(999, 3 * 3_600 / secondsPerGame)
        minimumGames = Int((capacity * 0.5).rounded(.down))
        maximumGames = Int((capacity * 0.8).rounded(.down))
    }
}

public struct OvernightAnalysisSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var level: LocalAnalysisLevel = .balanced
    public init() {}
    public static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= 22 || hour < 7
    }
    public static func nextOpportunity(after date: Date, calendar: Calendar = .current) -> Date {
        if isNight(date, calendar: calendar) { return date }
        return calendar.nextDate(after: date, matching: DateComponents(hour: 22, minute: 0), matchingPolicy: .nextTime) ?? date
    }
}

public struct LocalAnalysisJob: Codable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable { case queued, running, paused, completed, failed }
    public let id: String
    public let gameID: String
    public let configuration: DeviceEngineConfiguration
    public let level: LocalAnalysisLevel?
    public var nightOnly: Bool
    /// Explicit game selection remains scheduled even when automatic overnight imports are off.
    public var scheduledByUser: Bool?
    public var requiresPro: Bool
    public let createdAt: Date
    public var state: State = .queued
    public var message: String?
    public var checkpoint: GameAnalysis?
    public var processingSeconds: Double?
    public var timedDecisions: Int?

    public init(gameID: String, configuration: DeviceEngineConfiguration, level: LocalAnalysisLevel? = nil,
                nightOnly: Bool = false, requiresPro: Bool = false, createdAt: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.gameID = gameID; self.configuration = configuration; self.level = level
        self.nightOnly = nightOnly; self.requiresPro = requiresPro; self.createdAt = createdAt
    }
    public var isPending: Bool { (state == .queued || state == .running) && checkpoint?.isComplete != true }
    public var statusText: String {
        switch state {
        case .completed: return "Review ready"
        case .running: return "Analyzing with \(configuration.engine.title)"
        case .queued: return message ?? (nightOnly ? "Waiting for tonight and charging" : "Waiting to start")
        case .paused: return message ?? "Paused. Completed decisions are saved."
        case .failed: return message ?? "Review could not finish. Try resuming it."
        }
    }
    public var progress: Double {
        guard let checkpoint, checkpoint.totalPlies > 0 else { return state == .completed ? 1 : 0 }
        return Double(checkpoint.analyzedPlies) / Double(checkpoint.totalPlies)
    }
    public var reachedDepth: Int? { checkpoint?.moveAssessments?.map(\.completedDepth).min() }
    /// A cache-policy update must not discard an existing review checkpoint.
    /// Continue that job with its saved configuration and search identity.
    public func matches(configuration requested: DeviceEngineConfiguration, level requestedLevel: LocalAnalysisLevel?) -> Bool {
        if configuration == requested { return true }
        guard level != nil, level == requestedLevel, configuration.engine.isNeural else { return false }
        var ignoringCache = configuration
        ignoringCache.memoryMB = requested.memoryMB
        return ignoringCache == requested
    }
    public mutating func recoverAfterInterruption() {
        if checkpoint?.isComplete == true {
            state = .completed
            message = "Review ready"
            return
        }
        guard state == .running else { return }
        state = .queued
        message = "Waiting to resume. Completed decisions are saved."
    }
}
