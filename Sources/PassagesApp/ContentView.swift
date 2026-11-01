import SwiftUI
import PassagesCore

struct ContentView: View {
    @EnvironmentObject var model: LibraryViewModel

    var body: some View {
        Group {
            if model.needsBooksAccess {
                LibraryAccessView(
                    isChecking: model.isLoadingBooks,
                    chooseFolder: { model.connectBooksLibrary() },
                    accessMessage: model.libraryAccessMessage
                )
            } else {
                NavigationSplitView {
                    BookSidebar()
                        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
                } detail: {
                    HighlightDetailView()
                }
                .toolbar { ExportToolbar() }
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil && !model.needsBooksAccess },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let msg = model.lastExportMessage {
                ExportToast(message: msg) { model.lastExportMessage = nil }
            }
        }
        .sheet(isPresented: $model.showNotionSheet) {
            NotionExportView()
                .environmentObject(model)
        }
    }
}

struct BookSidebar: View {
    @EnvironmentObject var model: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selectedBookID },
                set: { model.select($0) }
            )) {
                if model.isLoadingBooks {
                    HStack { ProgressView().controlSize(.small); Text("Loading library…") }
                        .foregroundStyle(.secondary)
                } else if model.filteredBooks.isEmpty {
                    Text(model.books.isEmpty ? "No highlighted books found." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.filteredBooks) { book in
                    BookRow(book: book).tag(book.id)
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Image(systemName: "books.vertical")
                Text("\(model.books.count) books · \(model.totalHighlightCount) highlights")
                Spacer()
                Button {
                    model.loadLibrary()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.primary)
                .help("Reload from Apple Books")

                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.primary)
                .help("Settings")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search books")
        .navigationTitle("Passages")
    }
}

struct BookRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 10) {
            BookCover(book: book)
                .frame(width: 34, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))

            VStack(alignment: .leading, spacing: 2) {
                Text(book.displayTitle)
                    .font(.body)
                    .lineLimit(2)
                Text(book.displayAuthor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(book.highlightCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.quaternary))
        }
        .padding(.vertical, 3)
    }
}

struct BookCover: View {
    let book: Book

    var body: some View {
        if let localPath = book.localCoverPath,
           let image = NSImage(contentsOfFile: localPath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.accentColor.opacity(0.7), .accentColor.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "book.closed.fill")
                .foregroundStyle(.white.opacity(0.9))
                .font(.system(size: 14))
        }
    }
}

struct ExportToast: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).font(.callout)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.quaternary))
        .shadow(radius: 8, y: 2)
        .padding(.bottom, 16)
        .task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            dismiss()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
