import SwiftUI
import AppKit

enum Promo {
    static let website = "https://usufu.org"
    static let websiteLabel = "usufu.org"

    static var lede: String {
        L("A free, non-profit study tool from United States Universities For Ukraine, "
          + "built for Ukrainian students preparing for university in the United States.")
    }

    struct Point: Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
        var body: String
    }

    static var whatItDoes: [Point] {
        [
            Point(symbol: "doc.text.magnifyingglass",
                  title: L("Your own question bank"),
                  body: L("Export the questions you want from the College Board's "
                          + "Question Bank and import the PDF here. It becomes a "
                          + "practice test you can sit as many times as you like.")),
            Point(symbol: "clock",
                  title: L("The real thing's shape"),
                  body: L("The screen, the timing and the controls follow the digital "
                          + "test, so the format costs you nothing on the day. Sit a "
                          + "single module or the whole test, with the break.")),
            Point(symbol: "chart.line.uptrend.xyaxis",
                  title: L("Practice that knows what you missed"),
                  body: L("Questions you get wrong come back, spaced out over days. "
                          + "The statistics say which skills are costing you marks, "
                          + "and you can drill exactly those.")),
            Point(symbol: "lock",
                  title: L("Nothing leaves your computer"),
                  body: L("No account, no network, no subscription, no tracking. Your "
                          + "questions, answers and progress stay in a folder you can "
                          + "open, copy and delete yourself.")),
        ]
    }

    static var aboutUs: [String] {
        [
            L("United States Universities For Ukraine is an independent, non-profit "
              + "educational initiative. We help Ukrainian students and their families "
              + "understand how studying in the United States actually works — what to "
              + "prepare, when, and what it costs."),
            L("This app is one part of that, and it is free. The rest is on our "
              + "website: guides to admissions, scholarships and financial aid, visas "
              + "and documents, grade and score converters, and planning timelines."),
        ]
    }
}

struct AboutPanel: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    masthead
                    Rule()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionLabel(text: L("What this app does"))
                        ForEach(Promo.whatItDoes) { point in
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: point.symbol)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.brass)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(point.title)
                                        .font(Face.ui(12, .semibold))
                                        .foregroundStyle(Palette.text)
                                    Text(point.body)
                                        .font(Face.ui(11))
                                        .foregroundStyle(Palette.textMuted)
                                        .lineSpacing(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Rule()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: L("Who we are"))
                        ForEach(Array(Promo.aboutUs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Face.ui(11.5))
                                .foregroundStyle(Palette.text)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    websiteCard
                }
                .padding(26)
            }

            Rule()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Legal.copyright)
                    Text(Legal.footprint)
                }
                .font(Face.ui(9.5))
                .foregroundStyle(Palette.textMuted)
                Spacer()
                Button(L("Close"), action: onClose)
                    .buttonStyle(.plain)
                    .font(Face.ui(12, .semibold))
                    .foregroundStyle(Palette.navy)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
        }
        .frame(width: 620, height: 620)
        .background(Palette.paper)
    }

    private var masthead: some View {
        VStack(spacing: 14) {
            USUFUSeal(size: 108, tint: Palette.navy)
            USUFUWordmark(size: 19, tint: Palette.navy, accent: Palette.brass)
            Text(Promo.lede)
                .font(Face.ui(11.5))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var websiteCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L("Everything else is on our website"))
                .font(Face.display(13, .semibold))
                .foregroundStyle(Palette.navy)
            Text(L("Admissions, scholarships and aid, visas and documents, grade "
                   + "converters, and a planning timeline — all free, in English "
                   + "and Ukrainian."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: Promo.website) { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 6) {
                    Text(Promo.websiteLabel)
                        .font(Face.ui(12, .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Paper.stealth ? Palette.brass : Palette.onBrand)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Paper.stealth ? Palette.subtleFill : Palette.brandFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Paper.stealth ? Palette.brass.opacity(0.5) : .clear,
                                      lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.plain)
            .help(L("Opens in your browser"))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
