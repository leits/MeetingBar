//
//  AutoJoinScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 31.07.2023.
//  Copyright © 2023 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

struct AutoJoinScreen: View {
    var event: MBEvent
    var window: NSWindow?

    var body: some View {
        ZStack {
            Rectangle.semiOpaqueWindow()
            VStack {
                Text(event.title).font(.system(size: 40)).padding(.bottom, 2)
                Text(event.meetingLink?.service?.rawValue ?? "").font(.system(size: 16))
                VStack {
                    Text(getEventDateString(event)).padding(.bottom, 2)
                    if #available(macOS 11.0, *) {
                        Text(event.startDate, style: .relative).font(.system(size: 16))
                    }
                }.padding(15)
                HStack(spacing: 40) {
                    Button("Dismiss") {
                        self.window?.close()
                    }
                    Button("Join event") {
                        self.event.openMeeting()
                        self.window?.close()
                    }.background(Color.accentColor.opacity(1))
                }
            }
        }
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public extension View {
    static func semiOpaqueWindow() -> some View {
        if #available(macOS 11.0, *) {
            return VisualEffect().ignoresSafeArea()
        } else {
            return VisualEffect()
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

func getEventDateString(_ event: MBEvent) -> String {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: event.startDate, to: event.endDate)
}

func generateEvent() -> MBEvent {
    let calendar = MBCalendar(title: "Fake calendar", ID: "fake_cal", source: nil, email: nil, color: .black)

    let event = MBEvent(
        ID: "test_event",
        lastModifiedDate: nil,
        title: "Test event",
        status: .confirmed,
        notes: nil,
        location: nil,
        url: URL(string: "https://zoom.us/j/5551112222")!,
        organizer: nil,
        startDate: Calendar.current.date(byAdding: .minute, value: 3, to: Date())!,
        endDate: Calendar.current.date(byAdding: .minute, value: 33, to: Date())!,
        isAllDay: false,
        recurrent: false,
        calendar: calendar
    )
    return event
}

#Preview {
    AutoJoinScreen(event: generateEvent(), window: nil)
}
