//
//  Notifications.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 14.08.2020.
//  Copyright © 2020 Andrii Leitsius. All rights reserved.
//
import UserNotifications

func removeDeliveredNotifications() {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
}
