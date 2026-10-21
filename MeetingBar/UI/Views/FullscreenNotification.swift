//
//  FullscreenNotification.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 31.07.2023.
//  Copyright © 2023 Andrii Leitsius. All rights reserved.
//

import Defaults
import SwiftUI

enum FullscreenNotificationAction: Equatable {
    case dismiss
    case join
}

struct FullscreenNotificationPresentation: Equatable {
    let actions: [FullscreenNotificationAction]

    static func make(for event: MBEvent) -> FullscreenNotificationPresentation {
        FullscreenNotificationPresentation(
            actions: event.meetingLink == nil ? [.dismiss] : [.dismiss, .join]
        )
    }
}

struct FullscreenNotification: View {
    var event: MBEvent
    /// Other meetings running at the same time. When non-empty the alert shows
    /// every meeting with its own Join button so the user can pick one.
    var overlappingEvents: [MBEvent] = []
    var window: NSWindow?

    var body: some View {
        ZStack {
            Rectangle.semiOpaqueWindow()
            if overlappingEvents.isEmpty {
                singleEvent
            } else {
                eventPicker
            }
        }
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var singleEvent: some View {
        VStack {
            eventHeader(event)
            HStack(spacing: 30) {
                dismissButton
                joinButton(for: event)
            }
        }
    }

    private var eventPicker: some View {
        let events = [event] + overlappingEvents

        return GeometryReader { geo in
            ScrollView {
                VStack(spacing: 20) {
                    Text("fullscreen_notification_overlapping_title".loco())
                        .font(.headline)
                        .foregroundColor(.secondary)
                    ForEach(events, id: \.id) { candidate in
                        HStack(spacing: 30) {
                            eventHeader(candidate, alignment: .leading)
                                .frame(width: 460, alignment: .leading)
                            ZStack { joinButton(for: candidate) }.frame(width: 160)
                        }
                    }
                    dismissButton
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
    }

    private func eventHeader(_ event: MBEvent, alignment: HorizontalAlignment = .center) -> some View {
        VStack(alignment: alignment) {
            HStack {
                Image(nsImage: getIconForMeetingService(event.meetingLink?.service))
                    .resizable().frame(width: 25, height: 25)
                Text(event.title).font(.title)
            }
            VStack(spacing: 10) {
                Text(getEventDateString(event))
            }.padding(.horizontal, alignment == .leading ? 0 : 15).padding(.vertical, 15)

            // display location of the event, very useful if you
            // have a lot of meetings in a building with a lot of meeting rooms
            if let location = event.location {
                VStack(spacing: 10) {
                    Text(location)
                }.padding(.horizontal, alignment == .leading ? 0 : 15).padding(.vertical, 15)
            }
        }
    }

    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("fullscreen_notification_dismiss_action".loco())
                .padding(.vertical, 5)
                .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func joinButton(for event: MBEvent) -> some View {
        if FullscreenNotificationPresentation.make(for: event).actions.contains(.join) {
            Button(action: { joinEvent(event) }) {
                Text("notifications_meetingbar_join_event_action".loco()).padding(
                    .vertical, 5
                ).padding(.horizontal, 25)
            }
            .background(Color.accentColor)
            .cornerRadius(5)
            .accessibilityLabel("\("notifications_meetingbar_join_event_action".loco()), \(event.title)")
        }
    }

    func dismiss() {
        window?.close()
    }

    func joinEvent(_ event: MBEvent) {
        MeetingOpener.open(event: event)
        window?.close()
    }
}

public extension View {
    static func semiOpaqueWindow() -> some View {
        VisualEffect()
            .ignoresSafeArea()
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}

#if DEBUG
#Preview {
    FullscreenNotification(event: generateFakeEvent(), window: nil)
}
#endif
