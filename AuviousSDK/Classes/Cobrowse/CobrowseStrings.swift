//
//  CobrowseStrings.swift
//  AuviousSDK
//
//  Created by Auvious on 15/10/26.
//

import Foundation

/// User facing co-browse copy. Host apps can override any string by adding its key to their Localizable.strings.
internal enum CobrowseStrings {

    private static func text(_ key: String, _ value: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: .main, value: value, comment: "")
    }

    /// The agent's name, or a generic "your agent"
    static func agent(_ name: String?) -> String {
        if let name = name, !name.isEmpty {
            return name
        }
        return text("auvious.cobrowse.agentFallback", "your agent")
    }

    /// The agent's name, or a generic "Your agent" at the start of a sentence
    static func agentCapitalized(_ name: String?) -> String {
        if let name = name, !name.isEmpty {
            return name
        }
        return text("auvious.cobrowse.agentFallbackCapitalized", "Your agent")
    }

    //Status pill
    static var connecting: String { return text("auvious.cobrowse.connecting", "Connecting to your agent…") }
    static var sharing: String { return text("auvious.cobrowse.sharing", "Sharing") }
    static func sharingWith(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.sharingWith", "Sharing with %@"), agent(name))
    }
    static var drawing: String { return text("auvious.cobrowse.drawing", "Drawing · app paused") }
    static var notSharing: String { return text("auvious.cobrowse.notSharing", "Not sharing") }
    static var share: String { return text("auvious.cobrowse.share", "Share") }

    //Dock
    static var draw: String { return text("auvious.cobrowse.draw", "Draw") }
    static var end: String { return text("auvious.cobrowse.end", "End") }
    static var done: String { return text("auvious.cobrowse.done", "Done") }
    static var cancel: String { return text("auvious.cobrowse.cancel", "Cancel") }
    static var shareScreen: String { return text("auvious.cobrowse.shareScreen", "Share screen") }
    static var pen: String { return text("auvious.cobrowse.pen", "Pen") }
    static var arrow: String { return text("auvious.cobrowse.arrow", "Arrow") }
    static var undo: String { return text("auvious.cobrowse.undo", "Undo") }
    static var clearDrawings: String { return text("auvious.cobrowse.clearDrawings", "Clear drawings") }
    static var clearConfirm: String { return text("auvious.cobrowse.clearConfirm", "Clear all drawings?") }
    static var clear: String { return text("auvious.cobrowse.clear", "Clear") }
    static var annotate: String { return text("auvious.arpointer.annotate", "Annotate") }
    static var laserPointer: String { return text("auvious.arpointer.laser", "AR pointer") }
    static var laserActivated: String { return text("auvious.arpointer.activated", "AR pointer activated") }
    static var laserDeactivated: String { return text("auvious.arpointer.deactivated", "AR pointer deactivated") }
    static var framePaused: String { return text("auvious.arpointer.framePaused", "Frame paused by agent") }
    static var moveControls: String { return text("auvious.cobrowse.moveControls", "Drag to move the controls") }

    //Explainer sheet
    static func explainerTitle(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.explainer.title", "Share your screen with %@?"), agent(name))
    }
    /// Checklist items never name the agent
    static var explainerAppOnly: String {
        return String(format: text("auvious.cobrowse.explainer.appOnly", "%@ sees this app only, never other apps, photos or notifications."), agentCapitalized(nil))
    }
    static var explainerPrivate: String { return text("auvious.cobrowse.explainer.private", "Private fields, like card and account numbers, show as black boxes.") }
    static var explainerDraw: String { return text("auvious.cobrowse.explainer.draw", "You can both draw on the screen, and you can stop anytime with End.") }
    static var startSharing: String { return text("auvious.cobrowse.explainer.start", "Start sharing") }
    static var notNow: String { return text("auvious.cobrowse.explainer.notNow", "Not now") }
    static var explainerFootnote: String { return text("auvious.cobrowse.explainer.footnote", "Next, iOS asks you to allow screen recording.") }

    //End confirmation
    static var endTitle: String { return text("auvious.cobrowse.endConfirm.title", "End the session?") }
    static func endBody(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.endConfirm.body", "%@ will stop seeing your screen and all drawings are removed. To share again, you'll need a new code."), agentCapitalized(name))
    }
    static var endSession: String { return text("auvious.cobrowse.endConfirm.end", "End session") }
    static var keepSharing: String { return text("auvious.cobrowse.endConfirm.keep", "Keep sharing") }

    //Notices
    static var sessionEnded: String { return text("auvious.cobrowse.ended.title", "Session ended") }
    static func sessionEndedBody(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.ended.body", "%@ can no longer see your screen."), agentCapitalized(name))
    }
    static func agentStoppedViewing(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.agentStopped", "%@ stopped viewing your screen. You're still connected and can share again."), agentCapitalized(name))
    }
    static var shareFailed: String { return text("auvious.cobrowse.shareFailed", "Your screen couldn't be shared. Try again.") }

    //During a video call
    static func inCallExplainerTitle(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.inCall.explainer.title", "Co-browse with %@?"), agent(name))
    }
    static var inCallStart: String { return text("auvious.cobrowse.inCall.explainer.start", "Start co-browsing") }
    static var explainerCallContinues: String { return text("auvious.cobrowse.inCall.explainer.call", "Your call keeps going in a small window while you share.") }
    static var inCallEndTitle: String { return text("auvious.cobrowse.inCall.endConfirm.title", "End co-browsing?") }
    static func inCallEndBody(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.inCall.endConfirm.body", "%@ will stop seeing your screen and all drawings are removed. You stay on the call."), agentCapitalized(name))
    }
    static var inCallEndSession: String { return text("auvious.cobrowse.inCall.endConfirm.end", "End co-browsing") }
    static var inCallEnded: String { return text("auvious.cobrowse.inCall.ended.title", "Co-browsing ended") }
    static func inCallEndedBody(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.inCall.ended.body", "%@ can no longer see your screen. You're still on the call."), agentCapitalized(name))
    }
    static var stopCobrowsing: String { return text("auvious.cobrowse.inCall.stop", "Stop co-browsing") }
    static func callHidden(_ name: String?) -> String {
        return String(format: text("auvious.cobrowse.inCall.callHidden", "%@ can't see the call"), agentCapitalized(name))
    }
    static var privateField: String { return text("auvious.cobrowse.private", "Private") }
}
