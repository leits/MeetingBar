//
//  MeetingSummaryView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

struct MeetingSummaryPresentation: Equatable {
    let sectionTitle: String
    let eventTitle: String
    let metadata: [String]
    let meetingService: MeetingServices?
    /// Relative time until the meeting starts (e.g. "in 25m"); nil for
    /// running meetings, where the section title already says enough.
    var countdown: String?

    var metadataText: String {
        metadata.joined(separator: " • ")
    }

    var sectionTitleText: String {
        guard let countdown, !countdown.isEmpty else { return sectionTitle }
        return "\(sectionTitle) • \(countdown)"
    }
}

struct MeetingSummaryView: View {
    let presentation: MeetingSummaryPresentation
    let providerIcon: NSImage
    var onJoin: (() -> Void)?

    @State private var isHovered = false

    static let preferredWidth: CGFloat = 380
    static let preferredHeight: CGFloat = 66

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.sectionTitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 7) {
                    Image(nsImage: providerIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text(presentation.eventTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text(presentation.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if onJoin != nil {
                Spacer(minLength: 8)
                Text("notifications_meetingbar_join_event_action".loco())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentColor))
                    .opacity(isHovered ? 1.0 : 0.9)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(
            maxWidth: .infinity,
            minHeight: Self.preferredHeight,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered && onJoin != nil ? Color.primary.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            guard onJoin != nil else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture { onJoin?() }
    }
}

#Preview {
    MeetingSummaryView(
        presentation: MeetingSummaryPresentation(
            sectionTitle: "Next meeting",
            eventTitle: "Weekly product sync",
            metadata: ["10:00 – 10:30", "Zoom", "Work"],
            meetingService: .zoom,
            countdown: "in 25m"
        ),
        providerIcon: getIconForMeetingService(.zoom),
        onJoin: {}
    )
}
