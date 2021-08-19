//
import Defaults
//  EventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 12.06.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import EventKit

extension EKEventStore {
    func getMatchedCalendars(titles: [String] = [], ids: [String] = []) -> [EKCalendar] {
        var matchedCalendars: [EKCalendar] = []

        let allCalendars = calendars(for: .event)
        for calendar in allCalendars {
            if titles.contains(calendar.title) || ids.contains(calendar.calendarIdentifier) {
                matchedCalendars.append(calendar)
            }
        }
        return matchedCalendars
    }

    func getAllCalendars() -> [String: [EKCalendar]] {
        let calendars = self.calendars(for: .event)
        return Dictionary(grouping: calendars) { $0.source.title }
    }

    func loadEventsForDate(calendars: [EKCalendar], date: Date) -> [EKEvent] {
        let dayMidnight = Calendar.current.startOfDay(for: date)
        let nextDayMidnight = Calendar.current.date(byAdding: .day, value: 1, to: dayMidnight)!

        let showAlldayEvents: Bool = Defaults[.allDayEvents] == AlldayEventsAppereance.show

        let predicate = predicateForEvents(withStart: dayMidnight, end: nextDayMidnight, calendars: calendars)
        let calendarEvents = events(matching: predicate).filter { ($0.isAllDay && showAlldayEvents) || Calendar.current.isDate($0.startDate, inSameDayAs: dayMidnight) }

        var filteredCalendarEvents = [EKEvent]()

        for calendarEvent in calendarEvents {
            var addEvent = false

            if calendarEvent.isAllDay {
                if Defaults[.allDayEvents] == AlldayEventsAppereance.show {
                    addEvent = true
                } else if Defaults[.allDayEvents] == AlldayEventsAppereance.show_with_meeting_link_only {
                    let result = getMeetingLink(calendarEvent)

                    if result?.url != nil {
                        addEvent = true
                    }
                }
            } else {
                if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_meeting_link {
                    let result = getMeetingLink(calendarEvent)

                    if result?.url != nil {
                        addEvent = true
                    }
                } else {
                    addEvent = true
                }
            }

            let status = getEventParticipantStatus(calendarEvent)
            if status == .pending, Defaults[.showPendingEvents] == .hide {
                addEvent = false
            }

            if addEvent {
                filteredCalendarEvents.append(calendarEvent)
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = I18N.instance.locale

        let dateString = formatter.string(from: date)
        NSLog("Loaded events for date \(dateString) from calendars \(calendars.map { $0.title })")

        return filteredCalendarEvents
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

        let predicate = predicateForEvents(withStart: startPeriod, end: endPeriod, calendars: calendars)
        var nextEvents = events(matching: predicate)

        // Filter out personal events, if not marked as 'active'
        if Defaults[.personalEventsAppereance] != .show_active {
            nextEvents = nextEvents.filter { $0.hasAttendees }
        }

        // If the current event is still going on,
        // but the next event is closer than 13 minutes later
        // then show the next event
        for event in nextEvents {
            if event.isAllDay && Defaults[.allDayEvents] == AlldayEventsAppereance.hide {
                continue
            } else {
                if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.show_inactive_without_meeting_link {
                    let meetingLink = getMeetingLink(event)
                    if meetingLink == nil {
                        continue
                    }
                } else if Defaults[.nonAllDayEvents] == NonAlldayEventsAppereance.hide_without_meeting_link {
                    let result = getMeetingLink(event)

                    if result?.url == nil {
                        continue
                    }
                }
            }

            if let status = getEventParticipantStatus(event) {
                if status == .declined { // Skip event if declined
                    continue
                }

                if status == .pending, Defaults[.showPendingEvents] == PendingEventsAppereance.hide || Defaults[.showPendingEvents] == PendingEventsAppereance.show_inactive {
                    continue
                }
            }

            if event.status == .canceled {
                continue
            } else {
                if nextEvent == nil {
                    nextEvent = event
                    continue
                } else {
                    let soon = now.addingTimeInterval(780) // 13 min from now
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
