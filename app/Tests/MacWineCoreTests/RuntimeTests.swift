import XCTest
@testable import MacWineCore

private actor ProgressRecorder {
    var values: [Double] = []
    func record(_ line: String) { if let value = RuntimeProgress.percent(from: line) { values.append(value) } }
}
final class RuntimeTests: XCTestCase {
    func testReadinessRequiresInstalledUsableRuntime() throws {
        for json in [
            #"{"installed":null,"required":"v2","upToDate":false,"path":null}"#,
            #"{"installed":"v1","required":"v2","upToDate":false,"path":"/runtime"}"#,
            #"{"installed":"v2","required":"v2","upToDate":true,"path":null}"#
        ] { XCTAssertFalse(try JSONDecoder().decode(RuntimeStatus.self, from: Data(json.utf8)).isReady) }
        let local = #"{"installed":"bundled","required":null,"upToDate":true,"path":"/runtime"}"#
        XCTAssertTrue(try JSONDecoder().decode(RuntimeStatus.self, from: Data(local.utf8)).isReady)
    }
    func testProgressRejectsDiagnosticsAndInvalidValues() {
        XCTAssertEqual(RuntimeProgress.percent(from: "progress 42.5\r"), 42.5)
        for line in ["progress -1", "progress 101", "progress nan", "progress inf", "progress 20 extra", "Downloading 10", "progress"] {
            XCTAssertNil(RuntimeProgress.percent(from: line))
        }
    }
    func testStreamingProgressBeforeExitAndUnterminatedFinalLine() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("runtime")
        // The child waits for acknowledgement: buffering all stderr until exit would fail this test.
        let source = """
        #!/bin/bash
        printf 'pro' >&2
        printf 'gress 12\\n' >&2
        for i in {1..40}; do
          [ -f "$1/ack" ] && break
          sleep 0.05
        done
        [ -f "$1/ack" ] || exit 9
        printf 'diagnostic\\nprogress 100' >&2
        printf '{"installed":"v2"}'
        """
        try source.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let recorder = ProgressRecorder()
        let result = try await CLI(url: script).run([directory.path], onStderrLine: { line in
            await recorder.record(line)
            if RuntimeProgress.percent(from: line) == 12 { FileManager.default.createFile(atPath: directory.appendingPathComponent("ack").path, contents: nil) }
        })
        XCTAssertEqual(String(decoding: result, as: UTF8.self), #"{"installed":"v2"}"#)
        let values = await recorder.values
        XCTAssertEqual(values, [12, 100])
    }
    func testStreamingFailureDoesNotBecomeSuccessAt100Percent() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try "#!/bin/bash\necho 'progress 100' >&2\necho 'Checksum mismatch' >&2\nexit 2\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        do {
            _ = try await CLI(url: file).run([], onStderrLine: { _ in })
            XCTFail("Expected verification failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Checksum mismatch"))
            XCTAssertFalse(error.localizedDescription.contains("progress 100"))
        }
    }
}
