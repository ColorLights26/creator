Pod::Spec.new do |s|
  s.name             = 'scene_compositor_host'
  s.version          = '1.0.0'
  s.summary          = 'Standalone studio registration for the shared scene compositor.'
  s.description      = 'Registers the existing SceneSurface engine only in the standalone creator host.'
  s.homepage         = 'https://chic-apps.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Chic Apps' => 'support@chic-apps.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'scene_compositor', '1.0.0'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
