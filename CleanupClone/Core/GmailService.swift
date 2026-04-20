import Foundation
import GoogleSignIn
import UIKit

extension GIDGoogleUser: @unchecked @retroactive Sendable {}
extension GIDSignInResult: @unchecked @retroactive Sendable {}

struct GmailAccountSummary: Hashable {
    let email: String
    let displayName: String
    let avatarURL: URL?
    let grantedScopes: [String]
}

struct GmailCategorySummary: Identifiable, Hashable {
    let id: String
    let title: String
    let labelID: String
    let messageCount: Int
}

struct GmailSenderSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let emailCount: Int
    let unsubscribeURL: URL?
    let supportsOneClickPost: Bool
    let mailtoUnsubscribe: URL?
}

struct GmailMailboxSnapshot: Hashable {
    let account: GmailAccountSummary
    let categories: [GmailCategorySummary]
    let senders: [GmailSenderSummary]
    let syncedAt: Date
}

struct GmailMessagePreview: Identifiable, Hashable {
    let id: String
    let threadId: String
    let fromName: String
    let fromEmail: String
    let subject: String
    let snippet: String
    let date: Date?
    let isUnread: Bool
}

struct GmailMessagePage: Hashable {
    let messages: [GmailMessagePreview]
    let nextPageToken: String?
    let totalEstimate: Int
}

struct GmailMessageDetail: Hashable {
    let id: String
    let fromName: String
    let fromEmail: String
    let subject: String
    let date: Date?
    let htmlBody: String?
    let plainBody: String?
}

enum GmailUnsubscribeResult {
    case oneClickPosted
    case mailtoSent
    case openURL(URL)
    case notAvailable
}

enum GmailServiceError: LocalizedError {
    case missingPresenter
    case missingCurrentUser
    case invalidResponse
    case missingOAuthConfiguration

    var errorDescription: String? {
        switch self {
        case .missingPresenter:
            "Couldn't find a screen to present Google Sign-In."
        case .missingCurrentUser:
            "No Gmail account is currently connected."
        case .invalidResponse:
            "Google returned an unexpected response."
        case .missingOAuthConfiguration:
            "Google OAuth is missing from Info.plist."
        }
    }
}

@MainActor
final class GmailService {
    static let shared = GmailService()

    private static let gmailModifyScope = "https://www.googleapis.com/auth/gmail.modify"
    private static let signInErrorDomain = "com.google.GIDSignIn"
    private static let keychainErrorCodes: Set<Int> = [-2, -4]
    private static let senderSamplingLabels = [
        "CATEGORY_PROMOTIONS",
        "CATEGORY_SOCIAL",
        "CATEGORY_UPDATES",
        "CATEGORY_FORUMS"
    ]

    private let session = URLSession.shared

    private init() {}

    var isConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String != nil
    }

    func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func isRecoverableRestoreError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == Self.signInErrorDomain && Self.keychainErrorCodes.contains(nsError.code)
    }

    func userFacingMessage(for error: Error) -> String {
        if isRecoverableRestoreError(error) {
            return "Google Sign-In couldn't use Keychain on this simulator. Delete the app and try again, or test on a signed device build."
        }

        return error.localizedDescription
    }

    func restoreSessionIfPossible() async throws -> GmailMailboxSnapshot? {
        guard isConfigured else {
            throw GmailServiceError.missingOAuthConfiguration
        }
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            return nil
        }

        let user = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user else {
                    continuation.resume(throwing: GmailServiceError.missingCurrentUser)
                    return
                }
                continuation.resume(returning: user)
            }
        }

        return try await mailboxSnapshot(for: user)
    }

    @MainActor
    func signIn(presentingViewController: UIViewController) async throws -> GmailMailboxSnapshot {
        guard isConfigured else {
            throw GmailServiceError.missingOAuthConfiguration
        }

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingViewController,
                hint: nil,
                additionalScopes: [Self.gmailModifyScope]
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: GmailServiceError.invalidResponse)
                    return
                }
                continuation.resume(returning: result)
            }
        }

        return try await mailboxSnapshot(for: result.user)
    }

    func refreshMailbox() async throws -> GmailMailboxSnapshot {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        return try await mailboxSnapshot(for: currentUser)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func disconnect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            GIDSignIn.sharedInstance.disconnect { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    private func mailboxSnapshot(for user: GIDGoogleUser) async throws -> GmailMailboxSnapshot {
        let refreshedUser = try await refreshTokensIfNeeded(for: user)
        let accessToken = refreshedUser.accessToken.tokenString

        async let categoriesTask = fetchCategories(accessToken: accessToken)
        async let sendersTask = fetchTopSenders(accessToken: accessToken)

        return GmailMailboxSnapshot(
            account: accountSummary(from: refreshedUser),
            categories: try await categoriesTask,
            senders: try await sendersTask,
            syncedAt: Date()
        )
    }

    private func refreshTokensIfNeeded(for user: GIDGoogleUser) async throws -> GIDGoogleUser {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GIDGoogleUser, Error>) in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let user else {
                    continuation.resume(throwing: GmailServiceError.invalidResponse)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    private func accountSummary(from user: GIDGoogleUser) -> GmailAccountSummary {
        let profile = user.profile
        return GmailAccountSummary(
            email: profile?.email ?? "Connected Gmail",
            displayName: profile?.name ?? profile?.email ?? "Connected Gmail",
            avatarURL: profile?.hasImage == true ? profile?.imageURL(withDimension: 120) : nil,
            grantedScopes: user.grantedScopes ?? []
        )
    }

    private func fetchCategories(accessToken: String) async throws -> [GmailCategorySummary] {
        let response: GmailLabelListResponse = try await request(
            path: "users/me/labels",
            accessToken: accessToken
        )

        let labelsByID = Dictionary(uniqueKeysWithValues: response.labels.map { ($0.id, $0) })
        let definitions: [(String, String, String)] = [
            ("Social", "Social Media", "CATEGORY_SOCIAL"),
            ("Promotions", "Promotions", "CATEGORY_PROMOTIONS"),
            ("Updates", "Updates", "CATEGORY_UPDATES"),
            ("Newsletters", "Forum", "CATEGORY_FORUMS"),
            ("Notifications", "Spam", "SPAM")
        ]

        return definitions.map { id, title, labelID in
            GmailCategorySummary(
                id: id,
                title: title,
                labelID: labelID,
                messageCount: labelsByID[labelID]?.messagesTotal ?? 0
            )
        }
    }

    private func fetchTopSenders(accessToken: String) async throws -> [GmailSenderSummary] {
        var groupedSenders: [String: SenderAccumulator] = [:]

        try await withThrowingTaskGroup(of: [GmailMessageIdentifier].self) { group in
            for labelID in Self.senderSamplingLabels {
                group.addTask {
                    let response: GmailMessageListResponse = try await self.request(
                        path: "users/me/messages",
                        accessToken: accessToken,
                        queryItems: [
                            URLQueryItem(name: "labelIds", value: labelID),
                            URLQueryItem(name: "maxResults", value: "20")
                        ]
                    )
                    return response.messages ?? []
                }
            }

            for try await messages in group {
                for message in messages {
                    let metadata = try await fetchMessageMetadata(
                        accessToken: accessToken,
                        messageID: message.id
                    )
                    guard let sender = parseSender(from: metadata.payload.headers) else {
                        continue
                    }

                    var accumulator = groupedSenders[sender.email.lowercased()] ?? SenderAccumulator(
                        name: sender.name,
                        email: sender.email,
                        sampleCount: 0,
                        unsubscribeURL: nil,
                        supportsOneClickPost: false,
                        mailtoUnsubscribe: nil
                    )
                    accumulator.sampleCount += 1
                    accumulator.name = sender.name
                    let parsed = parseAllUnsubscribe(from: metadata.payload.headers)
                    accumulator.unsubscribeURL = accumulator.unsubscribeURL ?? parsed.httpURL
                    accumulator.mailtoUnsubscribe = accumulator.mailtoUnsubscribe ?? parsed.mailto
                    accumulator.supportsOneClickPost = accumulator.supportsOneClickPost || parsed.oneClick
                    groupedSenders[sender.email.lowercased()] = accumulator
                }
            }
        }

        let candidates = groupedSenders.values
            .sorted { lhs, rhs in
                if lhs.sampleCount == rhs.sampleCount {
                    return lhs.email < rhs.email
                }
                return lhs.sampleCount > rhs.sampleCount
            }
            .prefix(8)

        var resolved: [GmailSenderSummary] = []
        for candidate in candidates {
            let listResponse: GmailMessageListResponse = try await request(
                path: "users/me/messages",
                accessToken: accessToken,
                queryItems: [
                    URLQueryItem(name: "q", value: "from:\(candidate.email)"),
                    URLQueryItem(name: "maxResults", value: "1")
                ]
            )

            resolved.append(
                GmailSenderSummary(
                    id: candidate.email.lowercased(),
                    name: candidate.name,
                    email: candidate.email,
                    emailCount: max(candidate.sampleCount, listResponse.resultSizeEstimate ?? candidate.sampleCount),
                    unsubscribeURL: candidate.unsubscribeURL ?? candidate.mailtoUnsubscribe,
                    supportsOneClickPost: candidate.supportsOneClickPost,
                    mailtoUnsubscribe: candidate.mailtoUnsubscribe
                )
            )
        }

        return resolved.sorted {
            if $0.emailCount == $1.emailCount {
                return $0.email < $1.email
            }
            return $0.emailCount > $1.emailCount
        }
    }

    private func fetchMessageMetadata(accessToken: String, messageID: String) async throws -> GmailMessageMetadataResponse {
        try await request(
            path: "users/me/messages/\(messageID)",
            accessToken: accessToken,
            queryItems: [
                URLQueryItem(name: "format", value: "metadata"),
                URLQueryItem(name: "metadataHeaders", value: "From"),
                URLQueryItem(name: "metadataHeaders", value: "Subject"),
                URLQueryItem(name: "metadataHeaders", value: "Date"),
                URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe"),
                URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe-Post")
            ]
        )
    }

    // MARK: - Paginated message listing per label

    func listMessages(
        labelID: String,
        pageToken: String?,
        pageSize: Int = 50
    ) async throws -> GmailMessagePage {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        let refreshed = try await refreshTokensIfNeeded(for: currentUser)
        let accessToken = refreshed.accessToken.tokenString

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "labelIds", value: labelID),
            URLQueryItem(name: "maxResults", value: String(pageSize))
        ]
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        let listResponse: GmailMessageListResponse = try await request(
            path: "users/me/messages",
            accessToken: accessToken,
            queryItems: queryItems
        )

        let ids = listResponse.messages ?? []
        var previews: [GmailMessagePreview] = Array(repeating: placeholderPreview, count: ids.count)

        try await withThrowingTaskGroup(of: (Int, GmailMessagePreview?).self) { group in
            for (index, identifier) in ids.enumerated() {
                group.addTask {
                    let preview = try await self.fetchMessagePreview(
                        accessToken: accessToken,
                        messageID: identifier.id
                    )
                    return (index, preview)
                }
            }
            for try await (index, preview) in group {
                if let preview {
                    previews[index] = preview
                }
            }
        }

        previews.removeAll { $0.id.isEmpty }

        return GmailMessagePage(
            messages: previews,
            nextPageToken: listResponse.nextPageToken,
            totalEstimate: listResponse.resultSizeEstimate ?? previews.count
        )
    }

    private var placeholderPreview: GmailMessagePreview {
        GmailMessagePreview(id: "", threadId: "", fromName: "", fromEmail: "", subject: "", snippet: "", date: nil, isUnread: false)
    }

    private func fetchMessagePreview(accessToken: String, messageID: String) async throws -> GmailMessagePreview? {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageID)")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
            URLQueryItem(name: "metadataHeaders", value: "Date")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        let decoded = try JSONDecoder().decode(GmailMessageFullResponse.self, from: data)
        let headers = decoded.payload?.headers ?? []
        let sender = parseSender(from: headers)
        let subject = headers.first { $0.name.caseInsensitiveCompare("Subject") == .orderedSame }?.value ?? "(no subject)"
        let dateString = headers.first { $0.name.caseInsensitiveCompare("Date") == .orderedSame }?.value
        let date = dateString.flatMap(parseRFC2822Date)
        let isUnread = (decoded.labelIds ?? []).contains("UNREAD")

        return GmailMessagePreview(
            id: decoded.id,
            threadId: decoded.threadId ?? decoded.id,
            fromName: sender?.name ?? "(unknown)",
            fromEmail: sender?.email ?? "",
            subject: subject,
            snippet: decoded.snippet ?? "",
            date: date,
            isUnread: isUnread
        )
    }

    // MARK: - Message detail (full body)

    func fetchMessageDetail(messageID: String) async throws -> GmailMessageDetail {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        let refreshed = try await refreshTokensIfNeeded(for: currentUser)
        let accessToken = refreshed.accessToken.tokenString

        let response: GmailMessageFullResponse = try await request(
            path: "users/me/messages/\(messageID)",
            accessToken: accessToken,
            queryItems: [URLQueryItem(name: "format", value: "full")]
        )

        let headers = response.payload?.headers ?? []
        let sender = parseSender(from: headers)
        let subject = headers.first { $0.name.caseInsensitiveCompare("Subject") == .orderedSame }?.value ?? "(no subject)"
        let dateString = headers.first { $0.name.caseInsensitiveCompare("Date") == .orderedSame }?.value
        let date = dateString.flatMap(parseRFC2822Date)

        let (html, plain) = extractBodies(from: response.payload)

        return GmailMessageDetail(
            id: response.id,
            fromName: sender?.name ?? "(unknown)",
            fromEmail: sender?.email ?? "",
            subject: subject,
            date: date,
            htmlBody: html,
            plainBody: plain
        )
    }

    private func extractBodies(from payload: GmailPayloadFull?) -> (String?, String?) {
        guard let payload else { return (nil, nil) }
        var html: String?
        var plain: String?
        walk(payload, html: &html, plain: &plain)
        return (html, plain)
    }

    private func walk(_ part: GmailPayloadFull, html: inout String?, plain: inout String?) {
        let mime = (part.mimeType ?? "").lowercased()
        if mime == "text/html", html == nil, let body = decodeBody(part.body?.data) {
            html = body
        } else if mime == "text/plain", plain == nil, let body = decodeBody(part.body?.data) {
            plain = body
        }
        for child in part.parts ?? [] {
            walk(child, html: &html, plain: &plain)
        }
    }

    private func decodeBody(_ base64url: String?) -> String? {
        guard var value = base64url, !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 { value.append("=") }
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func parseRFC2822Date(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz"
        ]
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    // MARK: - Batch trash / archive

    func trashMessages(ids: [String]) async throws {
        try await modifyMessages(ids: ids, addLabelIds: ["TRASH"], removeLabelIds: [])
    }

    func archiveMessages(ids: [String]) async throws {
        try await modifyMessages(ids: ids, addLabelIds: [], removeLabelIds: ["INBOX"])
    }

    private func modifyMessages(ids: [String], addLabelIds: [String], removeLabelIds: [String]) async throws {
        guard !ids.isEmpty else { return }
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        let refreshed = try await refreshTokensIfNeeded(for: currentUser)
        let accessToken = refreshed.accessToken.tokenString

        // Gmail batchModify caps at 1000 ids.
        let chunks = stride(from: 0, to: ids.count, by: 900).map { Array(ids[$0..<min($0 + 900, ids.count)]) }
        for chunk in chunks {
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/batchModify")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "ids": chunk,
                "addLabelIds": addLabelIds,
                "removeLabelIds": removeLabelIds
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Gmail batchModify failed"
                throw NSError(domain: "GmailService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
    }

    // MARK: - One-click unsubscribe

    func unsubscribe(sender: GmailSenderSummary) async throws -> GmailUnsubscribeResult {
        if sender.supportsOneClickPost, let url = sender.unsubscribeURL, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "List-Unsubscribe=One-Click".data(using: .utf8)
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                return .oneClickPosted
            }
            return .openURL(url)
        }

        if let mailto = sender.mailtoUnsubscribe {
            try await sendMailtoUnsubscribe(mailto: mailto)
            return .mailtoSent
        }

        if let url = sender.unsubscribeURL {
            return .openURL(url)
        }
        return .notAvailable
    }

    private func sendMailtoUnsubscribe(mailto: URL) async throws {
        // Parse "mailto:addr?subject=unsubscribe&body=..."
        guard let comps = URLComponents(url: mailto, resolvingAgainstBaseURL: false), let path = comps.path.isEmpty ? nil : comps.path as String? else {
            return
        }
        let to = path
        let subject = comps.queryItems?.first(where: { $0.name.lowercased() == "subject" })?.value ?? "unsubscribe"
        let body = comps.queryItems?.first(where: { $0.name.lowercased() == "body" })?.value ?? "unsubscribe"

        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        let refreshed = try await refreshTokensIfNeeded(for: currentUser)
        let accessToken = refreshed.accessToken.tokenString
        let fromEmail = refreshed.profile?.email ?? ""

        let raw = """
        From: \(fromEmail)\r
        To: \(to)\r
        Subject: \(subject)\r
        MIME-Version: 1.0\r
        Content-Type: text/plain; charset=UTF-8\r
        \r
        \(body)
        """

        let encoded = Data(raw.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["raw": encoded])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Gmail send failed"
            throw NSError(domain: "GmailService", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    func trashAllFromSender(_ email: String) async throws -> Int {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GmailServiceError.missingCurrentUser
        }
        let refreshed = try await refreshTokensIfNeeded(for: currentUser)
        let accessToken = refreshed.accessToken.tokenString

        var allIDs: [String] = []
        var pageToken: String?
        repeat {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "q", value: "from:\(email)"),
                URLQueryItem(name: "maxResults", value: "500")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let response: GmailMessageListResponse = try await request(
                path: "users/me/messages",
                accessToken: accessToken,
                queryItems: queryItems
            )
            allIDs.append(contentsOf: (response.messages ?? []).map { $0.id })
            pageToken = response.nextPageToken
        } while pageToken != nil && allIDs.count < 5000

        try await trashMessages(ids: allIDs)
        return allIDs.count
    }

    private func request<Response: Decodable>(
        path: String,
        accessToken: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/\(path)")!
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailServiceError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Google API error"
            throw NSError(domain: "GmailService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func parseSender(from headers: [GmailHeader]) -> ParsedSender? {
        guard let rawValue = headers.first(where: { $0.name.caseInsensitiveCompare("From") == .orderedSame })?.value else {
            return nil
        }

        if let rangeStart = rawValue.range(of: "<"), let rangeEnd = rawValue.range(of: ">", range: rangeStart.upperBound ..< rawValue.endIndex) {
            let name = rawValue[..<rangeStart.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
            let email = String(rawValue[rangeStart.upperBound ..< rangeEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedSender(name: name.isEmpty ? email : name, email: email)
        }

        let email = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.contains("@") ? ParsedSender(name: email.components(separatedBy: "@").first ?? email, email: email) : nil
    }

    private func parseUnsubscribeURL(from headers: [GmailHeader]) -> URL? {
        parseAllUnsubscribe(from: headers).httpURL ?? parseAllUnsubscribe(from: headers).mailto
    }

    private func parseAllUnsubscribe(from headers: [GmailHeader]) -> (httpURL: URL?, mailto: URL?, oneClick: Bool) {
        let rawValue = headers.first { $0.name.caseInsensitiveCompare("List-Unsubscribe") == .orderedSame }?.value
        let postHeader = headers.first { $0.name.caseInsensitiveCompare("List-Unsubscribe-Post") == .orderedSame }?.value
        let oneClick = (postHeader ?? "").lowercased().contains("one-click")

        guard let rawValue else { return (nil, nil, false) }
        let fragments = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>\t")) }

        var http: URL?
        var mailto: URL?
        for fragment in fragments {
            guard let url = URL(string: fragment), let scheme = url.scheme?.lowercased() else { continue }
            if (scheme == "https" || scheme == "http"), http == nil { http = url }
            if scheme == "mailto", mailto == nil { mailto = url }
        }
        return (http, mailto, oneClick)
    }
}

private struct SenderAccumulator {
    var name: String
    var email: String
    var sampleCount: Int
    var unsubscribeURL: URL?
    var supportsOneClickPost: Bool
    var mailtoUnsubscribe: URL?
}

private struct ParsedSender {
    let name: String
    let email: String
}

private struct GmailLabelListResponse: Decodable {
    let labels: [GmailLabel]
}

private struct GmailLabel: Decodable {
    let id: String
    let messagesTotal: Int?
}

private struct GmailMessageListResponse: Decodable {
    let messages: [GmailMessageIdentifier]?
    let resultSizeEstimate: Int?
    let nextPageToken: String?
}

private struct GmailMessageIdentifier: Decodable {
    let id: String
}

private struct GmailMessageMetadataResponse: Decodable {
    let payload: GmailPayload
}

private struct GmailPayload: Decodable {
    let headers: [GmailHeader]
}

private struct GmailHeader: Decodable {
    let name: String
    let value: String
}

private struct GmailMessageFullResponse: Decodable {
    let id: String
    let threadId: String?
    let snippet: String?
    let labelIds: [String]?
    let payload: GmailPayloadFull?
}

private struct GmailPayloadFull: Decodable {
    let mimeType: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPayloadFull]?
}

private struct GmailBody: Decodable {
    let data: String?
    let size: Int?
}
