import Foundation

// Valve KeyValues supports quoted strings, nested objects and // comments.
public enum VDF {
    public indirect enum Value: Equatable {
        case string(String), object([String: Value])
        public var text: String? { if case .string(let s) = self { return s }; return nil }
        public var object: [String: Value]? { if case .object(let d) = self { return d }; return nil }
    }
    public static func parse(_ source: String) -> [String: Value] {
        let chars = Array(source); var i = 0; var tokens: [String] = []
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            if chars[i] == "/", i + 1 < chars.count, chars[i+1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }; continue
            }
            if chars[i] == "{" || chars[i] == "}" { tokens.append(String(chars[i])); i += 1; continue }
            var token = ""
            if chars[i] == "\"" {
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\", i+1 < chars.count, chars[i+1] == "\\" || chars[i+1] == "\"" { i += 1 }
                    token.append(chars[i]); i += 1
                }
                if i < chars.count { i += 1 }
            } else {
                while i < chars.count && !chars[i].isWhitespace && chars[i] != "{" && chars[i] != "}" { token.append(chars[i]); i += 1 }
            }
            tokens.append(token)
        }
        var position = 0
        func object() -> [String: Value] {
            var result: [String: Value] = [:]
            while position < tokens.count {
                let key = tokens[position]; position += 1
                if key == "}" { break }
                guard position < tokens.count else { break }
                let value = tokens[position]; position += 1
                result[key] = value == "{" ? .object(object()) : .string(value)
            }
            return result
        }
        return object()
    }
}

public struct LibraryResult {
    public var games: [Game]
    public var warnings: [String]
}
public struct LibraryScanner {
    public init() {}
    public func windowsURL(_ path: String, bottle: URL) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") { return URL(fileURLWithPath: normalized) }
        guard normalized.count >= 3 else { return nil }
        let letters = Array(normalized)
        guard letters[1] == ":", letters[2] == "/", letters[0].isLetter else { return nil }
        let drive = String(letters[0]).lowercased()
        let base = drive == "c" ? bottle.appendingPathComponent("drive_c") : bottle.appendingPathComponent("dosdevices/\(drive):")
        return base.appendingPathComponent(String(normalized.dropFirst(3))).standardizedFileURL
    }
    public func scan(_ bottles: [Bottle]) -> LibraryResult {
        var games: [Game] = []; var warnings: [String] = []
        let fm = FileManager.default
        func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func children(_ url: URL) -> [URL] { (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [] }
        func largestExecutable(_ folder: URL) -> String? {
            children(folder).filter { $0.pathExtension.lowercased() == "exe" }
                .max { a, b in
                    let x = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    let y = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return x < y
                }?.path
        }
        func json(_ url: URL) -> [String: Any]? {
            guard let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                warnings.append("Unable to read \(url.lastPathComponent)."); return nil
            }; return object
        }
        for bottle in bottles {
            let root = URL(fileURLWithPath: bottle.path)
            let drive = root.appendingPathComponent("drive_c")
            let steam = drive.appendingPathComponent("Program Files (x86)/Steam")
            var libraries = [steam]
            if let source = text(steam.appendingPathComponent("steamapps/libraryfolders.vdf")) {
                let dict = VDF.parse(source)["libraryfolders"]?.object ?? [:]
                for (key, value) in dict where Int(key) != nil {
                    if let path = value.object?["path"]?.text ?? value.text, let url = windowsURL(path, bottle: root) { libraries.append(url) }
                }
            }
            for library in Set(libraries.map { $0.standardizedFileURL }) {
                for manifest in children(library.appendingPathComponent("steamapps")) where manifest.lastPathComponent.hasPrefix("appmanifest_") && manifest.pathExtension == "acf" {
                    guard let source = text(manifest), let app = VDF.parse(source)["AppState"]?.object,
                          let id = app["appid"]?.text, id != "228980", let name = app["name"]?.text else { continue }
                    let installed = (Int(app["StateFlags"]?.text ?? "0") ?? 0) & 4 != 0
                    let executable = app["installdir"]?.text.flatMap { largestExecutable(library.appendingPathComponent("steamapps/common").appendingPathComponent($0)) }
                    games.append(Game(bottle: bottle.name, store: .steam, storeID: id, name: name, installed: installed, executable: executable))
                }
            }
            let epic = drive.appendingPathComponent("ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
            for file in children(epic) where file.pathExtension == "item" {
                guard let item = json(file), let id = item["AppName"] as? String, let name = item["DisplayName"] as? String else { continue }
                let location = (item["InstallLocation"] as? String).flatMap { windowsURL($0, bottle: root) }
                let executable = (item["LaunchExecutable"] as? String).flatMap { location?.appendingPathComponent($0.replacingOccurrences(of: "\\", with: "/")).path }
                let installed = location.map { fm.fileExists(atPath: $0.path) } ?? false
                games.append(Game(bottle: bottle.name, store: .epic, storeID: id, name: name, installed: installed, executable: executable))
            }
            for folder in ["GOG Games", "Program Files (x86)/GOG Galaxy/Games", "Program Files/GOG Galaxy/Games"] {
                for gameDir in children(drive.appendingPathComponent(folder)) {
                    for file in children(gameDir) where file.lastPathComponent.hasPrefix("goggame-") && file.pathExtension == "info" {
                        guard let item = json(file), let name = item["name"] as? String else { continue }
                        let id = (item["gameId"] as? String) ?? (item["gameId"] as? NSNumber)?.stringValue ?? file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "goggame-", with: "")
                        let tasks = item["playTasks"] as? [[String: Any]] ?? []
                        let task = tasks.first { $0["isPrimary"] as? Bool == true } ?? tasks.first
                        let executable = (task?["path"] as? String).map { gameDir.appendingPathComponent($0.replacingOccurrences(of: "\\", with: "/")).path }
                        games.append(Game(bottle: bottle.name, store: .gog, storeID: id, name: name, installed: true, executable: executable))
                    }
                }
            }
            if let registry = text(root.appendingPathComponent("system.reg")) {
                var id: String?
                for line in registry.components(separatedBy: .newlines) {
                    if line.hasPrefix("[") {
                        id = nil
                        let section = line.replacingOccurrences(of: "\\\\", with: "\\")
                        let marker = "\\ubisoft\\launcher\\installs\\"
                        if let range = section.lowercased().range(of: marker), let end = section[range.upperBound...].firstIndex(of: "]") {
                            let candidate = String(section[range.upperBound..<end])
                            if !candidate.isEmpty && !candidate.contains("\\") { id = candidate }
                        }
                    } else if let gameID = id, line.lowercased().hasPrefix("\"installdir\"="), let equal = line.firstIndex(of: "=") {
                        let raw = String(line[line.index(after: equal)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" \r"))
                        let path = raw.replacingOccurrences(of: "\\\\", with: "\\")
                        guard let url = windowsURL(path, bottle: root) else { continue }
                        games.append(Game(bottle: bottle.name, store: .ubisoft, storeID: gameID, name: url.lastPathComponent, installed: fm.fileExists(atPath: url.path), executable: largestExecutable(url)))
                    }
                }
            }
        }
        var seen = Set<String>()
        return LibraryResult(games: games.filter { seen.insert($0.id).inserted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, warnings: warnings)
    }
}
