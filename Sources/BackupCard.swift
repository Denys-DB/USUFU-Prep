import SwiftUI
import AppKit

struct BackupCard: View {
    @EnvironmentObject var store: AppStore
    @State private var written: URL?
    @State private var note: String?

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "externaldrive.badge.timemachine")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Palette.brass)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Keep a copy somewhere else"))
                            .font(Face.display(15, .semibold))
                            .foregroundStyle(Palette.navy)
                        Text(headline)
                            .font(Face.ui(11))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.dismissBackupNudge()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                            .padding(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .iconHelp(L("Not now"))
                }

                Text(L("Everything of yours — progress, statistics, highlights, "
                       + "notes, flashcards and study plans — is one small file. "
                       + "It is not the question sets: those are your own PDFs and "
                       + "you can import them again. Send it to yourself and it "
                       + "survives this computer."))
                    .font(Face.ui(11))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                if let note {
                    Text(note)
                        .font(Face.ui(11))
                        .foregroundStyle(Palette.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    BluebookButton(title: L("Save a copy…")) { export() }
                    if let written {
                        BluebookButton(title: L("Send it…"), style: .secondary) {
                            share(written)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headline: String {
        if let days = store.daysSinceBackup() {
            return days == 0
                ? L("Copied today.")
                : Lp(days, "The last copy you made was %d day ago.",
                     "The last copy you made was %d days ago.")
        }
        return L("You have never made one.")
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            "\(store.profile.name).\(PortableProfile.fileExtension)"
        panel.message = L("Save it where you can send it from — a mail draft, a "
                          + "chat to yourself, or a USB stick.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bytes = store.exportProfile(to: url) else { return }
        written = url
        note = Lf("Saved %1$@ · %2$d KB", url.lastPathComponent, max(1, bytes / 1024))
    }

    private func share(_ url: URL) {
        guard let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
