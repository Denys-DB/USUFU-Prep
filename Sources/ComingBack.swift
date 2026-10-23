import SwiftUI

struct StreakRestorePrompt: View {
    @EnvironmentObject var store: AppStore
    let gap: Mercy.Gap
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flame")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Palette.brass)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Your run is still here, if you want it"))
                        .font(Face.display(17, .semibold))
                        .foregroundStyle(Palette.navy)
                    Text(away)
                        .font(Face.ui(12))
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)

            Text(L("Days you set aside are skipped, the way a planned rest day "
                   + "is — never counted as days you practiced. Your best run "
                   + "and everything you have answered stay exactly as they are."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 12)

            Text(L("Entirely up to you. A run of days is worth having only while "
                   + "it is helping."))
                .font(Face.ui(11))
                .foregroundStyle(Palette.brass)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                BluebookButton(title: L("Leave it"), style: .plain) {
                    store.declineRestore(gap)
                    onClose()
                }
                BluebookButton(title: restoreTitle) {
                    store.restoreStreak(gap)
                    onClose()
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
        }
        .frame(width: 460)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    private var away: String {
        Lp(gap.daysAway, "You were away for %d day.", "You were away for %d days.")
            + " "
            + Lp(gap.streakBefore,
                 "Setting that time aside keeps the run of %d day you had going.",
                 "Setting that time aside keeps the run of %d days you had going.")
    }

    private var restoreTitle: String {
        Lp(gap.missed.count, "Set aside %d day", "Set aside %d days")
    }
}

struct WelcomeBackBanner: View {
    @EnvironmentObject var store: AppStore
    let welcome: AppStore.WelcomeBack
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("Welcome back"))
                    .font(Face.display(13, .semibold))
                    .foregroundStyle(Palette.navy)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .iconHelp(L("Hide this"))
            }
            Text(line)
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Palette.brassSoft.opacity(0.55))
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.brass).frame(width: 2)
        }
    }

    private var line: String {
        let since = Lp(welcome.daysAway,
                       "It has been %d day since you last practiced.",
                       "It has been %d days since you last practiced.")
        if welcome.skills.isEmpty {
            return since + " " + L("Pick up anywhere — a short sitting counts.")
        }
        let named = welcome.skills.count == 1
            ? welcome.skills[0]
            : Lf("%1$@ and %2$@", welcome.skills[0], welcome.skills[1])
        return since + " " + Lf("Worth going back over %@ first.", named)
    }
}

struct DamagedFilesNotice: View {
    @EnvironmentObject var store: AppStore
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("Some saved work could not be read, so it was kept aside, untouched, as a “.damaged” file in the app's folder."))
                .font(Face.ui(10.5))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .help(store.damagedFiles.joined(separator: "\n"))
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .iconHelp(L("Hide this"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Palette.brassSoft.opacity(0.55))
        .overlay(alignment: .leading) {
            Rectangle().fill(Palette.brass).frame(width: 2)
        }
    }
}
