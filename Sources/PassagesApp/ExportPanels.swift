import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PassagesCore

extension LibraryViewModel {

    func exportSelectedWithPanel() {
        Task {
            guard let result = await exportSelected() else { return }
            let panel = NSSavePanel()
            panel.title = "Export Highlights"
            panel.nameFieldStringValue = result.filename
            panel.allowedContentTypes = [UTType(filenameExtension: (result.filename as NSString).pathExtension) ?? .plainText]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task {
                    do { try await self.writeExport(contents: result.contents, to: url) }
                    catch { self.errorMessage = "Couldn't write file: \(error)" }
                }
            }
        }
    }

    func exportAllWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Export All Books"
        panel.message = "Choose a folder. Each book will be exported as a separate file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    let count = try await self.exportAllToDirectory(url)
                    self.lastExportMessage = "Exported \(count) book\(count == 1 ? "" : "s") to \(url.lastPathComponent)."
                } catch { self.errorMessage = "Export failed: \(error)" }
            }
        }
    }
}
