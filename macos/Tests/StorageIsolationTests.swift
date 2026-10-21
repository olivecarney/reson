import XCTest
@testable import Reson

final class StorageIsolationTests: XCTestCase {
    func testUnconfiguredXCTestCannotUsePersonalStorage() async throws {
        let bridge=LibraryBridge()
        let _:LibraryReply=try await bridge.request(["op":"query"])
        await bridge.shutdown()
        XCTAssertTrue(RuntimeStorage.current.isolated)
        XCTAssertTrue(RuntimeStorage.current.database.path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path))
        XCTAssertTrue(RuntimeStorage.current.artwork.path.hasPrefix(RuntimeStorage.current.root!.path))
        XCTAssertNotEqual(RuntimeStorage.current.preferences,UserDefaults.standard)
    }
    func testIsolatedPreferencesPersistOnlyUnderRootAndRejectEscapingLinks() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer {try? FileManager.default.removeItem(at:root)}
        let environment=["RESON_DATA_ROOT":root.path]
        let first=try RuntimeStorage.resolve(environment:environment,testing:false)
        first.preferences.set(0.35,forKey:"playbackVolume");first.preferences.set(true,forKey:"playbackMuted")
        let reopened=try RuntimeStorage.resolve(environment:environment,testing:false)
        XCTAssertEqual(reopened.preferences.double(forKey:"playbackVolume"),0.35)
        XCTAssertTrue(reopened.preferences.bool(forKey:"playbackMuted"))
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("Preferences.plist").path))
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("library.db"),withDestinationURL:root.deletingLastPathComponent().appendingPathComponent("outside.db"))
        XCTAssertThrowsError(try RuntimeStorage.resolve(environment:environment,testing:false))
    }
    func testIsolationFailsClosedWithoutAbsoluteSeparateRoot() throws {
        for environment in [["RESON_ISOLATED":"1"],["RESON_DATA_ROOT":"relative"],["RESON_LIBRARY_PATH":"/tmp/legacy.db"]] {
            XCTAssertThrowsError(try RuntimeStorage.resolve(environment:environment,testing:false))
        }
        let personal=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Reson")
        XCTAssertThrowsError(try RuntimeStorage.resolve(environment:["RESON_DATA_ROOT":personal.path],testing:false))
    }
}
