//
//  AutomaticJoinEvent.swift
//  MeetingBar
//
//  Created by Jens Goldhammer  on 22.03.22.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import Defaults
import Foundation

class ActionsOnEventStart: NSObject {
    var app: AppDelegate
    var timer: Timer?

    init(_ appDelegate: AppDelegate) {
        app = appDelegate
    }

    func startWatching() {
        timer = Timer(timeInterval: 10, target: self, selector: #selector(checkNextEvent), userInfo: nil, repeats: true)
        RunLoop.current.add(timer!, forMode: .common)
    }

    /**
     * we will schedule a common task to check if we have to execute the actions for event starts..
     * -  a new meeting is started within the timeframe of the notification timebox, but not later as the beginning of the meeting.
     * - All day events will be reported the first time when the current time is within the timeframe of the allday event (which can be several days).
     */
    @objc
    private func checkNextEvent() {
        // Cleanup Passed Events
        Defaults[.processedEventsForAutoJoin] = Defaults[.processedEventsForAutoJoin].filter { $0.eventEndDate.timeIntervalSinceNow > 0 }
        Defaults[.processedEventsForRunScriptOnEventStart] = Defaults[.processedEventsForRunScriptOnEventStart].filter { $0.eventEndDate.timeIntervalSinceNow > 0 }

        // Only run if the user has activated it.
        let autoJoinActionActive = Defaults[.automaticEventJoin]
        let runEventStartScriptActionActive = (Defaults[.runEventStartScript] && Defaults[.joinEventScriptLocation] != nil)

        if !autoJoinActionActive, !runEventStartScriptActionActive {
            return
        }
        //

        if let nextEvent = getNextEvent(events: app.statusBarItem.events) {
            let now = Date()

            let startEndRange = nextEvent.startDate ... nextEvent.endDate

            let timeInterval = nextEvent.startDate.timeIntervalSince(now)

            let allDayCandidate = nextEvent.isAllDay && startEndRange.contains(now)

            /*
             * -----------------------
             * MARK: Action: auto join event
             * ------------------------
             */
            let actionTimeForEventAutoJoin = Double(Defaults[.automaticEventJoinTime].rawValue)
            let nonAlldayCandidateForAutoJoin = (timeInterval > 0 && timeInterval < actionTimeForEventAutoJoin) || startEndRange.contains(now)

            if autoJoinActionActive && (nonAlldayCandidateForAutoJoin || allDayCandidate) {
                var events = Defaults[.processedEventsForAutoJoin]

                let matchedEvent = events.filter { $0.id == nextEvent.ID }.first

                // if a script was executed already for the event, but the start date is different, we will remove the the current event from the scheduled events, so that we can run the script again -> this is an edge case when the event was already notified for, but scheduled for a later time.
                if matchedEvent == nil || matchedEvent?.lastModifiedDate != nextEvent.lastModifiedDate {
                    if nextEvent.meetingLink != nil {
                        nextEvent.openMeeting()
                    }

                    // update the executed events
                    if matchedEvent != nil {
                        events = events.filter { $0.id != nextEvent.ID }
                    }
                    events.append(ProcessedEvent(id: nextEvent.ID, lastModifiedDate: nextEvent.lastModifiedDate, eventEndDate: nextEvent.endDate))
                    Defaults[.processedEventsForAutoJoin] = events
                }
            }

            /*
             * -----------------------
             * MARK: Action: run start event script
             * ------------------------
             */
            let actionTimeForScriptOnEventStart = Double(Defaults[.eventStartScriptTime].rawValue)
            let nonAlldayCandidateForRunStartEventScript = (timeInterval > 0 && timeInterval < actionTimeForScriptOnEventStart) || startEndRange.contains(now)

            if runEventStartScriptActionActive, nonAlldayCandidateForRunStartEventScript || allDayCandidate {
                var events = Defaults[.processedEventsForRunScriptOnEventStart]

                let matchedEvent = events.filter { $0.id == nextEvent.ID }.first

                // if a script was executed already for the event, but the start date is different, we will remove the the current event from the scheduled events, so that we can run the script again -> this is an edge case when the event was already notified for, but scheduled for a later time.
                if matchedEvent == nil || matchedEvent?.lastModifiedDate != nextEvent.lastModifiedDate {
                    runMeetingStartsScript(event: nextEvent, type: ScriptType.meetingStart)

                    // update the executed events
                    if matchedEvent != nil {
                        events = events.filter { $0.id != nextEvent.ID }
                    }
                    events.append(ProcessedEvent(id: nextEvent.ID, lastModifiedDate: nextEvent.lastModifiedDate, eventEndDate: nextEvent.endDate))
                    Defaults[.processedEventsForRunScriptOnEventStart] = events
                }
            }
        }
    }
}
