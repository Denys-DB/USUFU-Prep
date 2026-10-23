import SwiftUI

struct ArticlesView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    private var groups: [(subject: Subject, domain: String, articles: [Article])] {
        Articles.grouped(Articles.search(query))
    }

    private var sections: [(subject: Subject, groups: [(domain: String, articles: [Article])])] {
        [Subject.readingWriting, .math].compactMap { subject in
            let mine = groups.filter { $0.subject == subject }
                .map { (domain: $0.domain, articles: $0.articles) }
            return mine.isEmpty ? nil : (subject: subject, groups: mine)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rule()
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header

                    if sections.isEmpty {
                        Text(L("Nothing matches that."))
                            .font(Face.ui(12))
                            .foregroundStyle(Palette.textMuted)
                            .padding(.top, 30)
                    } else {
                        ForEach(sections, id: \.subject) { section in
                            subjectSection(section)
                        }
                    }
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: ArticleLayout.measure, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .frame(maxWidth: .infinity)
              }
              .onAppear {
                  guard let id = store.lastArticleRead else { return }
                  DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
              }
            }
        }
        .background(Palette.paper)
        .watchingKeys { event in
            guard Key.isPlain(event, code: Key.escape) else { return false }
            store.closeLearn()
            return true
        }
    }

    private var bar: some View {
        HStack(spacing: 14) {
            Button { store.closeLearn() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text(store.learnCoversResults ? L("Results") : L("Library")).font(Face.ui(12))
                }
                .foregroundStyle(Palette.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.learnCoversResults ? L("Back to your results") : L("Back to the library"))

            Spacer(minLength: 12)

            Text(L("Esc to leave"))
                .font(Face.ui(10))
                .foregroundStyle(Palette.textMuted.opacity(0.8))
        }
        .padding(.horizontal, 24)
        .padding(.top, WindowChrome.trafficLights + 6)
        .padding(.bottom, 12)
        .background(Palette.card)
    }

    private func subjectSection(
        _ section: (subject: Subject, groups: [(domain: String, articles: [Article])])
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(section.subject.sectionLabel)
                    .font(Face.display(19))
                    .foregroundStyle(Palette.navy)
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }

            ForEach(section.groups, id: \.domain) { group in
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: group.domain)
                    ForEach(group.articles) { article in
                        row(article)
                    }
                }
            }
        }
        .entrance(1)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Learn"))
                .font(Face.display(26))
                .foregroundStyle(Palette.navy)
            Rule().frame(width: 60)
            Text(L("Short explanations of what each skill is actually about, written for a student who wants the idea rather than another question. They work offline like everything else here."))
                .font(Face.ui(12))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L("Search the articles"), text: $query)
                .textFieldStyle(.roundedBorder)
                .font(Face.ui(12))
                .frame(maxWidth: 320)

            ArticleDisclaimer()
                .padding(.top, 4)
        }
        .entrance(0)
    }

    private func row(_ article: Article) -> some View {
        Button {
            store.openArticle(article.id)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(Face.display(14, .semibold))
                    .foregroundStyle(Palette.navy)
                Text(article.summary)
                    .font(Face.ui(11.5))
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(article.id)
    }
}

struct ArticleView: View {
    let article: Article
    var backTitle: String = L("Learn")
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(backTitle)
                            .font(Face.ui(12))
                    }
                    .foregroundStyle(Palette.textMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(L("Esc to leave"))
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted.opacity(0.7))
                Text("·")
                    .font(Face.ui(10))
                    .foregroundStyle(Palette.textMuted.opacity(0.4))
                Text(article.domain)
                    .font(Face.ui(10.5))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 28)
            .padding(.top, WindowChrome.trafficLights)
            .padding(.bottom, 12)

            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(article.title)
                            .font(Face.display(24))
                            .foregroundStyle(Palette.navy)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(article.summary)
                            .font(Face.ui(13))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)

                    ForEach(article.blocks) { block in
                        blockView(block)
                    }

                    Rule().padding(.top, 10)
                    ArticleDisclaimer()
                }
                .frame(maxWidth: ArticleLayout.measure, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.paper)
        .watchingKeys { event in
            guard Key.isPlain(event, code: Key.escape) else { return false }
            onClose()
            return true
        }
    }

    @ViewBuilder
    private func blockView(_ block: ArticleBlock) -> some View {
        switch block.kind {
        case .heading:
            Text(block.text)
                .font(Face.display(16, .semibold))
                .foregroundStyle(Palette.navy)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

        case .paragraph:
            Text(inline(block.text))
                .font(Face.ui(13.5))
                .foregroundStyle(Palette.text)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .list:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(block.ordered ? "\(i + 1)." : "•")
                            .font(Face.ui(12, .semibold))
                            .foregroundStyle(Palette.brass)
                            .frame(width: 16, alignment: .trailing)
                        Text(inline(item))
                            .font(Face.ui(13))
                            .foregroundStyle(Palette.text)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 2)

        case .rule:
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Palette.brass).frame(width: 2)
                Text(inline(block.text))
                    .font(Face.ui(13.5, .medium))
                    .foregroundStyle(Palette.navy)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

        case .diagram:
            ArticleDiagram(name: block.text, caption: block.answer)

        case .example:
            VStack(alignment: .leading, spacing: 7) {
                Text(block.text)
                    .font(Face.ui(13, .semibold))
                    .foregroundStyle(Palette.navy)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("→")
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                        Text(step)
                            .font(Face.ui(12.5))
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !block.answer.isEmpty {
                    Text(block.answer)
                        .font(Face.ui(13, .semibold))
                        .foregroundStyle(Palette.brass)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.subtleFill)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        var out = AttributedString()
        var bold = false
        for piece in text.components(separatedBy: "**") {
            var run = AttributedString(piece)
            if bold { run.font = Face.ui(13.5, .semibold) }
            out.append(run)
            bold.toggle()
        }
        return out
    }
}

struct ArticleLink: View {
    @EnvironmentObject var store: AppStore
    let skill: String
    var compact: Bool = false

    var body: some View {
        if let article = Articles.forSkill(skill) {
            Button {
                store.openArticle(article.id)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "book")
                        .font(.system(size: compact ? 9 : 10))
                    Text(Lf("Read about %@", skill))
                        .font(Face.ui(compact ? 10.5 : 11.5, .medium))
                }
                .foregroundStyle(Palette.brass)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(article.summary)
        }
    }
}

enum ArticleLayout {
    static let measure: CGFloat = 720
}

struct ArticleDisclaimer: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Palette.brass.opacity(0.55)).frame(width: 2)
            Text(L("These articles cover the basics of each skill and nothing more. They are a place to start, not a course, and they will not on their own get you any particular score. Real preparation means working through questions, and reading properly about the topics you find hard — this is only meant to help you begin."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
