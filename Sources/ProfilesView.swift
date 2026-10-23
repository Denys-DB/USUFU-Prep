import SwiftUI
import AppKit

enum ProfileAccent {
    static let colours: [Color] = [
        Color(red: 0.11, green: 0.16, blue: 0.31),
        Color(red: 0.62, green: 0.47, blue: 0.20),
        Color(red: 0.29, green: 0.38, blue: 0.33),
        Color(red: 0.48, green: 0.25, blue: 0.24),
        Color(red: 0.27, green: 0.33, blue: 0.45),
        Color(red: 0.40, green: 0.31, blue: 0.44),
    ]

    static func colour(_ i: Int) -> Color {
        colours[((i % colours.count) + colours.count) % colours.count]
    }
}

struct ProfileMark: View {
    let profile: Profile
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(ProfileAccent.colour(profile.accent))
            .frame(width: size, height: size)
            .overlay(
                Text(profile.initials)
                    .font(Face.ui(size * 0.40, .semibold))
                    .foregroundStyle(.white)
            )
    }
}

struct ProfileBar: View {
    @EnvironmentObject var store: AppStore
    @State private var showingSheet = false
    @State private var showingList = false

    var body: some View {
        Group {
            if store.profiles.profiles.count > 1 {
                Button { showingList.toggle() } label: {
                    HStack(spacing: 8) {
                        ProfileMark(profile: store.profile, size: 22)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(store.profile.displayName)
                                .font(Face.ui(12, .semibold))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(L("Switch student"))
                                .font(Face.ui(9.5))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .popover(isPresented: $showingList, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.profiles.profiles) { p in
                            Button {
                                showingList = false
                                store.use(profile: p)
                            } label: {
                                HStack(spacing: 9) {
                                    ProfileMark(profile: p, size: 20)
                                    Text(p.displayName)
                                        .font(Face.ui(12, p.id == store.profile.id
                                                          ? .semibold : .regular))
                                        .foregroundStyle(Palette.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    if p.id == store.profile.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Palette.brass)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Rule()
                        Button(L("Manage students…")) {
                            showingList = false
                            showingSheet = true
                        }
                        .buttonStyle(.plain)
                        .font(Face.ui(12, .semibold))
                        .foregroundStyle(Palette.navy)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .frame(width: 240)
                    .background(Palette.card)
                }
                .sheet(isPresented: $showingSheet) { ProfilesSheet() }
            }
        }
    }
}

struct ProfilesPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameTo = ""
    @FocusState private var renameFocused: Bool
    @State private var deleting: Profile?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(store.profiles.profiles) { p in
                row(p)
                Rule()
            }
            adder
        }
        .background(Palette.card)
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .alert(item: $deleting) { p in
            Alert(title: Text(Lf("Delete %@?", p.name)),
                  message: Text(L("Their progress, notes and flashcard decks are deleted. The question sets stay — they are shared with everyone on this computer.")),
                  primaryButton: .destructive(Text(L("Delete"))) {
                      store.deleteProfile(p.id)
                  },
                  secondaryButton: .cancel(Text(L("Cancel"))))
        }
    }

    private func row(_ p: Profile) -> some View {
        HStack(spacing: 12) {
            ProfileMark(profile: p, size: 32)

            if renaming == p.id {
                TextField(L("Student's name"), text: $renameTo)
                    .textFieldStyle(.roundedBorder)
                    .font(Face.ui(13))
                    .focused($renameFocused)
                    .onSubmit { commitRename(p) }
                Button(L("Save")) { commitRename(p) }
                    .buttonStyle(.plain)
                    .font(Face.ui(11, .semibold))
                    .foregroundStyle(Palette.navy)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name)
                        .font(Face.ui(13, .semibold))
                        .foregroundStyle(Palette.text)
                    if p.id == store.profile.id {
                        Text(L("Open now"))
                            .font(Face.ui(10))
                            .foregroundStyle(Palette.brass)
                    }
                }
                Spacer()
                colourPicker(p)
                Menu {
                    if p.id != store.profile.id {
                        Button(L("Open this student")) { store.use(profile: p) }
                    }
                    Button(L("Rename…")) {
                        renaming = p.id
                        renameTo = p.name
                        DispatchQueue.main.async { renameFocused = true }
                    }
                    if store.profiles.profiles.count > 1 {
                        Divider()
                        Button(L("Delete…"), role: .destructive) { deleting = p }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 26)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func colourPicker(_ p: Profile) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<Profile.accents, id: \.self) { i in
                Button {
                    store.setProfileAccent(p.id, to: i)
                } label: {
                    Circle()
                        .fill(ProfileAccent.colour(i))
                        .frame(width: 13, height: 13)
                        .overlay(Circle().strokeBorder(Palette.paper, lineWidth: p.accent == i ? 2 : 0))
                        .overlay(Circle().strokeBorder(Palette.hairline,
                                                       lineWidth: p.accent == i ? 1 : 0)
                            .padding(-2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var adder: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(Palette.textMuted)
                .frame(width: 32)
            TextField(L("Add another student"), text: $newName)
                .textFieldStyle(.plain)
                .font(Face.ui(13))
                .onSubmit(add)
            Button(L("Add")) { DispatchQueue.main.async(execute: add) }
                .buttonStyle(.plain)
                .font(Face.ui(11, .semibold))
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                 ? Palette.textMuted : Palette.navy)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func add() {
        _ = store.addProfile(named: newName)
        newName = ""
    }

    private func commitRename(_ p: Profile) {
        store.renameProfile(p.id, to: renameTo)
        renaming = nil
    }
}

struct ProfilesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L("Students on this computer"))
                    .font(Face.display(17))
                    .foregroundStyle(Palette.navy)
                Spacer()
                Button(L("Done")) { dismiss() }
                    .buttonStyle(.plain)
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            ProfilesPanel()
                .padding(.horizontal, 22)

            Text(L("Each student keeps their own progress, statistics, notes and flashcard decks. Question sets are shared, so a set only has to be imported once. Profiles are not password-protected — anyone using this computer can open any of them."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
        }
        .frame(width: 520)
        .background(Palette.paper)
    }
}

struct PortablePanel: View {
    @EnvironmentObject var store: AppStore
    @State private var incoming: PortableProfile?
    @State private var plan: ImportPlan?
    @State private var mode: AppStore.ImportMode = .merge
    @State private var report: AppStore.ImportReport?
    @State private var exported: String?
    @State private var writtenFile: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(L("Export this student…")) { exportProfile() }
                    .buttonStyle(.plain)
                    .font(Face.ui(12, .semibold))
                    .foregroundStyle(Palette.navy)
                Text("·").foregroundStyle(Palette.textMuted)
                Button(L("Import a student file…")) { chooseFile() }
                    .buttonStyle(.plain)
                    .font(Face.ui(12, .semibold))
                    .foregroundStyle(Palette.navy)
                Spacer()
            }

            if let exported {
                HStack(spacing: 10) {
                    Text(exported)
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.brass)
                    if let writtenFile {
                        Button(L("Send it…")) { share(writtenFile) }
                            .buttonStyle(.plain)
                            .font(Face.ui(11, .semibold))
                            .foregroundStyle(Palette.navy)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !store.pending.isEmpty {
                Text(Lp(store.pending.count,
                        "%d imported set is waiting for its question PDF. Its progress is kept and applied the moment you import it.",
                        "%d imported sets are waiting for their question PDFs. Their progress is kept and applied the moment you import them."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(L("An exported student holds progress, statistics, highlights, notes, flashcard decks and study plans — everything except the question sets themselves, which stay as your own PDFs. A sitting in progress is not carried: it belongs to the computer it was begun on."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $plan) { plan in
            ImportConfirmation(plan: plan, mode: $mode) { confirmed in
                if confirmed, let incoming {
                    report = store.importProfile(incoming, using: plan, mode: mode)
                }
                self.plan = nil
                self.incoming = nil
            }
        }
        .alert(item: $report) { r in
            Alert(title: Text(L("Imported")), message: Text(describe(r)),
                  dismissButton: .default(Text(L("Done"))))
        }
    }

    private func describe(_ r: AppStore.ImportReport) -> String {
        var lines = r.summary
        if lines.isEmpty { lines.append(L("Nothing in that file matched anything here.")) }
        return lines.joined(separator: "\n")
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            "\(store.profile.name).\(PortableProfile.fileExtension)"
        panel.message = L("Copy this onto a USB stick or email it to yourself, then import it on the other computer.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bytes = store.exportProfile(to: url) else { return }
        writtenFile = url
        exported = Lf("Exported %1$@ · %2$d KB", url.lastPathComponent, max(1, bytes / 1024))
    }

    private func share(_ url: URL) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: [url])
            .show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let file = store.readPortableProfile(at: url) else { return }
        incoming = file
        mode = .merge
        plan = store.importPlan(for: file)
    }
}

struct ImportConfirmation: View {
    let plan: ImportPlan
    @Binding var mode: AppStore.ImportMode
    let finish: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Lf("Import %@", plan.profileName.isEmpty ? L("a student") : plan.profileName))
                    .font(Face.display(17))
                    .foregroundStyle(Palette.navy)
                Text(Format.stamp(plan.exportedAt))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Rule()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(plan.matches) { match in
                        row(match)
                        Rule()
                    }
                }
            }
            .frame(maxHeight: 260)

            Picker("", selection: $mode) {
                Text(L("Add to this student")).tag(AppStore.ImportMode.merge)
                Text(L("Bring in as a new student")).tag(AppStore.ImportMode.newProfile)
            }
            .pickerStyle(.radioGroup)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)

            Text(L("Where both computers have a record of the same question, the one with more attempts on it is kept. Importing the same file twice changes nothing."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)

            HStack {
                Spacer()
                Button(L("Cancel")) { finish(false) }
                    .buttonStyle(.plain)
                    .font(Face.ui(12))
                    .foregroundStyle(Palette.textMuted)
                BluebookButton(title: L("Import")) { finish(true) }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(width: 540)
        .background(Palette.paper)
    }

    private func row(_ match: ImportPlan.Match) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.exportedName)
                    .font(Face.ui(12.5, .semibold))
                    .foregroundStyle(Palette.text)
                Text(detail(match))
                    .font(Face.ui(10.5))
                    .foregroundStyle(match.localBankID == nil ? Palette.brass : Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(Lf("%1$d records", match.records))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
    }

    private func detail(_ match: ImportPlan.Match) -> String {
        guard let local = match.localName else {
            return L("You have not imported this set here yet — its progress will be kept until you do.")
        }
        switch match.how {
        case .fingerprint: return Lf("The same set as your “%@”", local)
        case .name:        return Lf("Matched to your “%@” by name", local)
        case .overlap:     return Lf("Matched to your “%1$@” — %2$d questions in common", local, match.overlap)
        case .none:        return ""
        }
    }
}

extension ImportPlan: Identifiable {
    var id: String { profileName + "\(exportedAt.timeIntervalSince1970)" }
}

extension AppStore.ImportReport: Identifiable {
    var id: String { "\(sets)-\(records)-\(decks)-\(plans)-\(setAside)" }
}
