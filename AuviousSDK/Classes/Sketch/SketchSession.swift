//
//  SketchSession.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import UIKit
import SwiftyJSON
import os

/**
 Speaks the web sketch protocol on behalf of the customer:
 - discovers agent-started sketches through SKETCH / AR_POINTER / AR_POINTER_COLORS conference metadata
   (or a SketchAvailabilityChangedEvent),
 - joins them with `PUT api/sketch/{id}` and broadcasts finished items with `POST api/sketch/{id}`,
 - applies SketchCanvasUpdatedEvent operations and answers SketchUserJoinedEvent with our own items.

 Laser points are not part of the sketch: `ArPointerSession` renders those.

 Customer ink is always kept locally (it is visible in the screen share either way) and is only posted
 while a sketch is joined.
 */
internal final class SketchSession {

    private let canvas: SketchCanvasView

    /// The annotated stream. Nil means our own shared screen, whatever its correlation id (co-browse).
    var target: (endpointId: String, correlationId: String?)?

    /// Called when our claimed ink color changes
    var onInkColorChanged: ((UIColor) -> Void)?

    /// Our RTC identity (userId, userEndpointId)
    var identity: () -> (userId: String, endpointId: String)? = {
        guard let userId = AuviousConferenceSDK.sharedInstance.currentUserId,
              let endpointId = AuviousConferenceSDK.sharedInstance.userEndpointId else {
            return nil
        }
        return (userId, endpointId)
    }

    /// The sketch we are a member of
    private(set) var sketchId: String?
    private var version: Int?
    private var joiningSketchId: String?
    private var colorClaims: [String: String] = [:]

    /// Our ink color as the web writes it, sent with our laser points
    private(set) var inkHex: String = SketchGeometry.fallbackColor

    private(set) var inkColor: UIColor = SketchGeometry.color(hex: SketchGeometry.fallbackColor)! {
        didSet {
            onInkColorChanged?(inkColor)
        }
    }

    init(canvas: SketchCanvasView) {
        self.canvas = canvas

        canvas.localIdentity = { [weak self] in
            return self?.identity()
        }
        canvas.onLocalItemCreated = { [weak self] item in
            self?.post([SketchOperation.created(item)])
        }
        canvas.inkColor = inkColor
    }

    //MARK: Discovery

    /// Conference metadata received with the join response (late join)
    func applyJoinMetadata(_ values: [String: String]) {
        if let colors = values[ConferenceMetadataKey.arPointerColors] {
            metadataChanged(key: ConferenceMetadataKey.arPointerColors, operation: .set, rawValue: colors)
        }
        if let sketch = values[ConferenceMetadataKey.sketch] {
            metadataChanged(key: ConferenceMetadataKey.sketch, operation: .set, rawValue: sketch)
        }
    }

    func metadataChanged(key: String, operation: MetadataRequestOperation?, rawValue: String?) {
        switch key {
        case ConferenceMetadataKey.arPointerColors:
            colorClaims = [:]
            if operation != .remove, let raw = rawValue {
                for (endpointId, color) in JSON(parseJSON: raw)["colorClaims"].dictionaryValue {
                    if let hex = color.string {
                        colorClaims[endpointId] = hex
                    }
                }
            }
            updateInkColor()

        case ConferenceMetadataKey.arPointer:
            //The AR session (and its sketch) ended
            if operation == .remove {
                leave()
            }

        case ConferenceMetadataKey.sketch:
            guard operation != .remove, let raw = rawValue else {
                leave()
                return
            }

            guard let target = targetFilter() else { return }

            //Always one entry: { "<sketchId>": { enabled, target: { endpoint, username }, mediaType, correlationId } }
            let entry = JSON(parseJSON: raw).dictionaryValue.first { _, value in
                guard value["enabled"].boolValue, value["target"]["endpoint"].stringValue == target.endpointId else { return false }
                guard let correlationId = target.correlationId, let entryCorrelationId = value["correlationId"].string else { return true }
                return entryCorrelationId == correlationId
            }

            if let (id, _) = entry {
                join(id)
            } else {
                leave()
            }

        default:
            break
        }
    }

    //MARK: Incoming events

    func userEventReceived(_ type: RtcUserEventType, json: JSON) {
        guard let me = identity() else { return }

        switch type {
        case .sketchCanvasUpdated:
            guard let sketchId = sketchId, eventSketchId(json) == sketchId else { return }

            let events = json["payload"]["events"].array ?? json["events"].arrayValue
            let operations = SketchCodec.decodeOperations(from: events.compactMap { try? $0.rawData() })
            apply(operations, myEndpointId: me.endpointId)

        case .sketchUserJoined:
            guard let sketchId = sketchId, eventSketchId(json) == sketchId else { return }

            let joiner = json["payload"]["userEndpointId"].exists() ? json["payload"] : json
            guard let userId = joiner["userId"].string,
                  let endpointId = joiner["userEndpointId"].string,
                  endpointId != me.endpointId else { return }

            //Late joiners get everyone's items from their authors
            let mine = canvas.items(ownedBy: me.endpointId).map { SketchOperation.created($0) }
            if !mine.isEmpty {
                post(mine, target: (userId, endpointId))
            }

        case .sketchAvailabilityChanged:
            if let target = json["targetEndpointId"].string, target != targetFilter()?.endpointId {
                return
            }
            guard let connectionId = json["connectionId"].string else { return }

            if json["available"].boolValue {
                join(connectionId)
            } else if connectionId == sketchId {
                leave()
            }

        default:
            break
        }
    }

    private func targetFilter() -> (endpointId: String, correlationId: String?)? {
        if let target = target {
            return target
        }
        return identity().map { ($0.endpointId, nil) }
    }

    private func eventSketchId(_ json: JSON) -> String? {
        return json["sketchId"].string ?? json["payload"]["sketchId"].string
    }

    private func apply(_ operations: [SketchOperation], myEndpointId: String) {
        for operation in operations {
            switch operation {
            case .markerCreated(let item), .arrowCreated(let item):
                //Our own items are already on the canvas
                guard item.itemData?.userEndpointId != myEndpointId else { continue }
                canvas.add(item)
            case .erased(let references):
                references.forEach { canvas.remove(id: $0.id) }
            case .cleared:
                canvas.removeAll()
            }
        }
    }

    //MARK: Customer actions

    /// Removes the customer's most recent item
    func undo() {
        guard let me = identity(), let last = canvas.lastItemData(ownedBy: me.endpointId) else { return }
        canvas.remove(id: last.id)
        post([.erased([SketchErasedReference(id: last.id, userId: last.userId, userEndpointId: last.userEndpointId)])])
    }

    /// Removes every drawing, everyone's (same as the web's clear)
    func clear() {
        canvas.removeAll()
        post([.cleared])
    }

    /// Leaves the sketch and removes the agent's drawings. The customer's own ink stays.
    func stop() {
        leave()
    }

    /// Leaves the sketch and removes every drawing locally, including the customer's own (nothing is broadcast)
    func reset() {
        stop()
        canvas.removeAll()
    }

    //MARK: Membership

    private func join(_ id: String, attempt: Int = 1) {
        guard sketchId != id else { return }
        if attempt == 1 && joiningSketchId == id { return }
        guard let me = identity() else { return }

        if sketchId != nil {
            leave()
        }
        joiningSketchId = id

        API2.sharedInstance.joinSketch(id, object: SketchMemberRequest(userId: me.userId, userEndpointId: me.endpointId), onSuccess: { [weak self] json in
            self?.didJoin(id, version: json?["version"].int)
        }, onFailure: { [weak self] error in
            guard let self = self, self.joiningSketchId == id else { return }

            //409 is returned both for a create/join race and when we are already a member
            if case AuviousSDKError.httpError(let code) = error, code == 409 {
                if attempt < 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * Double(attempt)) {
                        self.join(id, attempt: attempt + 1)
                    }
                } else {
                    self.didJoin(id, version: nil)
                }
                return
            }

            os_log("Sketch join failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
            self.joiningSketchId = nil
        })
    }

    private func didJoin(_ id: String, version: Int?) {
        guard joiningSketchId == id else { return }

        joiningSketchId = nil
        sketchId = id
        self.version = version
        os_log("Joined sketch %@", log: Log.conferenceSDK, type: .debug, id)

        //Share anything the customer drew before the agent started the sketch
        if let me = identity() {
            let mine = canvas.items(ownedBy: me.endpointId).map { SketchOperation.created($0) }
            if !mine.isEmpty {
                post(mine)
            }
        }
    }

    private func leave() {
        joiningSketchId = nil
        guard sketchId != nil else { return }

        sketchId = nil
        version = nil

        let myEndpointId = identity()?.endpointId
        canvas.removeAll { $0.userEndpointId != myEndpointId }
    }

    //MARK: Broadcast

    private func post(_ operations: [SketchOperation], target: (userId: String, endpointId: String)? = nil, attempt: Int = 1) {
        guard let sketchId = sketchId, let me = identity(), !operations.isEmpty else { return }

        var payload: [String: Any] = ["events": SketchCodec.jsonObjects(for: operations)]
        if let target = target {
            payload["target"] = ["userId": target.userId, "userEndpointId": target.endpointId]
        }

        var body: [String: Any] = ["userId": me.userId, "userEndpointId": me.endpointId, "payload": payload]
        if let version = version {
            body["version"] = version
        }

        API2.sharedInstance.broadcastSketch(sketchId, body: body, onSuccess: { _ in }, onFailure: { [weak self] error in
            //Retry server errors and throttling, like the web client
            var retryable = true
            if case AuviousSDKError.httpError(let code) = error {
                retryable = code == 0 || code == 429 || code >= 500
            }

            guard retryable, attempt < 3, let self = self, self.sketchId == sketchId else {
                os_log("Sketch broadcast failed %@", log: Log.conferenceSDK, type: .error, error.localizedDescription)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(attempt)) {
                self.post(operations, target: target, attempt: attempt + 1)
            }
        })
    }

    //MARK: Colors

    private func updateInkColor() {
        if let me = identity()?.endpointId, let hex = colorClaims[me], let color = SketchGeometry.color(hex: hex) {
            inkHex = hex
            inkColor = color
        } else {
            //No claim for us: take the first free color, preferring ones that don't clash with the red sharing border
            let claimed = Set(colorClaims.values.map { $0.uppercased() })
            let hex = SketchGeometry.customerFallbackOrder.first { !claimed.contains($0.uppercased()) } ?? SketchGeometry.fallbackColor
            inkHex = hex
            inkColor = SketchGeometry.color(hex: hex) ?? inkColor
        }
        canvas.inkColor = inkColor
    }
}
