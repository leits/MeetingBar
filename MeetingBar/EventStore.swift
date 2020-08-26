//
//  EventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit
import Defaults

extension EKEventStore {
    func accessCheck(_ completion: @escaping (AuthResult) -> Void) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .authorized:
            NSLog("EventStore: already authorized")
            completion(.success(true))
        case .denied, .notDetermined:
            NSLog("EventStore: request access")
            self.requestAccess(
                to: .event,
                completion:
                { (granted: Bool, error: Error?) -> Void in
                    if error != nil {
                        completion(.failure(error!))
                    } else {
                        completion(.success(granted))
                    }
                })
        default:
            completion(.failure(NSError(domain: "Unknown authorization status", code: 0)))
        }
    }

    func getCalendars(titles: [String] = [], ids: [String] = []) -> [EKCalendar] {
        var matchedCalendars: [EKCalendar] = []

        let allCalendars = self.calendars(for: .event)
        for calendar in allCalendars {
            if titles.contains(calendar.title) || ids.contains(calendar.calendarIdentifier) {
                print("\(calendar.title): \(calendar.calendarIdentifier)")
                matchedCalendars.append(calendar)
            }
        }
        return matchedCalendars
    }

    func loadEventsForDate(calendars: [EKCalendar], date: Date) -> [EKEvent] {
        let dayMidnight = Calendar.current.startOfDay(for: date)
        let nextDayMidnight = Calendar.current.date(byAdding: .day, value: 1, to: dayMidnight)!

        let predicate = self.predicateForEvents(withStart: dayMidnight, end: nextDayMidnight, calendars: calendars)
        let calendarEvents = self.events(matching: predicate)

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateString = df.string(from: date)
        NSLog("Loaded events for date \(dateString) from calendars \(calendars.map { $0.title })")
        return calendarEvents
    }

    func getNextEvent(calendars: [EKCalendar]) -> EKEvent? {
        var nextEvent: EKEvent?

        let now = Date()
        let startPeriod = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        var endPeriod: Date

        let todayMidnight = Calendar.current.startOfDay(for: now)
        switch Defaults[.showEventsForPeriod] {
        case .today:
            endPeriod = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!
        case .today_n_tomorrow:
            endPeriod = Calendar.current.date(byAdding: .day, value: 2, to: todayMidnight)!
        }

        let predicate = self.predicateForEvents(withStart: startPeriod, end: endPeriod, calendars: calendars)
        let nextEvents = self.events(matching: predicate)
        // If the current event is still going on,
        // but the next event is closer than 10 minutes later
        // then show the next event
        for event in nextEvents {
            // Skip event if declined
            if event.isAllDay { continue }
            if Defaults[.ignoredCalendarItemIDs].contains(event.calendarItemIdentifier) { continue }
            if let status = getEventStatus(event) {
                if status == .declined { continue }
            }
            if event.status == .canceled {
                continue
            } else {
                if nextEvent == nil {
                    nextEvent = event
                    continue
                } else {
                    let soon = now.addingTimeInterval(600) // 10 min from now
                    if event.startDate < soon {
                        nextEvent = event
                    } else {
                        break
                    }
                }
            }
        }
        return nextEvent
    }
}
