import Foundation
import Darwin

enum AppStorage {
    static let domain = "com.passages.highlights"
    static var preferences: UserDefaults { .standard }

    static func configureNetworkPrivacy() {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
    }

    static func cleanupPrivateFiles() async throws {
        try await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let library = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            for parent in ["Caches", "HTTPStorages", "Saved Application State"] {
                let name = parent == "Saved Application State" ? domain + ".savedState" : domain
                let url = library.appendingPathComponent(parent).appendingPathComponent(name)
                if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
            }
            let temporary = manager.temporaryDirectory
            for url in try manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                let prefix = ["PassagesSnapshot-", "KlibSnapshot-"].first { url.lastPathComponent.hasPrefix($0) }
                guard let prefix, UUID(uuidString: String(url.lastPathComponent.dropFirst(prefix.count))) != nil,
                      try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                      let owner = try manager.attributesOfItem(atPath: url.path)[.ownerAccountID] as? NSNumber,
                      owner.uint32Value == getuid() else { continue }
                try manager.removeItem(at: url)
            }
        }.value
    }

    static func resetAllPermissions() async throws {
        var failures: [String] = []
        do { try await reset() } catch { failures.append(error.localizedDescription) }
        do {
            try await Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                process.arguments = ["reset", "All", domain]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = output
                try process.run()
                let details = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw NSError(domain: domain, code: Int(process.terminationStatus), userInfo: [
                        NSLocalizedDescriptionKey: "macOS permissions could not be reset. " + String(details.prefix(400))
                    ])
                }
            }.value
        } catch { failures.append(error.localizedDescription) }
        if !failures.isEmpty { throw resetError(failures) }
    }

    static func reset() async throws {
        var failures: [String] = []
        do { try await KeychainStore.deleteNotionKey() } catch {
            failures.append("The saved Keychain token could not be removed. " + error.localizedDescription)
        }
        do { try await cleanupPrivateFiles() } catch {
            failures.append("Private cache files could not be removed. " + error.localizedDescription)
        }
        preferences.removePersistentDomain(forName: domain)
        if !failures.isEmpty { throw resetError(failures) }
    }

    private static func resetError(_ failures: [String]) -> NSError {
        NSError(domain: domain, code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Reset completed with errors. " + failures.joined(separator: " ")
        ])
    }
}
