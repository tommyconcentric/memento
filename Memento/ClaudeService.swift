import Foundation
import SwiftData

/// What Claude extracts from a conversation transcript.
/// All fields are optional so a sparse reply still decodes.
struct ConversationInsights: Codable {
    var noteSummary: String?
    var location: String?
    var quickInfo: QuickInfoUpdates?
    var importantDates: [DateSuggestion]?

    struct QuickInfoUpdates: Codable {
        var partnerName: String?
        var childrenNames: String?
        var otherFamily: String?
        var jobTitle: String?
        var company: String?
        var hobbies: String?
        var hometown: String?
        var howWeMet: String?
        var foodPreferences: String?
        var birthday: String?   // "yyyy-MM-dd"
    }

    struct DateSuggestion: Codable {
        var label: String
        var date: String        // "yyyy-MM-dd"
    }
}

/// Talks to the Anthropic Messages API using the key stored in the Keychain.
/// Only the transcript text and the person's existing profile summary are
/// sent — never audio, photos, or other people's records.
enum ClaudeService {
    static let apiKeyKeychainKey = "MementoAnthropicAPIKey"

    /// Swap for another Claude model if you prefer — see
    /// https://docs.claude.com/en/api/overview for current model names.
    static let model = "claude-sonnet-4-6"

    static var storedAPIKey: String? {
        KeychainHelper.read(apiKeyKeychainKey)
    }

    enum ServiceError: LocalizedError {
        case missingKey
        case badResponse(String)
        case emptyReply
        case unparseable

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Add your Anthropic API key in Settings first."
            case .badResponse(let detail):
                return "The API request failed: \(detail)"
            case .emptyReply:
                return "Claude returned an empty reply. Try again."
            case .unparseable:
                return "Couldn't read Claude's reply. Try analyzing again."
            }
        }
    }

    // MARK: - Main call

    static func extractInsights(transcript: String, person: Person) async throws -> ConversationInsights {
        guard let apiKey = storedAPIKey?.trimmed, !apiKey.isEmpty else {
            throw ServiceError.missingKey
        }

        let system = """
        You turn transcripts of personal conversations into structured notes for a \
        personal-CRM app. Reply with ONLY a valid JSON object — no markdown, no code \
        fences, no commentary — matching exactly this schema:
        {"noteSummary": string, "location": string or null, "quickInfo": {"partnerName": \
        string or null, "childrenNames": string or null, "otherFamily": string or null, \
        "jobTitle": string or null, "company": string or null, "hobbies": string or null, \
        "hometown": string or null, "howWeMet": string or null, "foodPreferences": string \
        or null, "birthday": "yyyy-MM-dd" or null} or null, "importantDates": [{"label": \
        string, "date": "yyyy-MM-dd"}] or null}

        Rules:
        - noteSummary: 2–5 sentences in third person about what the person shared or \
        what was discussed — updates, plans, things worth following up on later.
        - location: the place they met or talked about meeting, if clearly stated.
        - Only fill a quickInfo field when the transcript clearly states NEW information \
        that differs from the existing profile; otherwise use null. For list-like fields \
        (hobbies, childrenNames, foodPreferences), return the existing value merged with \
        the new items as one string.
        - Only include importantDates the transcript states with a resolvable calendar \
        date; resolve relative dates ("next Friday", "in March") using today's date. \
        Omit anything uncertain.
        - Never invent details that are not in the transcript.
        """

        let userContent = """
        Person: \(person.name)

        Existing profile:
        \(profileSummary(for: person))

        Today's date: \(dayFormatter.string(from: .now))

        Conversation transcript:
        \"\"\"
        \(transcript)
        \"\"\"
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "system": system,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.badResponse(String(snippet.prefix(300)))
        }

        struct APIReply: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
        }

        let reply = try JSONDecoder().decode(APIReply.self, from: data)
        guard let text = reply.content.first(where: { $0.type == "text" })?.text else {
            throw ServiceError.emptyReply
        }

        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = cleaned.data(using: .utf8),
              let insights = try? JSONDecoder().decode(ConversationInsights.self, from: jsonData) else {
            throw ServiceError.unparseable
        }
        return insights
    }

    // MARK: - Helpers

    static func parseDay(_ string: String) -> Date? {
        dayFormatter.date(from: string.trimmed)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func profileSummary(for person: Person) -> String {
        var lines: [String] = []
        func add(_ label: String, _ value: String) {
            if !value.isEmpty { lines.append("- \(label): \(value)") }
        }
        if let birthday = person.birthday {
            add("Birthday", dayFormatter.string(from: birthday))
        }
        add("Partner", person.partnerName)
        add("Children", person.childrenNames)
        add("Other family", person.otherFamily)
        add("Job title", person.jobTitle)
        add("Company", person.company)
        add("Hobbies", person.hobbies)
        add("Hometown", person.hometown)
        add("How we met", person.howWeMet)
        add("Food & drink", person.foodPreferences)
        for item in person.importantDates {
            add(item.label, dayFormatter.string(from: item.date))
        }
        return lines.isEmpty ? "Nothing recorded yet." : lines.joined(separator: "\n")
    }
}
