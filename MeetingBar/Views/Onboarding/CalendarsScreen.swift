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
                    Text("Select at least one calendar").foregroundColor(Color.gray)
                }
                Button(action: self.close) {
                    Text("Start using app")
                    Image(nsImage: NSImage(named: NSImage.goForwardTemplateName)!)
                }.disabled(self.selectedCalendarIDs.isEmpty)
            }.padding(5)
        }
    }

    func close() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            app.onboardingWindow.close()
        }
    }
}
