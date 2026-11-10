# CocoaPods route, for apps that have Swift Package Manager turned off. Run scripts/build-ios.sh first.
Pod::Spec.new do |s|
  s.name                = 'athena_native'
  s.version             = '0.1.0'
  s.summary             = 'Athena: the kneejerk decision engine and device facts.'
  s.homepage            = 'https://github.com/moudrkat/kneejerk'
  s.license             = { :type => 'GPL-3.0-or-later', :file => '../../../LICENSE' }
  s.author              = 'ehollbach'
  s.source              = { :path => '.' }
  s.source_files        = 'athena_native/Sources/athena_native/**/*.swift'
  s.resource_bundles    = { 'athena_native_privacy' => ['athena_native/Sources/athena_native/PrivacyInfo.xcprivacy'] }
  s.vendored_frameworks = 'athena_native/AthenaEngine.xcframework'
  s.dependency 'Flutter'
  s.platform            = :ios, '16.4'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version       = '5.0'
end
