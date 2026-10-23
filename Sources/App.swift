import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var chosenAppearance: (() -> NSAppearance?)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = chosenAppearance?() ?? Appearance.system.nsAppearance
        openWide()
        holdTheFloor()
        openUnfocused()
        parkFocusAfterEveryClick()
        listTheWindowOnce()
        parkFocusInSheets()
    }

    private func parkFocusInSheets() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                               object: nil, queue: .main) { note in
            guard let sheet = note.object as? NSWindow, sheet.sheetParent != nil else { return }
            let opener = NSApp.currentEvent?.type
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WindowChrome.parkFocus(in: sheet, openedBy: opener)
            }
        }
    }

    private func listTheWindowOnce() {
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                               object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow,
                  window.styleMask.contains(.resizable), window.canBecomeMain else { return }
            window.isExcludedFromWindowsMenu = true
        }
    }

    private func holdTheFloor() {
        let apply = {
            for window in NSApp.windows where window.styleMask.contains(.resizable) {
                window.contentMinSize = NSSize(width: WindowChrome.minWidth,
                                               height: WindowChrome.minHeight)
            }
        }
        apply()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: apply)
    }

    private func openWide() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible }),
                  let screen = window.screen ?? NSScreen.main else { return }
            let saved = UserDefaults.standard.bool(forKey: Self.sizedKey)
            guard !saved else { return }
            UserDefaults.standard.set(true, forKey: Self.sizedKey)
            var frame = screen.visibleFrame
            frame.size.width = max(frame.size.width, WindowChrome.minWidth)
            frame.size.height = max(frame.size.height, WindowChrome.minHeight)
            window.setFrame(frame, display: true, animate: false)
        }
    }

    private func openUnfocused() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for window in NSApp.windows where window.isVisible {
                window.makeFirstResponder(nil)
            }
        }
    }

    private func parkFocusAfterEveryClick() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { event in
            DispatchQueue.main.async {
                guard let window = event.window ?? NSApp.keyWindow else { return }
                let holder = window.firstResponder
                guard !(holder is NSText), !(holder is NSTextView) else { return }
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private static let sizedKey = "usufu.windowSized"
}

@main
struct SATPrepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @StateObject private var intro = IntroState()

    var body: some Scene {
        WindowGroup(Brand.appName, id: MainWindowCommand.id) {
            RootView()
                .environmentObject(store)
                .environmentObject(intro)
                .onAppear {
                    appDelegate.chosenAppearance = { [weak store] in
                        guard let store else { return nil }
                        return store.settings.stealthMode
                            ? NSAppearance(named: .darkAqua)
                            : store.settings.appearance.nsAppearance
                    }
                    applyAppearance()
                }
                .onChange(of: store.settings.appearance) { _ in applyAppearance() }
                .onChange(of: store.settings.stealthMode) { _ in applyAppearance() }
                .task {
                    store.refreshReminders()
                    await store.rereadStaleBanks()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) {}
            CommandGroup(replacing: .appInfo) {
                Button(Lf("About %@", Brand.appName)) {
                    NotificationCenter.default.post(name: .usufuOpenAbout, object: nil)
                }
            }
            CommandGroup(after: .appInfo) {
                Button(L("Settings…")) { NotificationCenter.default.post(
                    name: .usufuOpenSettings, object: nil) }
                    .keyboardShortcut(",", modifiers: .command)
                Button(L("Open the questions folder")) {
                    NSWorkspace.shared.open(store.root)
                }
            }
            CommandGroup(before: .windowList) {
                MainWindowCommand()
            }
            CommandGroup(after: .toolbar) {
                Picker(L("Appearance"), selection: Binding(
                    get: { store.settings.appearance },
                    set: { store.settings.appearance = $0 })) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func applyAppearance() {
        NSApp.appearance = store.settings.stealthMode
            ? NSAppearance(named: .darkAqua)
            : store.settings.appearance.nsAppearance
    }
}

struct MainWindowCommand: View {
    static let id = "main"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(Brand.appName) {
            if let window = NSApp.windows.first(where: WindowChrome.isMain) {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            } else {
                openWindow(id: Self.id)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
