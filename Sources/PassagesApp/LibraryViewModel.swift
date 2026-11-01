import Foundation
import SwiftUI
import PassagesCore

@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var books: [Book] = []
    @Published var selectedBookID: Book.ID?
    @Published var highlights: [Highlight] = []

    @Published var searchText: String = ""
    @Published var isLoadingBooks = false
    @Published var isLoadingHighlights = false
    @Published var needsBooksAccess = false
    @Published var libraryAccessMessage: String?
    @Published var errorMessage: String?
    @Published var lastExportMessage: String?

    @Published var format: HighlightExporter.Format = LibraryViewModel.persistedFormat() {
        didSet { AppStorage.preferences.set(format.rawValue, forKey: Keys.format) }
    }
    @Published var includeNotes: Bool = AppStorage.preferences.object(forKey: Keys.includeNotes) as? Bool ?? true {
        didSet { AppStorage.preferences.set(includeNotes, forKey: Keys.includeNotes) }
    }
    @Published var groupByChapter: Bool = AppStorage.preferences.object(forKey: Keys.groupByChapter) as? Bool ?? true {
        didSet { AppStorage.preferences.set(groupByChapter, forKey: Keys.groupByChapter) }
    }
    @Published var includeMetadata: Bool = AppStorage.preferences.object(forKey: Keys.includeMetadata) as? Bool ?? false {
        didSet { AppStorage.preferences.set(includeMetadata, forKey: Keys.includeMetadata) }
    }

    private enum Keys {
        static let format = "exportFormat"
        static let includeNotes = "includeNotes"
        static let groupByChapter = "groupByChapter"
        static let includeMetadata = "includeMetadata"
    }

    private static func persistedFormat() -> HighlightExporter.Format {
        if let raw = AppStorage.preferences.string(forKey: Keys.format),
           let f = HighlightExporter.Format(rawValue: raw) {
            return f
        }
        return .markdown
    }

    enum NotionState { case idle, working, success, failure }
    @Published var showNotionSheet = false
    @Published var notionPageURL: String = ""
    @Published var notionState: NotionState = .idle
    @Published var notionStatusMessage: String = ""
    @Published private(set) var notionToken = ""
    @Published private(set) var tokenStorageNeedsAttention = false
    var hasNotionKey: Bool { !notionToken.isEmpty }

    private var hasBootstrapped = false
    private var tokenGeneration = 0
    private var libraryTask: Task<Void, Never>?
    private var highlightsTask: Task<Void, Never>?
    private var notionTask: Task<Void, Never>?
    private var notionExportID: UUID?

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        do {
            try await AppStorage.cleanupPrivateFiles()
            if CommandLine.arguments.contains("--reset-app") { try await AppStorage.reset() }
        } catch { errorMessage = error.localizedDescription }
        let generation = tokenGeneration
        do {
            let token = try await KeychainStore.loadNotionKey()
            if generation == tokenGeneration { notionToken = token }
        } catch {
            if generation == tokenGeneration { tokenStorageNeedsAttention = true }
        }
        loadLibrary()
    }

    func saveNotionToken(_ value: String) async throws {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try await NotionClient(apiKey: token).testToken()
        try Task.checkCancellation()
        do {
            try await KeychainStore.saveNotionKey(token)
        } catch {
            tokenStorageNeedsAttention = true
            throw error
        }
        tokenGeneration += 1
        notionToken = token
        tokenStorageNeedsAttention = false
    }

    @discardableResult
    func deleteNotionToken() async -> Bool {
        tokenGeneration += 1
        cancelNotionExport()
        notionToken = ""
        do {
            try await KeychainStore.deleteNotionKey()
            tokenStorageNeedsAttention = false
            return true
        } catch {
            tokenStorageNeedsAttention = true
            return false
        }
    }

    private let folderAccess = LibraryFolderAccess()
    private var folderPanel: NSOpenPanel?
    private let reader = LibraryReader()

    var selectedBook: Book? {
        guard let id = selectedBookID else { return nil }
        return books.first { $0.id == id }
    }

    var filteredBooks: [Book] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return books }
        let needle = searchText.lowercased()
        return books.filter {
            $0.displayTitle.lowercased().contains(needle)
            || $0.displayAuthor.lowercased().contains(needle)
        }
    }

    var totalHighlightCount: Int {
        books.reduce(0) { $0 + $1.highlightCount }
    }

    var exportOptions: HighlightExporter.Options {
        HighlightExporter.Options(
            includeNotes: includeNotes,
            groupByChapter: groupByChapter,
            includeMetadata: includeMetadata,
            includeAuthor: true
        )
    }

    func connectBooksLibrary() {
        AppStorage.preferences.set(true, forKey: "hasStartedLibraryConnection")
        loadLibrary(requestPermissionIfNeeded: true)
    }

    func loadLibrary(requestPermissionIfNeeded: Bool = false) {
        if !AppStorage.preferences.bool(forKey: "hasStartedLibraryConnection"),
           AppStorage.preferences.data(forKey: "appleBooksDataFolderBookmark") == nil {
            needsBooksAccess = true
            isLoadingBooks = false
            libraryAccessMessage = nil
            return
        }
        isLoadingBooks = true
        errorMessage = nil
        libraryAccessMessage = nil
        libraryTask?.cancel()
        libraryTask = Task {
            do {
                let folder: URL
                do {
                    folder = try self.folderAccess.restore() ?? self.folderAccess.connectDefault()
                } catch {
                    folder = self.folderAccess.connectDefault()
                }
                let loaded = try await reader.loadBooks(container: folder.appendingPathComponent("Documents"))
                try Task.checkCancellation()
                self.needsBooksAccess = false
                self.books = loaded
                if !loaded.contains(where: { $0.id == self.selectedBookID }) {
                    self.selectedBookID = loaded.first?.id
                }
                self.isLoadingBooks = false
                if let id = self.selectedBookID {
                    self.loadHighlights(for: id)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.needsBooksAccess = true
                self.libraryAccessMessage = "Allow access to the Apple Books folder to connect your library."
                self.isLoadingBooks = false
                if requestPermissionIfNeeded { self.chooseBooksFolder() }
            }
        }
    }

    func chooseBooksFolder() {
        guard folderPanel == nil else { return }
        let panel = NSOpenPanel()
        folderPanel = panel
        panel.title = "Connect Apple Books"
        panel.message = "This is the Apple Books folder. Click Allow Access to connect your highlights, metadata, and covers."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = LibraryFolderAccess.defaultFolder
        panel.begin { response in
            self.folderPanel = nil
            guard response == .OK, let folder = panel.url else { return }
            guard folder.standardizedFileURL == LibraryFolderAccess.defaultFolder.standardizedFileURL else {
                self.libraryAccessMessage = "The Apple Books folder is selected automatically. Please approve that folder."
                return
            }
            do {
                try self.folderAccess.authorize(folder)
                self.loadLibrary()
            } catch {
                self.needsBooksAccess = true
                self.libraryAccessMessage = "Couldn’t connect to Apple Books. Open Apple Books once, then retry."
            }
        }
        // Override AppKit’s remembered picker location after it finishes restoring.
        DispatchQueue.main.async {
            panel.directoryURL = LibraryFolderAccess.defaultFolder
        }

    }

    func loadHighlights(for bookID: Book.ID) {
        highlightsTask?.cancel()
        isLoadingHighlights = true
        highlightsTask = Task {
            do {
                let loaded = try await reader.highlights(for: bookID)
                try Task.checkCancellation()
                if selectedBookID == bookID { highlights = loaded; isLoadingHighlights = false }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "\(error)"
                isLoadingHighlights = false
            }
        }
    }

    func select(_ bookID: Book.ID?) {
        selectedBookID = bookID
        highlights = []
        if let bookID { loadHighlights(for: bookID) }
    }

    func exportSelected() async -> (filename: String, contents: String)? {
        guard let book = selectedBook else { return nil }
        let format = format
        let options = exportOptions
        let selected = highlights
        let exporter = HighlightExporter(format: format, options: options)
        let filename = exporter.suggestedFilename(for: book) + "." + format.fileExtension
        let contents = await reader.render(book: book, highlights: selected, format: format, options: options)
        return (filename, contents)
    }

    func writeExport(contents: String, to url: URL) async throws {
        try await reader.write(contents: contents, to: url)
    }

    func exportAllToDirectory(_ directory: URL) async throws -> Int {
        try await reader.exportAll(books: books, directory: directory, format: format, options: exportOptions)
    }

    func prepareForReset() async {
        let export = notionTask
        cancelNotionExport()
        libraryTask?.cancel()
        highlightsTask?.cancel()
        await export?.value
        await libraryTask?.value
        await highlightsTask?.value
        await reader.close()
        folderAccess.close()
        tokenGeneration += 1
        notionToken = ""
        books = []
        highlights = []
    }

    var canStartNotionExport: Bool {
        notionState != .working
        && hasNotionKey
        && selectedBook != nil
        && !highlights.isEmpty
        && !notionPageURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func beginNotionExport() {
        guard hasNotionKey, selectedBook != nil, !highlights.isEmpty else { return }
        cancelNotionExport()
        notionState = .idle
        notionStatusMessage = ""
        showNotionSheet = true
    }

    func cancelNotionExport() {
        notionExportID = nil
        notionTask?.cancel()
        notionTask = nil
        notionState = .idle
        notionStatusMessage = ""
    }

    func startNotionExport() {
        guard canStartNotionExport, let book = selectedBook else { return }
        let selectedHighlights = highlights
        let includeNotes = includeNotes
        let pageRef = notionPageURL
        let client = NotionClient(apiKey: notionToken)
        let id = UUID()
        notionExportID = id
        notionState = .working
        notionStatusMessage = "Verifying page…"
        notionTask = Task {
            defer {
                if notionExportID == id { notionTask = nil; notionExportID = nil }
            }
            do {
                let title = try await client.verifyPage(urlOrID: pageRef)
                try Task.checkCancellation()
                guard notionExportID == id else { return }
                notionStatusMessage = "Sending \(selectedHighlights.count) highlights to “\(title)”…"
                let count = try await client.appendHighlights(book: book, highlights: selectedHighlights,
                                                              toPageURLOrID: pageRef, includeNotes: includeNotes)
                try Task.checkCancellation()
                guard notionExportID == id else { return }
                notionState = .success
                notionStatusMessage = "Added \(count) blocks to “\(title)”."
            } catch {
                guard !Task.isCancelled, notionExportID == id else { return }
                notionState = .failure
                notionStatusMessage = String(describing: error)
            }
        }
    }
}
