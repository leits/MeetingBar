//
//  DayTimelineView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.05.2025.
//  Copyright © 2025 Andrii Leitsius. All rights reserved.
//

import SwiftUI
import Defaults

struct DaySegment: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let color: Color
}

enum DayTimelineLayout {
    /// How many hours are visible to the left / right of “now”
    static let hoursBefore: TimeInterval = 3 * 3600   // 3 h
    static let hoursAfter: TimeInterval = 6 * 3600   // 6 h

    static let baseTrackHeight: CGFloat = 22
    static let segmentHeight: CGFloat = 10
    static let rowSpacing: CGFloat = 4

    static var rowHeight: CGFloat { segmentHeight + rowSpacing }
}

struct DayTimelineLayoutCalculator {
    // MARK: Cached range information
    let now = Date()
    let visibleRange: ClosedRange<Date>
    private let totalSeconds: TimeInterval

    init() {
        let lower = now.addingTimeInterval(-DayTimelineLayout.hoursBefore)
        let upper = now.addingTimeInterval( DayTimelineLayout.hoursAfter)
        self.visibleRange = lower...upper
        self.totalSeconds = upper.timeIntervalSince(lower)
    }

    // MARK: X-position helpers
    func xPosition(of date: Date, width: CGFloat) -> CGFloat {
        let clamped = min(max(date, visibleRange.lowerBound), visibleRange.upperBound)
        let seconds = clamped.timeIntervalSince(visibleRange.lowerBound)
        return width * CGFloat(seconds / totalSeconds)
    }

    // MARK: Hour ticks
    func hourTicks() -> [Date] {
        var out: [Date] = []
        var current = Calendar.current.nextDate(
            after: visibleRange.lowerBound.addingTimeInterval(-1),
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .strict
        )!
        while current <= visibleRange.upperBound {
            out.append(current)
            current = Calendar.current.date(byAdding: .hour, value: 1, to: current)!
        }
        return out
    }

    // MARK: Row packing
    func rows(for segments: [DaySegment]) -> [[DaySegment]] {
        var rows: [[DaySegment]] = []
        for seg in segments where seg.end > visibleRange.lowerBound && seg.start < visibleRange.upperBound {
            if let idx = rows.firstIndex(where: { row in
                !row.contains(where: { $0.start < seg.end && $0.end > seg.start })
            }) {
                rows[idx].append(seg)
            } else {
                rows.append([seg])
            }
        }
        return rows
    }
}

struct DayRelativeTimelineView: View {
    let segments: [DaySegment]
    let currentDate: Date

    // Cached / pre-computed values
    private let layout   = DayTimelineLayoutCalculator()
    private let eventRows: [[DaySegment]]
    private let contentHeight: CGFloat

    /// Height the parent can rely on for sizing
    var preferredHeight: CGFloat { contentHeight + 20 }   // vertical padding

    // MARK: Init
    init(segments: [DaySegment], currentDate: Date) {
        self.segments     = segments
        self.currentDate  = currentDate
        self.eventRows    = layout.rows(for: segments)
        self.contentHeight = DayTimelineLayout.baseTrackHeight +
            DayTimelineLayout.rowHeight * CGFloat(max(eventRows.count - 1, 0))
    }

    // MARK: Body
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {

                // Hour grid
                ForEach(layout.hourTicks(), id: \.self) { tick in
                    let x = layout.xPosition(of: tick, width: width)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: contentHeight))
                    }
                    .stroke(Color.primary.opacity(0.25)
, lineWidth: 1)

                    Text(hourFormatter.string(from: tick))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .position(x: x, y: -8)
                }

                // Event rows
                ForEach(eventRows.indices, id: \.self) { row in
                    ForEach(eventRows[row]) { seg in
                        let startX  = layout.xPosition(of: max(seg.start, layout.visibleRange.lowerBound), width: width)
                        let endX    = layout.xPosition(of: min(seg.end, layout.visibleRange.upperBound), width: width)
                        let widthPx = max(endX - startX, 1)

                        Capsule()
                            .fill(seg.color.opacity(0.25))
                            .overlay(Capsule().stroke(seg.color, lineWidth: 1))
                            .frame(width: widthPx, height: DayTimelineLayout.segmentHeight)
                            .offset(
                                x: startX,
                                y: (DayTimelineLayout.baseTrackHeight - DayTimelineLayout.segmentHeight) / 2 +
                                   CGFloat(row) * DayTimelineLayout.rowHeight
                            )
                    }
                }

                // Current time indicator
                if layout.visibleRange.contains(currentDate) {
                    let x = layout.xPosition(of: currentDate, width: width)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2, height: contentHeight + 4)
                        .offset(x: x - 1, y: -2)
                }
            }
            .frame(height: contentHeight)
            .padding(.top, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Timeline with \(segments.count) events")
    }

    // Static formatter (built once)
    private static let hourFormatter: DateFormatter = {
        let format = DateFormatter()
        format.locale = I18N.instance.locale
        switch Defaults[.timeFormat] {
        case .am_pm:    format.dateFormat = "h a"
        case .military: format.dateFormat = "HH"
        }
        return format
    }()
    private var hourFormatter: DateFormatter { Self.hourFormatter }
}

// MARK: — Preview

#Preview {
    let cal = Calendar.current
    let now = Date()
    let sampleSegments = [
        DaySegment(
            start: cal.date(byAdding: .hour, value: -2, to: now)!,
            end: cal.date(byAdding: .hour, value: -1, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: -30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -90, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .minute, value: -30, to: now)!,
            end: cal.date(byAdding: .minute, value: 30, to: now)!,
            color: .blue
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 1, to: now)!,
            end: cal.date(byAdding: .hour, value: 2, to: now)!,
            color: .green
        ),
        DaySegment(
            start: cal.date(byAdding: .hour, value: 4, to: now)!,
            end: cal.date(byAdding: .hour, value: 5, to: now)!,
            color: .orange
        )
    ]

    DayRelativeTimelineView(
        segments: sampleSegments,
        currentDate: now
    )
    .padding()
}
