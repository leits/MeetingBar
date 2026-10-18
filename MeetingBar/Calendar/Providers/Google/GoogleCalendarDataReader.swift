import AppKit
import Foundation

/// Google Calendar's authenticated HTTP results -> calendar/event domain data.
/// GCEventStore retains AppAuth, Keychain, and the real network transport.
@MainActor
struct GoogleCalendarDataReader {
    typealias FetchJSON = @MainActor (_ url: URL, _ calendarID: String?) async throws -> [[String: Any]]

    let userEmail: String?
    let fetchJSON: FetchJSON

    func fetchCalendars() async throws -> [MBCalendar] {
        let url = URL(
            string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true"
        )!
        let items = try await fetchJSON(url, nil)

        return items.compactMap { item -> MBCalendar? in
            guard let title = item["summary"] as? String,
                  let calendarID = item["id"] as? String,
                  let backgroundColor = item["backgroundColor"] as? String else { return nil }

            return MBCalendar(
                title: title,
                id: calendarID,
                source: userEmail,
                email: userEmail,
                color: hexStringToUIColor(hex: backgroundColor)
            )
        }
    }

    func fetchEvents(for calendars: [MBCalendar], from: Date, to: Date) async throws -> [MBEvent] {
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: from)
        let timeMax = formatter.string(from: to)
        var events: [MBEvent] = []
        var forbiddenErrors: [Error] = []
        var successfulCalendars = 0

        for calendar in calendars {
            do {
                let url = try GCEventStore.eventsURL(
                    calendarID: calendar.id,
                    timeMin: timeMin,
                    timeMax: timeMax
                )
                let items = try await fetchJSON(url, calendar.id)
                events.append(contentsOf: items.compactMap {
                    GCEventStore.GCParser.event(from: $0, calendar: calendar)
                })
                successfulCalendars += 1
            } catch let error as GoogleCalendarError {
                switch error {
                case .forbiddenCalendar:
                    MeetingBarLogger.calendar.warning(
                        "Skipping inaccessible Google calendar \(calendar.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                    )
                    forbiddenErrors.append(error)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }

        return try GoogleCalendarBatchPolicy.finish(
            events: events.deduplicatedPreferringResolvedAttendee(),
            successfulCalendars: successfulCalendars,
            forbiddenErrors: forbiddenErrors
        )
    }
}
