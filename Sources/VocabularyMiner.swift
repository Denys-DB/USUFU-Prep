import Foundation

struct MinedCard: Identifiable, Hashable {
    var term: String
    var definition: String = ""
    var example: String = ""
    var questionID: String = ""
    var source: Source = .choice

    enum Source: String { case choice, prompt, rationale }

    var id: String { Vocabulary.key(term) }
    var hasDefinition: Bool { !definition.trimmed.isEmpty }
}

enum VocabularyMiner {

    static func opening(_ found: [MinedCard],
                        already: (MinedCard) -> Bool) -> (onlyDefined: Bool, chosen: Set<String>) {
        let anyDefined = found.contains { $0.hasDefinition }
        var chosen = Set<String>()
        for card in found where !already(card) && (card.hasDefinition || !anyDefined) {
            chosen.insert(card.id)
        }
        return (anyDefined || found.isEmpty, chosen)
    }

    static func hidden(_ found: [MinedCard], onlyDefined: Bool) -> Int {
        onlyDefined ? found.filter { !$0.hasDefinition }.count : 0
    }

    static func mine(_ bank: Bank) -> [MinedCard] {
        var found = [String: MinedCard]()

        func offer(_ card: MinedCard) {
            let key = card.id
            guard !key.isEmpty else { return }
            guard let existing = found[key] else { found[key] = card; return }
            let better = (card.hasDefinition ? 2 : 0) + (card.example.isEmpty ? 0 : 1)
            let current = (existing.hasDefinition ? 2 : 0) + (existing.example.isEmpty ? 0 : 1)
            if better > current { found[key] = card }
        }

        for question in bank.questions {
            for card in fromChoices(question) { offer(card) }
            for card in fromPrompt(question) { offer(card) }
            for card in fromRationale(question) { offer(card) }
        }

        let glossary = found.values.filter(\.hasDefinition)
            .reduce(into: [String: String]()) { $0[$1.id] = $1.definition }
        for (key, card) in found where !card.hasDefinition {
            if let known = glossary[key] {
                var filled = card
                filled.definition = known
                found[key] = filled
            }
        }

        return found.values.sorted {
            $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
    }

    static func teachesWords(_ q: Question) -> Bool {
        guard q.kind == .multipleChoice, q.choices.count == 4 else { return false }
        let prompt = plain(q.prompt).lowercased()
        guard !prompt.contains("most nearly mean") else { return false }
        if q.skill.caseInsensitiveCompare("Words in Context") == .orderedSame { return true }
        return prompt.contains("most logical and precise word or phrase")
    }

    static func fromChoices(_ q: Question) -> [MinedCard] {
        guard teachesWords(q) else { return [] }
        let rationale = plain(q.rationale)
        guard !rationale.isEmpty else { return [] }

        let blanked = blankSentence(in: plain(q.stimulus))

        return q.choices.compactMap { choice -> MinedCard? in
            guard let term = usableTerm(choice.plainText) else { return nil }
            let definition = definition(of: choice.plainText.trimmed, in: rationale)
                ?? definition(of: term, in: rationale)
            let isAnswer = choice.letter.caseInsensitiveCompare(q.correctAnswer.trimmed)
                == .orderedSame
            return MinedCard(term: term,
                             definition: definition ?? "",
                             example: isAnswer ? blanked : "",
                             questionID: q.id,
                             source: .choice)
        }
    }

    static func fromPrompt(_ q: Question) -> [MinedCard] {
        let prompt = plain(q.prompt)
        guard prompt.lowercased().contains("most nearly mean") else { return [] }
        guard let quoted = firstQuoted(in: prompt), let term = usableTerm(quoted) else { return [] }
        guard let answer = q.choices.first(where: {
            $0.letter.caseInsensitiveCompare(q.correctAnswer.trimmed) == .orderedSame
        }) else { return [] }
        let meaning = answer.plainText.trimmed
        guard !meaning.isEmpty, meaning.split(separator: " ").count <= 10 else { return [] }
        return [MinedCard(term: term,
                          definition: lowercasedFirst(meaning),
                          example: sentence(containing: term, in: plain(q.stimulus)),
                          questionID: q.id,
                          source: .prompt)]
    }

    private static let freeForm = try? NSRegularExpression(
        pattern: #""([A-Za-z][A-Za-z' \-]{2,28}),?"[ ]*,?[ ]*(?:which |that )?"#
            + adverbs + verbs + #"[ ]+([^.]{3,110})[.,]"#,
        options: [.caseInsensitive])

    static func fromRationale(_ q: Question) -> [MinedCard] {
        let text = normalise(plain(q.rationale))
        guard !text.isEmpty, let regex = freeForm else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).compactMap { match -> MinedCard? in
            guard let termRange = Range(match.range(at: 1), in: text),
                  let glossRange = Range(match.range(at: 2), in: text),
                  let term = usableTerm(String(text[termRange])) else { return nil }
            let gloss = tidy(String(text[glossRange]))
            guard acceptable(gloss) else { return nil }
            return MinedCard(term: term, definition: gloss,
                             questionID: q.id, source: .rationale)
        }
    }

    private static let adverbs =
        #"(?:can |could |would |will |generally |typically |usually |here |also "#
        + #"|literally |simply |both |most nearly |nearly )*"#
    private static let verbs =
        #"(?:means?|refers? to|is used to mean|is defined as|denotes?|describes?)"#

    private static let tails: [NSRegularExpression] = [
        #"^[ ]*,?[ ]*(?:which|that)[ ]+"# + adverbs + verbs + #"[ ]+(.+)$"#,
        #"^[ ]*,?[ ]*"# + adverbs + verbs + #"[ ]+(.+)$"#,
        #"^[ ]*[,\-]?[ ]*meaning[ ]+(.+)$"#,
        #"^[ ]*,?[ ]*or[ ]+(.+)$"#,
        #"^[ ]*\(([^)]{3,90})\)"#,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func definition(of term: String, in rationale: String) -> String? {
        let cleanTerm = term.trimmed
        guard !cleanTerm.isEmpty else { return nil }
        let text = normalise(rationale)
        let needle = "\"" + cleanTerm.lowercased()

        for sentence in sentences(text) where sentence.lowercased().contains(needle) {
            guard let after = afterQuoted(cleanTerm, in: sentence) else { continue }
            for pattern in tails {
                let range = NSRange(after.startIndex..., in: after)
                guard let m = pattern.firstMatch(in: after, range: range),
                      let captured = Range(m.range(at: 1), in: after) else { continue }
                for gloss in split(quotedList: String(after[captured])) {
                    let candidate = tidy(gloss)
                    if acceptable(candidate) { return candidate }
                }
            }
        }
        return nil
    }

    private static func afterQuoted(_ term: String, in sentence: String) -> String? {
        let lower = sentence.lowercased()
        for opener in ["\"" + term.lowercased() + ",\"", "\"" + term.lowercased() + "\""] {
            if let r = lower.range(of: opener) {
                return String(sentence[r.upperBound...])
            }
        }
        return nil
    }

    private static func split(quotedList text: String) -> [String] {
        let t = text.trimmed
        guard t.hasPrefix("\"") else { return [t] }
        let parts = t.split(separator: "\"").map(String.init)
            .map { $0.trimmed }
            .filter { $0.count > 1 && $0 != "or" && $0 != "and" }
        return parts.isEmpty ? [t] : parts
    }

    static func tidy(_ gloss: String) -> String {
        var d = gloss.squeezed.trimmed
        if let dash = d.range(of: " - ") { d = String(d[..<dash.lowerBound]) }
        if let comma = d.firstIndex(of: ",") { d = String(d[..<comma]) }
        d = d.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\".;:")))
        for prefix in ["that ", "to be ", "being "] where d.lowercased().hasPrefix(prefix) {
            d = String(d.dropFirst(prefix.count))
        }
        for suffix in [" in this context", " for this context"]
        where d.lowercased().hasSuffix(suffix) {
            d = String(d.dropLast(suffix.count))
        }
        return d.trimmed
    }

    private static let notADefinition = [
        "the text", "there is", "there are", "it's", "it is", "this ", "that the",
        "nothing", "he ", "she ", "they ", "we ", "in this", "however",
    ]

    static func acceptable(_ gloss: String) -> Bool {
        let words = gloss.split(separator: " ")
        guard !words.isEmpty, words.count <= 14, gloss.count > 2, gloss.count <= 110
        else { return false }
        let lower = gloss.lowercased()
        return !notADefinition.contains { lower.hasPrefix($0) }
    }

    static func usableTerm(_ raw: String) -> String? {
        var t = raw.squeezed.trimmed
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:\"'“”‘’"))
        for article in ["a ", "an ", "the ", "to "] where t.lowercased().hasPrefix(article) {
            t = String(t.dropFirst(article.count))
            break
        }
        guard !t.isEmpty, t.count <= 40 else { return nil }
        let words = t.split(separator: " ")
        guard (1...3).contains(words.count) else { return nil }
        let allowed = CharacterSet.letters.union(CharacterSet(charactersIn: " -'"))
        guard t.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard t.contains(where: { $0.isLetter }) else { return nil }
        return t
    }

    static func plain(_ blocks: [ContentBlock]) -> String {
        blocks.filter { $0.kind == .text }.map(\.text).joined(separator: "\n")
    }

    static func normalise(_ text: String) -> String {
        var s = ""
        s.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\u{201C}", "\u{201D}": s.append("\"")
            case "\u{2018}", "\u{2019}": s.append("'")
            case "\u{2014}", "\u{2013}": s.append(" - ")
            default: s.append(ch)
            }
        }
        return s
    }

    static func sentences(_ text: String) -> [String] {
        var out = [String]()
        var current = ""
        var inQuote = false
        var depth = 0
        var iterator = Array(text)
        var i = 0
        while i < iterator.count {
            let ch = iterator[i]
            current.append(ch)
            switch ch {
            case "\"": inQuote.toggle()
            case "(": depth += 1
            case ")": depth = max(0, depth - 1)
            case ".", "!", "?", "\n":
                if !inQuote && depth == 0 {
                    while i + 1 < iterator.count, iterator[i + 1] == "\"" || iterator[i + 1] == "'" {
                        i += 1
                        current.append(iterator[i])
                        if iterator[i] == "\"" { inQuote.toggle() }
                    }
                    let done = current.trimmed
                    if !done.isEmpty { out.append(done) }
                    current = ""
                }
            default: break
            }
            i += 1
        }
        let last = current.trimmed
        if !last.isEmpty { out.append(last) }
        return out
    }

    static func blankSentence(in stimulus: String) -> String {
        guard stimulus.contains("_") else { return "" }
        let found = sentences(normalise(stimulus)).first { $0.contains("__") }
        return found.map { $0.squeezed.trimmed } ?? ""
    }

    static func sentence(containing term: String, in text: String) -> String {
        let needle = term.lowercased()
        let found = sentences(normalise(text)).first { $0.lowercased().contains(needle) }
        return found.map { $0.squeezed.trimmed } ?? ""
    }

    static func firstQuoted(in text: String) -> String? {
        let t = normalise(text)
        guard let open = t.firstIndex(of: "\"") else { return nil }
        let rest = t[t.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        let inner = String(rest[..<close]).trimmed
        return inner.isEmpty ? nil : inner
    }

    private static func lowercasedFirst(_ s: String) -> String {
        guard let first = s.first, first.isUppercase else { return s }
        let rest = s.dropFirst()
        guard rest.allSatisfy({ !$0.isUppercase }) else { return s }
        return first.lowercased() + rest
    }
}
