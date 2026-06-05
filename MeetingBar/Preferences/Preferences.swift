//
//  PreferencesView.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.05.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var appModel: AppModel
    @ObservedObject var patronageService: PatronageService

    var body: some View {
        TabView {
            GeneralTab(patronageService: patronageService)
                .tabItem { Text("preferences_tab_general".loco()) }
            AppearanceTab().tabItem { Text("preferences_tab_appearance".loco()) }
            LinksTab().tabItem { Text("preferences_tab_links".loco()) }
            CalendarsTab().tabItem { Text("preferences_tab_calendars".loco()) }
            AdvancedTab().tabItem { Text("preferences_tab_advanced".loco()) }
            StatusTab().tabItem { Text("preferences_tab_status".loco()) }
        }.padding()
    }
}
