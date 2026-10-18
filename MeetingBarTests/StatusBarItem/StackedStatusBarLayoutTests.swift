import AppKit
import SwiftUI
import XCTest

@testable import MeetingBar

@MainActor
final class StackedStatusBarLayoutTests: BaseTestCase {
    func test_titleChangesResizeTheSameHostInBothDirections() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(presentation(title: "Hi", time: "now"))
        let host = try layout(controller)
        let shortWidth = host.frame.width

        controller.renderStatusBar(presentation(title: String(repeating: "W", count: 55), time: "now"))
        let expandedHost = try layout(controller)
        XCTAssertTrue(expandedHost === host)
        XCTAssertGreaterThan(expandedHost.frame.width, shortWidth + 100)
        assertFitsButton(controller, host: expandedHost)

        controller.renderStatusBar(presentation(title: "Hi", time: "now"))
        let contractedHost = try layout(controller)
        XCTAssertTrue(contractedHost === host)
        XCTAssertEqual(contractedHost.frame.width, shortWidth, accuracy: 1)
        assertFitsButton(controller, host: contractedHost)
    }

    func test_countdownChangesResizeTheSameHostInBothDirections() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        controller.renderStatusBar(presentation(title: "A", time: "in 1m"))
        let host = try layout(controller)
        let shortWidth = host.frame.width

        controller.renderStatusBar(presentation(title: "A", time: "now (1h 59m left)"))
        let expandedHost = try layout(controller)
        XCTAssertTrue(expandedHost === host)
        XCTAssertGreaterThan(expandedHost.frame.width, shortWidth + 10)
        assertFitsButton(controller, host: expandedHost)

        controller.renderStatusBar(presentation(title: "A", time: "in 1m"))
        let contractedHost = try layout(controller)
        XCTAssertTrue(contractedHost === host)
        XCTAssertEqual(contractedHost.frame.width, shortWidth, accuracy: 1)
        assertFitsButton(controller, host: contractedHost)
    }

    func test_laidOutContentFitsForDifferentScriptsIconsAndParticipationStyles() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let texts = [
            ("Weekly sync", "now (45m left)"),
            ("Планування зустрічі", "через 5 хв"),
            ("設計レビュー", "あと5分"),
            ("اجتماع الفريق", "بعد ٥ دقائق"),
            ("👩🏽‍💻 Team 🚀", "in 5m")
        ]
        let icons: [StatusBarIcon] = [.none, .asset(MenuStyleConstants.calendarIconName), .meetingService(.zoom)]
        for (title, time) in texts {
            for icon in icons {
                for style in [StatusBarTitleStyle.normal, .inactive, .underlined] {
                    controller.renderStatusBar(presentation(title: title, time: time, icon: icon, style: style))
                    let host = try layout(controller)
                    assertFitsButton(controller, host: host, context: "\(title), \(icon), \(style)")
                }
            }
        }
    }

    func test_layoutTransitionsDetachOldHostsAndRestoreNativeSizing() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        let button = try XCTUnwrap(controller.statusItem.button)
        let nativeSubviewCount = button.subviews.count
        let transitions = [
            StatusBarPresentation(mode: .nextEvent, title: "Inline", time: "in 5m", tooltip: nil,
                                  icon: .none, layout: .inline(showTime: true), titleStyle: .normal),
            StatusBarPresentation(mode: .nextEvent, title: "", time: "", tooltip: nil,
                                  icon: .asset(MenuStyleConstants.calendarIconName), layout: .none, titleStyle: .normal),
            StatusBarPresentation(mode: .noUpcoming, title: "", time: "", tooltip: nil,
                                  icon: .asset(MenuStyleConstants.calendarCheckmarkIconName), layout: .none, titleStyle: .normal)
        ]

        for next in transitions {
            controller.renderStatusBar(presentation(title: "A longer meeting title", time: "in 15m"))
            let previousHost = try layout(controller)
            assertFitsButton(controller, host: previousHost)

            controller.renderStatusBar(next)
            button.window?.contentView?.layoutSubtreeIfNeeded()
            button.layoutSubtreeIfNeeded()
            XCTAssertNil(previousHost.superview)
            XCTAssertNil(controller.stackedHostingView)
            XCTAssertEqual(button.subviews.count, nativeSubviewCount)
            XCTAssertEqual(controller.statusItem.length, NSStatusItem.variableLength)

            controller.renderStatusBar(presentation(title: "Back", time: "in 1m"))
            let replacement = try layout(controller)
            XCTAssertFalse(replacement === previousHost)
            XCTAssertEqual(button.subviews.count, nativeSubviewCount + 1)
            assertFitsButton(controller, host: replacement)
        }
    }

    func test_nativeButtonReceivesHitTestsAcrossTheLaidOutContent() throws {
        let controller = StatusBarItemController()
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }
        controller.renderStatusBar(presentation(
            title: "Weekly sync", time: "in 5m", icon: .asset(MenuStyleConstants.calendarIconName)
        ))
        let host = try layout(controller)
        let button = try XCTUnwrap(controller.statusItem.button)
        assertFitsButton(controller, host: host)

        // Test the enclosing native button's hit-test traversal, not just the
        // hosting view override. Points cover the icon and both text rows.
        for point in [
            NSPoint(x: 8, y: host.bounds.midY),
            NSPoint(x: host.bounds.maxX - 5, y: host.bounds.height * 0.25),
            NSPoint(x: host.bounds.maxX - 5, y: host.bounds.height * 0.75)
        ] {
            let pointInSuperview = host.convert(point, to: button.superview)
            XCTAssertTrue(button.hitTest(pointInSuperview) === button, "Hit test at \(point)")
        }
    }

    private func layout(_ controller: StatusBarItemController) throws -> NSHostingView<StatusBarStackedTitleView> {
        let button = try XCTUnwrap(controller.statusItem.button)
        let host = try XCTUnwrap(controller.stackedHostingView)
        XCTAssertNotNil(button.window)
        // Finish the surrounding AppKit layout after the controller changes
        // NSStatusItem.length. Intrinsic size alone does not prove the view fits.
        button.window?.contentView?.layoutSubtreeIfNeeded()
        button.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func assertFitsButton(
        _ controller: StatusBarItemController,
        host: NSHostingView<StatusBarStackedTitleView>,
        context: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let button = controller.statusItem.button else {
            XCTFail("Missing native status button", file: file, line: line)
            return
        }
        let contentFrame = host.convert(host.bounds, to: button)
        // One point tolerates AppKit's backing-scale rounding without allowing
        // a missing line, stale width or off-center content to pass.
        let tolerance: CGFloat = 1
        XCTAssertGreaterThan(contentFrame.width, 0, context, file: file, line: line)
        XCTAssertGreaterThan(contentFrame.height, 0, context, file: file, line: line)
        XCTAssertEqual(contentFrame.width, host.intrinsicContentSize.width, accuracy: tolerance, context, file: file, line: line)
        XCTAssertEqual(contentFrame.height, host.intrinsicContentSize.height, accuracy: tolerance, context, file: file, line: line)
        XCTAssertEqual(contentFrame.width, controller.statusItem.length, accuracy: tolerance, context, file: file, line: line)
        XCTAssertTrue(button.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(contentFrame),
                      "\(context): content \(contentFrame) outside button \(button.bounds)", file: file, line: line)
        XCTAssertEqual(contentFrame.midX, button.bounds.midX, accuracy: tolerance, context, file: file, line: line)
        XCTAssertEqual(contentFrame.midY, button.bounds.midY, accuracy: tolerance, context, file: file, line: line)
    }

    private func presentation(
        title: String,
        time: String,
        icon: StatusBarIcon = .none,
        style: StatusBarTitleStyle = .normal
    ) -> StatusBarPresentation {
        StatusBarPresentation(mode: .nextEvent, title: title, time: time, tooltip: title,
                              icon: icon, layout: .stacked, titleStyle: style)
    }
}
