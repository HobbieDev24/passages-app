import Foundation

public struct CoverProvider: Sendable {

    public let storeDirectory: URL?

    public init(container: URL = BooksDatabase.defaultContainer) {
        let dir = container
            .deletingLastPathComponent()
            .appendingPathComponent("Library/Caches/BCCoverCache-1/BICDiskDataStore")
        self.storeDirectory = FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    public func coverURL(for assetID: String) -> URL? {
        guard let storeDirectory, !assetID.isEmpty else { return nil }
        let bookDir = storeDirectory.appendingPathComponent(assetID)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: bookDir,
            includingPropertiesForKeys: nil
        ) else { return nil }

        let heics = files.filter { $0.pathExtension.lowercased() == "heic" }
        guard !heics.isEmpty else { return nil }

        let scored = heics.map { url -> (url: URL, area: Int, portrait: Bool) in
            let d = Self.dimensions(from: url)
            let w = d?.width ?? 0, h = d?.height ?? 0
            return (url, w * h, h >= w && h > 0)
        }
        let portrait = scored.filter(\.portrait).max { $0.area < $1.area }
        if let portrait { return portrait.url }
        return scored.max { $0.area < $1.area }?.url
    }

    static func dimensions(from url: URL) -> (width: Int, height: Int)? {
        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.components(separatedBy: "|")
        guard parts.count >= 4, let w = Int(parts[2]), let h = Int(parts[3]) else { return nil }
        return (w, h)
    }
}
