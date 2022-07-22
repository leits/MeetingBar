//
//  CalendarsScreen.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 13.01.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults

struct CalendarsScreen: View {
    @Default(.selectedCalendarIDs) var selectedCalendarIDs

    var body: some View {
        VStack {
            CalendarsTab()
            Divider()
            HStack {
                Spacer()
                if self.selectedCalendarIDs.isEmpty {
                    Text("calendars_screen_select_calendar_title".loco()).foregroundColor(Color.gray)
                }
                Button(action: self.close) {
                    Text("calendars_screen_start_button".loco())
                    Image(nsImage: NSImage(named: NSImage.goForwardTemplateName)!)
                }.disabled(self.selectedCalendarIDs.isEmpty)
            }.padding(5)
        }
    }

    func close() {
        NSApplication.shared.keyWindow?.close()
    }
}
