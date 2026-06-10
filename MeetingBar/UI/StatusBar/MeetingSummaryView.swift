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

    var metadataText: String {
        metadata.joined(separator: " • ")
    }
}

struct MeetingSummaryView: View {
    let presentation: MeetingSummaryPresentation
    let providerIcon: NSImage
    var onJoin: (() -> Void)? = nil

    static let preferredWidth: CGFloat = 380
    static let preferredHeight: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.sectionTitle)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(
            width: Self.preferredWidth,
            height: Self.preferredHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard onJoin != nil else { return }
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
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
            meetingService: .zoom
        ),
        providerIcon: getIconForMeetingService(.zoom)
    )
}
