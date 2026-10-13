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
        switch self { case .balanced: return 64; case .deep: return 128; case .maximum: return 256 }
    }
    public var requirement: String {
        switch self {
        case .balanced: return "iPhone 15 or newer"
        case .deep: return "iPhone 15 or newer with at least 8 GB memory"
        case .maximum: return "iPhone 17 or newer with at least 8 GB memory"
        }
    }
}

/// Eligibility is a product policy, not a claim about measured engine speed.
public struct LocalAnalysisHardware: Equatable, Sendable {
    public let modelIdentifier: String
    public let memoryMB: Int
    public let isSimulator: Bool
    public init(modelIdentifier: String, memoryMB: Int, isSimulator: Bool = false) {
        self.modelIdentifier = modelIdentifier; self.memoryMB = memoryMB; self.isSimulator = isSimulator
    }
    private var phoneFamily: Int? {
        guard modelIdentifier.hasPrefix("iPhone") else { return nil }
        return Int(modelIdentifier.dropFirst(6).split(separator: ",").first ?? "")
    }
    public var supportsOvernight: Bool {
        if isSimulator { return true }
        // iPhone 15 / 15 Plus share identifier family 15 with the older 14 Pro.
        if ["iPhone15,4", "iPhone15,5"].contains(modelIdentifier) { return true }
        if let phoneFamily { return phoneFamily >= 16 }
        return modelIdentifier.hasPrefix("iPad") && memoryMB >= 7_500
    }
    public func supports(_ level: LocalAnalysisLevel) -> Bool {
        guard supportsOvernight else { return false }
        if isSimulator { return true }
        switch level {
        case .balanced: return true
        case .deep: return memoryMB >= 7_500
        case .maximum:
            return memoryMB >= 7_500 && ((phoneFamily ?? 0) >= 18 || modelIdentifier.hasPrefix("iPad"))
        }
    }
    public func bounded(_ level: LocalAnalysisLevel) -> LocalAnalysisLevel {
        LocalAnalysisLevel.allCases.filter { supports($0) && $0.depth <= level.depth }.last ?? .balanced
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
    public var requiresPro: Bool
    public let createdAt: Date
    public var state: State = .queued
    public var message: String?
    public var checkpoint: GameAnalysis?

    public init(gameID: String, configuration: DeviceEngineConfiguration, level: LocalAnalysisLevel? = nil,
                nightOnly: Bool = false, requiresPro: Bool = false, createdAt: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; self.gameID = gameID; self.configuration = configuration; self.level = level
        self.nightOnly = nightOnly; self.requiresPro = requiresPro; self.createdAt = createdAt
    }
    public var isPending: Bool { state == .queued || state == .running }
    public var progress: Double {
        guard let checkpoint, checkpoint.totalPlies > 0 else { return state == .completed ? 1 : 0 }
        return Double(checkpoint.analyzedPlies) / Double(checkpoint.totalPlies)
    }
    public var reachedDepth: Int? { checkpoint?.moveAssessments?.map(\.completedDepth).min() }
    public mutating func recoverAfterInterruption() {
        guard state == .running else { return }
        state = .queued
        message = "Waiting to resume. Completed decisions are saved."
    }
}
