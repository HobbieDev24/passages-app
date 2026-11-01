import SwiftUI
import PassagesCore
import AppKit
import UniformTypeIdentifiers

@main
struct PassagesApp: App {
    @StateObject private var model: LibraryViewModel

    init() {
        AppStorage.configureNetworkPrivacy()
        _model = StateObject(wrappedValue: LibraryViewModel())
    }

    @MainActor
    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset Passages?"
        alert.informativeText = "Remove the saved Notion token, export preferences, and all Passages permissions. Your Apple Books highlights, Notion pages, and exported files are kept. Reopen Passages after it quits to start fresh."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset and Quit")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await model.prepareForReset()
            do {
                try await AppStorage.resetAllPermissions()
                NSApplication.shared.terminate(nil)
            } catch {
                model.needsBooksAccess = true
                let failure = NSAlert()
                failure.messageText = "Reset couldn’t finish completely"
                failure.informativeText = error.localizedDescription
                failure.addButton(withTitle: "OK")
                failure.runModal()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 540)
                .task { await model.bootstrap() }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Reset Passages…") { confirmReset() }
            }
            CommandGroup(after: .saveItem) {
                Button("Export Selected Book…") { model.exportSelectedWithPanel() }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(!model.hasNotionKey || model.selectedBook == nil || model.highlights.isEmpty)
                Button("Export All Books…") { model.exportAllWithPanel() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.books.isEmpty)
                Divider()
                Button("Export to Notion…") { model.beginNotionExport() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .disabled(!model.hasNotionKey || model.selectedBook == nil || model.highlights.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
