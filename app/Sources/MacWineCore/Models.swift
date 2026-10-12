import Foundation

public struct Bottle: Identifiable, Decodable, Hashable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let fps: Int
    public let graphics: String
    public let windows: String
    public let running: Bool
    public init(name: String, path: String, fps: Int = 0, graphics: String = "dxvk", windows: String = "win10", running: Bool = false) {
        self.name = name; self.path = path; self.fps = fps
        self.graphics = graphics; self.windows = windows; self.running = running
    }
}
public enum Store: String, CaseIterable, Identifiable, Codable {
    case steam, epic, gog, ubisoft, exe
    public var id: String { rawValue }
    public var title: String {
        switch self { case .steam: return "Steam"; case .epic: return "Epic Games"; case .gog: return "GOG"; case .ubisoft: return "Ubisoft Connect"; case .exe: return "Custom Apps" }
    }
}
public struct Game: Identifiable, Hashable {
    public var id: String { "\(bottle)\u{1f}\(store.rawValue)\u{1f}\(storeID)" }
    public var launchID: String { store == .exe ? (executable ?? storeID) : storeID }
    public let bottle: String
    public let store: Store
    public let storeID: String
    public let name: String
    public let installed: Bool
    public let executable: String?
    public let artworkURL: String?
    public init(bottle: String, store: Store, storeID: String, name: String, installed: Bool, executable: String? = nil, artworkURL: String? = nil) {
        self.bottle = bottle; self.store = store; self.storeID = storeID
        self.name = name; self.installed = installed; self.executable = executable; self.artworkURL = artworkURL
    }
}
public struct BottleSettings: Decodable {
    public var fps: Int
    public var graphics: String
    public var windows: String
    public var msync: Bool
    public var hud: Bool
}

// Argument arrays go straight to Process; game names and paths never enter a shell.
public struct CLI: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static func locate() -> CLI {
        if let path = ProcessInfo.processInfo.environment["MACWINE_CLI"] {
            return CLI(url: URL(fileURLWithPath: path))
        }
        return CLI(url: Bundle.main.resourceURL!.appendingPathComponent("macwine"))
    }
    public func run(_ arguments: [String], input: Data? = nil, onStderrLine: (@Sendable (String) async -> Void)? = nil) async throws -> Data {
        let command = url
        return try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.isExecutableFile(atPath: command.path) else {
                throw CLIError(message: "The MacWine launcher is unavailable. Open the packaged app, or set MACWINE_CLI for development.")
            }
            // Files avoid pipe deadlocks on large build/installer output.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("stdout")
            let error = directory.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: output.path, contents: nil)
            FileManager.default.createFile(atPath: error.path, contents: nil)
            let outHandle = try FileHandle(forWritingTo: output)
            let errHandle = try FileHandle(forWritingTo: error)
            defer { try? outHandle.close(); try? errHandle.close() }
            let process = Process()
            process.executableURL = command
            process.arguments = arguments
            process.standardOutput = outHandle
            process.standardError = errHandle
            let inputPipe = input == nil ? nil : Pipe()
            process.standardInput = inputPipe?.fileHandleForReading ?? FileHandle.nullDevice
            try process.run()
            if let input, let inputPipe {
                try inputPipe.fileHandleForWriting.write(contentsOf: input)
                try inputPipe.fileHandleForWriting.close()
            }
            if let onStderrLine {
                let reader = try FileHandle(forReadingFrom: error)
                defer { try? reader.close() }
                var pending = Data()
                func drain() async throws {
                    while let chunk = try reader.read(upToCount: 65536), !chunk.isEmpty {
                        pending.append(chunk)
                        while let newline = pending.firstIndex(of: 10) {
                            let line = String(decoding: pending[..<newline], as: UTF8.self)
                            pending.removeSubrange(...newline)
                            await onStderrLine(line)
                        }
                        // Bound memory for malformed diagnostics without line endings.
                        if pending.count > 65536 { pending.removeAll(keepingCapacity: true) }
                    }
                }
                while process.isRunning {
                    try await drain()
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                process.waitUntilExit()
                try await drain()
                if !pending.isEmpty { await onStderrLine(String(decoding: pending, as: UTF8.self)) }
            } else { process.waitUntilExit() }
            let data = try Data(contentsOf: output)
            if process.terminationStatus != 0 {
                var detail = (try? String(contentsOf: error, encoding: .utf8)) ?? ""
                if onStderrLine != nil {
                    detail = detail.components(separatedBy: .newlines)
                        .filter { RuntimeProgress.percent(from: $0) == nil }
                        .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let input, let secret = String(data: input, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty {
                    detail = detail.replacingOccurrences(of: secret, with: "[redacted]")
                }
                throw CLIError(message: detail.isEmpty ? "The operation exited with code \(process.terminationStatus)." : String(detail.suffix(6000)))
            }
            return data
        }.value
    }
    public func decode<T: Decodable>(_ type: T.Type, _ arguments: [String]) async throws -> T {
        let data = try await run(arguments)
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw CLIError(message: "The launcher returned invalid data. Make sure the app and launcher are from the same build.") }
    }
}
public struct CLIError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct CommunityRating: Decodable, Equatable {
    public let average: Double
    public let count: Int
    public let latestVersion: String?
}
public struct RatingsFile: Decodable {
    public let games: [String: CommunityRating]
}
