#!/usr/bin/env ruby
# Run the canonical descriptor/state and Metal renderer without application services.
require 'open3'
require 'tmpdir'
require 'json'

# The Swift sources and catalogs are UTF-8; without a UTF-8 locale Ruby would
# read them as US-ASCII and the regexps below would raise.
Encoding.default_external = Encoding::UTF_8

# Device-only diagnostics the compiled runtime files call but the iOS host
# (PictureInPictureHandler.swift, not compiled here) defines. With diagnostics
# off they do nothing, which is exactly this stand-in. It is only added when no
# compiled file defines the name, so moving the real one in never collides.
HOST_DIAGNOSTICS = {
  'sceneDiagnosticLog' => 'func sceneDiagnosticLog(_ message: String) {}'
}.freeze

def host_diagnostics(sources)
  text = sources.map { |source| File.read(source) }.join("\n")
  "import Foundation\n" + HOST_DIAGNOSTICS.select do |name, _|
    text.match?(/\b#{name}\b/) && !text.match?(/\bfunc\s+#{name}\b/)
  end.values.map { |stub| "#{stub}\n" }.join
end

runtime = File.expand_path('../Classes/Runtime', __dir__)
surface = File.read(File.join(runtime, 'SceneRenderV2ImageSurface.swift'))
allocator = surface[/@available\(iOS 15\.0, \*\)\n(?:private )?final class SceneSurfaceNativeOutputAllocator \{.*?^\}/m]
abort 'Production output allocator was not found' unless allocator
Dir.mktmpdir('creator-native-test-') do |temporary|
  support = File.join(temporary, 'Allocator.swift')
  File.write(support, "import Foundation\nimport Metal\n#{allocator}\n")
  presentation = File.read(File.join(runtime, 'PictureInPictureHandler.swift'))
  alignment = presentation[/struct SceneMediaSourceAlignment: Equatable \{.*?(?=final class SceneSurfaceSignalDeadline \{)/m]
  abort 'Production source alignment types were not found' unless alignment
  alignment_support = File.join(temporary, 'SourceAlignment.swift')
  File.write(alignment_support, "import Foundation\nimport CoreImage\nimport QuartzCore\n#{alignment}\n")
  executable = File.join(temporary, 'creator-tests')
  sources = Dir[File.join(runtime, 'SceneCatalog*.swift')].sort +
    [File.join(runtime, 'SceneRenderSignalFrameV2.swift'),
     File.join(runtime, 'SceneRegisteredImage.swift')]
  host_support = File.join(temporary, 'HostDiagnostics.swift')
  File.write(host_support, host_diagnostics([alignment_support, *sources]))
  command = ['xcrun', 'swiftc', '-O', '-o', executable, support, alignment_support, host_support,
    *sources, File.join(__dir__, 'creator_catalog_tests.swift')]
  output, status = Open3.capture2e(*command)
  puts output unless output.empty?
  abort 'Creator native tests failed to compile' unless status.success?
  output, status = Open3.capture2e(executable)
  puts output
  abort 'Creator native tests failed' unless status.success?
  unless ARGV.empty?
    catalog = File.expand_path(ARGV.fetch(0))
    abort "Creator catalog not found: #{catalog}" unless File.file?(catalog)
    # Stateful programs have their own full native admission probe. Keep this
    # compatibility check scoped to the legacy shader format.
    parsed = JSON.parse(File.read(catalog))
    parsed['visuals'].reject! { |entry| entry['kind'] == 'scene' }
    unless parsed['visuals'].empty?
      legacy = File.join(temporary, 'legacy-catalog.json')
      File.write(legacy, JSON.generate(parsed))
      output, status = Open3.capture2e(executable, legacy, *ARGV.drop(1))
      puts output
      abort 'Authored creator catalog Metal smoke failed' unless status.success?
    end
  end
end
