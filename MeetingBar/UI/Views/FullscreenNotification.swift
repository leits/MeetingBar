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
    /// Weak: the window owns this view through its NSHostingView, so a strong
    /// back-reference kept every closed alert (and its backing store) alive.
    weak var window: NSWindow?

    @State private var isVisible = false

    private let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    private var calendarColor: Color { Color(event.calendar.color) }

    var body: some View {
        let presentation = FullscreenNotificationPresentation.make(for: event)

        ZStack {
            backdrop
            card(presentation: presentation)
                .scaleEffect(isVisible ? 1 : 0.94)
                .opacity(isVisible ? 1 : 0)
        }
        .colorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                isVisible = true
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            VisualEffect()
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [calendarColor.opacity(0.35), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }

    private func card(presentation: FullscreenNotificationPresentation) -> some View {
        VStack(spacing: 28) {
            calendarChip

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdownText(now: context.date))
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .monospacedDigit()
            }

            Text(event.title)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                detailRow(systemImage: "clock", text: getEventDateString(event))
                if let location = event.location, !location.isEmpty {
                    detailRow(systemImage: "mappin.and.ellipse", text: location)
                }
            }

            actionButtons(presentation: presentation)
                .padding(.top, 8)
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
        .frame(maxWidth: 680)
        .background(
            shape
                .fill(.ultraThinMaterial)
        )
        .overlay(
            shape
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
        .padding(40)
    }

    private var calendarChip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(calendarColor)
                .frame(width: 10, height: 10)
            Text(event.calendar.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(shape.fill(Color.white.opacity(0.1)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private func detailRow(systemImage: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.white.opacity(0.55))
            Text(text)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .font(.system(size: 16, weight: .regular))
    }

    private func actionButtons(presentation: FullscreenNotificationPresentation) -> some View {
        HStack(spacing: 16) {
            Button(action: dismiss) {
                buttonLabel(
                    title: "fullscreen_notification_dismiss_action".loco(),
                    shortcutHint: "esc"
                )
                .background(shape.fill(Color.white.opacity(0.12)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(FullscreenButtonStyle())
            .keyboardShortcut(.cancelAction)

            if presentation.actions.contains(.join) {
                Button(action: joinEvent) {
                    buttonLabel(
                        title: "notifications_meetingbar_join_event_action".loco(),
                        shortcutHint: "↩",
                        icon: getIconForMeetingService(event.meetingLink?.service)
                    )
                    .background(shape.fill(Color.accentColor))
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 16, y: 6)
                }
                .buttonStyle(FullscreenButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func buttonLabel(title: String, shortcutHint: String, icon: NSImage? = nil) -> some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(shortcutHint)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.18)))
                .opacity(0.8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 26)
        .frame(minWidth: 160, minHeight: 48)
        .contentShape(shape)
    }

    private func countdownText(now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = I18N.instance.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: event.startDate, relativeTo: now)
    }

    func dismiss() {
        window?.close()
    }

    func joinEvent() {
        MeetingOpener.open(event: event)
        window?.close()
    }
}

private struct FullscreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
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
