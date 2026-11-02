# Handover: M155 migration and what is left

State of branch `m155-webrtc` (2026-10-22) and the work that continues from it. Delete this
file, or move it into the MR description, once its items are done or ticketed.

## Where things are

- **WebRTC fork and its CI:** gitlab.auvious.com `auvious/api/google-webrtc`, release branch
  `auvious-m155.8059`, iOS jobs in `auvious-ci/ios.gitlab-ci.yml` (README in `auvious-ci/`).
  Issue #2 is the original iOS plan, issue #4 the review follow-ups, MR !2 the open follow-up MR.
- **WebRTC binary:** Nexus (nexus.auvious.com), `com.auvious:google-webrtc-ios:<version>:zip`,
  anonymous download. The podspec pointing at it is pushed to github.com/auvious/CocoaPodSpecs by
  google-webrtc's CI.
- **Mac:** the office Mac mini (on loan, not the team's own: don't change its system settings).
  GitLab runner 37 "Macmini runner", tag `macos`, shell executor, one job at a time. The WebRTC
  build reuses its checkout in `~/webrtc-ios`; this repo's jobs keep a CocoaPods cache in
  `~/sdk-ios-ci/cocoapods`.
- **Public SDK repo:** github.com/auvious/auvious-sdk-ios, pushed by hand at each release (last 1.4.0).

## What the branch does

- WebRTC M84 → M155 (`AuviousGoogleWebRTC`, built by google-webrtc's CI on the Mac).
- Plan B → Unified Plan in `RTCModule`: local tracks with `addTrack` (audio first), mute through
  the senders, remote streams delivered from `didAdd rtpReceiver`, once per stream id. Tracks
  without a stream (msid "-") are grouped into one stream per connection; transceivers the answer
  rejected are left out.
- iOS 15 minimum everywhere (Xcode 27 refuses lower deployment targets).
- SDK views: Metal only (M155 has no `RTCEAGLVideoView`); the conference UI
  (`AuviousConferenceVCNew`) lays out from the window/scene instead of `statusBarOrientation`.
- ExampleSimpleConference: UIScene life cycle (iOS 27 SDK apps don't launch without it).
- `Example/Pods` no longer committed: run `pod install` in `Example/`.
- XCTests (`Tests/`, podspec `test_spec` hosted in `app_spec` `TestHost`): RTCModule against an
  in-process fake SFU, real media over loopback, no backend.
- GitLab CI (`.gitlab-ci.yml`): `build-example` (also fails when `Podfile.lock` is out of date)
  and `test-sdk`.
- Version 1.5.0 (minor, like 1.3 → 1.4 raised iOS 10 → 13), release notes in the README.
- Depends on `AuviousGoogleWebRTC '~> 155.8059.3'` (tag `auvious-m155.8059.3` of google-webrtc,
  2026-10-26); not `'~> 155.8059'`, which would also allow the test version `155.8059.0`.

Checked live on STG with ExampleSimpleConference (2026-10-20, two simulators in one conference:
publish, view, rotation); everything since is covered by the tests and CI. Simulators have no
camera, so video tiles are grey: test on a device before release.

## Before release (in this order)

Done: the WebRTC pod 155.8059.3 is published, the SDK pins it, version 1.5.0, `Podfile.lock`
committed.

1. **Test on a device** (simulators have no camera).
2. **MR** `m155-webrtc` → `master` (!16). For its description:
   - The 1:1 call SDK (`AuviousCallSDK`, `AuviousCallVC`, snapshots) and the stale examples
     ExampleCall, ExampleSimpleCall and ExampleConference were removed: conferences only.
   - Mute/hold behave as before (`track.isEnabled = false` sends silence/black frames).
   Open decision to mention: really stopping the send on mute/hold (`sender.track = nil` /
   `replaceTrack`), which would save bandwidth but changes behaviour.
3. **Publish:** tag the version on GitLab, then start the manual job `publish` in the tag's pipeline
   (README, "Publish version"). Before it can run: `GITHUB_TOKEN` in this project (Contents write
   access to github.com/auvious/auvious-sdk-ios and CocoaPodSpecs), and version tags protected.

## Swift Package Manager (not started)

Parked: it needs someone with access to the public GitHub repo, where SPM finds the package and
its version tags. Estimated 1–2 days on top of this branch; CocoaPods and SPM can ship from the
same sources and tags. No earlier SPM attempt was found (GitLab, GitHub, the Mac). Spec:
google-webrtc issue #4 item 6. Why now: CocoaPods is in maintenance mode and its public trunk turns
read-only on 2026-12-02 (our own spec repo keeps working; Sentry/SwiftyJSON get no new versions
through CocoaPods after that).

What it takes, from the code:

| Area | Change |
|---|---|
| WebRTC | `.binaryTarget(url:checksum:)` to the Nexus zip. The checksum is the sha256 google-webrtc's CI prints. Same file CocoaPods uses. |
| MQTT / websocket | The `_IOS13` forks (jkritikos) only rename modules and raise the minimum iOS; under SPM use upstream `emqx/CocoaMQTT` (products CocoaMQTT, CocoaMQTTWebSocket; brings Starscream and MqttCocoaAsyncSocket). Only `MQTTModule2.swift` imports it. |
| `import WebRTC` | The SDK's header `AuviousSDK/Classes/AuviousSDK.h` imports the WebRTC headers, so under CocoaPods every Swift file sees them. SPM has no such header: 12 files need `import WebRTC` (all users of RTC* types except `ScreenCapturer.swift`). Apps need it too, because public API takes RTC types (`AuviousSDKBaseProtocol`, `StreamViewNew`): use `@_exported import WebRTC` in one file. |
| Resources | 3 xibs, `Assets.xcassets` (at the repo root, outside the target: move it) and 3 pngs, found in ~9 places with `Bundle(for:)` and the name `AuviousSDKAssets.bundle`. Write one helper that returns the CocoaPods bundle, or `Bundle.module` under SPM. The main work, about half a day. |
| SDK version in User-Agent | Read from the SDK bundle's Info.plist (`Utilities.swift`), which SPM doesn't have: use a constant. |
| `Package.swift` | New, at the repo root. The podspec's `AUVIOUSSDK` flag is used by no source file, and its `exclude_files` paths match nothing: neither needs carrying over. CI: add an SPM build (`xcodebuild -scheme AuviousSDK -destination 'generic/platform=iOS Simulator'`) next to the pod jobs. |

Recommended: keep CocoaPods alongside SPM; WebRTC binary on Nexus (one copy for both); do it on a
branch off this one.

## Known limitations and follow-ups (not blocking)

SDK:
- `peerConnections` is mutated from WebRTC callbacks and main without a lock (older than this
  branch).
- A track that arrives after its stream was delivered (renegotiation) isn't added to it: delivery
  is once per stream id. The conference flow doesn't renegotiate viewed streams today.
- Answering a call: an m-line the caller offers but doesn't send still gets a (silent) track in the
  grouped stream; the answer can't tell it apart (comment in `RTCModule`).
- `RTCModule.toggleRemoteStreams` (internal) mutes/unmutes on hold; the name doesn't say so.
- `AuviousConferenceVCNew` lays out in `viewDidAppear`; `viewIsAppearing` (iOS 13+ via back
  deployment) is the hook meant for layout that depends on the window.
- Swift language mode is old and inconsistent: podspec `swift_versions = '4.2'`, Example project
  `SWIFT_VERSION` 4.0 and 4.2. Moving to Swift 5 may surface compile errors; do it with a build.

CI and infrastructure:
- The Mac runner isn't protected: any branch can run jobs on it, including google-webrtc's
  publishing jobs that hold `GITHUB_TOKEN`. Protect it and delete the stale runner 4
  (google-webrtc issue #4 item 1; needs a GitLab admin).
- `GITHUB_TOKEN` (CocoaPodSpecs push in google-webrtc's CI) expires 2026-11-12. A deploy key with
  write access to that repo only would replace it (needs a GitHub admin).
- google-webrtc's wiki iOS section and issue #2 still describe the old manual pod flow.
- Cleanup once released: google-webrtc branch `ios-ci-probe`, Nexus test versions
  (`155.8059.0`, `155.8059.3.test.0`) and the Mac's `~/webrtc-ios/m155.bundle`.

## Running the tests

On a Mac with Xcode 27 and CocoaPods (any simulator; CI creates its own per job):

```
cd Example && pod install
xcodebuild test -workspace AuviousSDK.xcworkspace -scheme AuviousSDK-Unit-Tests \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The tests stay on loopback: the Mac's firewall (stealth mode) drops UDP to unsigned apps on the
LAN address.
