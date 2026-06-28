import Foundation

struct Mod: Identifiable, Hashable, Codable {
    let id: String
    let url: String
    let urlV2: String?      // download for the v2.x build (falls back to url)
    let urlMelon: String?   // download to use when the loader is MelonLoader
    let v2: Bool            // available on the v2.x (Unity 2022) build
    let v3: Bool            // available on the v3.x+ (Unity 6) build
    let jalib: Bool         // depends on JALib (currently broken — hidden, banner shown)
    let install: String?    // special install handler key (e.g. "quartz"); nil = default

    init(id: String, url: String, urlV2: String? = nil, urlMelon: String? = nil,
         v2: Bool = true, v3: Bool = true, jalib: Bool = false, install: String? = nil) {
        self.id = id
        self.url = url
        self.urlV2 = urlV2
        self.urlMelon = urlMelon
        self.v2 = v2
        self.v3 = v3
        self.jalib = jalib
        self.install = install
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        urlV2 = try c.decodeIfPresent(String.self, forKey: .urlV2)
        urlMelon = try c.decodeIfPresent(String.self, forKey: .urlMelon)
        v2 = try c.decodeIfPresent(Bool.self, forKey: .v2) ?? true
        v3 = try c.decodeIfPresent(Bool.self, forKey: .v3) ?? true
        jalib = try c.decodeIfPresent(Bool.self, forKey: .jalib) ?? false
        install = try c.decodeIfPresent(String.self, forKey: .install)
    }

    func resolvedURL(isGameV2: Bool, isMelonLoader: Bool) -> String {
        if isMelonLoader, let melon = urlMelon { return melon }
        if isGameV2, let v2 = urlV2 { return v2 }
        return url
    }
}

private struct ModList: Codable {
    let mods: [Mod]
}

enum ModRegistryError: LocalizedError {
    case badURL
    case http(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL:        return "Invalid mod registry URL."
        case .http(let c):   return "Couldn't fetch the mod list (HTTP \(c))."
        case .empty:         return "The mod list was empty."
        }
    }
}

enum ModRegistry {
    /// Source of truth at runtime — edit mods.json in the repo to change the mod
    /// list without rebuilding the app.
    static let registryURL = "https://raw.githubusercontent.com/sbrothers7/UMMInstall/main/mods.json"

    /// Fetches the mod list from the repo. Throws on any network/decode failure
    /// — the caller surfaces the error rather than masking it with stale data.
    static func fetch() async throws -> [Mod] {
        guard let url = URL(string: registryURL) else { throw ModRegistryError.badURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw ModRegistryError.http(http.statusCode)
        }
        let list = try JSONDecoder().decode(ModList.self, from: data)
        if list.mods.isEmpty { throw ModRegistryError.empty }
        return list.mods
    }
}
