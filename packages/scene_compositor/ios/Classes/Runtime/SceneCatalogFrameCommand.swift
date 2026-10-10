import Foundation
import Metal

/// One ordered GPU submission for an authored frame. Renderers encode into
/// this command without waiting between draws; the owner waits before publish
/// or reuse. Include superseded scratch allocations until GPU completion.
@available(iOS 15.0, *)
final class SceneCatalogFrameCommand {
  let command: MTLCommandBuffer
  private let budgetBytes: Int
  private var resources = Set<ObjectIdentifier>()
  private(set) var retainedBytes = 0

  init(queue: MTLCommandQueue, budgetBytes: Int = 128 * 1024 * 1024) throws {
    guard let command = queue.makeCommandBuffer() else { throw Failure("frame_command_unavailable") }
    self.command = command
    self.budgetBytes = budgetBytes
  }

  func retain(_ resource: MTLResource) throws {
    guard resource.storageMode != .memoryless,
      resources.insert(ObjectIdentifier(resource)).inserted else { return }
    guard resource.allocatedSize <= budgetBytes - retainedBytes else {
      throw Failure("frame_intermediate_budget")
    }
    retainedBytes += resource.allocatedSize
  }

  func complete() throws {
    command.commit(); command.waitUntilCompleted()
    guard command.status == .completed else { throw command.error ?? Failure("frame_command_failed") }
  }

  private struct Failure: LocalizedError {
    let code: String
    init(_ code: String) { self.code = code }
    var errorDescription: String? { code }
  }
}
