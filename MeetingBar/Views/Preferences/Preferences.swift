//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        VStack {
            TabView {
                GeneralTab().tabItem { Text("preferences_tab_general".loco()) }
                AppearanceTab().tabItem { Text("preferences_tab_appearance".loco()) }
                ServicesTab().tabItem { Text("preferences_tab_services".loco()) }
                BookmarksTab().tabItem { Text("preferences_tab_bookmarks".loco()) }
                CalendarsTab().tabItem { Text("preferences_tab_calendars".loco()) }
                AdvancedTab().tabItem { Text("preferences_tab_advanced".loco()) }
            }
        }.padding()
    }
}
