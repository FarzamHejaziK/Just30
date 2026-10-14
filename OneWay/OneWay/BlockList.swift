import Foundation

enum BlockListError: LocalizedError {
    case limit(String)
    case invalidDomain(String)
    var errorDescription: String? {
        switch self {
        case .limit(let kind): return "iOS supports up to 50 \(kind) in this block list. Nothing was changed."
        case .invalidDomain(let value): return "Enter a website domain or HTTPS URL, such as example.com. Invalid entry: \(value)"
        }
    }
}

// The only mutation exposed by this type is a validated union.
struct BlockList<A: Hashable & Codable, C: Hashable & Codable, W: Hashable & Codable>: Codable {
    private(set) var apps: Set<A> = []
    private(set) var categories: Set<C> = []
    private(set) var websites: Set<W> = []
    private(set) var domains: Set<String> = []
    var isEmpty: Bool { apps.isEmpty && categories.isEmpty && websites.isEmpty && domains.isEmpty }

    func adding(apps: Set<A> = [], categories: Set<C> = [], websites: Set<W> = [], domains: Set<String> = []) throws -> Self {
        var next = self
        next.apps.formUnion(apps)
        next.categories.formUnion(categories)
        next.websites.formUnion(websites)
        next.domains.formUnion(domains)
        try next.validate()
        return next
    }

    func validate() throws {
        for (count, kind) in [(apps.count, "individual apps"), (categories.count, "categories"), (websites.count, "picker websites"), (domains.count, "typed website domains")] {
            if count > 50 { throw BlockListError.limit(kind) }
        }
        for domain in domains where try DomainParser.normalize(domain) != domain {
            throw BlockListError.invalidDomain(domain)
        }
    }
}

enum DomainParser {
    static func parse(_ input: String) throws -> Set<String> {
        try Set(input.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map { try normalize(String($0)) })
    }
    static func normalize(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = value.contains("://") ? value : "https://" + value
        guard let parts = URLComponents(string: url),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.port == nil,
              var host = parts.host?.lowercased(), !host.isEmpty else {
            throw BlockListError.invalidDomain(input)
        }
        if host.hasSuffix(".") { host.removeLast() }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { throw BlockListError.invalidDomain(input) }
        return host
    }
}

struct BlockListFile<A: Hashable & Codable, C: Hashable & Codable, W: Hashable & Codable> {
    typealias List = BlockList<A, C, W>
    let url: URL
    func load() throws -> List {
        guard FileManager.default.fileExists(atPath: url.path) else { return List() }
        let list = try JSONDecoder().decode(List.self, from: Data(contentsOf: url))
        try list.validate()
        return list
    }
    func save(_ list: List) throws {
        try list.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(list).write(to: url, options: .atomic)
    }
}

struct WebsiteSuggestion: Identifiable, Equatable {
    let name: String
    let domain: String
    let aliases: Set<String>
    let symbol: String
    var id: String { domain }
    var domains: Set<String> { aliases.union([domain]) }
}

enum WebsiteCatalog {
    // Suggestions are local; typing never sends a search or visits the website.
    static let all: [WebsiteSuggestion] = [
        .init(name: "YouTube", domain: "youtube.com", aliases: ["youtu.be"], symbol: "play.rectangle.fill"),
        .init(name: "Instagram", domain: "instagram.com", aliases: [], symbol: "camera.fill"),
        .init(name: "Reddit", domain: "reddit.com", aliases: ["redd.it"], symbol: "bubble.left.and.bubble.right.fill"),
        .init(name: "TikTok", domain: "tiktok.com", aliases: [], symbol: "music.note"),
        .init(name: "X / Twitter", domain: "x.com", aliases: ["twitter.com"], symbol: "at"),
        .init(name: "Facebook", domain: "facebook.com", aliases: ["fb.com"], symbol: "person.2.fill"),
        .init(name: "Netflix", domain: "netflix.com", aliases: [], symbol: "film.fill"),
        .init(name: "Twitch", domain: "twitch.tv", aliases: [], symbol: "video.fill"),
        .init(name: "LinkedIn", domain: "linkedin.com", aliases: [], symbol: "briefcase.fill"),
        .init(name: "Pinterest", domain: "pinterest.com", aliases: ["pin.it"], symbol: "pin.fill"),
        .init(name: "Discord", domain: "discord.com", aliases: ["discord.gg"], symbol: "headphones"),
        .init(name: "Amazon", domain: "amazon.com", aliases: [], symbol: "bag.fill"),
        .init(name: "Hacker News", domain: "news.ycombinator.com", aliases: [], symbol: "newspaper.fill")
    ]

    static func matches(_ input: String) -> [WebsiteSuggestion] {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return Array(all.prefix(6)) }
        let host = try? DomainParser.normalize(query)
        return all.filter { site in
            site.name.lowercased().contains(query) || site.domains.contains(where: {
                $0.contains(query) || $0 == host || host?.hasSuffix("." + $0) == true
            })
        }
    }

    static func candidate(_ input: String) -> WebsiteSuggestion? {
        guard let domain = try? DomainParser.normalize(input) else { return nil }
        if let known = all.first(where: { $0.domains.contains(domain) || $0.domains.contains(where: { domain.hasSuffix("." + $0) }) }) {
            return .init(name: known.name, domain: known.domain, aliases: known.domains.union([domain]).subtracting([known.domain]), symbol: known.symbol)
        }
        return .init(name: domain, domain: domain, aliases: [], symbol: "globe")
    }
}
