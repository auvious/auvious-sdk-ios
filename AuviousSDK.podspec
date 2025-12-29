#
# Be sure to run `pod lib lint AuviousSDK.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'AuviousSDK'
  s.version          = '1.4.0-beta.6'
  s.summary          = 'AuviousSDK makes it easy to use Auvious services in your app.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
AuviousSDK makes it easy to use Auvious services in your app. Add now video call,
multiparty video conferencing, snapshot, and many more things are coming your way!
                       DESC

  s.homepage         = 'https://github.com/auvious/auvious-sdk-ios.git'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Auvious' => 'team@auvious.com' }
  s.source           = { :git => 'https://github.com/auvious/auvious-sdk-ios.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '13.0'

  s.source_files = 'AuviousSDK/Classes/**/*'
  s.exclude_files = 'AuviousSDK/AuviousSDK/Classes/Modules/API/**/*', 'AuviousSDK/AuviousSDK/Classes/Modules/MQTTModule.swift'
  
  
  s.resources = 'AuviousSDK/Assets/*.png'
  
  s.resource_bundles = {
    'AuviousSDKAssets' => ['Assets.xcassets']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'SwiftyJSON', '~> 5.0'
  s.dependency 'AuviousGoogleWebRTC', '~> 84.4147.4'
  s.dependency 'CocoaMQTTWebsocket_IOS13'
  s.dependency 'MqttCocoaAsyncSocket_IOS13', '~> 14.0.0'
  s.dependency 'Starscream_IOS13', '~> 4.0.4'
  
  s.swift_versions = '4.2'
  s.pod_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'AUVIOUSSDK',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) AUVIOUSSDK',
    # Xcode 12 workaround
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }

  s.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }
end
