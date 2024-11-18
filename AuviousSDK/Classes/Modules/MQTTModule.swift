//
//  MQTTClient.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 04/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON
import os

internal protocol MQTTConferenceDelegate {
    
    func conferenceMessageReceived(_ object: ConferenceEvent)
}

internal protocol MQTTCallDelegate {
    
    func callMessageReceived(_ object: CallEvent)
}

internal protocol MQTTSnapshotDelegate {
    
    func snapshotMessageReceived(_ object: SnapshotEvent)
}

internal final class MQTTModule: NSObject, MQTTSessionDelegate {
    
    /// Singleton instance
    public static let sharedInstance = MQTTModule()
    
    //Configuration
    //private let mqttQueue = DispatchQueue(label: "gr.auvious.mqttQueue", attributes: .concurrent)
    private let keepAliveSeconds: UInt16 = UInt16(55)
    private var endpointId: String!
    
    private var transport: MQTTWebsocketTransport!
    private var session: MQTTSession!
    
    private var subscriptionCallback: (()->())?
    
    //Delegates
    var callDelegate: MQTTCallDelegate?
    var conferenceDelegate: MQTTConferenceDelegate?
    var snapshotDelegate: MQTTSnapshotDelegate?
    
    func configure(endpointId: String) {
        self.endpointId = endpointId
    }
    
    internal func clearSubscriptionCallback(){
        subscriptionCallback = nil
    }
    
    //Accept an optional closure to be called upon succesfull subscription to our topic
    func connect(onSubscription:(()->())? = nil) {
        if let closure = onSubscription {
            self.subscriptionCallback = closure
        }
        
        self.transport = MQTTWebsocketTransport()
        self.transport.url = URL(string: ServerConfiguration.mqttHost)
        self.transport.allowUntrustedCertificates = true
        self.transport.tls = true
        
        self.session = MQTTSession()
        self.session.clientId = UUID().uuidString
        self.session.userName = ServerConfiguration.mqttUser
        self.session.password = ServerConfiguration.mqttPass
        self.session.keepAliveInterval = keepAliveSeconds
        //TODO: WHY DOES THIS BREAK EVERYTHING????
        //session.queue = mqttQueue
        
        self.session.cleanSessionFlag = false
        self.session!.transport = self.transport
        self.session!.delegate = self
        self.session!.connect()
    }
    
    func disconnect() {
        os_log("MQTT disconnecting", log: Log.mqtt, type: .debug)
        self.session.userName = ServerConfiguration.mqttUser
        self.session.disconnect()
    }
    
    func reconnect() {
        os_log("MQTT reconnect called", log: Log.mqtt, type: .debug)
        
        switch session.status {
        case .connected:
            os_log("MQTT session status CONNECTED - no need to reconnect", log: Log.mqtt, type: .debug)
        case .connecting:
            os_log("MQTT session status CONNECTING - no need to reconnect", log: Log.mqtt, type: .debug)
        default:
            os_log("MQTT reconnecting", log: Log.mqtt, type: .debug)
            session.connect()
        }
    }
    
    func subscribeForUserEndpoint() {
        let topic = "user/\(ServerConfiguration.mqttUser)/\(self.endpointId ?? "unknown")"
        self.session.subscribe(toTopic: topic, at: .atLeastOnce)
    }

    //MARK: Session Delegation
    
    func connected(_ session: MQTTSession!) {
        os_log("MQTT connected", log: Log.mqtt, type: .debug)
        subscribeForUserEndpoint()
    }
    
    func newMessage(_ session: MQTTSession!, data: Data!, onTopic topic: String!, qos: MQTTQosLevel, retained: Bool, mid: UInt32) {
        os_log("MQTT received message:", log: Log.mqtt, type: .debug)
        
        do {
            let jsonObject = try JSON(data: data)
            os_log("%@", log: Log.mqtt, type: .debug, jsonObject.debugDescription)
            
            if let eventType = ConferenceEventType(rawValue: jsonObject["type"].stringValue) {
                
                var model: ConferenceEvent!
                
                switch eventType {
                case .conferenceEnded:
                    model = ConferenceEndedEvent(fromJson: jsonObject)
                case .conferenceJoined:
                    model = ConferenceJoinedEvent(fromJson: jsonObject)
                case .conferenceLeft:
                    model = ConferenceLeftEvent(fromJson: jsonObject)
                case .conferenceStreamPublished:
                    model = ConferenceStreamPublishedEvent(fromJson: jsonObject)
                case .conferenceStreamUnpublished:
                    model = ConferenceStreamUnpublishedEvent(fromJson: jsonObject)
                case .conferenceMetadataUpdatedEvent:
                    model = ConferenceMetadataUpdatedEvent(fromJson: jsonObject)
                case .conferenceNetworkIndicatorEvent:
                    model = ConferenceNetworkIndicatorEvent(fromJson: jsonObject)
                case .conferenceStreamMetadataUpdatedEvent:
                    model = ConferenceStreamMetadataUpdatedEvent(fromJson: jsonObject)
                default:
                    break
                }
                
                conferenceDelegate?.conferenceMessageReceived(model)
                
            } else if let eventType = CallEventType(rawValue: jsonObject["type"].stringValue) {
                var model: CallEvent!
                
                switch eventType {
                case .callAnswered:
                    model = CallAnsweredEvent(fromJson: jsonObject)
                case .callEnded:
                    model = CallEndedEvent(fromJson: jsonObject)
                case .callCreated:
                    model = CallCreatedEvent(fromJson: jsonObject)
                case .callRinging:
                    model = CallRingingEvent(fromJson: jsonObject)
                case .callRejected:
                    model = CallRejectedEvent(fromJson: jsonObject)
                case .callCancelled:
                    model = CallCancelledEvent(fromJson: jsonObject)
                case .callIceCandidatesFound:
                    model = IceCandidatesFoundEvent(fromJson: jsonObject)
                }
                
                callDelegate?.callMessageReceived(model)
                
            } else if let eventType = SnapshotEventType(rawValue: jsonObject["type"].stringValue) {
                var model: SnapshotEvent!
                
                switch eventType {
                case .snapshotAcquiredEvent:
                    model = SnapshotAcquiredEvent(fromJson: jsonObject)
                case .snapshotApprovedEvent:
                    model = SnapshotApprovedEvent(fromJson: jsonObject)
                case .snapshotCameraRequestedEvent:
                    model = SnapshotCameraRequestedEvent(fromJson: jsonObject)
                case .snapshotCameraRequestProcessedEvent:
                    model = SnapshotCameraRequestProcessedEvent(fromJson: jsonObject)
                case .snapshotRequestedEvent:
                    model = SnapshotRequestedEvent(fromJson: jsonObject)
                }
                
                snapshotDelegate?.snapshotMessageReceived(model)
                
            } else {
                os_log("MQTT message with unknown type %@", log: Log.mqtt, type: .debug, jsonObject["type"].stringValue)
                let model: ConferenceEvent = ConferenceEvent(fromJson: jsonObject)
                conferenceDelegate?.conferenceMessageReceived(model)
            }
            
        } catch {
            os_log("Error creating JSON object for MQTT message", log: Log.mqtt, type: .error)
        }
    }
    
    func connectionError(_ session: MQTTSession!, error: Error!) {
        os_log("MQTT connection error", log: Log.mqtt, type: .error, error.localizedDescription)
    }
    
    func connectionRefused(_ session: MQTTSession!, error: Error!) {
        os_log("MQTT connection refused! Error", log: Log.mqtt, type: .error, error.localizedDescription)
    }
    
    func connectionClosed(_ session: MQTTSession!) {
        os_log("MQTT connection closed", log: Log.mqtt, type: .debug)
        if AuviousConferenceSDK.sharedInstance.isLoggedIn {
            reconnect()
        }
    }
    
    func connected(_ session: MQTTSession!, sessionPresent: Bool) {
        //os_log("MQTT connected, sessionPresent %@", log: Log.mqtt, type: .debug, sessionPresent)
    }
    
    func handleEvent(_ session: MQTTSession!, event eventCode: MQTTSessionEvent, error: Error!) {
        //os_log("MQTT handle event with code %@", log: Log.mqtt, type: .debug, eventCode.rawValue)
    }
    
    func protocolError(_ session: MQTTSession!, error: Error!) {
        os_log("MQTT protocol error %@", log: Log.mqtt, type: .error, error.localizedDescription)
    }
    
    func unsubAckReceived(_ session: MQTTSession!, msgID: UInt16) {
        os_log("MQTT unsubAckReceived", log: Log.mqtt, type: .debug)
    }
    
    func subAckReceived(_ session: MQTTSession!, msgID: UInt16, grantedQoss qoss: [NSNumber]!) {
        os_log("MQTT subAckReceived", log: Log.mqtt, type: .debug)
        
        //Notify the SDK of the topic subcription
        if let closure = subscriptionCallback {
            closure()
        }
    }
    
    func session(_ session: MQTTSession!, handle eventCode: MQTTSessionEvent) {
    }
    
    func session(_ session: MQTTSession!, newMessage data: Data!, onTopic topic: String!) {
    }
}
