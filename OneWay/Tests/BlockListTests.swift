import Foundation

@main
struct BlockListTests {
    static func main() throws {
        typealias List = BlockList<String, String, String>
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = BlockListFile<String, String, String>(url: directory.appendingPathComponent("blocks.json"))
        let first = try List().adding(apps: ["app-a", "app-b"], categories: ["social"], websites: ["site-token"], domains: ["example.com"])
        try file.save(first)
        // Simulate a later picker submission that omits every previous choice.
        let second = try file.load().adding(apps: ["app-c"], domains: ["other.example"])
        try file.save(second)
        let restored = try file.load()
        precondition(restored.apps == ["app-a", "app-b", "app-c"])
        precondition(restored.categories == ["social"] && restored.websites == ["site-token"])
        precondition(restored.domains == ["example.com", "other.example"])
        let emptyAddition = try restored.adding()
        precondition(emptyAddition.apps == restored.apps && emptyAddition.domains == restored.domains)
        let parsed = try DomainParser.parse("https://EXAMPLE.com/path?q=1, example.com\nother.example.")
        precondition(parsed == ["example.com", "other.example"])
        precondition(WebsiteCatalog.matches("yout").first?.name == "YouTube")
        precondition(WebsiteCatalog.matches("REDD").first?.domain == "reddit.com")
        precondition(WebsiteCatalog.candidate("youtube") == nil)
        precondition(WebsiteCatalog.candidate("https://youtube.com/watch?v=123")?.domains == ["youtube.com", "youtu.be"])
        precondition(WebsiteCatalog.candidate("twitter.com")?.domains == ["x.com", "twitter.com"])
        precondition(WebsiteCatalog.candidate("notyoutube.com")?.name == "notyoutube.com")
        precondition(WebsiteCatalog.candidate("youtube.com.evil.example")?.domains == ["youtube.com.evil.example"])
        precondition(WebsiteCatalog.candidate("https://name:pass@youtube.com") == nil)
        for input in ["localhost", "https://name:password@example.com", "*.example.com", "example..com", "https://example.com:444", "file://example.com", "-bad.example"] {
            do { _ = try DomainParser.parse(input); fatalError("Accepted invalid input: \(input)") }
            catch is BlockListError { }
        }
        let full = try List().adding(apps: Set((0..<50).map(String.init)))
        let duplicate = try full.adding(apps: ["0"])
        precondition(duplicate.apps.count == 50)
        do { _ = try full.adding(apps: ["51"]); fatalError("Limit not enforced") }
        catch is BlockListError { }
        // Bad saved data must throw, never silently produce an empty list.
        try Data("broken".utf8).write(to: file.url)
        do { _ = try file.load(); fatalError("Corrupt data was reset") }
        catch is DecodingError { }
        // A failed write must leave the last persisted list recoverable.
        try file.save(restored)
        let impossible = BlockListFile<String, String, String>(url: file.url.appendingPathComponent("child.json"))
        do { try impossible.save(first); fatalError("Unexpected write success") } catch { }
        let afterFailedWrite = try file.load()
        precondition(afterFailedWrite.apps == restored.apps)
        print("Passed: monotonic additions, persistence, duplicates, empty submissions, domain normalization, autocomplete, alias previews, deceptive domains, invalid input, capacity, corrupt data, and write failure.")
    }
}
