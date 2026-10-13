import Foundation

public struct StoreAccount: Decodable, Identifiable {
    public var id: String { store.rawValue }
    public let store: Store
    public let connected: Bool
    public let fullLibrary: Bool?
    public let accountName: String?
    public let bottle: String?
    public let status: String?
    public let message: String?
}
public struct OwnedGame: Decodable {
    public let id: String
    public let name: String
    public let installed: Bool
    public let bottle: String?
    public let executable: String?
    public let artworkURL: String?
}
public struct StoreLibrary: Decodable {
    public let games: [OwnedGame]
    public let complete: Bool
    public let message: String?
    public init(from decoder: Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([OwnedGame].self) {
            games = array; complete = false; message = nil
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            games = try c.decode([OwnedGame].self, forKey: .games)
            complete = try c.decodeIfPresent(Bool.self, forKey: .complete) ?? false
            message = try c.decodeIfPresent(String.self, forKey: .message)
        }
    }
    enum CodingKeys: String, CodingKey { case games, complete, message }
}

public enum LibraryMerge {
    // Account ownership does not prove installation. Only a local match or an
    // explicit installed flag from the backend enables Play.
    public static func merge(local: [Game], owned: [OwnedGame], store: Store, bottle: String) -> [Game] {
        var output = local
        for item in owned {
            let target = item.bottle ?? bottle
            if let i = output.firstIndex(where: { $0.store == store && $0.storeID == item.id && $0.bottle == target }) {
                let found = output[i]
                output[i] = Game(bottle: target, store: store, storeID: item.id, name: item.name,
                                 installed: found.installed || item.installed,
                                 // the backend knows the store's real launch file; the local scan only guesses (largest .exe)
                                 executable: item.executable ?? found.executable, artworkURL: item.artworkURL ?? found.artworkURL)
            } else {
                output.append(Game(bottle: target, store: store, storeID: item.id, name: item.name,
                                   installed: item.installed, executable: item.executable, artworkURL: item.artworkURL))
            }
        }
        return output.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
