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
}

struct GmailMailboxSnapshot: Hashable {
    let account: GmailAccountSummary
    let categories: [GmailCategorySummary]
    let senders: [GmailSenderSummary]
    let syncedAt: Date
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
                        unsubscribeURL: nil
                    )
                    accumulator.sampleCount += 1
                    accumulator.name = sender.name
                    accumulator.unsubscribeURL = accumulator.unsubscribeURL ?? parseUnsubscribeURL(from: metadata.payload.headers)
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
                    unsubscribeURL: candidate.unsubscribeURL
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
                URLQueryItem(name: "metadataHeaders", value: "List-Unsubscribe")
            ]
        )
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
        guard let rawValue = headers.first(where: { $0.name.caseInsensitiveCompare("List-Unsubscribe") == .orderedSame })?.value else {
            return nil
        }

        let fragments = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>")) }

        for fragment in fragments {
            if let url = URL(string: fragment), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                return url
            }
        }

        return nil
    }
}

private struct SenderAccumulator {
    var name: String
    var email: String
    var sampleCount: Int
    var unsubscribeURL: URL?
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
