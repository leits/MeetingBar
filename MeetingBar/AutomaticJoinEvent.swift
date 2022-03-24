//
//  AutomaticJoinEvent.swift
//  MeetingBar
//
//  Created by Jens Goldhammer  on 22.03.22.
//  Copyright © 2022 Andrii Leitsius. All rights reserved.
//

import Foundation
import Carbon
import Defaults
import EventKit

class AutomaticJoinEvent: NSObject {
    var eventStore: EKEventStore

    override
    init() {
        eventStore = initEventStore()
    }

    /**
    * we will schedule a common task to check if we have to execute the apple script for event starts..
    * -  a new meeting is started within the timeframe of the notification timebox, but not later as the beginning of the meeting.
    * - All day events will be reported the first time when the current time is within the timeframe of the allday event (which can be several days).
    */
    func scheduleRunScriptForAutomaticMeetingJoin() {
        let timer = Timer(timeInterval: 10 * 1, target: self, selector: #selector(runScriptsForAutomaticMeetingJoin), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    /**
     *
     * automatically join meetings by
     */
    @objc
    private func runScriptsForAutomaticMeetingJoin() {
        // only run if the user has activated it.
        if !Defaults[.automaticEventJoin] {
            return
        }

        NSLog("Firing reccuring runScriptsForAutomaticMeetingJoin")

        if let nextEvent = nextEvent(eventStore:eventStore) {
            let now = Date()
            let notificationTime = Double(Defaults[.automaticEventJoinTime].rawValue)
            let timeInterval = nextEvent.startDate.timeIntervalSince(now)
            let scriptNonAlldayCandidate = timeInterval > 0 && timeInterval < notificationTime

            let startEndRange = nextEvent.startDate...nextEvent.endDate
            let scriptAllDayCandidate = nextEvent.isAllDay && startEndRange.contains(now)

            if scriptNonAlldayCandidate || scriptAllDayCandidate {
                var events = Defaults[.automaticJoinedEvents]
                
                let matchedEvent = events.firstIndex { $0.id == nextEvent.eventIdentifier }

                // was a script for the event identified by id already scheduled?
                var alreadyExecuted = matchedEvent != nil

                // if a script was executed already for the event, but the start date is different, we will remove the the current event from the scheduled events, so that we can run the script again -> this is an edge case when the event was already notified for, but scheduled for a later time.
                if  alreadyExecuted && events[matchedEvent!].lastModifiedDate != nextEvent.lastModifiedDate {
                    events.remove(at: matchedEvent!)
                    alreadyExecuted = false
                }

                if !alreadyExecuted {
                
                    openEvent(nextEvent)

                    // append the new event to already executed events
                    events.append(Event(id: nextEvent.eventIdentifier,
                                        lastModifiedDate: nextEvent.lastModifiedDate!))

                    // save the executed events again
                    Defaults[.automaticJoinedEvents] = events
                }
            }
        }
    }
    
}
