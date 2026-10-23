import SwiftUI
import AppKit

struct ParentSummaryView: View {
    @EnvironmentObject var store: AppStore
    @State private var saved: String?

    private var summary: ParentSummary { store.parentSummary() }

    var body: some View {
        let s = summary
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("For a parent"))
                        .font(Face.display(16, .semibold))
                        .foregroundStyle(Palette.navy)
                    Text(L("A plain-language page about how this is going, in whichever language you have the app set to. Print it or send it."))
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(L("Save as a page…")) { save(s) }
                    .buttonStyle(.plain)
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(s.isEmpty ? Palette.textMuted : Palette.navy)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Palette.border, lineWidth: 1))
                    .disabled(s.isEmpty)
            }

            if let saved {
                Text(saved).font(Face.ui(11)).foregroundStyle(Palette.brass)
            }

            VStack(alignment: .leading, spacing: 14) {
                if !s.tiles.isEmpty {
                    HStack(alignment: .top, spacing: 30) {
                        ForEach(Array(s.tiles.enumerated()), id: \.offset) { _, tile in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tile.value)
                                    .font(Face.figures(24, .semibold))
                                    .foregroundStyle(Palette.navy)
                                Text(tile.label)
                                    .font(Face.ui(10))
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        Spacer()
                    }
                }
                ForEach(Array(s.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Face.ui(12.5))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !s.caveats.isEmpty {
                    Rule()
                    ForEach(Array(s.caveats.enumerated()), id: \.offset) { _, caveat in
                        Text(caveat)
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func save(_ s: ParentSummary) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = Lf("Practice summary — %@", s.studentName) + ".pdf"
        panel.message = L("One page, in the language the app is set to. It holds no personal information beyond the name shown on it.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PDFExporter.exportParentSummary(s, to: url)
            saved = Lf("Saved %@", url.lastPathComponent)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
