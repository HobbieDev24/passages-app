import SwiftUI
import PassagesCore

struct NotionExportView: View {
    @EnvironmentObject var model: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !model.hasNotionKey {
                missingKeyNotice
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notion page URL")
                    .font(.subheadline.weight(.medium))
                TextField("https://www.notion.so/Your-Page-abc123…", text: $model.notionPageURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(model.notionState == .working)
                Text("Paste the URL of the Notion page to append highlights to. Make sure your integration is added to that page’s Connections.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            statusRow

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { model.cancelNotionExport(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.notionState == .working ? "Sending…" : "Export") {
                    model.startNotionExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canStartNotionExport)
            }
        }
        .padding(20)
        .frame(width: 480, height: 380)
        .onDisappear { model.cancelNotionExport() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let book = model.selectedBook {
                BookCover(book: book)
                    .frame(width: 40, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export to Notion").font(.title3.bold())
                    Text("\(book.displayTitle) · \(model.highlights.count) highlights")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Export to Notion").font(.title3.bold())
            }
            Spacer()
        }
    }

    private var missingKeyNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            Text("Add your token in Settings → Integrations → Notion before exporting.")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusRow: some View {
        switch model.notionState {
        case .idle:
            EmptyView()
        case .working:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(model.notionStatusMessage.isEmpty ? "Sending to Notion…" : model.notionStatusMessage)
                    .font(.callout).foregroundStyle(.secondary)
            }
        case .success:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(model.notionStatusMessage).font(.callout)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        case .failure:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(model.notionStatusMessage)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
