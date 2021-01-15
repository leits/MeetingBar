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
                GeneralTab().tabItem { Text("General") }
                AppearanceTab().tabItem { Text("Appearance") }
                ServicesTab().tabItem { Text("Services") }
                BookmarksTab().tabItem { Text("Bookmarks") }
                CalendarsTab().tabItem { Text("Calendars") }
                AdvancedTab().tabItem { Text("Advanced") }
            }
        }.padding()
    }
}
