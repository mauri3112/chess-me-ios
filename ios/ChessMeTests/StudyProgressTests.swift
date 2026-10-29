import XCTest
import ChessMeCore
@testable import ChessMe

@MainActor
final class StudyProgressTests: XCTestCase {
    func testDeletingTheRealLocalLibraryAlsoDeletesFundamentalsProgress() throws {
        let key = FundamentalsProgress.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("library.json")
        let storage = try LocalLibrary(url: url)
        try storage.save(LibrarySnapshot())
        UserDefaults.standard.set("back-rank", forKey: key)
        let model = AppModel(libraryStorage: storage)
        model.deleteLocalData()
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(model.library.games.isEmpty)
    }

    func testClearingSampleGamesPreservesRealFundamentalsProgress() {
        let key = FundamentalsProgress.preferenceKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("back-rank", forKey: key)
        let model = AppModel(previewLibrary: LibrarySnapshot(isDemo: true))
        model.deleteLocalData()
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "back-rank")
        XCTAssertTrue(model.library.isDemo)
    }
}
