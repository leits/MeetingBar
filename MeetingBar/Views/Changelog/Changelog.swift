//
//  Changelog.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 22.03.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import SwiftUI

import Defaults


struct ChangelogView: View {
    @Default(.lastRevisedVersionInChangelog) var lastRevisedVersionInChangelog

    var body: some View {
        VStack(alignment: .center, spacing: 15) {
            List {
                if lastRevisedVersionInChangelog < "3.2.0" {
                    Section(header: Text("Version 3.2.0")) {
                        Text("• Added setting to only show events starting in x minutes")
                        Text("• Added Safari as a browser option")
                        Text("• Recognize meetings in outlook safe links")
                        Text("• New integrations: Discord, Jam, and Blackboard Collaborate")
                        Text("and small bug fixes")
                    }
                }
            }.listStyle(SidebarListStyle())
            Button("Close", action: close)
        }.padding()
    }

    func close() {
        if let app = NSApplication.shared.delegate as! AppDelegate? {
            app.changelogWindow.close()
        }
    }
}
