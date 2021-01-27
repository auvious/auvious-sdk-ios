//
//  StreamView.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 14/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import UIKit
import os

public class StreamView: UIView, RTCVideoViewDelegate, ZoomableUIView {
    
    //Various states for the overlay
    private enum OverlayState: CustomStringConvertible {
        case audioMuted, videoMuted, avMuted, none
        
        var description: String {
            switch self {
            case .audioMuted:
                return "audioMuted"
            case .videoMuted:
                return "videoMuted"
            case .avMuted:
                return "avMuted"
            case .none:
                return "none"
            }
        }
    }
    
    //UI components
    @IBOutlet weak var statusLabel: UILabel!
    var videoTrack: RTCVideoTrack!
    
    //UI Overlay
    private var overlayView: UIView?
    private var overlayIcon: UIImageView?
    private var overlayState: OverlayState = .none
    private var existingOverlayConstraints: [NSLayoutConstraint] = []
    
    //Switch from OpenGL to Metal if we can
    #if arch(i386) || arch(x86_64) || arch(arm)
    let supportsMetal: Bool = false
    var videoView: RTCEAGLVideoView = RTCEAGLVideoView(frame: CGRect.zero)
    #else
    let supportsMetal: Bool = true
    var videoView:RTCMTLVideoView = RTCMTLVideoView(frame: CGRect.zero)
    #endif
    
    //Control flags
    private var hasAudioStream: Bool = false
    private var hasVideoStream: Bool = false
    private var isScreen: Bool = false
    
    var size: CGSize = .zero
    
    internal var participantEndpoint: ParticipantEndpoint?
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        
        nibSetup()
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        
        nibSetup()
    }
    
    override public func awakeFromNib() {
        super.awakeFromNib()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
                
        if (self.size.width > 0 && self.size.height > 0) {
            var videoFrame = AVMakeRect(aspectRatio: CGSize(width: bounds.width, height: bounds.height), insideRect: bounds)
            var scale: CGFloat = 1.0
            if (videoFrame.size.width > videoFrame.size.height) {
                scale = bounds.size.height / videoFrame.size.height
            } else {
                scale = bounds.size.width / videoFrame.size.width
            }
            videoFrame.size.width = videoFrame.size.width * scale
            videoFrame.size.height = videoFrame.size.height * scale
            self.videoView.frame = videoFrame
            self.videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        } else {
            self.videoView.frame = bounds
        }
        
        if let o = overlayView {
            if overlayState == .audioMuted {
                o.cornerRadius(usingCorners: .bottomRight, cornerRadii: CGSize(width: 8, height: 8))
            } else {
                o.layer.mask = nil
            }
        }
    }
    
    private func nibSetup() {
        backgroundColor = .clear
        
        videoView.frame = bounds
        //prevent hickup when switching camera
        videoView.clipsToBounds = true
        
        videoView.delegate = self
        
        let view = loadViewFromNib()
        view.frame = bounds
        view.clipsToBounds = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.translatesAutoresizingMaskIntoConstraints = true
        //view.layer.borderColor = UIColor.black.cgColor
        //view.layer.borderWidth = 1.0
        view.layer.cornerRadius = 10
        layer.cornerRadius = 10
        clipsToBounds = true
        addSubview(view)
        
        addSubview(videoView)
        
        #if arch(i386) || arch(x86_64) || arch(arm)
        #else
        videoView.videoContentMode = .scaleAspectFill
        #endif
        
        createOverlay()
        resetStreamView()
    }
    
    private func loadViewFromNib() -> UIView {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: String(describing: type(of: self)), bundle: bundle)
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        
        return nibView
    }
    
    //MARK: Overlays
    private func createOverlay() {
        overlayView = UIView(frame: .zero)
        addSubview(overlayView!)
        overlayView!.translatesAutoresizingMaskIntoConstraints = false
        
        overlayIcon = UIImageView(frame: .zero)
        overlayIcon!.translatesAutoresizingMaskIntoConstraints = false
        overlayIcon!.contentMode = .scaleAspectFit
        overlayView!.addSubview(overlayIcon!)
    }
    
    private func handleOverlay() {
        guard !isScreen else {
            return
        }
        
        var constraints: [NSLayoutConstraint] = []
        
        var backgroundColor: UIColor!
        var iconName: String?
        var iconAlpha: CGFloat = 1
        
        if hasAudioStream && hasVideoStream {
            overlayState = .none
        } else {
            if !hasAudioStream && hasVideoStream {
                overlayState = .audioMuted
            } else if hasAudioStream && !hasVideoStream {
                overlayState = .videoMuted
            } else if !hasAudioStream && !hasVideoStream {
                overlayState = .avMuted
            }
        }
        
        switch overlayState {
        case .audioMuted:
            iconName = "notificationMicrophoneOff"
            backgroundColor = UIColor.black.withAlphaComponent(0.1)
            constraints.append(overlayView!.topAnchor.constraint(equalTo: self.topAnchor, constant: 0))
            constraints.append(overlayView!.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0))
            constraints.append(overlayView!.widthAnchor.constraint(equalToConstant: 42))
            constraints.append(overlayView!.heightAnchor.constraint(equalToConstant: 42))
            constraints.append(overlayIcon!.centerYAnchor.constraint(equalTo: overlayView!.centerYAnchor, constant: 0))
            constraints.append(overlayIcon!.centerXAnchor.constraint(equalTo: overlayView!.centerXAnchor, constant: 0))
            constraints.append(overlayIcon!.widthAnchor.constraint(equalToConstant: 26))
        case .videoMuted:
            iconName = "notificationMicrophoneOn"
            backgroundColor = .black
            constraints.append(overlayView!.topAnchor.constraint(equalTo: self.topAnchor, constant: 0))
            constraints.append(overlayView!.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0))
            constraints.append(overlayView!.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0))
            constraints.append(overlayView!.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0))
            constraints.append(overlayIcon!.centerYAnchor.constraint(equalTo: overlayView!.centerYAnchor, constant: 0))
            constraints.append(overlayIcon!.centerXAnchor.constraint(equalTo: overlayView!.centerXAnchor, constant: 0))
            constraints.append(overlayIcon!.widthAnchor.constraint(equalToConstant: 40))
        case .avMuted:
            iconName = "notificationMicrophoneOff"
            backgroundColor = .black
            constraints.append(overlayView!.topAnchor.constraint(equalTo: self.topAnchor, constant: 0))
            constraints.append(overlayView!.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0))
            constraints.append(overlayView!.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0))
            constraints.append(overlayView!.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0))
            constraints.append(overlayIcon!.centerYAnchor.constraint(equalTo: overlayView!.centerYAnchor, constant: 0))
            constraints.append(overlayIcon!.centerXAnchor.constraint(equalTo: overlayView!.centerXAnchor, constant: 0))
            constraints.append(overlayIcon!.widthAnchor.constraint(equalToConstant: 40))
        case .none:
            backgroundColor = .clear
            constraints.append(overlayView!.widthAnchor.constraint(equalToConstant: 0))
            constraints.append(overlayView!.heightAnchor.constraint(equalToConstant: 0))
            iconAlpha = 0
        }
        
        if let icon = iconName {
            overlayIcon!.image = UIImage(podAssetName: icon)
        }
        
//        UIView.animate(withDuration: 0.18, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 9, options: .curveEaseInOut, animations: {
            //Clear existing constraints
            if !self.existingOverlayConstraints.isEmpty {
                NSLayoutConstraint.deactivate(self.existingOverlayConstraints)
            }
            
            self.overlayView?.backgroundColor = backgroundColor
            self.overlayIcon?.alpha = iconAlpha
            
            NSLayoutConstraint.activate(constraints)
            self.existingOverlayConstraints = constraints
            
            self.layoutIfNeeded()
        //})
        
        os_log("handleOverlay() for state %@", log: Log.conferenceUI, type: .debug, overlayState.description)
    }
    
    public func audioStreamAdded(){
        hasAudioStream = true
        
        if !hasVideoStream {
            statusLabel.text = "Audio only"
            statusLabel.alpha = 1.0
        }
        
        //Apply overlay
        handleOverlay()
    }
    
    public func audioStreamRemoved(){
        hasAudioStream = false
        
//        if !hasVideoStream {
//            resetStreamView()
//        }
        //Apply overlay
        handleOverlay()
    }
    
    public func videoStreamAdded(_ videoTrack: RTCVideoTrack, isScreen: Bool = false){
        hasVideoStream = true
        self.isScreen = isScreen
        
        #if arch(i386) || arch(x86_64) || arch(arm)
        #else
        if isScreen {
            videoView.videoContentMode = .scaleAspectFit
        }
        #endif
        
        statusLabel.alpha = 0.0
        self.videoTrack = videoTrack
        self.videoTrack.add(videoView)
        videoView.frame = bounds
        videoView.alpha = 1.0
        
        //Apply overlay
        handleOverlay()
    }
    
    public func videoStreamAdded() {
        hasVideoStream = true
        
        videoView.frame = bounds
        videoView.alpha = 1.0
        
        //Apply overlay
        handleOverlay()
    }
    
    public func videoStreamRemoved(){
        hasVideoStream = false
        
        videoView.alpha = 0.0
//        if videoTrack != nil {
//            self.videoTrack.remove(videoView)
//        }
//        self.videoTrack = nil
        
//        if hasAudioStream {
//            statusLabel.text = "Audio only"
//            statusLabel.alpha = 1.0
//        }
        
        //Apply overlay
        handleOverlay()
    }
    
    public func avStreamAdded(_ videoTrack: RTCVideoTrack){
        videoStreamAdded(videoTrack)
        hasAudioStream = true
        
        //Apply overlay
        handleOverlay()
    }
    
    public func avStreamRemoved(){
        resetStreamView()
        
        //Apply overlay
        handleOverlay()
    }
    
    public func resetStreamView(){
        hasAudioStream = false
        hasVideoStream = false
        
        statusLabel.alpha = 0.0
        videoView.alpha = 0.0
        
        if videoTrack != nil {
            videoTrack.remove(videoView)
        }
    }
    
    //MARK: RTCVideoViewDelegate
    
    public func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        self.size = size
    }
    
    public func viewForZooming() -> UIView {
        return videoView
    }
    
    public func optionsForZooming() -> ZoomableViewOptions {
        return ZoomableViewOptions(minZoom: 1, maxZoom: 8)
    }
    
}
