//
//  ArPointerSession.swift
//  AuviousSDK
//
//  Created by Auvious on 22/10/26.
//

import UIKit
import SwiftyJSON
import os

/**
 Speaks the web AR pointer protocol on behalf of the customer, in a regular call:
 - learns that an agent pointed at a stream from the AR_POINTER conference metadata (removed when it stops),
 - renders the `ArPointerIndicatedEvent` points aimed at that stream and sends our own,
 - tracks the agent's frame freeze (`ArPointerFreezeFrameChangedEvent`, a toggle like on the web),
 - runs the sketch that comes with the pointer, scoped to the target stream.

 The target may be one of our streams (camera or screen share) or another participant's camera.
 The host attaches an `AnnotationSurfaceView` once it knows where the target is drawn.
 */
internal final class ArPointerSession {

    struct Target: Equatable {
        let userId: String
        let endpointId: String
        /// The web's stream type: "video" (mic and cam), "cam" or "screen"
        let streamType: String
        let correlationId: String

        var isScreen: Bool {
            return streamType.lowercased() == "screen"
        }
    }

    static let pointTimeToLive: TimeInterval = 5

    /// The stream being pointed at, nil while no AR pointer session runs
    private(set) var target: Target?

    /// The agent froze the target's frame
    private(set) var isFrozen = false

    /// Called on the main thread when the target or the frozen state changes
    var onChange: (() -> Void)?

    /// Called when our ink color changes
    var onInkColorChanged: ((UIColor) -> Void)?

    /// Our RTC identity (userId, userEndpointId)
    var identity: () -> (userId: String, endpointId: String)? = {
        guard let userId = AuviousConferenceSDK.sharedInstance.currentUserId,
              let endpointId = AuviousConferenceSDK.sharedInstance.userEndpointId else {
            return nil
        }
        return (userId, endpointId)
    }

    /// Everyone else in the conference, who our points are sent to
    var participants: () -> [RemoteParticipant] = {
        return Array(AuviousConferenceSDK.sharedInstance.remoteParticipants.values)
    }

    /// Delivers one user event
    var send: (SendEventRequest) -> Void = { request in
        API2.sharedInstance.sendEvent(request, onSuccess: { _ in }, onFailure: { error in
            sdkLog("AR pointer event failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
        })
    }

    private(set) var surface: AnnotationSurfaceView?
    private(set) var sketch: SketchSession?

    /// The latest SKETCH and AR_POINTER_COLORS values, replayed into the sketch once a surface is attached
    private var sketchMetadata: [String: String] = [:]
    private var pointIndex = 0

    var inkColor: UIColor {
        return sketch?.inkColor ?? SketchGeometry.color(hex: SketchGeometry.fallbackColor)!
    }

    //MARK: Signalling

    /// Conference metadata received with the join response (late join)
    func applyJoinMetadata(_ values: [String: String]) {
        for key in [ConferenceMetadataKey.arPointerColors, ConferenceMetadataKey.arPointer, ConferenceMetadataKey.sketch] {
            if let value = values[key] {
                metadataChanged(key: key, operation: .set, rawValue: value)
            }
        }
    }

    func metadataChanged(key: String, operation: MetadataRequestOperation?, rawValue: String?) {
        switch key {
        case ConferenceMetadataKey.arPointer:
            if operation == .remove {
                setTarget(nil)
            } else if let raw = rawValue {
                setTarget(ArPointerSession.target(from: JSON(parseJSON: raw)))
            }

        case ConferenceMetadataKey.sketch, ConferenceMetadataKey.arPointerColors:
            if operation == .remove {
                sketchMetadata[key] = nil
            } else {
                sketchMetadata[key] = rawValue
            }
            sketch?.metadataChanged(key: key, operation: operation, rawValue: rawValue)

        default:
            break
        }
    }

    func userEventReceived(_ type: RtcUserEventType, json: JSON) {
        switch type {
        case .arPointerIndicated:
            guard let target = target, isAimedAtTarget(json) else { return }
            let color = json["color"].string.flatMap { SketchGeometry.color(hex: $0) } ?? SketchGeometry.color(hex: SketchGeometry.fallbackColor)!
            surface?.laser.show(x: CGFloat(json["coordinates"]["x"].doubleValue),
                                y: CGFloat(json["coordinates"]["y"].doubleValue),
                                areaWidth: CGFloat(json["area"]["width"].doubleValue),
                                areaHeight: CGFloat(json["area"]["height"].doubleValue),
                                color: color,
                                index: json["index"].intValue,
                                ttl: json["ttl"].double ?? ArPointerSession.pointTimeToLive)
            sdkLog("AR pointer point on %@", log: Log.conferenceSDK, type: .debug, target.correlationId)

        case .arPointerFreezeFrameChanged:
            guard target != nil, isAimedAtTarget(json) else { return }
            isFrozen.toggle()
            onChange?()

        case .sketchCanvasUpdated, .sketchUserJoined, .sketchAvailabilityChanged:
            sketch?.userEventReceived(type, json: json)

        case .cobrowseDisplayCaptureRequest, .cobrowseDisplayCaptureTerminate:
            break
        }
    }

    private func isAimedAtTarget(_ json: JSON) -> Bool {
        guard let target = target else { return false }
        if let endpoint = json["targetUserEndpointId"].string, endpoint != target.endpointId {
            return false
        }
        if let correlationId = json["targetStreamCorrelationId"].string, correlationId != target.correlationId {
            return false
        }
        return true
    }

    static func target(from json: JSON) -> Target? {
        guard let endpointId = json["target"]["endpoint"].string,
              let correlationId = json["streamCorrelationId"].string else {
            return nil
        }
        return Target(userId: json["target"]["username"].stringValue,
                      endpointId: endpointId,
                      streamType: json["streamType"].stringValue,
                      correlationId: correlationId)
    }

    private func setTarget(_ newTarget: Target?) {
        guard newTarget != target else { return }

        detach()
        target = newTarget
        isFrozen = false
        pointIndex = 0
        if newTarget == nil {
            sketchMetadata[ConferenceMetadataKey.sketch] = nil
        }
        onChange?()
    }

    //MARK: Surface

    /// Draws the session on `surface` and starts its sketch, scoped to the target stream
    func attach(_ surface: AnnotationSurfaceView) {
        guard let target = target, self.surface !== surface else { return }

        detach()
        self.surface = surface

        let sketch = SketchSession(canvas: surface.canvas)
        sketch.identity = identity
        sketch.target = (target.endpointId, target.correlationId)
        sketch.onInkColorChanged = { [weak self] color in
            self?.onInkColorChanged?(color)
        }
        self.sketch = sketch
        //Colors first, so the ink is right before anything is drawn
        for key in [ConferenceMetadataKey.arPointerColors, ConferenceMetadataKey.sketch] {
            if let value = sketchMetadata[key] {
                sketch.metadataChanged(key: key, operation: .set, rawValue: value)
            }
        }
        onInkColorChanged?(sketch.inkColor)

        surface.onPoint = { [weak self] location, area in
            self?.point(at: location, area: area)
        }
    }

    /// Stops drawing on the current surface and clears it
    func detach() {
        sketch?.reset()
        sketch = nil
        surface?.onPoint = nil
        surface?.laser.clear()
        surface = nil
    }

    //MARK: Customer actions

    /// Places one of our points, in the surface's own coordinates
    func point(at location: CGPoint, area: CGSize) {
        guard let target = target, let me = identity(), area.width > 0, area.height > 0 else { return }

        pointIndex += 1
        let hex = sketch?.inkHex ?? SketchGeometry.fallbackColor
        surface?.laser.show(x: location.x, y: location.y, areaWidth: area.width, areaHeight: area.height,
                            color: inkColor, index: pointIndex, ttl: ArPointerSession.pointTimeToLive)

        let event = ArPointerSession.indicatedEvent(target: target, location: location, area: area, index: pointIndex, color: hex)
        for participant in participants() where participant.endpointId != me.endpointId {
            send(SendEventRequest(userId: participant.userId, userEndpointId: participant.endpointId, event: event))
        }
    }

    func undo() {
        sketch?.undo()
    }

    func clear() {
        sketch?.clear()
    }

    static func indicatedEvent(target: Target, location: CGPoint, area: CGSize, index: Int, color: String) -> [String: Any] {
        return [
            "type": RtcUserEventType.arPointerIndicated.rawValue,
            "timestamp": timestampFormatter.string(from: Date()),
            "targetUserId": target.userId,
            "targetUserEndpointId": target.endpointId,
            "targetStreamType": target.streamType,
            "targetStreamCorrelationId": target.correlationId,
            "coordinates": ["x": Double(location.x), "y": Double(location.y)],
            "area": ["width": Double(area.width), "height": Double(area.height)],
            "index": index,
            "ttl": Int(pointTimeToLive),
            "color": color
        ]
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
