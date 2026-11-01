import Foundation
import PassagesCore

final class LibraryFolderAccess {
    private static let bookmarkKey = "appleBooksDataFolderBookmark"
    static var defaultFolder: URL { BooksDatabase.defaultContainer.deletingLastPathComponent() }
    private var activeFolder: URL?

    deinit { activeFolder?.stopAccessingSecurityScopedResource() }

    func close() {
        activeFolder?.stopAccessingSecurityScopedResource()
        activeFolder = nil
    }

    func restore() throws -> URL? {
        if let activeFolder { return activeFolder }
        guard let bookmark = AppStorage.preferences.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                             relativeTo: nil, bookmarkDataIsStale: &stale)
        guard folder.standardizedFileURL == Self.defaultFolder.standardizedFileURL else {
            throw CocoaError(.fileReadNoPermission)
        }
        _ = folder.startAccessingSecurityScopedResource()
        do {
            if stale { try saveBookmark(for: folder) }
            activeFolder = folder
            return folder
        } catch {
            folder.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    func connectDefault() -> URL {
        let folder = Self.defaultFolder
        // An existing grant may allow reading even if a new bookmark cannot be saved.
        try? saveBookmark(for: folder)
        activeFolder = folder
        return folder
    }

    func authorize(_ selectedFolder: URL) throws {
        _ = selectedFolder.startAccessingSecurityScopedResource()
        do {
            guard selectedFolder.standardizedFileURL == Self.defaultFolder.standardizedFileURL else {
                throw CocoaError(.fileReadNoPermission)
            }
            try saveBookmark(for: selectedFolder)
            activeFolder?.stopAccessingSecurityScopedResource()
            activeFolder = selectedFolder
        } catch {
            selectedFolder.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private func saveBookmark(for folder: URL) throws {
        let data = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                          includingResourceValuesForKeys: nil, relativeTo: nil)
        AppStorage.preferences.set(data, forKey: Self.bookmarkKey)
    }
}
