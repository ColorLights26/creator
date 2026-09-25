Pod::Spec.new do |s|
  s.name             = 'scene_compositor'
  s.version          = '1.0.0'
  s.summary          = 'Shared native SceneSurface compositor for the visual creator.'
  s.description      = 'The production SceneSurface source, packaged without application services.'
  s.homepage         = 'https://chic-apps.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Chic Apps' => 'support@chic-apps.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'AVKit', 'CoreImage', 'CoreMedia', 'CoreVideo', 'CryptoKit', 'ImageIO', 'Metal', 'UIKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
