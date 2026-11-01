import SwiftUI
import PassagesCore

struct HighlightDetailView: View {
    @EnvironmentObject var model: LibraryViewModel

    var body: some View {
        Group {
            if let book = model.selectedBook {
                VStack(alignment: .leading, spacing: 0) {
                    header(book)
                    Divider()
                    if model.isLoadingHighlights {
                        Spacer()
                        HStack { ProgressView().controlSize(.small); Text("Loading highlights…") }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    } else if model.highlights.isEmpty {
                        emptyState
                    } else {
                        highlightList
                    }
                }
            } else {
                noSelection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ book: Book) -> some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(book: book)
                .frame(width: 56, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .shadow(radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.displayTitle).font(.title2.bold()).lineLimit(2)
                Text(book.displayAuthor).font(.subheadline).foregroundStyle(.secondary)
                if let genre = book.genre, !genre.isEmpty {
                    Text(genre).font(.caption).foregroundStyle(.tertiary)
                }
                Text("\(model.highlights.count) highlight\(model.highlights.count == 1 ? "" : "s")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer()
        }
        .padding(16)
    }

    private var highlightList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(model.highlights.enumerated()), id: \.element.id) { index, highlight in
                    HighlightCard(highlight: highlight, index: index + 1)
                }
            }
            .padding(16)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Highlights",
            systemImage: "highlighter",
            description: Text("This book has no highlights.")
        )
    }

    private var noSelection: some View {
        ContentUnavailableView(
            "Select a Book",
            systemImage: "books.vertical",
            description: Text("Choose a book on the left to see its highlights, then export to Markdown or text.")
        )
    }
}

struct HighlightCard: View {
    let highlight: Highlight
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                if let chapter = highlight.chapter, !chapter.isEmpty {
                    Text(chapter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(highlight.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = highlight.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "pencil").font(.caption2).foregroundStyle(.secondary)
                        Text(note)
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private var color: Color {
        switch highlight.style {
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .pink: return .pink
        case .purple: return .purple
        case .underline: return .gray
        case .unknown: return .accentColor
        }
    }
}
