import XCTest
@testable import MacWineCore

final class LibraryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func write(_ path: String, _ value: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try value.write(to: file, atomically: true, encoding: .utf8)
    }
    func testVDFCommentsEscapesAndNestedObjects() {
        let value = VDF.parse(#"""
        // header
        "libraryfolders" { "0" { "path" "C:\\Games\\Steam" "apps" { "123" "4" } } }
        "title" "A \"quoted\" game"
        "tail" "ok"
        "truncated"
        """#)
        XCTAssertEqual(value["libraryfolders"]?.object?["0"]?.object?["path"]?.text, #"C:\Games\Steam"#)
        XCTAssertEqual(value["title"]?.text, "A \"quoted\" game")
        XCTAssertEqual(value["tail"]?.text, "ok")
    }
    func testSteamExternalLibrariesDeduplicateAndStateBits() throws {
        let steam = "drive_c/Program Files (x86)/Steam/steamapps"
        try write(steam + "/libraryfolders.vdf", #"""
        "libraryfolders" { "0" { "path" "C:\\Program Files (x86)\\Steam" } "1" { "path" "C:\\Games" } }
        """#)
        try write(steam + "/appmanifest_10.acf", #"""
        "AppState" { "appid" "10" "name" "Installed" "StateFlags" "6" }
        """#)
        try write(steam + "/appmanifest_228980.acf", #"""
        "AppState" { "appid" "228980" "name" "Redistributable" "StateFlags" "4" }
        """#)
        try write("drive_c/Games/steamapps/appmanifest_11.acf", #"""
        "AppState" { "appid" "11" "name" "Pending" "StateFlags" "2" }
        """#)
        let games = LibraryScanner().scan([Bottle(name: "test", path: root.path)]).games
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first { $0.storeID == "10" }?.installed, true)
        XCTAssertEqual(games.first { $0.storeID == "11" }?.installed, false)
    }
    func testEpicGOGAndUbisoftWithMalformedManifest() throws {
        try write("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests/a.item", #"""
        {"DisplayName":"Epic title","AppName":"epic-id","InstallLocation":"C:\\Epic Game","LaunchExecutable":"bin\\play.exe"}
        """#)
        try write("drive_c/Epic Game/bin/play.exe", "")
        try write("drive_c/ProgramData/Epic/EpicGamesLauncher/Data/Manifests/b.item", "broken")
        try write("drive_c/GOG Games/Gog title/goggame-42.info", #"""
        {"gameId":42,"name":"Gog title","playTasks":[{"path":"config.exe"},{"isPrimary":true,"path":"bin\\play.exe"}]}
        """#)
        try write("drive_c/Ubisoft Game/game.exe", "")
        try write("system.reg", #"""
        [Software\\Wow6432Node\\Ubisoft\\Launcher\\Installs\\123] 0
        "InstallDir"="C:\\Ubisoft Game"
        [Software\\Other] 0
        "InstallDir"="C:\\Not a game"
        """#)
        let result = LibraryScanner().scan([Bottle(name: "test", path: root.path)])
        XCTAssertEqual(Set(result.games.map(\.store)), Set([.epic, .gog, .ubisoft]))
        XCTAssertTrue(result.games.allSatisfy(\.installed))
        XCTAssertTrue(result.games.first { $0.store == .gog }?.executable?.hasSuffix("/\(root.lastPathComponent)/drive_c/GOG Games/Gog title/bin/play.exe") == true)
        XCTAssertEqual(result.games.first { $0.store == .ubisoft }?.name, "Ubisoft Game")
        XCTAssertEqual(result.warnings.count, 1)
    }
    func testWindowsDriveMappingAndMissingLibraries() {
        let scanner = LibraryScanner()
        XCTAssertEqual(scanner.windowsURL(#"D:\Games\Title"#, bottle: root)?.path, root.appendingPathComponent("dosdevices/d:/Games/Title").path)
        XCTAssertNil(scanner.windowsURL("relative.exe", bottle: root))
        XCTAssertTrue(scanner.scan([Bottle(name: "empty", path: root.path)]).games.isEmpty)
    }
    func testCLIArgumentsDoNotEnterShellAndLargeOutputDoesNotDeadlock() async throws {
        try write("mock", "#!/bin/bash\nprintf '%s\\n' \"$1\"\n/usr/bin/head -c 100000 /dev/zero\n/usr/bin/head -c 100000 /dev/zero >&2\n")
        let mock = root.appendingPathComponent("mock")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mock.path)
        let input = "a; touch \(root.path)/INJECTED"
        let data = try await CLI(url: mock).run([input])
        XCTAssertTrue(String(decoding: data.prefix(input.utf8.count), as: UTF8.self) == input)
        XCTAssertGreaterThan(data.count, 100000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("INJECTED").path))
    }
    func testCLIErrorsPreserveDiagnostic() async throws {
        try write("mock", "#!/bin/bash\necho 'Chyba instalace' >&2\nexit 4\n")
        let mock = root.appendingPathComponent("mock")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mock.path)
        do { _ = try await CLI(url: mock).run([]); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Chyba instalace")) }
    }
}
