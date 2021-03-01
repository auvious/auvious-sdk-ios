//
//  NotificationView.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 1/10/20.
//

import Foundation
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

internal class NetworkDetailsNotificationView: UIView {
    
    //UI components
    internal var titleLabel: UILabel = UILabel(frame: .zero)
    internal var subtitleLabel: UILabel = UILabel(frame: .zero)
    internal var closeButton: UIButton = UIButton(frame: .zero)
    
    private var statistics: NetworkStatistics?
    
    init(with details: NetworkStatistics?) {
        super.init(frame: .zero)
        
        self.statistics = details
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(frame: .zero)
        setupUI()
    }
    
    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 10
        backgroundColor = .white
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10).isActive = true
        titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.text = NSLocalizedString("Network indicator (beta)", comment: "Notification")
        
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5).isActive = true
        subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10).isActive = true
        subtitleLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        subtitleLabel.textColor = UIColor.black.withAlphaComponent(0.8)
        
        closeButton.isUserInteractionEnabled = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)
        closeButton.backgroundColor = .clear
        closeButton.setBackgroundImage(UIImage(podAssetName: "closeButton"), for: [])
        closeButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0).isActive = true
        closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10).isActive = true
        closeButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 20).isActive = true
        closeButton.layer.zPosition = 2199

        updateUI(with: statistics)
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
        
        titleLabel.text = NSLocalizedString("Network indicator (beta)", comment: "Notification")
        subtitleLabel.text = detailsMsg
    }
    
    internal func updateUI(with title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
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
            os_log("WARNING, notification skipped", log: Log.conferenceUI, type: .debug)
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
            os_log("WARNING, AuviousNotification.updateNotification() skipped", log: Log.conferenceUI, type: .debug)
            return
        }
        
    }
}
