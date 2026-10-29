import XCTest
@testable import ChessMe

final class FundamentalsProgressContextTests: XCTestCase {
    func testSampleCompletionCannotCrossIntoPersonalProgress() {
        let generation = UUID()
        let opened = FundamentalsProgressContext(generation: generation, isSample: true)
        XCTAssertFalse(opened.acceptsCompletion(in: FundamentalsProgressContext(generation: generation, isSample: false)))
        XCTAssertFalse(opened.acceptsCompletion(in: FundamentalsProgressContext(generation: UUID(), isSample: false)))
        XCTAssertTrue(opened.acceptsCompletion(in: opened))
    }

    func testClearInvalidatesBothPersonalAndSampleRunsEvenWhenModeStaysTheSame() {
        for sample in [false, true] {
            let opened = FundamentalsProgressContext(generation: UUID(), isSample: sample)
            let cleared = FundamentalsProgressContext(generation: UUID(), isSample: sample)
            XCTAssertFalse(opened.acceptsCompletion(in: cleared))
            XCTAssertTrue(cleared.acceptsCompletion(in: cleared))
        }
    }

    @MainActor
    func testActualLibraryClearAndDemoExitInvalidateAnOpenSampleExercise() {
        let model = AppModel(previewLibrary: LibrarySnapshot(isDemo: true))
        let opened = FundamentalsProgressContext(generation: model.reviewGeneration, isSample: model.isDemo)
        model.deleteLocalData()
        let cleared = FundamentalsProgressContext(generation: model.reviewGeneration, isSample: model.isDemo)
        XCTAssertTrue(cleared.isSample)
        XCTAssertFalse(opened.acceptsCompletion(in: cleared))
        model.exitDemo()
        let personal = FundamentalsProgressContext(generation: model.reviewGeneration, isSample: model.isDemo)
        XCTAssertFalse(personal.isSample)
        XCTAssertFalse(cleared.acceptsCompletion(in: personal))
    }
}
