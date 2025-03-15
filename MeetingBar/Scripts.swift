//
//  Scripts.swift
//  MeetingBar
//
//  Created by Jens Goldhammer on 17.01.21.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//
import Carbon
import Foundation

enum ScriptType: String, Codable, CaseIterable {
    /// supported script type when a meeting will start
    case meetingStart
    /// not supported yet to execute apple scripts for meeting end
    case meetingEnd
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
 * 7. parameter - recurrent event (bool) - true if it is part of an recurrent event, false for single event
 * 8. parameter - attendee count (int32) - number of attendees- 0 for events without attendees
 * 9. parameter - meeting url (string) - the url to the meeting found in notes, url or location - only one meeting url is supported - if no meeting url is set, the value will be "EMPTY"
 * 10. parameter - meeting service (string), e.g teams or zoom- if no meeting is found, the meeting service value is "EMPTY"
 * 11. parameter - meeting notes (string)- if no notes are set, value "EMPTY" will be used
 * 12. parameter - calendar name (string) - the name of the calendar this event belongs to
 * 13. parameter - calendar source (string) - the source/account of the calendar (e.g., iCloud, Gmail)
 */
func createAppleScriptParametersForEvent(event: MBEvent) -> NSAppleEventDescriptor {
    let parameters = NSAppleEventDescriptor.list()
    parameters.insert(NSAppleEventDescriptor(string: event.ID), at: 0)
    parameters.insert(NSAppleEventDescriptor(string: event.title), at: 0)
    parameters.insert(NSAppleEventDescriptor(boolean: event.isAllDay), at: 0)
    parameters.insert(NSAppleEventDescriptor(date: event.startDate), at: 0)
    parameters.insert(NSAppleEventDescriptor(date: event.endDate), at: 0)
    parameters.insert(NSAppleEventDescriptor(string: event.location ?? "EMPTY"), at: 0)
    parameters.insert(NSAppleEventDescriptor(boolean: event.recurrent), at: 0)
    parameters.insert(NSAppleEventDescriptor(int32: Int32(event.attendees.count)), at: 0)

    if let meetingLink = event.meetingLink {
        parameters.insert(NSAppleEventDescriptor(string: meetingLink.url.absoluteString), at: 0)
        parameters.insert(NSAppleEventDescriptor(string: meetingLink.service!.rawValue), at: 0)
    } else {
        parameters.insert(NSAppleEventDescriptor(string: "EMPTY"), at: 0)
        parameters.insert(NSAppleEventDescriptor(string: "EMPTY"), at: 0)
    }

    parameters.insert(NSAppleEventDescriptor(string: event.notes ?? "EMPTY"), at: 0)

    // Add calendar information
    parameters.insert(NSAppleEventDescriptor(string: event.calendar.title), at: 0)
    parameters.insert(NSAppleEventDescriptor(string: event.calendar.source), at: 0)

    return parameters
}

// runs the predefined script with parameters.
func runMeetingStartsScript(event: MBEvent, type: ScriptType) {
    let parameters = createAppleScriptParametersForEvent(event: event)

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

    let url = scriptPath.appendingPathComponent("eventStartScript.scpt")

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
        displayAlert(title: "Apple Script file not found", text: "Apple script could not be executed. Please check that your script eventStartScript.scpt exists in \(scriptPath.path).")
    }
}

/**
 * runs the apple script with a sample event for enduser testing from the preferences dialog.
 * This method will create an in memory event and use the parameter to execute the apple script.
 */
func runAppleScriptForNextEvent(events: [MBEvent]) {
    if let nextEvent = getNextEvent(events: events) {
        runMeetingStartsScript(event: nextEvent, type: .meetingStart)
    } else {
        sendNotification("next_meeting_empty_title".loco(), "next_meeting_empty_message".loco())
    }
}
