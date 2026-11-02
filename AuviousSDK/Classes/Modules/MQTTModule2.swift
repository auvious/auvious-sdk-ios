//
//  MQTTModule2.swift
//  AuviousSDK
//
//  Created by Jason Kritikos on 24/2/25.
//

import Foundation
import CocoaMQTTWebsocket_IOS13
import SwiftyJSON
import os

internal protocol MQTTConferenceDelegate {
    
    func conferenceMessageReceived(_ object: ConferenceEvent)
}

internal protocol MQTTUserEventDelegate: AnyObject {

    func userEventReceived(_ type: RtcUserEventType, json: JSON)
}

internal final class MQTTModule2: CocoaMQTTDelegate {

    // Singleton instance
    public static let sharedInstance = MQTTModule2()
    
    //Internal properties
    private var mqtt: CocoaMQTT!

    /// Lost since it last connected, so a new subscription is a reconnect
    private var lostConnection = false

    /// We disconnected to reconnect with new credentials; CocoaMQTT doesn't reconnect after a disconnect of ours
    private var reconnectAfterDisconnect = false

    /// Called once the connection is back after a drop and the topic is subscribed again
    var onReconnected: (() -> Void)?
    private var endpointId: String!
    private var subscriptionCallback: (()->())?
    
    //Delegates
    var conferenceDelegate: MQTTConferenceDelegate?
    weak var userEventDelegate: MQTTUserEventDelegate?

    func configure(endpointId: String) {
        self.endpointId = endpointId
    }
    
    internal func clearSubscriptionCallback(){
        subscriptionCallback = nil
    }
    
    func connect(onSubscription:(()->())? = nil) {
        if let closure = onSubscription {
            self.subscriptionCallback = closure
        }
        
        let clientID = "CocoaMQTT-" + String(ProcessInfo().processIdentifier)
        let websocket = CocoaMQTTWebSocket(uri: "/ws")
        websocket.enableSSL = true
        self.mqtt = CocoaMQTT(clientID: clientID, host: ServerConfiguration.mqttHost, port: 443, socket: websocket)
        self.mqtt.username = ServerConfiguration.mqttUser
        self.mqtt.password = ServerConfiguration.mqttPass
        self.mqtt.allowUntrustCACertificate = true
        self.mqtt.enableSSL = true
        self.mqtt.autoReconnect = true
        //Retries back off from 1s; during a call 30s is the longest worth waiting
        self.mqtt.maxAutoReconnectTimeInterval = 30
        self.mqtt.delegate = self
        _ = self.mqtt.connect()
        
        print("MQTT2 connect()")
    }
    
    /// Clean disconnect — will not auto-reconnect.
    func disconnect() {
        os_log("MQTT2 disconnecting (permanent)", log: Log.mqtt, type: .debug)
        self.mqtt.autoReconnect = false
        self.mqtt.disconnect()
    }

    /// Disconnect and reconnect with updated credentials (used by token refresh).
    func disconnectAndReconnect() {
        os_log("MQTT2 disconnecting (will reconnect)", log: Log.mqtt, type: .debug)
        reconnectAfterDisconnect = true
        refreshCredentials()
        self.mqtt.disconnect()
    }

    func reconnect() {
        os_log("MQTT2 reconnect called", log: Log.mqtt, type: .debug)
        guard mqtt != nil else { return }
        switch mqtt.connState {
        case .connected:
            os_log("MQTT2 session status CONNECTED - no need to reconnect", log: Log.mqtt, type: .debug)
        case .connecting:
            os_log("MQTT2 session status CONNECTING - no need to reconnect", log: Log.mqtt, type: .debug)
        default:
            os_log("MQTT2 reconnecting", log: Log.mqtt, type: .debug)
            refreshCredentials()
            _ = mqtt.connect()
        }
    }

    /// The broker password is the access token, so the client must pick up the latest one
    /// after a token refresh — otherwise reconnects keep sending the expired login token.
    private func refreshCredentials() {
        self.mqtt.username = ServerConfiguration.mqttUser
        self.mqtt.password = ServerConfiguration.mqttPass
    }
    
    private func subscribeForUserEndpoint() {
        let topic = "user/\(ServerConfiguration.mqttUser)/\(self.endpointId ?? "unknown")"
        print("MQTT2 subscribing to topic \(topic)")
        self.mqtt.subscribe(topic, qos: CocoaMQTTQoS.qos1)
    }
 
    //MARK: MQTT Delegation
    
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("MQTT2 didConnectAck \(ack)")
        if ack == .accept {
            subscribeForUserEndpoint()
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        os_log("MQTT received message:", log: Log.mqtt, type: .debug)
        if let payload = message.string {
            let jsonObject = JSON(parseJSON: payload)
            os_log("%@", log: Log.mqtt, type: .debug, jsonObject.debugDescription)

            //User events (co-browse, sketch, laser) are not conference versioned, route them directly
            if let userEventType = RtcUserEventType(rawValue: jsonObject["type"].stringValue) {
                userEventDelegate?.userEventReceived(userEventType, json: jsonObject)
                return
            }

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
                
            } else {
                os_log("MQTT message with unknown type %@", log: Log.mqtt, type: .debug, jsonObject["type"].stringValue)
                let model: ConferenceEvent = ConferenceEvent(fromJson: jsonObject)
                conferenceDelegate?.conferenceMessageReceived(model)
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        print("MQTT2 didSubscribeTopics \(success)")
        
        if !success.allKeys.isEmpty {
            //Notify the SDK of the topic subcription
            if let closure = subscriptionCallback {
                closure()
            }
            if lostConnection {
                lostConnection = false
                onReconnected?()
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: (any Error)?) {
        print("MQTT2 mqttDidDisconnect (autoReconnect=\(mqtt.autoReconnect), error=\(err.map { String(describing: $0) } ?? "none"))")
        guard mqtt.autoReconnect else { return }
        lostConnection = true
        //A lost connection is retried by CocoaMQTT, backing off up to maxAutoReconnectTimeInterval, and right away
        //once the device is back online (AuviousConferenceSDK's network monitor). Retrying here as well spun
        //thousands of times a minute while offline, each attempt failing at once
        if reconnectAfterDisconnect {
            reconnectAfterDisconnect = false
            self.reconnect()
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        print("MQTT2 didStateChangeTo \(state.description)")
    }
}
