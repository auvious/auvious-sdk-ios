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
    private var hasVideoStream: Bool = false {
        didSet {
            updateBorderAndClip()
        }
    }
    private var isScreen: Bool = false
    
    var size: CGSize = .zero
    
    internal var participantEndpoint: ParticipantEndpoint?

    /// AR pointer points and sketch over the video, while this tile is the pointer's target
    private(set) var annotationSurface: AnnotationSurfaceView?

    /// Set by tapping a remote tile: the tile takes the video's shape, so the whole video shows
    /// (or, with tapSwitchesToPortrait, the call switches to the portrait layout)
    private var tappedToFit = false

    /// Set by the call for the only remote tile of a 1:1 call in portrait: the tile is shaped like its video,
    /// and a tap switches the call to the portrait layout (the video fills the screen) and back
    var tapSwitchesToPortrait = false

    /// True while a tap has switched a 1:1 call to the portrait layout
    var isTappedToPortrait: Bool {
        return tappedToFit && tapSwitchesToPortrait && togglesFitOnTap && !portraitMode
    }

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

    /// A participant who publishes no video: a square tile, with the camera off overlay (the mic icon, or the muted mic)
    var showsNoVideoPlaceholder = false {
        didSet {
            guard showsNoVideoPlaceholder != oldValue else { return }
            updateFitTapGesture()
            //A tile without any stream yet has no overlay until now
            handleOverlay()
            //Square while it shows, the video's shape again after
            onVideoShapeChange?()
        }
    }

    /// True when the call should shape the tile like its video, fitted inside the space its layout gives it (`layoutSlot`).
    /// The video still fills the tile, which then crops nothing. For screens and the AR pointer's tile (no black bars) unless zoomed in,
    /// off in PiP for tapped cameras. The no video placeholder is square, also off in PiP (togglesFitOnTap is on only in full screen).
    var followsVideoShape: Bool {
        if showsNoVideoPlaceholder { return togglesFitOnTap }
        guard hasVideoSize else { return false }
        return (fitsVideo && !isZoomed) || (togglesFitOnTap && !portraitMode && tappedToFit != tapSwitchesToPortrait)
    }

    /// The shape a tile that follows its video's shape takes: its video's, or square for the no video placeholder
    var videoShape: CGSize {
        return showsNoVideoPlaceholder ? CGSize(width: 1, height: 1) : size
    }

    /// True while pinched in. A zoomed in tile fills its whole slot, but shows (and is outlined) only where the zoomed video is.
    var isZoomed: Bool {
        return videoView.transform.a > optionsForZooming().minZoom
    }

    /// Called when the tile is zoomed in from unzoomed and back, so the call can switch it between its video's shape and its slot
    var onZoomChange: (() -> Void)?

    //isZoomed last reported through onZoomChange
    private var reportedZoomed = false

    /// Drawn around a camera tile whatever it shows (video, camera off, no video, loading), and around a screen
    /// while it shows (from its first frame), never around its empty space
    var videoBorder: (color: UIColor, width: CGFloat)? {
        didSet {
            updateBorderAndClip()
        }
    }

    //While zoomed in the border is drawn around the visible video instead of the tile's edge
    private let zoomedBorder = CAShapeLayer()

    /// The space the call's layout gives a tile that follows its video's shape. Owned by the tile's superview.
    let layoutSlot = UILayoutGuide()

    private lazy var fitTapGesture = UITapGestureRecognizer(target: self, action: #selector(fitTapped))

    /// The whole video shows (aspect fit) for screens and while the AR pointer points at the tile, so nothing pointed at is cropped
    private var fitsVideo: Bool {
        return isScreen || annotationSurface != nil
    }

    /// Off for portrait videos, and for screens and the AR pointer's tile, which always fit
    /// (so the tap never competes with the annotation surface's own taps), and without a video
    private func updateFitTapGesture() {
        fitTapGesture.isEnabled = togglesFitOnTap && !portraitMode && !isScreen && annotationSurface == nil && !showsNoVideoPlaceholder
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
        //Zoomed with the video
        surface.transform = videoView.transform
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
                
        //Through bounds and center, so a zoomed (transformed) video keeps its zoom
        videoView.bounds = CGRect(origin: .zero, size: bounds.size)
        videoView.center = CGPoint(x: bounds.midX, y: bounds.midY)

        if let surface = annotationSurface {
            let rect = videoContentRect
            surface.bounds = CGRect(origin: .zero, size: rect.size)
            surface.center = CGPoint(x: rect.midX, y: rect.midY)
        }

        //The tile may have been reshaped, keep the zoomed video covering it
        clampZoom()
        updateBorderAndClip()

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
            //After the reshape has started, so the border can wait for it
            self.updateBorderAndClip()
        }
    }
    
    public func viewForZooming() -> UIView {
        return videoView
    }
    
    public func optionsForZooming() -> ZoomableViewOptions {
        return ZoomableViewOptions(minZoom: 1, maxZoom: 8)
    }

    public func contentRectForZooming() -> CGRect {
        return videoContentRect
    }

    public func zoomDidChange() {
        updateBorderAndClip()
        if isZoomed != reportedZoomed {
            reportedZoomed = isZoomed
            onZoomChange?()
        }
    }

    /// Outlines the tile (a screen while it shows). Clips the zoomed in tile to the part of its slot the zoomed video covers,
    /// rounded and outlined like the tile.
    private func updateBorderAndClip() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        //A screen from when the call was told its shape (not hasVideoSize, which the first frame sets off the main thread before that)
        let showsBorder = !isScreen || (reportedAspect > 0 && hasVideoStream)
        var borderWidth = showsBorder ? videoBorder?.width ?? 0 : 0
        layer.borderColor = videoBorder?.color.cgColor

        //A border appearing while the tile is reshaped (to its video's shape at the first frame) would follow it,
        //so it appears once the tile has its shape
        if borderWidth > 0 && layer.borderWidth == 0 && !isZoomed && isBeingReshaped {
            borderWidth = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.updateBorderAndClip()
            }
        }

        guard isZoomed else {
            layer.mask = nil
            zoomedBorder.removeFromSuperlayer()
            layer.borderWidth = borderWidth
            return
        }

        //The video's rect, zoomed around the video view's centre
        let center = videoView.center
        let visible = videoContentRect
            .offsetBy(dx: -center.x, dy: -center.y)
            .applying(videoView.transform)
            .offsetBy(dx: center.x, dy: center.y)
            .intersection(bounds)
        guard !visible.isNull else { return }

        layer.borderWidth = 0
        let mask = layer.mask as? CAShapeLayer ?? CAShapeLayer()
        mask.path = UIBezierPath(roundedRect: visible, cornerRadius: layer.cornerRadius).cgPath
        layer.mask = mask

        zoomedBorder.path = UIBezierPath(roundedRect: visible.insetBy(dx: borderWidth / 2, dy: borderWidth / 2),
                                         cornerRadius: max(0, layer.cornerRadius - borderWidth / 2)).cgPath
        zoomedBorder.lineWidth = borderWidth
        zoomedBorder.strokeColor = layer.borderColor
        zoomedBorder.fillColor = nil
        //Over the video and the annotations
        zoomedBorder.zPosition = 1000
        if zoomedBorder.superlayer == nil {
            layer.addSublayer(zoomedBorder)
        }
    }

    /// True while what is on screen hasn't reached the tile's size and position yet (an animation runs, or it is still to start)
    private var isBeingReshaped: Bool {
        guard let shown = layer.presentation() else { return false }
        return abs(shown.bounds.width - layer.bounds.width) > 0.5 || abs(shown.bounds.height - layer.bounds.height) > 0.5
            || abs(shown.position.x - layer.position.x) > 0.5 || abs(shown.position.y - layer.position.y) > 0.5
            || !(layer.animationKeys() ?? []).filter { $0.hasPrefix("bounds") || $0.hasPrefix("position") }.isEmpty
    }

    public func viewsZoomingAlong() -> [UIView] {
        return annotationSurface.map { [$0] } ?? []
    }

    /// While annotating, touches draw and point instead of zooming
    public func canZoom() -> Bool {
        return annotationSurface?.isAnnotating != true
    }
    
}
