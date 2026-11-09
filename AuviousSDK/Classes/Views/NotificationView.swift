//
//  NotificationView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 1/10/20.
//

import Foundation
import UIKit
import os

//Notification types
internal enum NotificationType {
    case cameraOn, cameraOff, microphoneOn, microphoneOff
    
    var title: String {
        switch self {
        case .cameraOff:
            return NSLocalizedString("Camera off", comment: "Notification")
        case .cameraOn:
            return NSLocalizedString("Camera on", comment: "Notification")
        case .microphoneOn:
            return NSLocalizedString("Microphone on", comment: "Notification")
        case .microphoneOff:
            return NSLocalizedString("Microphone off", comment: "Notification")
        }
    }
    
    var icon: UIImage? {
        switch self {
        case .cameraOff:
            return UIImage(podAssetName: "notificationCameraOff")
        case .cameraOn:
            return UIImage(podAssetName: "notificationCameraOn")
        case .microphoneOff:
            return UIImage(podAssetName: "notificationMicrophoneOff")
        case .microphoneOn:
            return UIImage(podAssetName: "notificationMicrophoneOn")
        }
    }
}

/// Top banner for short notices in the video call (e.g. recording started/stopped)
internal class DismissableNotificationView: AuviousBannerView {

    init(title: String, subtitle: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        updateUI(withTitle: title, subtitle: subtitle)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
    }

    internal func updateUI(withTitle: String, subtitle: String?, symbol: String? = nil, image: UIImage? = nil, tint: UIColor? = nil) {
        configure(symbol: symbol, image: image, tint: tint, title: withTitle, message: subtitle)
    }
}

/// Top banner with the network indicator details, also used for participant limit notices
internal class NetworkDetailsNotificationView: AuviousBannerView {

    private var statistics: NetworkStatistics?

    init(with details: NetworkStatistics?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        updateUI(with: details)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
        updateUI(with: nil)
    }

    internal func updateUI(with data: NetworkStatistics?) {
        self.statistics = data

        let detailsText = "Jitter: %@   Packet loss: %@   Round-trip time: %@"
        var detailsMsg = ""

        if let data = statistics {
            let packetLoss = String(100 - data.avgNetworkQuality)
            detailsMsg = String(format: detailsText, String(data.avgJitter), "\(packetLoss)%", String(data.avgRtt))
        } else {
            detailsMsg = String(format: detailsText, "n/a", "n/a", "n/a")
        }

        configure(symbol: "wifi", tint: .systemBlue, title: NSLocalizedString("Network indicator (beta)", comment: "Notification"), message: detailsMsg)
    }

    /// A participant notice (e.g. limited visibility) shown in the same banner
    internal func updateUI(with title: String, subtitle: String) {
        configure(symbol: "person.2.fill", tint: .systemBlue, title: title, message: subtitle)
    }
}

//A notification view
internal class NotificationView: UIView {
    
    //UI components
    private var imageView: UIImageView = UIImageView(frame: .zero)
    private var label: UILabel = UILabel(frame: .zero)
    
    private var notificationType: NotificationType!
    
    init(type: NotificationType) {
        super.init(frame: .zero)
        
        self.notificationType = type
        setupUI()
        setupContent()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        //setup container
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.black.withAlphaComponent(0.7)
        clipsToBounds = true
        layer.cornerRadius = 10
        
        //setup icon
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        imageView.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        imageView.topAnchor.constraint(equalTo: topAnchor, constant: 30).isActive = true
        imageView.widthAnchor.constraint(equalToConstant: 68).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 68).isActive = true
        
        //setup label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        addSubview(label)
        label.textAlignment = .center
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18).isActive = true
    }
    
    private func setupContent() {
        imageView.image = notificationType.icon
        label.text = notificationType.title
    }
    
    internal func update(newType: NotificationType) {
        self.notificationType = newType
        setupContent()
    }
    
}

//Singleton for managing the display of notifications
internal class AuviousNotification {
    
    //Singleton instance
    static let shared = AuviousNotification()
    
    //Notification center extensions
    internal let agentStartedScreenShare = "agentStartedScreenShare"
    internal let agentStoppedScreenShare = "agentStoppedScreenShare"
    
    //The notification being displayed
    private var view: NotificationView!
    
    //The VC that will host this notification
    internal var presenter: UIViewController?
    
    //Determines if a notification is being presented
    private var isPresenting: Bool = false
    
    //UI properties
    private let size: CGFloat = 150
    
    //Displays the given notification
    func show(_ type: NotificationType) {
        guard let presenter = presenter else {
            sdkLog("WARNING, notification skipped", log: Log.conferenceUI, type: .debug)
            return
        }
        
        //If we're already presenting, update the notification
        if isPresenting {
            view.update(newType: type)
        } else {
        
            isPresenting = true
            view = NotificationView(type: type)
            view.alpha = 1
            
            presenter.view.addSubview(view)
            view.centerXAnchor.constraint(equalTo: presenter.view.centerXAnchor, constant: 0).isActive = true
            view.centerYAnchor.constraint(equalTo: presenter.view.centerYAnchor, constant: 0).isActive = true
            view.widthAnchor.constraint(equalToConstant: size).isActive = true
            view.heightAnchor.constraint(equalToConstant: size).isActive = true
            
            view.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
            view.alpha = 0.3
            UIView.animate(withDuration: 0.2, animations: {
                self.view.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.view.alpha = 1
            }, completion: { finished in
                UIView.animate(withDuration: 0.2, delay: 1.2, options: [], animations: {
                    self.view.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
                    self.view.alpha = 0.3
                }, completion: { finished in
                    self.isPresenting = false
                    self.view.removeFromSuperview()
                })
            })
        }
    }
    
    private func updateNotification(newType: NotificationType) {
        guard isPresenting else {
            sdkLog("WARNING, AuviousNotification.updateNotification() skipped", log: Log.conferenceUI, type: .debug)
            return
        }
        
    }
}
