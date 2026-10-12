import XCTest
@testable import MacWineCore

final class StoreLibraryTests: XCTestCase {
    func testOwnedUninstalledGamesRemainInstallableAndLocalCopiesStayInstalled() throws {
        let data = Data(#"""
        [{"id":"1","name":"Owned installed","installed":false,"bottle":"test","artworkURL":"https://example.com/1.jpg"},
         {"id":"2","name":"Owned not installed","installed":false,"bottle":"test"}]
        """#.utf8)
        let library = try JSONDecoder().decode(StoreLibrary.self, from: data)
        let result = LibraryMerge.merge(local: [Game(bottle: "test", store: .steam, storeID: "1", name: "Local title", installed: true, executable: "/game.exe")], owned: library.games, store: .steam, bottle: "test")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.first { $0.storeID == "1" }!.installed)
        XCTAssertEqual(result.first { $0.storeID == "1" }?.executable, "/game.exe")
        XCTAssertEqual(result.first { $0.storeID == "1" }?.artworkURL, "https://example.com/1.jpg")
        XCTAssertFalse(result.first { $0.storeID == "2" }!.installed)
        XCTAssertFalse(library.complete, "An array alone cannot establish a complete account library")
    }
    func testMergeDoesNotConfuseStoresOrBottles() throws {
        let data = Data(#"[{"id":"1","name":"Steam owned","installed":false}]"#.utf8)
        let owned = try JSONDecoder().decode([OwnedGame].self, from: data)
        let local = [Game(bottle: "other", store: .steam, storeID: "1", name: "Other", installed: true),
                     Game(bottle: "test", store: .gog, storeID: "1", name: "GOG", installed: true)]
        let merged = LibraryMerge.merge(local: local, owned: owned, store: .steam, bottle: "test")
        XCTAssertEqual(merged.count, 3)
        XCTAssertFalse(merged.first { $0.bottle == "test" && $0.store == .steam }!.installed)
    }
    func testAccountCapabilityAndLibraryEnvelope() throws {
        let data = Data(#"[{"store":"gog","connected":true,"fullLibrary":false,"status":"not-supported","bottle":"test","message":"Launcher only"}]"#.utf8)
        let accounts = try JSONDecoder().decode([StoreAccount].self, from: data)
        XCTAssertEqual(accounts[0].fullLibrary, false)
        XCTAssertEqual(accounts[0].message, "Launcher only")
        let library = try JSONDecoder().decode(StoreLibrary.self, from: Data(#"{"games":[],"complete":true,"message":"Empty account"}"#.utf8))
        XCTAssertTrue(library.complete)
    }
    func testSecretInputIsNotInArgumentsAndErrorIsRedacted() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("mock")
        try "#!/bin/bash\nread -r secret\nprintf 'args=%s secret=%s' \"$*\" \"$secret\" >&2\nexit 2\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        do {
            _ = try await CLI(url: file).run(["set-key", "steam"], input: Data("test-secret-123\n".utf8))
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("test-secret-123"))
            XCTAssertTrue(error.localizedDescription.contains("args=set-key steam secret=[redacted]"))
        }
    }
}
