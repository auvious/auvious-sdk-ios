//
//  StreamView.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 14/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import UIKit

public class StreamView: UIView, RTCVideoViewDelegate {
    
    //UI components
    @IBOutlet weak var statusLabel: UILabel!
    //@IBOutlet weak var videoView: RTCMTLVideoView!
    var videoTrack:RTCVideoTrack!
    
    //Switch from OpenGL to Metal if we can
    #if arch(i386) || arch(x86_64) || arch(arm)
    let supportsMetal: Bool = false
    var videoView: RTCEAGLVideoView = RTCEAGLVideoView(frame: CGRect.zero)
    #else
    let supportsMetal: Bool = true
    var videoView:RTCMTLVideoView = RTCMTLVideoView(frame: CGRect.zero)
    #endif
    
    private var hasAudioStream:Bool = false
    private var hasVideoStream:Bool = false
    
    var size: CGSize = .zero
    
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
        view.layer.borderColor = UIColor.black.cgColor
        view.layer.borderWidth = 1.0
        addSubview(view)
        
        addSubview(videoView)
        
        #if arch(i386) || arch(x86_64) || arch(arm)
        #else
        videoView.videoContentMode = .scaleAspectFill
        #endif
        
        resetStreamView()
    }
    
    private func loadViewFromNib() -> UIView {
        let bundle = Bundle(for: type(of: self))
        let nib = UINib(nibName: String(describing: type(of: self)), bundle: bundle)
        let nibView = nib.instantiate(withOwner: self, options: nil).first as! UIView
        
        return nibView
    }
    
    public func audioStreamAdded(){
        hasAudioStream = true
        
        if !hasVideoStream {
            statusLabel.text = "Audio only"
            statusLabel.alpha = 1.0
        }
    }
    
    public func audioStreamRemoved(){
        hasAudioStream = false
        
        if !hasVideoStream {
            resetStreamView()
        }
    }
    
    public func videoStreamAdded(_ videoTrack:RTCVideoTrack){
        hasVideoStream = true
        
        statusLabel.alpha = 0.0
        self.videoTrack = videoTrack
        self.videoTrack.add(videoView)
        videoView.frame = bounds
        videoView.alpha = 1.0
    }
    
    public func videoStreamRemoved(){
        hasVideoStream = false
        
        videoView.alpha = 0.0
        if videoTrack != nil {
            self.videoTrack.remove(videoView)
        }
        self.videoTrack = nil
        
        if hasAudioStream {
            statusLabel.text = "Audio only"
            statusLabel.alpha = 1.0
        }
    }
    
    public func avStreamAdded(_ videoTrack:RTCVideoTrack){
        videoStreamAdded(videoTrack)
        hasAudioStream = true
    }
    
    public func avStreamRemoved(){
        resetStreamView()
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
}
