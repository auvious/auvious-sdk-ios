#
# Be sure to run `pod lib lint AuviousSDK.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'AuviousSDK'
  s.version          = '1.0.10'
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

  s.ios.deployment_target = '10.0'

  s.source_files = 'AuviousSDK/Classes/**/*'
  
  s.resources = 'AuviousSDK/Assets/*.png'
  
  s.resource_bundles = {
    'AuviousSDK' => ['Assets.xcassets']
  }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
  s.dependency 'Alamofire', '~> 4.7'
  s.dependency 'SwiftyJSON', '~> 5.0'
  s.dependency 'AuviousGoogleWebRTC', '~> 84.4147.2'
  s.dependency 'MQTTClient/Websocket', '~> 0.15'
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
