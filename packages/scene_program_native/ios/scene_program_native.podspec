Pod::Spec.new do |s|
  s.name = 'scene_program_native'
  s.version = '1.0.0'
  s.summary = 'Portable compiled Creator scene programs'
  s.description = 'A C ABI for stateful scenes, owned by the existing compositor.'
  s.homepage = 'https://chic-apps.com'
  s.license = { :type => 'Proprietary' }
  s.author = { 'Chic Apps' => 'support@chic-apps.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*.{h,cpp}'
  s.public_header_files = 'Classes/creator_abi.h'
  s.platform = :ios, '15.0'
  s.libraries = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES', 'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_ROOT)/../../build/creator_native/$(CONFIGURATION)"',
    'GCC_SYMBOLS_PRIVATE_EXTERN' => 'NO'
  }
  s.script_phase = {
    :name => 'Prepare Creator programs', :execution_position => :before_compile,
    :always_out_of_date => '1',
    :script => <<-SH
set -eu
HOST_ROOT="$(cd "$PODS_ROOT/../.." && pwd)"
FLUTTER_SDK="$(sed -n 's/^FLUTTER_ROOT=//p' "$HOST_ROOT/ios/Flutter/Generated.xcconfig" | head -1)"
CREATOR_NATIVE_CONFIGURATION="$CONFIGURATION" "$FLUTTER_SDK/bin/cache/dart-sdk/bin/dart" --packages="$HOST_ROOT/.dart_tool/package_config.json" "$HOST_ROOT/tool/compile_creator.dart"
SH
  }
end
