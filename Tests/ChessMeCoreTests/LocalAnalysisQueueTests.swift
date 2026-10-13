import XCTest
@testable import ChessMeCore

final class LocalAnalysisQueueTests: XCTestCase {
    func testBase15AndOlderDevicesKeepEveryDepthWithSmallerCaches() {
        for device in [LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144),
                       LocalAnalysisHardware(modelIdentifier: "iPhone15,2", memoryMB: 6_144),
                       LocalAnalysisHardware(modelIdentifier: "iPhone12,1", memoryMB: 4_096),
                       LocalAnalysisHardware(modelIdentifier: "iPad7,11", memoryMB: 3_072)] {
            XCTAssertTrue(device.supportsOvernight)
            for level in LocalAnalysisLevel.allCases { XCTAssertTrue(device.supports(level)) }
            XCTAssertEqual(device.bounded(.maximum), .maximum)
            XCTAssertLessThanOrEqual(device.cacheMegabytes(for: .maximum), 128)
        }
        let base15 = LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144)
        XCTAssertEqual(base15.cacheMegabytes(for: .maximum), 128)
        XCTAssertEqual(LocalAnalysisHardware(modelIdentifier: "iPad7,11", memoryMB: 3_072).cacheMegabytes(for: .maximum), 32)
    }

    func testMemoryPolicyUsesAppHeadroomAndCanWaitWithoutChangingDepth() {
        XCTAssertEqual(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 128, availableToAppMB: 512), 128)
        XCTAssertEqual(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 128, availableToAppMB: 448), 64)
        XCTAssertEqual(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 128, availableToAppMB: 400), 16)
        XCTAssertNil(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 128, availableToAppMB: 390))
        XCTAssertNil(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 32, availableToAppMB: 0))
        XCTAssertEqual(LocalAnalysisMemoryPolicy.cacheMegabytes(requested: 32, availableToAppMB: 2_048), 32)
    }

    func testSmallerCachePolicyRetainsJobsButAChangedDepthRequiresANewReview() {
        var old = DeviceEngineConfiguration()
        old.depth = 28; old.memoryMB = 128; old.secondsPerPosition = 60
        let job = LocalAnalysisJob(gameID: "saved-game", configuration: old, level: .deep)
        var requested = old
        requested.memoryMB = 64
        XCTAssertTrue(job.matches(configuration: requested, level: .deep))
        requested.depth = 32
        XCTAssertFalse(job.matches(configuration: requested, level: .maximum))
        requested = old; requested.secondsPerPosition = 180
        XCTAssertFalse(job.matches(configuration: requested, level: .deep))
    }

    func testNightCapacityUsesGameLengthsAndLowerCapacityForDeeperReviews() {
        func estimate(_ level: LocalAnalysisLevel, decisions: Double = 40) -> LocalAnalysisNightEstimate {
            var configuration = DeviceEngineConfiguration()
            configuration.depth = level.depth; configuration.secondsPerPosition = level.secondsPerDecision
            return LocalAnalysisNightEstimate(configuration: configuration, typicalDecisions: decisions,
                                               hardwareIdentifier: "iPhone15,4", engineVersion: "test")
        }
        let balanced = estimate(.balanced)
        XCTAssertEqual(balanced.minimumGames, 9)
        XCTAssertEqual(balanced.maximumGames, 14)
        XCTAssertLessThan(estimate(.deep).maximumGames, balanced.maximumGames)
        XCTAssertLessThan(estimate(.maximum).maximumGames, estimate(.deep).maximumGames)
        XCTAssertGreaterThan(estimate(.balanced, decisions: 20).minimumGames, balanced.minimumGames)
        XCTAssertLessThan(estimate(.balanced, decisions: 80).maximumGames, balanced.maximumGames)
        XCTAssertTrue(estimate(.maximum, decisions: 100).summary.contains("more than one night"))
        XCTAssertFalse(balanced.usesMeasuredSpeed)
    }

    func testCapacityCalibratesOnlyMatchingCompleteReviews() {
        var configuration = DeviceEngineConfiguration()
        configuration.depth = 28; configuration.secondsPerPosition = 60
        func timing(model: String = "iPhone15,4", version: String = "test", seconds: Double = 400) -> LocalAnalysisTiming {
            LocalAnalysisTiming(level: .deep, configurationID: configuration.options.configurationID,
                                engineVersion: version, hardwareIdentifier: model, decisions: 40, seconds: seconds)
        }
        let original = LocalAnalysisNightEstimate(configuration: configuration, hardwareIdentifier: "iPhone15,4", engineVersion: "test")
        let calibrated = LocalAnalysisNightEstimate(configuration: configuration, hardwareIdentifier: "iPhone15,4",
            engineVersion: "test", timings: [timing(), timing(model: "iPhone16,1", seconds: 1),
                                            timing(version: "old", seconds: 1), timing(seconds: .nan)])
        XCTAssertTrue(calibrated.usesMeasuredSpeed)
        XCTAssertGreaterThan(calibrated.minimumGames, original.maximumGames)
        XCTAssertEqual(calibrated.maximumGames, 21)
        let differentSettings = LocalAnalysisNightEstimate(configuration: DeviceEngineConfiguration(),
            hardwareIdentifier: "iPhone15,4", engineVersion: "test", timings: [timing()])
        XCTAssertFalse(differentSettings.usesMeasuredSpeed)
    }

    func testNightWindowAndNextOpportunityUseLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        func date(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour, minute: minute))!
        }
        XCTAssertFalse(OvernightAnalysisSettings.isNight(date(21, 59), calendar: calendar))
        XCTAssertTrue(OvernightAnalysisSettings.isNight(date(22), calendar: calendar))
        XCTAssertTrue(OvernightAnalysisSettings.isNight(date(6, 59), calendar: calendar))
        XCTAssertFalse(OvernightAnalysisSettings.isNight(date(7), calendar: calendar))
        XCTAssertEqual(OvernightAnalysisSettings.nextOpportunity(after: date(14), calendar: calendar), date(22))
        XCTAssertEqual(OvernightAnalysisSettings.nextOpportunity(after: date(23), calendar: calendar), date(23))
    }

    func testInterruptedJobRetainsCheckpointAndExplicitPauseIsPreserved() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        var configuration = DeviceEngineConfiguration()
        configuration.engine = .tactical; configuration.depth = 1
        var job = LocalAnalysisJob(gameID: game.id, configuration: configuration, level: .balanced)
        job.checkpoint = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1, maximumPositions: 1)).analyze(game: game)
        job.processingSeconds = 2.5; job.timedDecisions = 1
        job.state = .running
        let encoded = try JSONEncoder().encode(job)
        var recovered = try JSONDecoder().decode(LocalAnalysisJob.self, from: encoded)
        recovered.recoverAfterInterruption()
        XCTAssertEqual(recovered.state, .queued)
        XCTAssertEqual(recovered.checkpoint?.analyzedPlies, 1)
        XCTAssertEqual(recovered.checkpoint?.gameID, game.id)
        XCTAssertEqual(recovered.processingSeconds, 2.5)
        XCTAssertEqual(recovered.timedDecisions, 1)
        recovered.state = .paused
        recovered.recoverAfterInterruption()
        XCTAssertEqual(recovered.state, .paused)
    }

    func testCachedCompleteReviewNeverSaysItIsWaitingForTonight() throws {
        let game = try XCTUnwrap(DemoContent.games().first)
        let complete = try LocalAnalyzer(options: AnalysisOptions(maximumDepth: 1)).analyze(game: game)
        var job = LocalAnalysisJob(gameID: game.id, configuration: DeviceEngineConfiguration(), level: .balanced, nightOnly: true)
        job.checkpoint = complete; job.state = .completed
        XCTAssertEqual(job.statusText, "Review ready")
        job.message = "Waiting for tonight and charging"
        XCTAssertEqual(job.statusText, "Review ready")
        job.state = .running
        XCTAssertFalse(job.isPending)
        job.recoverAfterInterruption()
        XCTAssertEqual(job.state, .completed)
        XCTAssertEqual(job.statusText, "Review ready")
    }

    func testCompletedHigherBudgetCoversSmallerRequestsWithoutChangingEngine() {
        var high = DeviceEngineConfiguration()
        high.depth = 32; high.secondsPerPosition = 180; high.searchNodeLimit = 100_000_000
        var low = high
        low.depth = 24; low.secondsPerPosition = 15; low.searchNodeLimit = 5_000_000; low.memoryMB = 32
        XCTAssertTrue(high.covers(low))
        XCTAssertFalse(low.covers(high))
        low.engine = .arasan
        XCTAssertFalse(high.covers(low))
    }
}
