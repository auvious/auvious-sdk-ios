# AuviousSDK

This is Auvious iOS SDK, which simplifies integration with [Auvious](https://auvious.com) services. It provides both an API which allows you to build your custom call/conference UI, and ready out-of-the-self UI components/views which simplify integration for the most common scenarios.

## Requirements

iOS version >= 13.0

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
  pod 'AuviousSDK', '1.2.0'
  ```
- Auvious SDK github repo. This method only requires the following line on the target dependencies:
  ```ruby
  pod 'AuviousSDK', :git => 'https://github.com/auvious/auvious-sdk-ios.git', :tag => '1.2.0'
  ```
  
Next you need to run `pod install` in order for AuviousSDK and it's dependencies to be installed in the project workspace.

Finally you'll need disable bitcode in 'Build Settings' and also add NSMicrophoneUsageDescription,NSCameraUsageDescription texts in Info.plist.

## Examples
The following example applications are included in this repository. If unsure, begin with ExampleSimpleConference, which demonstrates how to use a ready-to-use ViewController we provide, for joining a video conference call.

- [ExampleCall](Example/ExampleCall)
- [ExampleSimpleCall](Example/ExampleSimpleCall)
- [ExampleConference](Example/ExampleConference)
- [ExampleSimpleConference](Example/ExampleSimpleConference)

To try the above examples you should open the Example/AuviousSDK.xcworkspace in Xcode.

There is also a separate repository with examples available at https://github.com/auvious/ios-examples. At the current moment the following examples are available there:

- [SimpleConference](https://github.com/auvious/ios-examples/tree/master/SimpleConference) Similar to ExampleSimpleConference written in SwiftUI.
- [GenesysCloudSimpleConference](https://github.com/auvious/ios-examples/tree/master/GenesysCloudSimpleConference) Demonstrates how to quickly add video call capability to your iOS application, utilizing Genesys Cloud webChat channel for ACD routing.


## Publish version

Follow the steps below to publish a new version

### Publish to git
Increase the version in `AuviousSDK.podspec`

Tag git with the version (ex `1.2.0`)

Push the version and the tag to github

### Publish Pod
If this is the first time you do this process in your machine, you need to have cocoapods installed. Follow the instructions in http://cocoapods.org on how to install it in your machine. 

Once you have the pod command ready, add the auvious podspec repo to your pod repos by running this command. This will add a repo that requires SSH authentication so be sure that you have setup an SSH key with gitHub.  

```
pod repo add <your-pod-name> git@github.com:auvious/CocoaPodSpecs.git
```

Example: 

```
pod repo add auvious-cocoa-pod git@github.com:auvious/CocoaPodSpecs.git
```

Next you need to push to that repo

```
pod repo push <your-pod-name> AuviousSDK.podspec --verbose --allow-warnings
```

Example: 
```
pod repo push auvious-cocoa-pod AuviousSDK.podspec --verbose --allow-warnings
```
 
## Release notes

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
