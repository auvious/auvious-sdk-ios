//
//  StreamRecoveryManagerTests.swift
//  AuviousSDKLogicTests
//
//  Created by Auvious on 02/11/26.
//

import XCTest

final class StreamRecoveryManagerTests: XCTestCase {

    private var attempts: [String] = []
    private var states: [StreamRecoveryState?] = []

    /// Quick timings; `result` decides what each attempt returns (the new stream ID, or nil when gone)
    private func manager(connectTimeout: TimeInterval = 5, result: @escaping (String) -> String? = { $0 }) -> StreamRecoveryManager {
        return StreamRecoveryManager(
            disconnectGrace: 0.1, retryDelay: 0.01, connectTimeout: connectTimeout, failureLimit: 3, networkSettleDelay: 0.05,
            recover: { [unowned self] streamId, _ in
                self.attempts.append(streamId)
                return result(streamId)
            },
            stateChanged: { [unowned self] _, _, state in self.states.append(state) }
        )
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testAFailedConnectionIsRebuiltAndReconnectingUntilItConnects() {
        let recovery = manager()

        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .failed)
        XCTAssertEqual(attempts, ["s1"])
        XCTAssertEqual(states, [.reconnecting])
        XCTAssertTrue(recovery.isRecovering("s1"))

        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .connected)
        XCTAssertEqual(states, [.reconnecting, nil])
        XCTAssertFalse(recovery.isRecovering("s1"))
    }

    func testADisconnectThatComesBackWithinTheGracePeriodIsLeftAlone() {
        let recovery = manager()

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .disconnected)
        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .connected)
        wait(0.25)

        XCTAssertTrue(attempts.isEmpty)
        XCTAssertTrue(states.isEmpty)
    }

    func testADisconnectThatLastsIsRebuilt() {
        let recovery = manager()

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .disconnected)
        wait(0.25)

        XCTAssertEqual(attempts, ["s1"])
        XCTAssertEqual(states, [.reconnecting])
    }

    func testARepublishedStreamCarriesOnUnderItsNewId() {
        let recovery = manager(result: { _ in "s2" })

        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .failed)
        XCTAssertTrue(recovery.isRecovering("s2"))
        XCTAssertFalse(recovery.isRecovering("s1"))

        recovery.iceStateChanged(streamId: "s2", isLocal: true, endpointId: "me", state: .connected)
        XCTAssertEqual(states, [.reconnecting, nil])
    }

    func testGivesUpAfterTheFailureLimit() {
        let recovery = manager()

        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .failed)
        recovery.attemptFailed("s1")
        wait(0.05)
        recovery.attemptFailed("s1")
        wait(0.05)
        recovery.attemptFailed("s1")
        wait(0.05)

        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(states, [.reconnecting, .failed])
    }

    func testAStreamThatGaveUpIsTriedAgainWhenTheNetworkChanges() {
        let recovery = manager(connectTimeout: 0.05)

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .failed)
        wait(0.3)
        XCTAssertEqual(states, [.reconnecting, .failed])

        //After the settle delay, before that attempt times out
        recovery.setNetworkAvailable(true)
        wait(0.075)
        XCTAssertEqual(attempts.count, 4)
        XCTAssertEqual(states, [.reconnecting, .failed, .reconnecting])

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .connected)
        XCTAssertEqual(states, [.reconnecting, .failed, .reconnecting, nil])
    }

    func testAConnectionThatNeverConnectsIsTriedAgain() {
        let recovery = manager(connectTimeout: 0.05)

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .failed)
        wait(0.3)

        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(states, [.reconnecting, .failed])
    }

    func testWaitsForTheNetworkBeforeTrying() {
        let recovery = manager()
        recovery.setNetworkAvailable(false)

        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .failed)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(states, [.reconnecting])

        recovery.setNetworkAvailable(true)
        XCTAssertTrue(attempts.isEmpty)
        wait(0.1)
        XCTAssertEqual(attempts, ["s1"])
    }

    func testAConnectionThatComesBackWithTheNetworkIsNotRebuilt() {
        let recovery = manager()
        recovery.setNetworkAvailable(false)
        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .failed)

        recovery.setNetworkAvailable(true)
        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .connected)
        wait(0.1)

        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(states, [.reconnecting, nil])
    }

    func testAStreamThatNoLongerExistsIsDropped() {
        let recovery = manager(result: { _ in nil })

        recovery.iceStateChanged(streamId: "s1", isLocal: false, endpointId: "agent", state: .failed)

        XCTAssertEqual(attempts, ["s1"])
        XCTAssertEqual(states, [.reconnecting, nil])
        XCTAssertFalse(recovery.isRecovering("s1"))
    }

    func testAForgottenStreamStopsRecovering() {
        let recovery = manager()
        recovery.setNetworkAvailable(false)
        recovery.iceStateChanged(streamId: "s1", isLocal: true, endpointId: "me", state: .failed)

        recovery.forget("s1")
        recovery.setNetworkAvailable(true)

        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(states, [.reconnecting, nil])
    }
}
