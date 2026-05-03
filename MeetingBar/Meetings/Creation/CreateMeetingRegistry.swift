//
//  CreateMeetingRegistry.swift
//  MeetingBar
//
//  Maps each CreateMeetingServices case to the URL and MeetingServices context
//  needed to open a new meeting. The custom-URL case is handled in createMeeting()
//  because it requires runtime validation.
//
//  Phase 3 PR 5: createMeeting() delegates to this registry.
//

import Foundation

/// The URL and provider context required to create a new meeting.
struct CreateMeetingDescriptor {
    let url: URL
    let meetingService: MeetingServices?
}

enum CreateMeetingRegistry {
    /// Returns the descriptor for a built-in create-meeting service, or nil for
    /// the `.url` case (which requires runtime input).
    static func descriptor(for service: CreateMeetingServices) -> CreateMeetingDescriptor? {
        entries[service]
    }

    private static let entries: [CreateMeetingServices: CreateMeetingDescriptor] = makeEntries()

    private static func makeEntries() -> [CreateMeetingServices: CreateMeetingDescriptor] {
        var map = [CreateMeetingServices: CreateMeetingDescriptor]()
        map[.meet] = CreateMeetingDescriptor(
            url: URL(string: "https://meet.google.com/new")!, meetingService: MeetingServices.meet)
        map[.zoom] = CreateMeetingDescriptor(
            url: URL(string: "https://zoom.us/start?confno=123456789&zc=0")!,
            meetingService: MeetingServices.zoom)
        map[.teams] = CreateMeetingDescriptor(
            url: URL(string: "https://teams.microsoft.com/l/meeting/new?subject=")!,
            meetingService: MeetingServices.teams)
        map[.jam] = CreateMeetingDescriptor(
            url: URL(string: "https://jam.systems/new")!, meetingService: MeetingServices.jam)
        map[.coscreen] = CreateMeetingDescriptor(
            url: URL(string: "https://cs.new")!, meetingService: MeetingServices.coscreen)
        map[.gcalendar] = CreateMeetingDescriptor(
            url: URL(string: "https://calendar.google.com/calendar/u/0/r/eventedit")!,
            meetingService: nil)
        map[.outlook_live] = CreateMeetingDescriptor(
            url: URL(string: "https://outlook.live.com/calendar/0/action/compose")!,
            meetingService: nil)
        map[.outlook_office365] = CreateMeetingDescriptor(
            url: URL(string: "https://outlook.office365.com/calendar/0/action/compose")!,
            meetingService: nil)
        return map
    }
}
