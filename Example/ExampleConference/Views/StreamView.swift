//
//  StreamView.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 14/01/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import UIKit
import AuviousSDK

class StreamView: UIView {
    
    //UI components
    @IBOutlet weak var statusLabel: UILabel!
    //@IBOutlet weak var videoView: RTCMTLVideoView!
    var videoTrack:RTCVideoTrack!
    
    //Switch from OpenGL to Metal if we can
    #if arch(i386) || arch(x86_64) || arch(arm)
    let supportsMetal:Bool = false
    var videoView:RTCEAGLVideoView = RTCEAGLVideoView(frame: CGRect.zero)
    #else
    let supportsMetal:Bool = true
    var videoView:RTCMTLVideoView = RTCMTLVideoView(frame: CGRect.zero)
    #endif
    
    private var hasAudioStream:Bool = false
    private var hasVideoStream:Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        nibSetup()
    }
    
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
        
        nibSetup()
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }
    
    private func nibSetup() {
        backgroundColor = .clear
        
        videoView.frame = bounds
        
        let view = loadViewFromNib()
        view.frame = bounds
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
    
    func audioStreamAdded(){
        hasAudioStream = true
        
        if !hasVideoStream {
            statusLabel.text = "Audio only"
            statusLabel.alpha = 1.0
        }
    }
    
    func audioStreamRemoved(){
        hasAudioStream = false
        
        if !hasVideoStream {
            resetStreamView()
        }
    }
    
    func videoStreamAdded(_ videoTrack:RTCVideoTrack){
        hasVideoStream = true
        
        statusLabel.alpha = 0.0
        self.videoTrack = videoTrack
        self.videoTrack.add(videoView)
        videoView.frame = bounds
        videoView.alpha = 1.0
    }
    
    func videoStreamRemoved(){
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
    
    func avStreamAdded(_ videoTrack:RTCVideoTrack){
        videoStreamAdded(videoTrack)
        hasAudioStream = true
    }
    
    func avStreamRemoved(){
        resetStreamView()
    }
    
    func resetStreamView(){
        hasAudioStream = false
        hasVideoStream = false
        
        statusLabel.alpha = 0.0
        videoView.alpha = 0.0
        
        if videoTrack != nil {
            videoTrack.remove(videoView)
        }
    }
}
