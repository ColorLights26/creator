#!/usr/bin/env ruby
# Run the canonical descriptor/state and Metal renderer without application services.
require 'open3'
require 'tmpdir'

runtime = File.expand_path('../Classes/Runtime', __dir__)
surface = File.read(File.join(runtime, 'SceneRenderV2ImageSurface.swift'))
allocator = surface[/@available\(iOS 15\.0, \*\)\n(?:private )?final class SceneSurfaceNativeOutputAllocator \{.*?^\}/m]
abort 'Production output allocator was not found' unless allocator
Dir.mktmpdir('creator-native-test-') do |temporary|
  support = File.join(temporary, 'Allocator.swift')
  File.write(support, "import Foundation\nimport Metal\n#{allocator}\n")
  executable = File.join(temporary, 'creator-tests')
  sources = Dir[File.join(runtime, 'SceneCatalog*.swift')].sort +
    [File.join(runtime, 'SceneRenderSignalFrameV2.swift')]
  command = ['xcrun', 'swiftc', '-O', '-o', executable, support, *sources,
    File.join(__dir__, 'creator_catalog_tests.swift')]
  output, status = Open3.capture2e(*command)
  puts output unless output.empty?
  abort 'Creator native tests failed to compile' unless status.success?
  output, status = Open3.capture2e(executable)
  puts output
  abort 'Creator native tests failed' unless status.success?
  unless ARGV.empty?
    catalog = File.expand_path(ARGV.fetch(0))
    abort "Creator catalog not found: #{catalog}" unless File.file?(catalog)
    output, status = Open3.capture2e(executable, catalog, *ARGV.drop(1))
    puts output
    abort 'Authored creator catalog Metal smoke failed' unless status.success?
  end
end
