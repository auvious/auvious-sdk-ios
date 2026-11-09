//
//  StreamRecoveryManager.swift
//  AuviousSDK
//
//  Created by Auvious on 02/11/26.
//

import Foundation
import os

/// How a conference stream is doing while its connection is being rebuilt
public enum StreamRecoveryState {
    /// The connection dropped and is being rebuilt; the video may be frozen meanwhile
    case reconnecting
    /// Rebuilding the connection kept failing, so it was given up
    case failed
}

/// The ICE connection states the recovery acts on
internal enum StreamIceState {
    case connected, disconnected, failed, other
}

/**
 Rebuilds the peer connection of a conference stream whose ICE connection was lost, like the JS SDK's
 publish and view loops: republishes our own streams and resubscribes remote ones.

 - A connection that is `failed`, or `disconnected` for longer than `disconnectGrace`, is rebuilt.
 - A rebuilt connection that fails, or doesn't connect within `connectTimeout`, is tried again after
   `retryDelay`. Attempts wait while the device has no network, and `networkSettleDelay` once it is back:
   a connection that was only disconnected often comes back by itself then.
 - After `failureLimit` failures in a row the stream is marked `failed`, until the network changes. A connection
   that connects clears the count, so a long call on a flaky network keeps recovering.

 Used on the main queue only.
 */
internal final class StreamRecoveryManager {

    /**
     Starts rebuilding a stream's connection. Returns the ID of the stream the new connection carries
     (a republished stream gets a new one), or nil if there is nothing to recover any more.
     */
    typealias Recover = (_ streamId: String, _ isLocal: Bool) -> String?

    /// Told when a participant's stream starts or stops being unhealthy (nil once it is fine)
    typealias StateChanged = (_ endpointId: String, _ isLocal: Bool, _ state: StreamRecoveryState?) -> Void

    private final class Entry {
        let isLocal: Bool
        let endpointId: String
        var failures = 0
        var recovering = false
        var gaveUp = false
        var waitingForNetwork = false
        var graceWork: DispatchWorkItem?
        var attemptWork: DispatchWorkItem?

        init(isLocal: Bool, endpointId: String) {
            self.isLocal = isLocal
            self.endpointId = endpointId
        }

        func cancelTimers() {
            graceWork?.cancel()
            graceWork = nil
            attemptWork?.cancel()
            attemptWork = nil
        }
    }

    private let recover: Recover
    private let stateChanged: StateChanged
    private let disconnectGrace: TimeInterval
    private let retryDelay: TimeInterval
    private let connectTimeout: TimeInterval
    private let failureLimit: Int
    private let networkSettleDelay: TimeInterval

    private var entries: [String: Entry] = [:]
    private var networkAvailable = true

    init(disconnectGrace: TimeInterval = 4, retryDelay: TimeInterval = 2, connectTimeout: TimeInterval = 20, failureLimit: Int = 15,
         networkSettleDelay: TimeInterval = 1, recover: @escaping Recover, stateChanged: @escaping StateChanged) {
        self.disconnectGrace = disconnectGrace
        self.networkSettleDelay = networkSettleDelay
        self.retryDelay = retryDelay
        self.connectTimeout = connectTimeout
        self.failureLimit = failureLimit
        self.recover = recover
        self.stateChanged = stateChanged
    }

    /// Whether the stream is being rebuilt, so signalling failures for it belong to the recovery
    func isRecovering(_ streamId: String) -> Bool {
        return entries[streamId]?.recovering == true
    }

    func iceStateChanged(streamId: String, isLocal: Bool, endpointId: String, state: StreamIceState) {
        let entry = entries[streamId] ?? {
            let entry = Entry(isLocal: isLocal, endpointId: endpointId)
            entries[streamId] = entry
            return entry
        }()

        switch state {
        case .connected:
            entry.cancelTimers()
            entry.failures = 0
            entry.gaveUp = false
            if entry.recovering {
                entry.recovering = false
                os_log("Stream %{public}@ recovered", log: Log.conferenceSDK, type: .default, streamId)
                stateChanged(entry.endpointId, entry.isLocal, nil)
            }
        case .disconnected:
            //Often comes back by itself (e.g. a Wi-Fi handover), so give it a moment
            guard !entry.recovering, entry.graceWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let entry = self.entries[streamId] else { return }
                entry.graceWork = nil
                os_log("Stream %{public}@ still disconnected after %.0fs", log: Log.conferenceSDK, type: .default, streamId, self.disconnectGrace)
                self.startRecovery(streamId, entry)
            }
            entry.graceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + disconnectGrace, execute: work)
        case .failed:
            entry.graceWork?.cancel()
            entry.graceWork = nil
            if entry.recovering {
                attemptFailed(streamId)
            } else {
                startRecovery(streamId, entry)
            }
        case .other:
            break
        }
    }

    /// Negotiating a rebuilt connection failed (e.g. the publish or view request); counts as a failed attempt
    func attemptFailed(_ streamId: String) {
        guard let entry = entries[streamId], entry.recovering, !entry.gaveUp else { return }
        entry.cancelTimers()
        entry.failures += 1
        guard entry.failures < failureLimit else {
            os_log("Gave up on stream %{public}@ after %d failures in a row", log: Log.conferenceSDK, type: .error, streamId, entry.failures)
            entry.gaveUp = true
            stateChanged(entry.endpointId, entry.isLocal, .failed)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.attempt(streamId)
        }
        entry.attemptWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: work)
    }

    /// Lets waiting recoveries go ahead as soon as the device is back online. A network that changed may work
    /// where the last one didn't, so streams that were given up are tried again too
    func setNetworkAvailable(_ available: Bool) {
        networkAvailable = available
        guard available else { return }
        for (streamId, entry) in entries where entry.waitingForNetwork || entry.gaveUp {
            if entry.gaveUp {
                os_log("Network changed, trying stream %{public}@ again", log: Log.conferenceSDK, type: .default, streamId)
                entry.gaveUp = false
                entry.failures = 0
                stateChanged(entry.endpointId, entry.isLocal, .reconnecting)
            }
            entry.waitingForNetwork = false
            //A stream that connects meanwhile cancels this
            let work = DispatchWorkItem { [weak self] in
                self?.attempt(streamId)
            }
            entry.attemptWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + networkSettleDelay, execute: work)
        }
    }

    /// Stops recovering a stream that was unpublished or unsubscribed on purpose, or is gone
    func forget(_ streamId: String) {
        guard let entry = entries.removeValue(forKey: streamId) else { return }
        entry.cancelTimers()
        if entry.recovering {
            stateChanged(entry.endpointId, entry.isLocal, nil)
        }
    }

    func clear() {
        entries.values.forEach { $0.cancelTimers() }
        entries.removeAll()
    }

    private func startRecovery(_ streamId: String, _ entry: Entry) {
        guard !entry.recovering else { return }
        entry.recovering = true
        stateChanged(entry.endpointId, entry.isLocal, .reconnecting)
        attempt(streamId)
    }

    private func attempt(_ streamId: String) {
        guard let entry = entries[streamId], entry.recovering, !entry.gaveUp else { return }
        guard networkAvailable else {
            os_log("Waiting for the network to recover stream %{public}@", log: Log.conferenceSDK, type: .default, streamId)
            entry.waitingForNetwork = true
            return
        }

        os_log("Rebuilding the connection of %{public}@ stream %{public}@ (failures in a row: %d)", log: Log.conferenceSDK, type: .default,
               entry.isLocal ? "published" : "subscribed", streamId, entry.failures)
        guard let newStreamId = recover(streamId, entry.isLocal) else {
            os_log("Stream %{public}@ no longer exists, nothing to recover", log: Log.conferenceSDK, type: .default, streamId)
            forget(streamId)
            return
        }

        //A republished stream carries on under its new ID
        if newStreamId != streamId {
            entries.removeValue(forKey: streamId)
            entries[newStreamId] = entry
        }

        //The new connection reports its own ICE state; one that never gets anywhere is tried again
        let work = DispatchWorkItem { [weak self] in
            os_log("Stream %{public}@ did not connect in time", log: Log.conferenceSDK, type: .default, newStreamId)
            self?.attemptFailed(newStreamId)
        }
        entry.attemptWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + connectTimeout, execute: work)
    }
}
