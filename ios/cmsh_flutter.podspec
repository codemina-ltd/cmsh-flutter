#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint cmsh_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'cmsh_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Deep links and full-journey attribution for CMSH.io short links.'
  s.description      = <<-DESC
Deep links and full-journey attribution for CMSH.io short links.
                       DESC
  s.homepage         = 'https://cmsh.io'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CMSH.io' => 'support@cmsh.io' }
  s.source           = { :path => '.' }
  s.source_files = 'cmsh_flutter/Sources/cmsh_flutter/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'cmsh_flutter_privacy' => ['cmsh_flutter/Sources/cmsh_flutter/PrivacyInfo.xcprivacy']}
end
