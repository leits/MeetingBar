//
//  StatusBarStackedTitleView.swift
//  MeetingBar
//

import AppKit
import SwiftUI

/// Two-line status bar content (title on top, time underneath) used by the
/// "show time under title" appearance.
///
/// Rendered through an `NSHostingView` rather than a two-line
/// `NSAttributedString`, because `NSStatusBarButton` is built for a single
/// line: packing two lines into an attributed title (with a tight
/// `lineHeightMultiple` and a negative `baselineOffset`) clips the glyphs and
/// ghosts badly on inactive displays. A SwiftUI stack lays the two lines out
/// cleanly and is dimmed uniformly by the system compositor on inactive
/// screens, matching the rest of the menu bar.
struct StatusBarStackedTitleView: View {
    let icon: NSImage?
    let title: String
    let time: String
    let style: StatusBarTitleStyle

    var body: some View {
        let content = HStack(spacing: 4) {
            if let icon {
                iconImage(icon)
                    .frame(width: 16, height: 16)
            }

            VStack(spacing: -2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .underline(style == .underlined)
                Text(time)
                    .font(.system(size: 9, weight: .medium))
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .fixedSize()

        // Apply the inactive dimming to the whole stack so a template icon dims
        // alongside the text. For normal/underlined events the color is left
        // unset so the text and template icon inherit the menu bar's vibrant
        // label color, which dims on inactive displays and blends like native
        // menu bar items; forcing Color.primary here renders fully opaque and
        // stands out against neighbors.
        if style == .inactive {
            content.foregroundStyle(.secondary)
        } else {
            content
        }
    }

    private func iconImage(_ icon: NSImage) -> some View {
        // Template icons follow the label color (so they tint with the menu
        // bar's active/inactive state); full-color icons keep their artwork.
        let base = Image(nsImage: icon)
        let rendered = base.renderingMode(icon.isTemplate ? .template : .original)
        return rendered
            .resizable()
            .scaledToFit()
    }
}

#Preview {
    StatusBarStackedTitleView(
        icon: getIconForMeetingService(.teams),
        title: "Weekly product sync",
        time: "in 45m",
        style: .normal
    )
    .padding()
}
