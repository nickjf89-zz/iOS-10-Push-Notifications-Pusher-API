//
//  NotificationViewController.swift
//  Content Extension
//
//  Created by Nick Farrant on 12/09/2016.
//  Copyright © 2016 Pusher. All rights reserved.
//

import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {

    @IBOutlet var titleLabel: UILabel?
    @IBOutlet var subtitleLabel: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any required interface initialization here.
    }
    
    func didReceive(_ notification: UNNotification) {
        titleLabel?.text = notification.request.content.title
        subtitleLabel?.text = notification.request.content.subtitle
    }
}
