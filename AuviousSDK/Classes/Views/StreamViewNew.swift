//
//  StreamViewNew.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 26/9/20.
//

import Foundation

class StreamViewNew: UIView, RTCVideoViewDelegate {
    
    var videoTrack: RTCVideoTrack!
    
    //Switch from OpenGL to Metal if we can
    #if arch(i386) || arch(x86_64) || arch(arm)
    let supportsMetal: Bool = false
    var videoView: RTCEAGLVideoView = RTCEAGLVideoView(frame: CGRect.zero)
    #else
    let supportsMetal: Bool = true
    var videoView: RTCMTLVideoView = RTCMTLVideoView(frame: CGRect.zero)
    #endif
    
    private var hasAudioStream: Bool = false
    private var hasVideoStream: Bool = false
    
    public func audioStreamAdded() {
        hasAudioStream = true
        
        if !hasVideoStream {
            //statusLabel.text = "Audio only"
            //statusLabel.alpha = 1.0
        }
    }
    
    public func audioStreamRemoved() {
        hasAudioStream = false
        
        if !hasVideoStream {
            resetStreamView()
        }
    }
    
    public func videoStreamAdded(_ videoTrack:RTCVideoTrack){
        hasVideoStream = true
        
        //statusLabel.alpha = 0.0
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
//            statusLabel.text = "Audio only"
//            statusLabel.alpha = 1.0
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
        
//        statusLabel.alpha = 0.0
        videoView.alpha = 0.0
        
        if videoTrack != nil {
            videoTrack.remove(videoView)
        }
    }
    
    //MARK: RTCVideoViewDelegate
    
    public func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        //self.size = size
    }
    
}
