//
//  View+Ext.swift
//  MeetingBar
//
//  Created by Sergey Ryazanov on 30.04.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import Foundation
import SwiftUI

extension View {
    @ViewBuilder func isHidden(_ hidden: Bool, remove: Bool = false) -> some View {
        if hidden {
            if !remove {
                self.hidden()
            }
        } else {
            self
        }
    }
}
