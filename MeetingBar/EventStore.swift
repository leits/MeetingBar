//
//  EventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit

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

    func getCalendars(_ titles: [String]) -> [EKCalendar] {
        var selectedCalendars: [EKCalendar] = []

        let allCalendars = self.calendars(for: .event)
        for calendar in allCalendars {
            if titles.contains(calendar.title) {
                selectedCalendars.append(calendar)
            }
        }
        return selectedCalendars
    }

    func loadTodayEvents(calendars: [EKCalendar]) -> [EKEvent] {
        let todayMidnight = Calendar.current.startOfDay(for: Date())
        let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

        let predicate = self.predicateForEvents(withStart: todayMidnight, end: tomorrowMidnight, calendars: calendars)
        let calendarEvents = self.events(matching: predicate)

        NSLog("Calendars \(calendars.map { $0.title }) loaded")
        return calendarEvents
    }

    func getNextEvent(calendars: [EKCalendar]) -> EKEvent? {
        var nextEvent: EKEvent?

        let now = Date()
        let nextMinute = Calendar.current.date(byAdding: .minute, value: 1, to: now)!
        let todayMidnight = Calendar.current.startOfDay(for: now)
        let tomorrowMidnight = Calendar.current.date(byAdding: .day, value: 1, to: todayMidnight)!

        let predicate = self.predicateForEvents(withStart: nextMinute, end: tomorrowMidnight, calendars: calendars)
        let nextEvents = self.events(matching: predicate)
        // If the current event is still going on,
        // but the next event is closer than 10 minutes later
        // then show the next event
        for event in nextEvents {
            // Skip event if declined
            if event.isAllDay { continue }
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
