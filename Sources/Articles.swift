import Foundation

struct ArticleBlock: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case heading
        case paragraph
        case list
        case rule
        case example
        case diagram
    }

    var id = UUID()
    var kind: Kind = .paragraph
    var text: String = ""
    var items: [String] = []
    var ordered: Bool = false
    var answer: String = ""

    init(kind: Kind = .paragraph, text: String = "", items: [String] = [],
         ordered: Bool = false, answer: String = "") {
        self.kind = kind
        self.text = text
        self.items = items
        self.ordered = ordered
        self.answer = answer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .paragraph
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        ordered = try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
    }

    enum CodingKeys: String, CodingKey { case kind, text, items, ordered, answer }
}

struct Article: Codable, Identifiable, Hashable {
    var id: String = ""
    var subject: Subject = .readingWriting
    var domain: String = ""
    var skills: [String] = []
    var title: String = ""
    var summary: String = ""
    var blocks: [ArticleBlock] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        subject = try c.decodeIfPresent(Subject.self, forKey: .subject) ?? .readingWriting
        domain = try c.decodeIfPresent(String.self, forKey: .domain) ?? ""
        skills = try c.decodeIfPresent([String].self, forKey: .skills) ?? []
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        blocks = try c.decodeIfPresent([ArticleBlock].self, forKey: .blocks) ?? []
    }

    init(id: String, subject: Subject, domain: String, skills: [String],
         title: String, summary: String, blocks: [ArticleBlock]) {
        self.id = id
        self.subject = subject
        self.domain = domain
        self.skills = skills
        self.title = title
        self.summary = summary
        self.blocks = blocks
    }

    var minutes: Int {
        let words = blocks.reduce(0) {
            $0 + $1.text.split(separator: " ").count
                + $1.items.reduce(0) { $0 + $1.split(separator: " ").count }
        }
        return max(1, Int((Double(words) / 180.0).rounded()))
    }
}

struct ArticleFile: Codable {
    var version: Int = 1
    var articles: [Article] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        articles = try c.decodeIfPresent([Article].self, forKey: .articles) ?? []
    }
}

enum Articles {

    private static var cache: [Language: [Article]] = [:]

    static var current: [Article] {
        let english = load(.english)
        guard Localisation.current != .english else { return english }
        let translated = load(Localisation.current)
        guard !translated.isEmpty else { return english }
        let byID = Dictionary(translated.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return english.map { byID[$0.id] ?? $0 }
    }

    static func load(_ language: Language) -> [Article] {
        if let hit = cache[language] { return hit }
        let loaded = read(language)
        cache[language] = loaded
        return loaded
    }

    private static func read(_ language: Language) -> [Article] {
        guard let url = url(for: language),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ArticleFile.self, from: data)
        else { return [] }
        return file.articles
    }

    private static func url(for language: Language) -> URL? {
        let name = "articles-\(language.rawValue)"
        if let bundled = Bundle.main.url(forResource: name, withExtension: "json") {
            return bundled
        }
        let beside = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Articles/\(name).json")
        return FileManager.default.fileExists(atPath: beside.path) ? beside : nil
    }

    static func forSkill(_ skill: String, in articles: [Article]? = nil) -> Article? {
        let all = articles ?? current
        let wanted = skill.lowercased()
        return all.first { $0.skills.contains { $0.lowercased() == wanted } }
    }

    static func forDomain(_ domain: String, in articles: [Article]? = nil) -> [Article] {
        let all = articles ?? current
        let wanted = domain.lowercased()
        return all.filter { $0.domain.lowercased() == wanted }
    }

    static func grouped(_ articles: [Article]? = nil) -> [(subject: Subject, domain: String,
                                                           articles: [Article])] {
        let all = articles ?? current
        var out: [(Subject, String, [Article])] = []
        for subject in [Subject.readingWriting, .math] {
            let here = all.filter { $0.subject == subject }
            for domain in here.map(\.domain).reduced() {
                out.append((subject, domain, here.filter { $0.domain == domain }))
            }
        }
        return out.map { (subject: $0.0, domain: $0.1, articles: $0.2) }
    }

    static func search(_ query: String, in articles: [Article]? = nil) -> [Article] {
        let all = articles ?? current
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { article in
            article.title.localizedCaseInsensitiveContains(q)
                || article.summary.localizedCaseInsensitiveContains(q)
                || article.skills.contains { $0.localizedCaseInsensitiveContains(q) }
                || article.blocks.contains {
                    $0.text.localizedCaseInsensitiveContains(q)
                        || $0.items.contains { $0.localizedCaseInsensitiveContains(q) }
                }
        }
    }

    static func missing(skills: [String], from articles: [Article]? = nil) -> [String] {
        let all = articles ?? current
        return skills.filter { forSkill($0, in: all) == nil }
    }
}

private extension Array where Element == String {
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
