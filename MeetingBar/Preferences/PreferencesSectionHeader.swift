//
//  PreferencesSectionHeader.swift
//  MeetingBar
//

import SwiftUI

struct PreferencesSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    VStack {
        PreferencesSectionHeader(title: "Example Section", systemImage: "gearshape")
        Text("Content goes here")
    }
    .padding()
}
