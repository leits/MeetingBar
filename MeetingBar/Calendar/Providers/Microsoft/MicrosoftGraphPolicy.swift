//
//  MicrosoftGraphPolicy.swift
//  MeetingBar
//
//  Pure, Foundation-only decisions for the Microsoft 365 provider
//  (Microsoft Graph + MSAL). Mirrors `GoogleCalendarPolicy.swift` so the
//  hostless `MeetingBarLogic` package can test HTTP classification, date
//  parsing, field mapping, URL building, and configuration resolution
//  without MSAL, AppKit, or Defaults.
//

import Foundation

// MARK: - Errors

/// Authentication-level failures raised by the Microsoft 365 provider.
///
/// Kept separate from Google's `AuthError` so the two providers never share
/// user-facing wording and the Google policy file stays untouched.
enum MicrosoftAuthError: LocalizedError, Equatable {
    case cancelled
    case notSignedIn
    case refreshFailed
    /// No client ID is available: the `MICROSOFT_CLIENT_ID` build setting is
    /// empty or still carries its placeholder.
    case configurationMissing
    /// A client ID was provided but is malformed. Surfaced verbatim so the
    /// misconfiguration is visible.
    case configurationInvalid(reason: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Microsoft 365 sign-in was cancelled"
        case .notSignedIn:
            return "Microsoft 365 sign-in is required"
        case .refreshFailed:
            return "Microsoft 365 token refresh failed"
        case .configurationMissing:
            return "Microsoft 365 is not configured: the MICROSOFT_CLIENT_ID build setting is missing"
        case let .configurationInvalid(reason):
            return "Microsoft 365 configuration is invalid: \(reason)"
        }
    }
}

/// HTTP-level failures from Microsoft Graph.
enum MicrosoftGraphError: LocalizedError, Equatable {
    /// 403 or 404 for a specific calendar (shared calendar revoked, removed,
    /// or never accessible). One inaccessible calendar must not disconnect
    /// the account, so the store skips it.
    case forbiddenCalendar(calendarID: String?, url: URL)
    /// The signed-in account has no Exchange Online / Outlook.com mailbox
    /// (Graph returns 404 with `MailboxNotEnabledForRESTAPI`).
    case mailboxNotAvailable(URL)
    case rateLimited(retryAfter: TimeInterval, url: URL)
    case httpStatus(Int, code: String?, url: URL)
    case malformedResponse(URL)

    var errorDescription: String? {
        switch self {
        case let .forbiddenCalendar(calendarID, url):
            if let calendarID {
                return "Microsoft 365 calendar is not accessible: \(calendarID)"
            }
            return "Microsoft 365 access is forbidden: \(url.absoluteString)"
        case let .mailboxNotAvailable(url):
            return "This Microsoft account has no Exchange Online or Outlook.com mailbox: \(url.absoluteString)"
        case let .rateLimited(retryAfter, url):
            return "Microsoft 365 is throttling requests (retry after \(Int(retryAfter))s): \(url.absoluteString)"
        case let .httpStatus(statusCode, code, url):
            if let code {
                return "Microsoft 365 request failed with HTTP \(statusCode) (\(code)): \(url.absoluteString)"
            }
            return "Microsoft 365 request failed with HTTP \(statusCode): \(url.absoluteString)"
        case let .malformedResponse(url):
            return "Microsoft 365 response did not contain a value array: \(url.absoluteString)"
        }
    }
}

// MARK: - HTTP status policy

enum MicrosoftGraphHTTPDecision: Equatable {
    case proceed
    case retryWithForcedTokenRefresh
    case clearAuthAndThrowAuthRequired
    case retryAfterDelay(TimeInterval)
    case throwError(MicrosoftGraphError)
}

/// The facts about a single Microsoft Graph HTTP response that
/// `MicrosoftGraphHTTPStatusPolicy` needs to decide what to do next.
struct MicrosoftGraphResponse: Equatable {
    let statusCode: Int
    let url: URL
    let calendarID: String?
    let graphErrorCode: String?
    let retryAfterHeader: String?

    init(
        statusCode: Int,
        url: URL,
        calendarID: String? = nil,
        graphErrorCode: String? = nil,
        retryAfterHeader: String? = nil
    ) {
        self.statusCode = statusCode
        self.url = url
        self.calendarID = calendarID
        self.graphErrorCode = graphErrorCode
        self.retryAfterHeader = retryAfterHeader
    }
}

enum MicrosoftGraphHTTPStatusPolicy {
    /// Longest delay we will wait for inline before retrying. Longer
    /// `Retry-After` values are deferred to the next scheduled sync rather
    /// than retried early (an early retry would just get throttled again).
    static let maxInlineRetryDelay: TimeInterval = 20
    /// Delay used for a 429/503 that carries no usable `Retry-After` header.
    static let defaultRetryAfter: TimeInterval = 2
    /// Graph error codes that mean "this account has no REST-enabled
    /// mailbox" rather than "this calendar is missing".
    static let mailboxUnavailableCodes: Set<String> = [
        "MailboxNotEnabledForRESTAPI",
        "MailboxNotSupportedForRESTAPI",
        "ResourceNotFound"
    ]

    /// Decides how to handle a Graph HTTP response: proceed, refresh the token, defer, or throw.
    static func classify(
        _ response: MicrosoftGraphResponse,
        retrying: Bool,
        rateLimitRetries: Int
    ) -> MicrosoftGraphHTTPDecision {
        let url = response.url
        let calendarID = response.calendarID
        let graphErrorCode = response.graphErrorCode
        switch response.statusCode {
        case 200...299:
            return .proceed
        case 401:
            return retrying ? .clearAuthAndThrowAuthRequired : .retryWithForcedTokenRefresh
        case 403:
            // Graph 403 is a permission decision, not a stale token; a token
            // refresh would not change it.
            return .throwError(.forbiddenCalendar(calendarID: calendarID, url: url))
        case 404:
            if calendarID != nil {
                return .throwError(.forbiddenCalendar(calendarID: calendarID, url: url))
            }
            if let graphErrorCode, mailboxUnavailableCodes.contains(graphErrorCode) {
                return .throwError(.mailboxNotAvailable(url))
            }
            return .throwError(.httpStatus(response.statusCode, code: graphErrorCode, url: url))
        case 429, 503:
            let parsed = retryAfterInterval(header: response.retryAfterHeader)
            if rateLimitRetries < 1 {
                let delay = parsed ?? defaultRetryAfter
                if delay <= maxInlineRetryDelay {
                    return .retryAfterDelay(delay)
                }
            }
            return .throwError(.rateLimited(retryAfter: parsed ?? defaultRetryAfter, url: url))
        default:
            return .throwError(.httpStatus(response.statusCode, code: graphErrorCode, url: url))
        }
    }

    /// Parses a `Retry-After` header (delta-seconds or an HTTP-date). Returns
    /// nil when the header is absent or unparseable so the caller can apply its
    /// own default.
    static func retryAfterInterval(header: String?, now: Date = Date()) -> TimeInterval? {
        guard let header else { return nil }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed) {
            return seconds > 0 ? seconds : nil
        }
        guard let date = httpDateFormatter.date(from: trimmed) else { return nil }
        let interval = date.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

enum MicrosoftGraphBatchPolicy {
    /// Same semantics as `GoogleCalendarBatchPolicy.finish`: individual
    /// inaccessible calendars are skipped, but if every calendar failed the
    /// first error is surfaced so the user sees why nothing loaded.
    static func finish<Event>(
        events: [Event],
        successfulCalendars: Int,
        forbiddenErrors: [Error]
    ) throws -> [Event] {
        if successfulCalendars == 0, let error = forbiddenErrors.first {
            throw error
        }
        return events
    }
}

// MARK: - Date parsing

/// Parses Graph `dateTimeTimeZone` values.
///
/// Graph emits `"2026-09-09T10:00:00.0000000"` (seven fractional digits, no
/// zone designator) with the zone in a sibling `timeZone` field. Because the
/// store requests `Prefer: outlook.timezone="UTC"` that field is normally
/// `"UTC"`, but IANA identifiers and explicit `Z`/offset suffixes are
/// accepted too.
enum MicrosoftGraphDateParser {
    // Literal pattern compiled once; a typo would fail every parser test, so
    // the force-try cannot reach users.
    private static let pattern = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?(Z|[+-]\d{2}:?\d{2})?$"#
    )
    /// Shared proleptic Gregorian calendar; `Calendar` is a value type and
    /// `date(from:)` honours the components' own time zone, so one instance
    /// serves every call without a `DateFormatter` per event.
    private static let gregorian = Calendar(identifier: .gregorian)
    // "UTC" is a fixed identifier present in every tz database, so this
    // cannot fail.
    private static let utc = TimeZone(identifier: "UTC")!

    /// Parses a Graph `dateTime` string (optionally with a sibling time-zone id) into a `Date`.
    static func dateTime(_ value: String, timeZoneID: String?) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = pattern.firstMatch(in: trimmed, range: range),
              let baseRange = Range(match.range(at: 1), in: trimmed) else {
            return nil
        }

        let fraction: TimeInterval
        if let fractionRange = Range(match.range(at: 2), in: trimmed) {
            fraction = TimeInterval("0." + trimmed[fractionRange]) ?? 0
        } else {
            fraction = 0
        }

        let timeZone: TimeZone
        if let suffixRange = Range(match.range(at: 3), in: trimmed) {
            guard let parsed = Self.timeZone(fromDesignator: String(trimmed[suffixRange])) else { return nil }
            timeZone = parsed
        } else {
            timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? utc
        }

        guard let components = dateComponents(fromBase: trimmed[baseRange], timeZone: timeZone),
              let base = gregorian.date(from: components) else {
            return nil
        }
        return base.addingTimeInterval(fraction)
    }

    /// Splits a regex-validated `yyyy-MM-ddTHH:mm:ss` string into components,
    /// rejecting out-of-range fields the way `DateFormatter` would.
    private static func dateComponents(fromBase base: Substring, timeZone: TimeZone) -> DateComponents? {
        let fields = base.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard fields.count == 6,
              (1...12).contains(fields[1]),
              (1...31).contains(fields[2]),
              (0...23).contains(fields[3]),
              (0...59).contains(fields[4]),
              (0...60).contains(fields[5]) else {
            return nil
        }
        var components = DateComponents()
        components.calendar = gregorian
        components.timeZone = timeZone
        components.year = fields[0]
        components.month = fields[1]
        components.day = fields[2]
        components.hour = fields[3]
        components.minute = fields[4]
        components.second = fields[5]
        // Reject dates the calendar would otherwise roll over (e.g. Feb 30).
        guard let date = gregorian.date(from: components) else { return nil }
        let roundTrip = gregorian.dateComponents(in: timeZone, from: date)
        guard roundTrip.month == fields[1], roundTrip.day == fields[2] else { return nil }
        return components
    }

    /// All-day events carry midnight boundaries in the requested zone. Only
    /// the calendar date is meaningful, so it is re-anchored to local
    /// midnight (matching how the Google provider treats `date` values).
    static func allDayLocalDate(_ value: String, calendar: Calendar = .current) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let fields = trimmed.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard fields.count == 3, (1...12).contains(fields[1]), (1...31).contains(fields[2]) else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = fields[0]
        components.month = fields[1]
        components.day = fields[2]
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// Parses a trailing `Z` or ±hh:mm designator into a `TimeZone`.
    private static func timeZone(fromDesignator designator: String) -> TimeZone? {
        if designator == "Z" {
            return TimeZone(identifier: "UTC")
        }
        let sign: Int = designator.hasPrefix("-") ? -1 : 1
        let digits = designator.dropFirst().replacingOccurrences(of: ":", with: "")
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2)) else {
            return nil
        }
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}

// MARK: - Field mapping

/// Provider-neutral event status used inside the hostless package.
/// The app target maps it onto `MBEventStatus`.
enum MicrosoftGraphEventStatusValue: Equatable {
    case confirmed
    case tentative
    case canceled
}

/// Provider-neutral attendee response used inside the hostless package.
/// The app target maps it onto `MBEventAttendeeStatus`.
enum MicrosoftGraphResponseValue: Equatable {
    case accepted
    case declined
    case tentative
    case pending
    case unknown
}

enum MicrosoftGraphEventMapping {
    /// Maps Graph `isCancelled`/`showAs` to a provider-neutral event status.
    static func status(isCancelled: Bool, showAs: String?) -> MicrosoftGraphEventStatusValue {
        if isCancelled {
            return .canceled
        }
        if showAs?.lowercased() == "tentative" {
            return .tentative
        }
        return .confirmed
    }

    /// Maps a Graph attendee `responseStatus.response` to a provider-neutral value.
    static func attendeeStatus(response: String?) -> MicrosoftGraphResponseValue {
        switch response?.lowercased() {
        case "accepted", "organizer":
            return .accepted
        case "declined":
            return .declined
        case "tentativelyaccepted":
            return .tentative
        case "notresponded", "none":
            // Graph reports the current user's own non-response as `none`
            // from the organizer's perspective; it is equivalent to
            // `notResponded`.
            return .pending
        default:
            return .unknown
        }
    }

    /// Whether a Graph attendee `type` marks the attendee optional.
    static func isOptional(attendeeType: String?) -> Bool {
        attendeeType?.lowercased() == "optional"
    }

    /// Picks the online-meeting join URL, preferring the structured `onlineMeeting.joinUrl`.
    static func conferenceURL(onlineMeetingJoinURL: String?, onlineMeetingURL: String?) -> URL? {
        for candidate in [onlineMeetingJoinURL, onlineMeetingURL] {
            if let candidate, !candidate.isEmpty, let url = URL(string: candidate) {
                return url
            }
        }
        return nil
    }

    /// Whether a Graph event belongs to a recurring series.
    static func isRecurrent(type: String?, seriesID: String?) -> Bool {
        if let seriesID, !seriesID.isEmpty {
            return true
        }
        switch type?.lowercased() {
        case "occurrence", "exception", "seriesmaster":
            return true
        default:
            return false
        }
    }

    /// Case-insensitive comparison of an attendee address to the signed-in user.
    static func isCurrentUser(address: String?, username: String?) -> Bool {
        guard let address, let username else { return false }
        return address.caseInsensitiveCompare(username) == .orderedSame
    }
}

// MARK: - Configuration

/// Resolved Entra app registration used by the Microsoft 365 provider.
///
/// The initial release always authenticates against MeetingBar's own app
/// registration (the `common` authority, so work, school, and personal
/// Microsoft accounts can sign in). Letting an organization substitute its own
/// registration is intentionally out of scope for now.
struct MicrosoftGraphConfiguration: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        /// Baked into the build via `MICROSOFT_CLIENT_ID` in Info.plist.
        case buildSetting
        /// No usable client ID (placeholder or empty).
        case missing
    }

    let clientID: String
    let authorityURL: URL
    let redirectURI: String
    let source: Source

    var isConfigured: Bool { source != .missing }

    var sourceLabel: String {
        switch source {
        case .buildSetting: return "build setting"
        case .missing: return "missing"
        }
    }
}

enum MicrosoftGraphConfigurationPolicy {
    static let buildClientIDKey = "MICROSOFT_CLIENT_ID"
    static let placeholderPrefix = "REPLACE_BY_"
    /// The `common` authority accepts work, school, and personal accounts.
    /// A literal, well-formed https URL: `URL(string:)` cannot return nil.
    static let authorityURL = URL(string: "https://login.microsoftonline.com/common")!

    /// Resolves the app's Entra client ID from the build setting. A placeholder
    /// or empty value yields `.missing` (onboarding shows a configuration
    /// error); a present-but-malformed value throws so the mistake is visible.
    static func resolve(
        buildClientID: String?,
        bundleID: String
    ) throws -> MicrosoftGraphConfiguration {
        let redirectURI = "msauth.\(bundleID)://auth"

        guard let buildClientID = normalized(buildClientID),
              !buildClientID.hasPrefix(placeholderPrefix) else {
            return MicrosoftGraphConfiguration(
                clientID: "",
                authorityURL: authorityURL,
                redirectURI: redirectURI,
                source: .missing
            )
        }
        guard isValidClientID(buildClientID) else {
            throw MicrosoftAuthError.configurationInvalid(
                reason: "\(buildClientIDKey) build setting is not a GUID"
            )
        }
        return MicrosoftGraphConfiguration(
            clientID: buildClientID,
            authorityURL: authorityURL,
            redirectURI: redirectURI,
            source: .buildSetting
        )
    }

    /// Whether a string is a well-formed client-ID GUID (8-4-4-4-12 hex).
    static func isValidClientID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// Trims whitespace and returns nil for an empty result.
    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

// MARK: - URL building

enum MicrosoftGraphURLBuilder {
    static let host = "graph.microsoft.com"
    static let basePath = "/v1.0"
    static let calendarSelectFields = "id,name,hexColor,isDefaultCalendar,owner,canShare"
    /// Only the fields `MSGraphParser.event` reads. Without `$select` Graph
    /// returns the full event resource (recurrence, categories, reminders,
    /// full HTML body…), several KB per event that is parsed and discarded.
    static let eventSelectFields = [
        "id", "subject", "bodyPreview", "body", "start", "end", "isAllDay", "isCancelled", "showAs",
        "location", "onlineMeeting", "onlineMeetingUrl", "webLink", "lastModifiedDateTime",
        "organizer", "attendees", "responseStatus", "type", "seriesMasterId"
    ].joined(separator: ",")
    static let defaultPageSize = 250
    /// `ISO8601DateFormatter` is documented thread-safe and this instance is
    /// never mutated after creation, so it is shared instead of rebuilt per
    /// calendar per sync. Unlike `DateFormatter` it is not marked Sendable
    /// by Foundation, hence the explicit opt-out.
    nonisolated(unsafe) private static let utcTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Builds the `/me/calendars` request URL.
    static func calendarsURL(top: Int = 100) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "\(basePath)/me/calendars"
        components.queryItems = [
            .init(name: "$select", value: calendarSelectFields),
            .init(name: "$top", value: String(top))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// Characters that may appear unescaped inside a single path segment.
    /// Graph calendar IDs are long base64-style strings that can contain
    /// `=`, `+`, and `/`; `URLComponents.path` would leave `/` alone (it is
    /// a segment separator), so the ID is percent-encoded explicitly and
    /// assigned through `percentEncodedPath`.
    private static let pathSegmentAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))

    /// Builds a calendar's `calendarView` URL for the range, percent-encoding the id exactly once.
    static func calendarViewURL(
        calendarID: String,
        start: Date,
        end: Date,
        top: Int = defaultPageSize
    ) throws -> URL {
        let formatter = utcTimestampFormatter

        guard let escapedID = calendarID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed),
              !escapedID.isEmpty else {
            throw URLError(.badURL)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = "\(basePath)/me/calendars/\(escapedID)/calendarView"
        components.queryItems = [
            .init(name: "startDateTime", value: formatter.string(from: start)),
            .init(name: "endDateTime", value: formatter.string(from: end)),
            .init(name: "$select", value: eventSelectFields),
            .init(name: "$orderby", value: "start/dateTime"),
            .init(name: "$top", value: String(top))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// Extracts the pagination link, but only if it stays on Graph over HTTPS.
    /// The link comes from the response body, so a foreign or non-HTTPS host is
    /// rejected before the caller can send the bearer token to it.
    static func nextLink(from root: [String: Any]) -> URL? {
        guard let link = root["@odata.nextLink"] as? String,
              let url = URL(string: link),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host else {
            return nil
        }
        return url
    }
}
