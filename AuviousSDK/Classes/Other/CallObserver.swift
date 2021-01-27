//
//  CallObserver.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 02/09/2019.
//  Copyright © 2019 Auvious. All rights reserved.
//

import Foundation
import CallKit
import os

internal final class CallObserver: NSObject, CXCallObserverDelegate {
    
    var callObserver: CXCallObserver? = nil
    
    func start(){
        if callObserver == nil {
            os_log("Started call monitoring", log: Log.callObserver, type: .debug)
            callObserver = CXCallObserver()
            callObserver!.setDelegate(self, queue: nil)
        }
    }
    
    func stop(){
        callObserver = nil
    }
    
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        
        if call.hasEnded   == true && call.isOutgoing == false || // incoming end
            call.hasEnded   == true && call.isOutgoing == true {   // outgoing end
            os_log("Disconnected", log: Log.callObserver, type: .debug)
        }
        
        if call.isOutgoing == true && call.hasConnected == false && call.hasEnded == false {
            os_log("Dialing", log: Log.callObserver, type: .debug)
        }
        
        if call.isOutgoing == false && call.hasConnected == false && call.hasEnded == false {
            os_log("Incoming", log: Log.callObserver, type: .debug)
        }
        
        if call.hasConnected == true && call.hasEnded == false {
            os_log("Connected", log: Log.callObserver, type: .debug)
            AuviousCallSDK.sharedInstance.onApplicationPause()
        }
    }
}
