//
//  Scripts.swift
//  MeetingBar
//
//  Created by Jens Goldhammer on 17.01.21.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
import Carbon
import Defaults
import EventKit
import Foundation

class Scripts: NSObject {
    var eventStore: EKEventStore

    override
    init() {
        eventStore = initEventStore()
    }

    /**
     * the kind of apple script to trigger
     */
    enum ScriptType: String, Codable, CaseIterable {
        /**
         * supported script type when a meeting will start
         */
        case meetingStart
        /**
         * not supported yet to execute apple scripts for meeting end
         */
        case meetingEnd
    }

    /**
    * we will schedule a common task to check if we have to execute the apple script for event starts..
    * -  a new meeting is started within the timeframe of the notification timebox, but not later as the beginning of the meeting.
    * - All day events will be reported the first time when the current time is within the timeframe of the allday event (which can be several days).
    */
    func scheduleRunScriptForMeetingStart() {
        let timer = Timer(timeInterval: 60 * 1, target: self, selector: #selector(runScriptsForMeetingStart), userInfo: nil, repeats: true)
        RunLoop.current.add(timer, forMode: .common)
    }

    /**
     * cleanup the passed events from the
     */
    private func cleanupPassedEvents() {
        let eventCleanupCandidates = Defaults[.processedEvents]
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
     * We will store the already executed events in the userdefaults as event array. The event contains the unique id and the last modified date of the event.
     * If the last modified date has changed, e.g. to shift the appointment to another time, we will execute the apple script again
     */
    @objc
    private func runScriptsForMeetingStart() {
        cleanupPassedEvents()

        // only run if the user has activated it.
        if !Defaults[.runAutomaticEventScript] {
            return
        }

        NSLog("Firing reccuring runscriptfornextmeeting")

        if let nextEvent = nextEvent(eventStore: eventStore) {
            let now = Date()

            let notificationTime = Double(Defaults[.joinEventNotificationTime].rawValue)
            let timeInterval = nextEvent.startDate.timeIntervalSince(now)
            let scriptNonAlldayCandidate = timeInterval > 0 && timeInterval < notificationTime

            let startEndRange = nextEvent.startDate ... nextEvent.endDate
            let scriptAllDayCandidate = nextEvent.isAllDay && startEndRange.contains(now)

            if scriptNonAlldayCandidate || scriptAllDayCandidate {
                var events = Defaults[.processedEvents]
                let matchedEvent = events.firstIndex { $0.id == nextEvent.eventIdentifier }

                // was a script for the event identified by id already scheduled?
                var alreadyExecuted = matchedEvent != nil

                // if a script was executed already for the event, but the start date is different, we will remove the the current event from the scheduled events, so that we can run the script again -> this is an edge case when the event was already notified for, but scheduled for a later time.
                if alreadyExecuted, events[matchedEvent!].lastModifiedDate != nextEvent.lastModifiedDate {
                    events.remove(at: matchedEvent!)
                    alreadyExecuted = false
                }

                if !alreadyExecuted {
                    runMeetingStartsScript(event: nextEvent, type: ScriptType.meetingStart)

                    // append the new event to already executed events
                    events.append(Event(id: nextEvent.eventIdentifier,
                                        lastModifiedDate: nextEvent.lastModifiedDate!, eventEndDate: nextEvent.endDate))

                    // save the executed events again
                    Defaults[.processedEvents] = events
                }
            }
        }
    }

    /**
     * create the parameters for the apple event which can be used in the apple script.
     *
     * 1. parameter - event identifier (string) - unique identifier from apples eventkit implementation
     * 2. parameter - title (string) - the title of the event (event title can be null, although it makes no sense!)
     * 3. parameter - allday event or not (bool) - true for allday events, false for non allday events
     * 4. parameter - start date of the event (date)
     * 5 .parameter - end date of the event (date)
     * 6. parameter - location (string) - if no location is set, the value will be "EMPTY"
     * 7. parameter - repeating event (bool) - true if it is part of an repeating event, false for single event
     * 8. parameter - attendee count (int32) - number of attendees- 0 for events without attendees
     * 9. parameter - meeting url (string) - the url to the meeting found in notes, url or location - only one meeting url is supported - if no meeting url is set, the value will be "EMPTY"
     * 10. parameter - meeting service (string), e.g teams or zoom- if no meeting is found, the meeting service value is "EMPTY"
     * 11. parameter - meeting notes (string)- if no notes are set, value "EMPTY" will be used
     */
    func createParameters(event: EKEvent) -> NSAppleEventDescriptor {
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(NSAppleEventDescriptor(string: event.eventIdentifier), at: 0)
        parameters.insert(NSAppleEventDescriptor(string: event.title ?? "EMPTY"), at: 0)
        parameters.insert(NSAppleEventDescriptor(boolean: event.isAllDay), at: 0)
        parameters.insert(NSAppleEventDescriptor(date: event.startDate), at: 0)
        parameters.insert(NSAppleEventDescriptor(date: event.endDate), at: 0)
        parameters.insert(NSAppleEventDescriptor(string: event.location ?? "EMPTY"), at: 0)
        parameters.insert(NSAppleEventDescriptor(boolean: event.hasRecurrenceRules), at: 0)
        parameters.insert(NSAppleEventDescriptor(int32: Int32(event.attendees?.count ?? 0)), at: 0)

        if let meetingLink = getMeetingLink(event) {
            parameters.insert(NSAppleEventDescriptor(string: meetingLink.url.absoluteString), at: 0)
            parameters.insert(NSAppleEventDescriptor(string: meetingLink.service!.rawValue), at: 0)
        } else {
            parameters.insert(NSAppleEventDescriptor(string: "EMPTY"), at: 0)
            parameters.insert(NSAppleEventDescriptor(string: "EMPTY"), at: 0)
        }

        parameters.insert(NSAppleEventDescriptor(string: event.notes ?? "EMPTY"), at: 0)

        NSLog("... with parameters: \(parameters)")
        return parameters
    }

    /*
     * runs the predefined script with parameters.
     *
     */
    func runMeetingStartsScript(event: EKEvent, type: ScriptType) {
        NSLog("Run apple script for event \(String(describing: event.eventIdentifier))")

        let parameters = createParameters(event: event)

        let appleEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        appleEvent.setDescriptor(NSAppleEventDescriptor(string: type.rawValue), forKeyword: AEKeyword(keyASSubroutineName))
        appleEvent.setDescriptor(parameters, forKeyword: AEKeyword(keyDirectObject))

        let scriptPath = try! FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)

        NSLog("... in scriptPath: \(String(describing: scriptPath.absoluteString))")

        let url = scriptPath.appendingPathComponent("meetingStartScript.scpt")

        NSLog("... using script: \(String(describing: url.absoluteString))")

        if FileManager.default.fileExists(atPath: url.path) {
            let appleScript = try! NSUserAppleScriptTask(url: url)
            appleScript.execute(withAppleEvent: appleEvent) { _, error in
                if let error = error {
                    DispatchQueue.main.async {
                        displayAlert(title: "Apple Script execution failed", text: "Following error occured while executing the script \(scriptPath.path): \n \(error)")
                    }
                }
            }
        } else {
            displayAlert(title: "Apple Script file not found", text: "Apple script could not be executed. Please check that your script meetingStartScript.scpt exists in \(scriptPath.path).")
        }
    }

    /**
     * runs the apple script with a sample event for enduser testing from the preferences dialog.
     * This method will create an in memory event and use the parameter to execute the apple script.
     */
    public func runAppleScriptForSampleEvent() {
        let sampleEvent = EKEvent()
        sampleEvent.title = "Sample meeting title"
        sampleEvent.isAllDay = false
        sampleEvent.startDate = Date() + 5 * 60
        sampleEvent.endDate = sampleEvent.startDate + 60 * 60
        sampleEvent.url = URL(string: "https://teams.microsoft.com/l/meetup-join/sampleLinkNotWorking")
        sampleEvent.location = "Onlinemeeting"
        sampleEvent.notes = "Don't forget to bring the meeting memos"

        var attendees = [EKParticipant]()
        if let attendee = createParticipant(email: "testing@gmail.com") {
            attendees.append(attendee)
        }
        sampleEvent.setValue(attendees, forKey: "attendees")
        runMeetingStartsScript(event: sampleEvent, type: .meetingStart)
    }

    private func createParticipant(email: String) -> EKParticipant? {
        let clazz: AnyClass? = NSClassFromString("EKAttendee")
        if let type = clazz as? NSObject.Type {
            let attendee = type.init()
            attendee.setValue(email, forKey: "emailAddress")
            return attendee as? EKParticipant
        }
        return nil
    }
}
