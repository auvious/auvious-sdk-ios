# AuviousSDK

This is Auvious iOS SDK, which simplifies integration with [Auvious](https://auvious.com) services. It provides both an API which allows you to build your custom call/conference UI, and ready out-of-the-shelf UI components/views which simplify integration for the most common scenarios.

## Requirements

iOS version >= 15.0

## Installation

AuviousSDK is available through as a [CocoaPod](https://cocoapods.org). You can install it using one of the following ways:

- Auvious Cocoa Pods Repo. Add the following sources to your Podfile
  ```ruby
  source 'https://github.com/auvious/CocoaPodSpecs.git'
  ```
  Make sure you also include the official CocoaPods repo source or a valid mirror of it
  ```ruby
  source 'https://cdn.cocoapods.org/'
  ```
  Last but not least, you need to add the AuviousSDK pod on all targets that will need it
  ```ruby
  pod 'AuviousSDK', '1.5.0'
  ```
- Auvious SDK github repo. This method only requires the following line on the target dependencies:
  ```ruby
  pod 'AuviousSDK', :git => 'https://github.com/auvious/auvious-sdk-ios.git', :tag => '1.5.0'
  ```

Next you need to run `pod install` in order for AuviousSDK and it's dependencies to be installed in the project workspace.

Finally you'll need disable bitcode in 'Build Settings' and also add NSMicrophoneUsageDescription,NSCameraUsageDescription texts in Info.plist.

---

## Setup Instructions

### 1. Info.plist Permissions

Add the following keys to your `Info.plist` to request camera and microphone access:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for video calls.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required for audio calls.</string>
```

### 2. Build Settings

Disable Bitcode in your target's **Build Settings**:

- Navigate to **Build Settings → Enable Bitcode** and set it to **No**.

### 3. Background Audio (Optional)

If you want audio to continue when the app goes to the background, add the audio background mode to your `Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

Then enable it in the SDK configuration (see `backgroundAudioEnabled` below).

### 4. App Lifecycle Hooks

The SDK needs to be notified when the app moves between foreground and background. Add the following calls in your `AppDelegate` or `SceneDelegate`:

```swift
import AuviousSDK

// In applicationDidEnterBackground / sceneDidEnterBackground
AuviousConferenceSDK.sharedInstance.onApplicationPause()

// In applicationWillEnterForeground / sceneWillEnterForeground
AuviousConferenceSDK.sharedInstance.onApplicationResume()
```

---

## Usage Example

### Simple Conference (Recommended)

The easiest way to add a conference to your app is using the built-in `AuviousConferenceVCNew` view controller.

```swift
import AuviousSDK

class ViewController: UIViewController {

    func joinConference() {
        // 1. Build the configuration
        let config = AuviousConferenceConfiguration()
        config.username = "<ticket>" // set the auvious ticket
        config.baseEndpoint = "https://auvious.video/"
        config.mqttEndpoint = "auvious.video"

        // 2. Set call mode
        config.callMode = .audioVideo

        // 3. (Optional) Customize the UI
        config.conferenceBackgroundColor = .black
        config.cameraAvailable = true
        config.microphoneAvailable = true
        config.speakerAvailable = true
        config.pipAvailable = true
        config.screenSharingAvailable = false
        config.backgroundAudioEnabled = false

        // 4. Present the conference view controller
        let conferenceVC = AuviousConferenceVCNew(configuration: config, delegate: self)
        present(conferenceVC, animated: true)
    }
}

// MARK: - AuviousSimpleConferenceDelegate

extension ViewController: AuviousSimpleConferenceDelegate {

    func onConferenceSuccess() {
        // Called when the conference ends normally
        print("Conference ended successfully")
    }

    func onConferenceError(_ error: AuviousSDKGenericError) {
        // Called on error (authentication failure, network issues, etc.)
        switch error {
        case .AUTHENTICATION_FAILURE:
            print("Authentication failed — check credentials")
        case .NETWORK_ERROR:
            print("Network error")
        case .PERMISSION_REQUIRED:
            print("Camera or microphone permission denied")
        case .INVALID_TICKET(let ticketId):
            print("Invalid ticket: \(ticketId)")
        default:
            print("Conference error: \(error)")
        }
    }
}
```

### Low-Level Conference API

For full control over the conference flow and UI, use `AuviousConferenceSDK` directly.

```swift
import AuviousSDK

class ConferenceManager: AuviousSDKConferenceDelegate {

    func setup() {
        AuviousConferenceSDK.sharedInstance.delegate = self

        // Configure the SDK
        AuviousConferenceSDK.sharedInstance.configure(
            params: [:],
            username: "<ticket>",
            password: "<password>",
            name: nil,
            clientId: "<client-id>",
            baseEndpoint: "https://auvious.video/",
            mqttEndpoint: "auvious.video"
        )

        // Log in
        AuviousConferenceSDK.sharedInstance.login(
            onLoginSuccess: { [weak self] endpoint in
                self?.joinConference()
            },
            onLoginFailure: { error in
                print("Login failed: \(error)")
            }
        )
    }

    func joinConference() {
        AuviousConferenceSDK.sharedInstance.joinConference(
            conferenceId: "<conference-name>",
            onSuccess: { [weak self] conference in
                // Start publishing local audio/video
                self?.publishLocalStream()
            },
            onFailure: { error in
                print("Failed to join: \(error)")
            }
        )
    }

    func publishLocalStream() {
        AuviousConferenceSDK.sharedInstance.startPublishLocalStreamFlow(type: .micAndCam)
    }

    func leaveConference() {
        AuviousConferenceSDK.sharedInstance.leaveConference(
            conferenceId: "<conference-name>",
            onSuccess: { },
            onFailure: { _ in }
        )
    }

    // MARK: - AuviousSDKConferenceDelegate

    func auviousSDK(didReceiveLocalVideoTrack localVideoTrack: RTCVideoTrack!) {
        // Render the local video track in your UI
    }

    func auviousSDK(didReceiveRemoteStream stream: RTCMediaStream, streamId: String,
                    endpointId: String, type: StreamType) {
        // Render the incoming remote stream in your UI
    }

    func auviousSDK(didReceiveLocalStream stream: RTCMediaStream, streamId: String,
                    type: StreamType) {
        // Local stream is ready
    }

    func auviousSDK(onError error: AuviousSDKError) {
        print("SDK error: \(error)")
    }

    func auviousSDK(didChangeState newState: StreamEventState, streamId: String,
                    streamType: StreamType, endpointId: String) {
        // React to stream state transitions (connecting, connected, disconnected, etc.)
    }

    func auviousSDK(trackMuted type: StreamType, endpointId: String) { }
    func auviousSDK(trackUnmuted type: StreamType, endpointId: String) { }
    func auviousSDK(conferenceOnHold flag: Bool) { }
    func auviousSDK(didReceiveConferenceEvent event: ConferenceEvent) { }
    func auviousSDK(didRejoinConference conference: ConferenceSimpleView) { }
    func auviousSDK(recorderStateChanged toActive: Bool) { }
    func auviousSDK(agentPortraitMode flag: Bool, endpointId: String) { }
    func auviousSDK(screenSharingStarted: Bool) { }
    func auviousSDK(screenSharingStopped: Bool) { }
    func auviousSDK(didResumeFromBackground withActiveAudio: Bool) { }
}
```

---

## Configuration Options Reference

### AuviousConferenceConfiguration

Used when presenting `AuviousConferenceVCNew` for the built-in conference UI.

#### Authentication & Connection

| Property       | Type     | Description                                                          |
| -------------- | -------- | -------------------------------------------------------------------- |
| `username`     | `String` | Username (or ticket) used to authenticate with the Auvious platform. |
| `password`     | `String` | Password used to authenticate.                                       |
| `grantType`    | `String` | OAuth grant type. Default: `"password"`.                             |
| `clientId`     | `String` | Client identifier registered on the Auvious platform. Default: `"customer"`               |
| `conference`   | `String` | Name of the conference room to join or create.                       |
| `baseEndpoint` | `String` | Base URL of the Auvious API (e.g. `"https://auvious.video/"`).       |
| `mqttEndpoint` | `String` | Hostname of the MQTT WebSocket broker (e.g. `"auvious.video"`).      |

#### Call Behaviour

| Property                 | Type              | Default       | Description                                                                                                     |
| ------------------------ | ----------------- | ------------- | --------------------------------------------------------------------------------------------------------------- |
| `callMode`               | `AuviousCallMode` | `.audioVideo` | Stream mode for the call. Use `.audio` for audio-only, `.video` for video-only, or `.audioVideo` for both.      |
| `enableSpeaker`          | `Bool`            | `true`        | Route audio to the loudspeaker on join.                                                                         |
| `backgroundAudioEnabled` | `Bool`            | `false`       | Keep audio running when the app moves to the background. Requires the `audio` UIBackgroundMode in `Info.plist`. |
| `participantName`        | `String?`         | `nil`         | Optional display name shown to other participants.                                                              |

#### UI Controls

| Property                    | Type      | Default     | Description                               |
| --------------------------- | --------- | ----------- | ----------------------------------------- |
| `conferenceBackgroundColor` | `UIColor` | `.darkGray` | Background colour of the conference view. |
| `cameraAvailable`           | `Bool`    | `true`      | Show the camera toggle button.            |
| `microphoneAvailable`       | `Bool`    | `true`      | Show the microphone mute/unmute button.   |
| `speakerAvailable`          | `Bool`    | `true`      | Show the speaker toggle button.           |
| `pipAvailable`              | `Bool`    | `true`      | Show the Picture-in-Picture button.       |
| `screenSharingAvailable`    | `Bool`    | `true`      | Show the screen-sharing button.           |

---

### AuviousConferenceSDK — Key Properties

| Property                 | Type                            | Description                                                                                    |
| ------------------------ | ------------------------------- | ---------------------------------------------------------------------------------------------- |
| `delegate`               | `AuviousSDKConferenceDelegate?` | Receives stream, state, and error events.                                                      |
| `publishVideoResolution` | `PublishVideoResolution`        | Video quality for the outgoing stream. `.min` (640×480), `.mid` (960×720), `.max` (1920×1080). |
| `isLoggedIn`             | `Bool`                          | Whether the SDK is currently authenticated. Read-only.                                         |
| `userEndpointId`         | `String?`                       | The current user's endpoint identifier. Read-only.                                             |

---

### AuviousDiagnostics — Error Reporting & Logging

Set these before using the SDK, e.g. in `application(_:didFinishLaunchingWithOptions:)`. Same settings as the Android SDK.

```swift
AuviousDiagnostics.errorReporting = .custom(dsn: "https://<key>@<your-sentry>/<project>") // .auvious (default), .disabled
AuviousDiagnostics.logLevel = .minimal                                                  // .minimal (default), .full
AuviousDiagnostics.consoleLogLevel = .error
```

| Property          | Type                     | Default    | Description                                                                                                                         |
| ----------------- | ------------------------ | ---------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `errorReporting`  | `AuviousErrorReporting`  | `.auvious` | Where Sentry reports go: `.auvious`, `.custom(dsn:)` (your own Sentry) or `.disabled`.                                               |
| `logLevel`        | `AuviousLogLevel`        | `.minimal` | What goes to Sentry. `.minimal`: crashes in the SDK, with its error logs as breadcrumbs. `.full`: also the SDK's errors as events and all its logs as breadcrumbs. |
| `consoleLogLevel` | `AuviousConsoleLogLevel` | `.warning` | SDK console logs at this level or above: `.none`, `.error`, `.warning`, `.info`, `.debug`.                                           |

Only crashes with a frame in the SDK's code (AuviousSDK, WebRTC) are reported, not the rest of the app's crashes. Reporting
starts when the SDK is first used; a crash is sent the next time the app uses the SDK.

If your app uses Sentry, start it before using the SDK. The SDK then leaves your Sentry as it is, sends its reports through a
client of its own and catches no crashes. Otherwise the SDK starts Sentry itself to catch crashes, with everything else of
Sentry's (sessions, app hangs, network and UI tracking) off.

---

### Enumerations

#### AuviousCallMode

| Value         | Description           |
| ------------- | --------------------- |
| `.audio`      | Audio-only call.      |
| `.video`      | Video-only call.      |
| `.audioVideo` | Audio and video call. |

#### StreamType

| Value        | Description             |
| ------------ | ----------------------- |
| `.mic`       | Audio stream only.      |
| `.cam`       | Video stream only.      |
| `.micAndCam` | Audio and video stream. |
| `.screen`    | Screen-sharing stream.  |

#### PublishVideoResolution

| Value  | Resolution  |
| ------ | ----------- |
| `.min` | 640 × 480   |
| `.mid` | 960 × 720   |
| `.max` | 1920 × 1080 |

#### AuviousSDKGenericError

| Value                       | Description                                             |
| --------------------------- | ------------------------------------------------------- |
| `.AUTHENTICATION_FAILURE`   | Credentials were rejected by the platform.              |
| `.PERMISSION_REQUIRED`      | Camera or microphone permission was denied by the user. |
| `.NETWORK_ERROR`            | A network-level failure occurred.                       |
| `.CALL_REJECTED`            | The call was rejected by the remote party.              |
| `.CONFERENCE_MISSING`       | The specified conference room does not exist.           |
| `.INVALID_TICKET(ticketId)` | The provided ticket is invalid or expired.              |
| `.UNKNOWN_FAILURE`          | An unexpected error occurred.                           |

---

## Examples

This repository includes one example application, [ExampleSimpleConference](Example/ExampleSimpleConference), which demonstrates how to use a ready-to-use ViewController we provide, for joining a video conference call.

To try ExampleSimpleConference run `pod install` in `Example/`, then open `Example/AuviousSDK.xcworkspace` in Xcode. Apps built with Xcode 27 (iOS 27 SDK) must use the scene life cycle; ExampleSimpleConference shows how (`SceneDelegate` in its `AppDelegate.swift`).

There is also a separate repository with examples available at https://github.com/auvious/ios-examples. At the current moment the following examples are available there:

- [SimpleConference](https://github.com/auvious/ios-examples/tree/master/SimpleConference) Similar to ExampleSimpleConference written in SwiftUI.
- [GenesysCloudSimpleConference](https://github.com/auvious/ios-examples/tree/master/GenesysCloudSimpleConference) Demonstrates how to quickly add video call capability to your iOS application, utilizing Genesys Cloud webChat channel for ACD routing.

## Tests

`Tests/` holds XCTests of the SDK, a `test_spec` of `AuviousSDK.podspec` hosted in its `app_spec` TestHost
(an app with the scene life cycle). After `pod install` in `Example/` they are the scheme
`AuviousSDK-Unit-Tests` of the workspace:

    xcodebuild test -workspace Example/AuviousSDK.xcworkspace -scheme AuviousSDK-Unit-Tests \
      -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO

CI runs them in the job test-sdk. `RTCModuleLoopbackTests` runs `RTCModule`'s conference signalling
against `FakeSFU`, a peer connection in the same process standing in for the server: publishing a stream,
and viewing one, with video from a synthetic camera (the simulator has none). No backend, no network:
both sides only use the loopback interface.

## Publish version

A version is published to two GitHub repos: its source as a git tag on
github.com/auvious/auvious-sdk-ios (the podspec's `source`), and its podspec in the spec repo
github.com/auvious/CocoaPodSpecs, where `pod install` finds it.

### From CI

1. Set the version in `AuviousSDK.podspec` (e.g. `1.5.0`, `1.5.0-beta.1`, `1.5.0-rc.1`), add release notes
   below, run `pod install` in `Example/` and commit `Podfile.lock`.
2. Tag that commit on GitLab with the same version and push the tag.
3. In the tag's pipeline, once build-example and test-sdk passed, start the manual job **publish**.

It pushes the tag to GitHub, then adds the podspec to the spec repo (`ci/publish.sh`). It checks
before pushing anything: the tag matches `s.version`, write access to both repos, and the version
isn't in the spec repo already with other content (then tag a new version). Safe to retry.

It needs the CI variable `GITHUB_TOKEN` (masked, protected): a GitHub token with Contents write
access to both repos. Version tags have to be protected tags, or the job doesn't appear.

### By hand

Push the version's commit and tag to github.com/auvious/auvious-sdk-ios, then:

```
pod repo add auvious-cocoa-pod git@github.com:auvious/CocoaPodSpecs.git
pod repo push auvious-cocoa-pod AuviousSDK.podspec --verbose --allow-warnings --skip-tests
```

`pod repo push` first builds the pod. With Xcode 27 that build fails on the dependencies (Sentry,
SwiftyJSON and the _IOS13 pods declare iOS 11–13, Xcode 27 accepts 15 and later), which the Example's
Podfile fixes for apps but the lint can't. CI's publish job therefore lints with `--quick` and commits the
podspec itself; build-example and test-sdk build and test the same commit. Without `--skip-tests`, the lint
also builds the TestHost app and runs the [tests](#tests) on a simulator.

## Release notes

### 1.5.0

- Feature / `AuviousDiagnostics`: Sentry reporting like the Android SDK (`errorReporting`, `logLevel`), only crashes in the SDK's code; `consoleLogLevel` for the SDK's console logs (default `.warning`)
- Example / ExampleSimpleConference no longer starts Sentry itself
- Update / WebRTC M155 (AuviousGoogleWebRTC 155.8059.3). Unified Plan: streams are published as tracks, remote streams arrive through the receivers
- Update / iOS 15 minimum (Xcode 27 rejects lower deployment targets)
- Update / video views are Metal (RTCMTLVideoView) only, also on simulators
- Bug fix / tracks a server or caller sends without a stream are delivered together, video included, and without the ones the answer rejected (no black tile for a refused camera)
- Behaviour / a track that can't be added to a connection is reported to the delegate (`internalError`), not only logged; the offer still goes out with the other tracks
- Bug fix / conference UI: the notch side follows the interface orientation, and the layout is redone once the view is on screen
- Example / ExampleSimpleConference uses the scene life cycle (apps built with the iOS 27 SDK don't launch without it), landscape layout without statusBarOrientation
- Example / Pods are no longer committed: run `pod install` in `Example/`
- Tests / XCTests of RTCModule against an in-process SFU, run in CI

### 1.4.0

- Feature / screen sharing. Only works within app
- Feature / Picture in Picture. Can work as standalone or while screen sharing
- Feature / Support background audio. If app is in background, call continues with audio only
- Feature / add 'user-agent' to headers to track usage
- Feature / 3 dots menu (more) if more than 4 actions are available
- Bug fix / If recording started before app joins the call, the indicator was not shown
- Bug fix / Use icon instead of 'audio only' if camera is off
- Bug fix / MQTT Fails if wrong ticket is used
- Bug fix / if agent changes from MIC to MIC_AND_CAM while PiP, app crashed
- Bug fix / Add participant and stream metadata when joining the call
- Bug fix / Do not rejoin conference if notification center is shown

### 1.3.1

- Feature / Added support for portrait mode
- Feature / Changed the remote stream aspect ratio closer to 4:3

### 1.3.0

- Feature / Option to show/hide mic, camera and speaker buttons
- Feature / Option to change background color in conference view
- Feature / Option to output audio directly to speaker

### 1.2.1

- Feature / Show notifications and indicator when recordring starts / stops

### 1.2.0

- Feature / Simple confernce can now start with either mic, cam or both

## Author

Auvious, team@auvious.com

## License

AuviousSDK is available under the MIT license. See the LICENSE file for more info.
