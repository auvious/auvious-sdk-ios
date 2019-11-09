//
//  MQTTClient.swift
//  AuviousSDK_Foundation
//
//  Created by Jason Kritikos on 04/12/2018.
//  Copyright © 2018 Auvious. All rights reserved.
//

import Foundation
import SwiftyJSON

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
        print("MQTT disconnecting")
        self.session.disconnect()
    }
    
    func reconnect() {
        print("MQTT reconnect called:")
        switch session.status {
        case .connected:
            print("MQTT session status CONNECTED - no need to reconnect")
        case .connecting:
            print("MQTT session status CONNECTING - no need to reconnect")
        default:
            print("MQTT session status \(session.status) - reconnecting")
            session.connect()
        }
        
    }
    
    func subscribeForUserEndpoint() {
        let topic = "users/endpoints/" + self.endpointId
        self.session.subscribe(toTopic: topic, at: .atLeastOnce)
    }

    //MARK: Session Delegation
    
    func connected(_ session: MQTTSession!) {
        print("*** MQTT connected")
        subscribeForUserEndpoint()
    }
    
    func newMessage(_ session: MQTTSession!, data: Data!, onTopic topic: String!, qos: MQTTQosLevel, retained: Bool, mid: UInt32) {
        print("*** MQTT received message:")
        
        do {
            let jsonObject = try JSON(data: data)
            print(jsonObject)
            
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
                print("MQTT message ignored - unknown type " + jsonObject["type"].stringValue)
            }
            
        } catch {
            print("Error creating JSON object for MQTT message")
        }
    }
    
    func connectionError(_ session: MQTTSession!, error: Error!) {
        print("*** MQTT connection error \(String(describing: error))")
    }
    
    func connectionRefused(_ session: MQTTSession!, error: Error!) {
        print("*** MQTT connection refused! Error \(String(describing: error))")
    }
    
    func connectionClosed(_ session: MQTTSession!) {
        print("*** MQTT connection closed")
    }
    
    func connected(_ session: MQTTSession!, sessionPresent: Bool) {
        print("*** MQTT connected, sessionPresent \(sessionPresent)")
    }
    
    func handleEvent(_ session: MQTTSession!, event eventCode: MQTTSessionEvent, error: Error!) {
        print("*** MQTT handle event with code \(eventCode.rawValue)")
    }
    
    func protocolError(_ session: MQTTSession!, error: Error!) {
        print("*** MQTT protocol error \(String(describing: error))")
    }
    
    func unsubAckReceived(_ session: MQTTSession!, msgID: UInt16) {
        print("*** MQTT unsubAckReceived")
    }
    
    func subAckReceived(_ session: MQTTSession!, msgID: UInt16, grantedQoss qoss: [NSNumber]!) {
        print("*** MQTT subAckReceived")
        
        //Notify the SDK of the topic subcription
        if let closure = subscriptionCallback {
            closure()
        }
    }
    
    func session(_ session: MQTTSession!, handle eventCode: MQTTSessionEvent) {
        print("**************** handle event")
    }
    
    func session(_ session: MQTTSession!, newMessage data: Data!, onTopic topic: String!) {
        print("**************** new msg")
    }
}
