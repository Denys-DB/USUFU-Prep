import SwiftUI

struct NotesPanel: View {
    @EnvironmentObject var store: AppStore
    let question: Question
    let bankID: String
    var onClose: () -> Void

    @State private var editing: Annotation?

    private var items: [Annotation] { store.annotations(for: question.id, in: bankID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rule(onPaper: true)
            if items.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(items) { item in row(item) }
                    }
                    .padding(20)
                }
                .background(Paper.paper)
            }
            Rule(onPaper: true)
            footer
        }
        .frame(width: 560, height: 480)
        .background(Paper.paper)
        .sheet(item: $editing) { a in
            NoteEditor(annotation: a, bankID: bankID) { editing = nil }
                .environmentObject(store)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L("Highlights & Notes"))
                .font(Face.display(19, .semibold))
                .foregroundStyle(Paper.navy)
            Rule(brass: true, onPaper: true).frame(width: 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(Paper.card)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "highlighter")
                .font(.system(size: 26))
                .foregroundStyle(Paper.border)
            Text(L("Nothing marked on this question yet"))
                .font(Face.display(14, .semibold))
                .foregroundStyle(Paper.text)
            Text(L("Select words in a passage, or in Math text without formulas, to highlight them, and add a note if you want one."))
                .font(Face.ui(11))
                .foregroundStyle(Paper.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Paper.paper)
    }

    private func row(_ a: Annotation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Paper.highlight(a.colorIndex))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(excerpt(a))
                        .font(Face.ui(12))
                        .foregroundStyle(Paper.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if a.hasNote {
                        Text(a.note)
                            .font(Face.ui(12))
                            .foregroundStyle(Paper.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 10)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Paper.brass).frame(width: 2)
                            }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Button(a.hasNote ? L("Edit note") : L("Add note")) { editing = a }
                        .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Paper.navy)
                    Button(L("Remove")) { store.removeAnnotation(a.id, in: bankID) }
                        .buttonStyle(.plain).font(Face.ui(11)).foregroundStyle(Paper.wrong)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.card)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Paper.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func excerpt(_ a: Annotation) -> String {
        let blocks = a.field == .stimulus ? question.stimulus : question.prompt
        guard a.blockIndex < blocks.count else { return L("(passage changed)") }
        let chars = Array(blocks[a.blockIndex].text)
        let lo = max(0, min(a.start, chars.count))
        let hi = max(lo, min(a.end, chars.count))
        let s = String(chars[lo..<hi])
        return s.count > 220 ? String(s.prefix(220)) + "…" : s
    }

    private var footer: some View {
        HStack {
            if !items.isEmpty {
                Button(L("Remove all")) { store.clearAnnotations(for: question.id, in: bankID) }
                    .buttonStyle(.plain).font(Face.ui(12)).foregroundStyle(Paper.wrong)
            }
            Spacer()
            BluebookButton(title: L("Done")) { onClose() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Paper.card)
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: AppStore
    let annotation: Annotation
    let bankID: String
    var onClose: () -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(L("Note"))
                    .font(Face.display(18, .semibold))
                    .foregroundStyle(Paper.navy)
                Rule(brass: true, onPaper: true).frame(width: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 14)
            .background(Paper.card)
            Rule(onPaper: true)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .foregroundStyle(Paper.text)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Paper.card)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Paper.hairline, lineWidth: 1))
                .padding(20)
                .background(Paper.paper)

            Rule(onPaper: true)
            HStack {
                Button(L("Remove highlight")) {
                    store.removeAnnotation(annotation.id, in: bankID)
                    onClose()
                }
                .buttonStyle(.plain).font(Face.ui(12)).foregroundStyle(Paper.wrong)
                Spacer()
                Button(L("Cancel")) { onClose() }
                    .buttonStyle(.plain).font(Face.ui(12)).foregroundStyle(Paper.textMuted)
                BluebookButton(title: L("Save")) {
                    var updated = annotation
                    updated.note = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.updateAnnotation(updated, in: bankID)
                    onClose()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Paper.card)
        }
        .frame(width: 480, height: 340)
        .background(Paper.paper)
        .onAppear { text = annotation.note }
    }
}
