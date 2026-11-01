import Foundation

public struct NotionClient: Sendable {

    public static let apiVersion = "2022-06-28"
    // Notion limits each request to 100 blocks and each text run to 2,000 characters.
    private static let maxBlocksPerRequest = 100
    private static let maxTextRunLength = 2000

    public enum NotionError: Error, CustomStringConvertible {
        case missingAPIKey
        case invalidPageURL
        case rateLimited
        case payloadTooLarge
        case invalidToken
        case http(status: Int, message: String)
        case transport(String)
        case decoding(String)

        public var description: String {
            switch self {
            case .missingAPIKey:
                return "No Notion API key set. Add one in Settings (⌘,)."
            case .invalidPageURL:
                return "That doesn't look like a Notion page URL. Paste the full URL of the page you want to export into."
            case .rateLimited:
                return "Notion's rate limit was reached. Wait a moment and try again."
            case .payloadTooLarge:
                return "This book exceeds Notion's request limits. Export it to a file instead."
            case .invalidToken:
                return "The integration token is invalid. Paste your Notion token again."
            case .http(let status, let message):
                return "Notion API error (HTTP \(status)): \(message)"
            case .transport(let m):
                return "Network error: \(m)"
            case .decoding(let m):
                return "Couldn't read Notion's response: \(m)"
            }
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration, delegate: NotionRedirectPolicy(), delegateQueue: nil)
    }()

    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func pageID(from urlOrID: String) -> String? {
        let input = urlOrID.trimmingCharacters(in: .whitespacesAndNewlines)
        func identifier(_ value: String) -> String? {
            if value.count == 36, let uuid = UUID(uuidString: value) { return uuid.uuidString.lowercased() }
            guard value.count == 32, value.unicodeScalars.allSatisfy({
                (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
            }) else { return nil }
            let chars = Array(value.lowercased())
            return "\(String(chars[0..<8]))-\(String(chars[8..<12]))-\(String(chars[12..<16]))-\(String(chars[16..<20]))-\(String(chars[20..<32]))"
        }
        if let id = identifier(input) { return id }
        let address = input.contains("://") ? input : "https://" + input
        guard let components = URLComponents(string: address), components.scheme == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              ["notion.so", "www.notion.so", "notion.com", "www.notion.com", "app.notion.com", "notion.site"].contains(host) || host.hasSuffix(".notion.site"),
              let segment = components.path.split(separator: "/").last.map(String.init) else { return nil }
        if let id = identifier(segment) { return id }
        for length in [36, 32] where segment.count > length {
            let suffix = String(segment.suffix(length))
            let prefix = segment.dropLast(length)
            if prefix.last == "-", let id = identifier(suffix) { return id }
        }
        return nil
    }

    static func blocks(for book: Book, highlights: [Highlight], includeNotes: Bool) -> [[String: Any]] {
        var blocks: [[String: Any]] = []

        blocks.append(heading("\(book.displayTitle) by \(book.displayAuthor)", level: 1))

        for highlight in highlights {
            blocks.append(paragraph(highlight.text))
            if includeNotes, let note = highlight.note, !note.isEmpty {
                blocks.append(paragraph("Note: \(note)", italic: true))
            }
        }
        return blocks
    }

    private static func richText(_ text: String, italic: Bool = false) -> [[String: Any]] {
        var chunks: [String] = []
        var chunk = String.UnicodeScalarView()
        var length = 0
        for scalar in text.unicodeScalars {
            let size = scalar.value > 0xffff ? 2 : 1
            if length + size > maxTextRunLength {
                chunks.append(String(chunk))
                chunk = String.UnicodeScalarView()
                length = 0
            }
            chunk.append(scalar)
            length += size
        }
        if !chunk.isEmpty { chunks.append(String(chunk)) }
        return chunks.map {
            ["type": "text", "text": ["content": $0], "annotations": ["italic": italic]]
        }
    }

    private static func paragraph(_ text: String, italic: Bool = false) -> [String: Any] {
        ["object": "block", "type": "paragraph",
         "paragraph": ["rich_text": text.isEmpty ? [] : richText(text, italic: italic)]]
    }

    private static func heading(_ text: String, level: Int) -> [String: Any] {
        let key = "heading_\(min(max(level, 1), 3))"
        return ["object": "block", "type": key,
                key: ["rich_text": richText(text)]]
    }

    public func testToken() async throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotionError.missingAPIKey
        }
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/users/me")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        try applyHeaders(to: &request)
        let (data, response) = try await send(request)
        try checkResponse(response: response, data: data)
        guard let user = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              user["object"] as? String == "user", user["id"] as? String != nil else {
            throw NotionError.decoding("Expected a Notion user response")
        }
    }

    @discardableResult
    public func appendHighlights(
        book: Book,
        highlights: [Highlight],
        toPageURLOrID urlOrID: String,
        includeNotes: Bool = true
    ) async throws -> Int {
        guard !apiKey.isEmpty else { throw NotionError.missingAPIKey }
        guard let pageID = Self.pageID(from: urlOrID) else { throw NotionError.invalidPageURL }

        let allBlocks = Self.blocks(for: book, highlights: highlights, includeNotes: includeNotes)
        guard !allBlocks.isEmpty else { return 0 }

        let chunks = allBlocks.chunked(into: Self.maxBlocksPerRequest)
        for chunk in chunks {
            try Task.checkCancellation()
            _ = try Self.requestBody(chunk)
        }
        var appended = 0
        for chunk in chunks {
            try Task.checkCancellation()
            try await appendChunk(chunk, pageID: pageID)
            appended += chunk.count
        }
        return appended
    }

    public func verifyPage(urlOrID: String) async throws -> String {
        guard !apiKey.isEmpty else { throw NotionError.missingAPIKey }
        guard let pageID = Self.pageID(from: urlOrID) else { throw NotionError.invalidPageURL }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages/\(pageID)")!)
        request.httpMethod = "GET"
        try applyHeaders(to: &request)

        let (data, response) = try await send(request)
        try checkResponse(response: response, data: data)
        return Self.extractTitle(from: data) ?? "Notion page"
    }

    private func appendChunk(_ blocks: [[String: Any]], pageID: String) async throws {
        let url = URL(string: "https://api.notion.com/v1/blocks/\(pageID)/children")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        try applyHeaders(to: &request)

        request.httpBody = try Self.requestBody(blocks)

        let (data, response) = try await send(request)
        try checkResponse(response: response, data: data)
    }

    private static func requestBody(_ blocks: [[String: Any]]) throws -> Data {
        for block in blocks {
            if let type = block["type"] as? String,
               let body = block[type] as? [String: Any],
               let runs = body["rich_text"] as? [[String: Any]], runs.count > 100 {
                throw NotionError.payloadTooLarge
            }
        }
        let data = try JSONSerialization.data(withJSONObject: ["children": blocks])
        guard data.count <= 500_000 else { throw NotionError.payloadTooLarge }
        return data
    }

    private func applyHeaders(to request: inout URLRequest) throws {
        guard !apiKey.isEmpty else { throw NotionError.missingAPIKey }
        guard !apiKey.contains("\r"), !apiKey.contains("\n") else { throw NotionError.invalidToken }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        do {
            let result = try await Self.session.data(for: request)
            try Task.checkCancellation()
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NotionError.transport(redacted(error.localizedDescription))
        }
    }

    private func checkResponse(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw NotionError.transport("No HTTP response") }
        if http.statusCode == 429 { throw NotionError.rateLimited }
        if http.statusCode == 401 { throw NotionError.invalidToken }
        if http.statusCode == 403 || http.statusCode == 404 {
            throw NotionError.http(status: http.statusCode, message: "Couldn't access that page. Check the URL and its Connections.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw NotionError.http(status: http.statusCode, message: redacted(Self.extractErrorMessage(from: data) ?? "Request failed"))
        }
    }

    private func redacted(_ message: String) -> String {
        let safe = apiKey.isEmpty ? message : message.replacingOccurrences(of: apiKey, with: "[redacted]")
        return String(safe.replacingOccurrences(of: "(?:secret_|ntn_)[A-Za-z0-9_-]+", with: "[redacted]", options: .regularExpression).prefix(400))
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["message"] as? String
    }

    private static func extractTitle(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = obj["properties"] as? [String: Any] else { return nil }
        for (_, value) in props {
            if let v = value as? [String: Any], v["type"] as? String == "title",
               let arr = v["title"] as? [[String: Any]] {
                let text = arr.compactMap { ($0["plain_text"] as? String) }.joined()
                if !text.isEmpty { return text }
            }
        }
        return nil
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private final class NotionRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
