import SwiftUI
import PassagesCore

struct ExportToolbar: ToolbarContent {
    @EnvironmentObject var model: LibraryViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.exportSelectedWithPanel()
            } label: {
                Label("Export Book", systemImage: "square.and.arrow.up")
            }
            .disabled(model.selectedBook == nil || model.highlights.isEmpty)
            .help("Export the selected book’s highlights")

            Button {
                model.exportAllWithPanel()
            } label: {
                Label("Export All", systemImage: "square.and.arrow.up.on.square")
            }
            .disabled(model.books.isEmpty)
            .help("Export highlights from every book")

            Button {
                model.beginNotionExport()
            } label: {
                Label { Text("Notion") } icon: { NotionIcon() }
            }
            .disabled(!model.hasNotionKey || model.selectedBook == nil || model.highlights.isEmpty)
            .help(model.hasNotionKey ? "Add the selected book’s highlights to Notion" : "Save a Notion token in Settings → Integrations to enable export.")
        }
    }
}

private struct NotionIcon: View {
    var body: some View {
        Text("N")
            .font(.system(size: 15, weight: .black, design: .serif))
            .frame(width: 19, height: 19)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.4))
            .accessibilityHidden(true)
    }
}
