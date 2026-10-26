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

    /// The round mic-off badge in the video's bottom left corner. Off for the agent while the call is
    /// in PiP, where the status capsule shows it instead.
    var showsAudioMutedBadge: Bool = true {
        didSet {
            handleOverlay()
        }
    }

    /// The badge stays above this anchor (the call buttons), for videos that run to the bottom of the screen
    var audioMutedBadgeBottomLimit: NSLayoutYAxisAnchor? {
        didSet {
            handleOverlay()
        }
    }

    //Shown from the moment a video track is attached until its first frame is rendered,
    //so the view never sits there empty
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)

    //Width / height last reported through onVideoShapeChange (0 = no size yet)
    private var reportedAspect: CGFloat = 0

    /// The spinner while a video track loads. Off for our own camera, whose video fades in instead.
    var showsLoadingIndicator = true

    //True from attaching a track until its first frame
    private var awaitingFirstFrame = false

    /// True once a frame has told us the video's dimensions. It stays true when the camera is muted,
    /// so the tile keeps the video's shape instead of going back to the loading square.
    var hasVideoSize: Bool {
        return size != .zero
    }

    /// Called when the video's size first becomes known and whenever its aspect ratio changes
    /// (rotation, camera switch), so the call can reshape the tile to the video
    var onVideoShapeChange: (() -> Void)?
    
    // Metal on devices and simulators (M155 has no RTCEAGLVideoView)
    var videoView:RTCMTLVideoView = RTCMTLVideoView(frame: CGRect.zero)
    
    //Control flags
    private var hasAudioStream: Bool = false
    private var hasVideoStream: Bool = false
    private var isScreen: Bool = false
    
    var size: CGSize = .zero
    
    internal var participantEndpoint: ParticipantEndpoint?

    /// AR pointer points and sketch over the video, while this tile is the pointer's target
    private(set) var annotationSurface: AnnotationSurfaceView?

    /// Set by tapping a remote tile: the tile takes the video's shape, so the whole video shows
    private var tappedToFit = false

    /// Taps switch the tile between fitting its video and filling its space in the layout.
    /// On for remote tiles while the call is full screen.
    var togglesFitOnTap = false {
        didSet {
            updateFitTapGesture()
        }
    }

    /// The stream's portraitMode metadata. Its tile always fills its space, taps don't change it.
    var portraitMode = false {
        didSet {
            if portraitMode && tappedToFit {
                tappedToFit = false
                onFitChange?()
            }
            updateFitTapGesture()
        }
    }

    /// Called when a tap switches between fit and fill, so the call can reshape the tile
    var onFitChange: (() -> Void)?

    /// True when the call should shape the tile like its video, fitted inside the space its layout gives it (`layoutSlot`).
    /// The video still fills the tile, which then crops nothing. Off in PiP.
    var followsVideoShape: Bool {
        return tappedToFit && togglesFitOnTap && !portraitMode && hasVideoSize
    }

    /// The space the call's layout gives a tile that follows its video's shape. Owned by the tile's superview.
    let layoutSlot = UILayoutGuide()

    private lazy var fitTapGesture = UITapGestureRecognizer(target: self, action: #selector(fitTapped))

    /// The whole video shows (aspect fit) for screens and while the AR pointer points at the tile, so nothing pointed at is cropped
    private var fitsVideo: Bool {
        return isScreen || annotationSurface != nil
    }

    /// Off for portrait videos, and for screens and the AR pointer's tile, which always fit
    /// (so the tap never competes with the annotation surface's own taps)
    private func updateFitTapGesture() {
        fitTapGesture.isEnabled = togglesFitOnTap && !portraitMode && !isScreen && annotationSurface == nil
    }

    @objc private func fitTapped() {
        tappedToFit.toggle()
        onFitChange?()
    }

    override public func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)
        //The slot belongs to the old superview; the call adds it to the new one when it lays the tile out
        layoutSlot.owningView?.removeLayoutGuide(layoutSlot)
    }

    private func updateVideoContentMode() {
        videoView.videoContentMode = fitsVideo ? .scaleAspectFit : .scaleAspectFill
        setNeedsLayout()
    }

    /// Where the video's frames are drawn: aspect filled for cameras (it can overflow the clipped tile), aspect fit when fitsVideo
    var videoContentRect: CGRect {
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        if fitsVideo {
            return AVMakeRect(aspectRatio: size, insideRect: bounds)
        }
        let scale = max(bounds.width / size.width, bounds.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
    }

    func installAnnotationSurface(_ surface: AnnotationSurfaceView) {
        guard annotationSurface !== surface else { return }
        removeAnnotationSurface()
        annotationSurface = surface
        videoView.videoContentMode = .scaleAspectFit
        insertSubview(surface, aboveSubview: videoView)
        surface.frame = videoContentRect
        updateFitTapGesture()
    }

    func removeAnnotationSurface() {
        annotationSurface?.removeFromSuperview()
        annotationSurface = nil
        updateVideoContentMode()
        updateFitTapGesture()
    }
    
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
            let videoFrame = AVMakeRect(aspectRatio: CGSize(width: bounds.width, height: bounds.height), insideRect: bounds)
            var scale: CGFloat = 1.0
            if (videoFrame.size.width > videoFrame.size.height) {
                scale = bounds.size.height / videoFrame.size.height
            } else {
                scale = bounds.size.width / videoFrame.size.width
            }
            
            if scale.isNaN {
                scale = 1
            }
            
            var width = videoFrame.size.width
            var height = videoFrame.size.height
            if width.isNaN {
               width = 0
            }
            
            if height.isNaN {
                height = 0
            }
            
            var x = videoFrame.origin.x
            if x.isNaN {
                x = 0
            }
            
            var y = videoFrame.origin.y
            if y.isNaN {
                y = 0
            }
            
            width = width * scale
            height = height * scale
            self.videoView.frame = CGRect(x: x, y: y, width: width, height: height)
            self.videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        } else {
            self.videoView.frame = bounds
        }
        
        annotationSurface?.frame = videoContentRect

        if let o = overlayView {
            if overlayState == .audioMuted {
                //Round badge
                o.cornerRadius(usingCorners: [.bottomRight, .bottomLeft, .topRight, .topLeft], cornerRadii: CGSize(width: o.bounds.height / 2, height: o.bounds.height / 2))
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
        view.layer.cornerRadius = 12
        layer.cornerRadius = 12
        clipsToBounds = true
        addSubview(view)
        
        addSubview(videoView)
        
        videoView.videoContentMode = .scaleAspectFill

        updateFitTapGesture()
        addGestureRecognizer(fitTapGesture)

        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingIndicator)
        loadingIndicator.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
        loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true

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
    
    func hideOverlay() {
        overlayView?.alpha = 0
        overlayIcon?.alpha = 0
    }
    
    func restoreOverlay() {
        overlayView?.alpha = 1
        overlayIcon?.alpha = 1
    }
    
    func overlayInPIP() {
        overlayIcon?.layer.opacity = 0.6
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
        
        if overlayState == .audioMuted && !showsAudioMutedBadge {
            overlayState = .none
        }
        
        switch overlayState {
        case .audioMuted:
            //The mute icon of the call buttons, in a round badge
            iconName = "micDisabled"
            backgroundColor = UIColor.black.withAlphaComponent(0.5)
            //Bottom left, clear of the status capsule and PiP's top corners
            let atVideoBottom = overlayView!.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -6)
            atVideoBottom.priority = .defaultHigh
            constraints.append(atVideoBottom)
            if let limit = audioMutedBadgeBottomLimit {
                constraints.append(overlayView!.bottomAnchor.constraint(lessThanOrEqualTo: limit, constant: -12))
            }
            constraints.append(overlayView!.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6))
            constraints.append(overlayView!.widthAnchor.constraint(equalToConstant: 30))
            constraints.append(overlayView!.heightAnchor.constraint(equalToConstant: 30))
            constraints.append(overlayIcon!.centerYAnchor.constraint(equalTo: overlayView!.centerYAnchor, constant: 0))
            constraints.append(overlayIcon!.centerXAnchor.constraint(equalTo: overlayView!.centerXAnchor, constant: 0))
            constraints.append(overlayIcon!.widthAnchor.constraint(equalToConstant: 18))
            constraints.append(overlayIcon!.heightAnchor.constraint(equalToConstant: 18))
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
            iconName = ""
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
    
    public func audioStreamRemoved(screenMode: ScreenMode){
        hasAudioStream = false
        
//        if !hasVideoStream {
//            resetStreamView()
//        }
        
        
        if screenMode == .expandedPip {
            hasAudioStream = true
            hasVideoStream = true
        }
        
        //Apply overlay
        handleOverlay()
    }
    
    public func videoStreamAdded(_ videoTrack: RTCVideoTrack, isScreen: Bool = false){
        hasVideoStream = true
        self.isScreen = isScreen

        if isScreen {
            videoView.videoContentMode = .scaleAspectFit
        }
        updateFitTapGesture()

        // Remove the old track from the renderer before attaching the new one
        // so the frozen last frame doesn't persist after a rejoin.
        if self.videoTrack != nil {
            self.videoTrack.remove(videoView)
        }

        statusLabel.alpha = 0.0
        self.videoTrack = videoTrack
        //Until the first frame of the new track arrives: a spinner, or nothing (it fades in)
        awaitingFirstFrame = true
        if showsLoadingIndicator {
            loadingIndicator.startAnimating()
        }
        self.videoTrack.add(videoView)
        videoView.frame = bounds
        videoView.alpha = showsLoadingIndicator ? 1.0 : 0.0

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
        loadingIndicator.stopAnimating()
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
        loadingIndicator.stopAnimating()
        
        if videoTrack != nil {
            videoTrack.remove(videoView)
        }
    }
    
    //MARK: RTCVideoViewDelegate
    
    public func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        self.size = size

        //The first frame has been rendered
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            //Annotations follow the video's shape
            if self.annotationSurface != nil {
                self.setNeedsLayout()
            }
            if self.awaitingFirstFrame {
                self.awaitingFirstFrame = false
                //Fade the first frame in, unless the camera was turned off meanwhile
                if self.hasVideoStream && self.videoView.alpha < 1 {
                    UIView.animate(withDuration: 0.3) {
                        self.videoView.alpha = 1
                    }
                }
            }
            //Not on every resolution step of the stream, only when the shape changes
            let aspect = self.hasVideoSize ? self.size.width / self.size.height : 0
            if abs(aspect - self.reportedAspect) > 0.01 {
                self.reportedAspect = aspect
                self.onVideoShapeChange?()
            }
        }
    }
    
    public func viewForZooming() -> UIView {
        return videoView
    }
    
    public func optionsForZooming() -> ZoomableViewOptions {
        return ZoomableViewOptions(minZoom: 1, maxZoom: 8)
    }
    
}
