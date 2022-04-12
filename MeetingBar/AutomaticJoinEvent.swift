//
//  AutomaticJoinEvent.swift
//  MeetingBar
//
//  Created by Jens Goldhammer  on 22.03.22.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import Carbon
import Defaults
import EventKit
import Foundation

class AutomaticJoinEvent: NSObject {
    var app: AppDelegate

    init(_ appDelegate: AppDelegate) {
        app = appDelegate
    }

    /**
     * we will schedule a common task to check if we have to execute the apple script for event starts..
     * -  a new meeting is started within the timeframe of the notification timebox, but not later as the beginning of the meeting.
     * - All day events will be reported the first time when the current time is within the timeframe of the allday event (which can be several days).
     */
    func scheduleRunScriptForAutomaticMeetingJoin() {
        let timer = Timer(timeInterval: 30 * 1, target: self, selector: #selector(runScriptsForAutomaticMeetingJoin), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    /**
     * cleanup the passed events from the
     */
    private func cleanupPassedEvents() {
        let eventCleanupCandidates = Defaults[.automaticJoinedEvents]
        var cleanedEvents: [Event] = []

        for event in eventCleanupCandidates {
            if event.eventEndDate.timeIntervalSinceNow > 0 {
                cleanedEvents.append(event)
            }
        }

        Defaults[.automaticJoinedEvents] = cleanedEvents
    }

    /**
     *
     * automatically join meetings by open the event in the configured application
     */
    @objc
    private func runScriptsForAutomaticMeetingJoin() {
        cleanupPassedEvents()

        // only run if the user has activated it.
        if !Defaults[.automaticEventJoin] {
            return
        }

        NSLog("Firing reccuring runScriptsForAutomaticMeetingJoin")

        if let nextEvent = getNextEvent(events: app.statusBarItem.events) {
            let now = Date()
            let notificationTime = Double(Defaults[.automaticEventJoinTime].rawValue)

            let startEndRange = nextEvent.startDate ... nextEvent.endDate

            let timeInterval = nextEvent.startDate.timeIntervalSince(now)
            let scriptNonAlldayCandidate = (timeInterval > 0 && timeInterval < notificationTime) || startEndRange.contains(now)

            let scriptAllDayCandidate = nextEvent.isAllDay && startEndRange.contains(now)

            if scriptNonAlldayCandidate || scriptAllDayCandidate {
                var events = Defaults[.automaticJoinedEvents]

                let matchedEvent = events.firstIndex { $0.id == nextEvent.ID }

                // was a script for the event identified by id already scheduled?
                var alreadyExecuted = matchedEvent != nil

                // if a script was executed already for the event, but the start date is different, we will remove the the current event from the scheduled events, so that we can run the script again -> this is an edge case when the event was already notified for, but scheduled for a later time.
                if alreadyExecuted, events[matchedEvent!].lastModifiedDate != nextEvent.lastModifiedDate {
                    events.remove(at: matchedEvent!)
                    alreadyExecuted = false
                }

                if !alreadyExecuted {
                    nextEvent.openMeeting()

                    // append the new event to already executed events
                    events.append(Event(id: nextEvent.ID,
                                        lastModifiedDate: nextEvent.lastModifiedDate!,
                                        eventEndDate: nextEvent.endDate))

                    // save the executed events again
                    Defaults[.automaticJoinedEvents] = events
                }
            }
        }
    }
}
