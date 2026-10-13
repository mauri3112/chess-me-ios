import XCTest
@testable import ChessMeCore

final class LocalAnalysisQueueTests: XCTestCase {
    func testHardwarePolicyDistinguishesBase15FromOlder14Pro() {
        XCTAssertFalse(LocalAnalysisHardware(modelIdentifier: "iPhone15,2", memoryMB: 6_144).supportsOvernight)
        XCTAssertTrue(LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144).supports(.balanced))
        XCTAssertFalse(LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144).supports(.deep))
        XCTAssertTrue(LocalAnalysisHardware(modelIdentifier: "iPhone16,1", memoryMB: 8_192).supports(.deep))
        XCTAssertFalse(LocalAnalysisHardware(modelIdentifier: "iPhone17,3", memoryMB: 8_192).supports(.maximum))
        XCTAssertTrue(LocalAnalysisHardware(modelIdentifier: "iPhone18,3", memoryMB: 8_192).supports(.maximum))
        XCTAssertEqual(LocalAnalysisHardware(modelIdentifier: "iPhone15,4", memoryMB: 6_144).bounded(.maximum), .balanced)
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
        job.state = .running
        let encoded = try JSONEncoder().encode(job)
        var recovered = try JSONDecoder().decode(LocalAnalysisJob.self, from: encoded)
        recovered.recoverAfterInterruption()
        XCTAssertEqual(recovered.state, .queued)
        XCTAssertEqual(recovered.checkpoint?.analyzedPlies, 1)
        XCTAssertEqual(recovered.checkpoint?.gameID, game.id)
        recovered.state = .paused
        recovered.recoverAfterInterruption()
        XCTAssertEqual(recovered.state, .paused)
    }
}
