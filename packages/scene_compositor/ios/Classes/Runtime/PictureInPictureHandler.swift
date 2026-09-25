import AVFoundation
import AVKit
import CoreImage
import CoreMedia
import CoreVideo
import CryptoKit
import Flutter
import ImageIO
import Metal
import UIKit

/// Queue-confined, reusable deadline. A completed delivery disarms the timer
/// instead of leaving an asyncAfter closure queued for every musical frame.
final class SceneSurfaceSignalDeadline {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var deadline: DispatchTime?
    private var onTimeout: (() -> Void)?

    init(queue: DispatchQueue) { self.queue = queue }

    var isArmed: Bool { deadline != nil }

    func arm(after delay: TimeInterval, onTimeout: @escaping () -> Void) {
        precondition(delay.isFinite && delay > 0)
        if timer == nil {
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .distantFuture)
            source.setEventHandler { [weak self] in self?.expireIfNeeded() }
            source.resume()
            timer = source
        }
        let nextDeadline = DispatchTime.now() + delay
        deadline = nextDeadline
        self.onTimeout = onTimeout
        timer?.schedule(deadline: nextDeadline)
    }

    func cancel() {
        deadline = nil
        onTimeout = nil
        timer?.schedule(deadline: .distantFuture)
    }

    func expireIfNeeded(now: DispatchTime = .now()) {
        // An already enqueued event from a cancelled/replaced deadline must
        // never expire the next delivery early.
        guard let deadline, now >= deadline else { return }
        let action = onTimeout
        cancel()
        action?()
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

func sceneSurfaceAttachReceiptLine(
    sessionId: String?,
    outcome: String,
    code: String?,
    elapsedMilliseconds: Int
) -> String {
    let normalizedSessionId = sessionId.flatMap { value in
        value.isEmpty ? nil : value
    } ?? "<missing>"
    let normalizedCode = code.flatMap { value in
        value.isEmpty ? nil : value
    } ?? "none"
    return "[SceneSurfaceAttach] sessionId=\(normalizedSessionId) " +
        "outcome=\(outcome) code=\(normalizedCode) " +
        "elapsedMs=\(max(0, elapsedMilliseconds))"
}

func sceneSurfaceCapabilityReceiptLine(
    supported: Bool,
    rendererRevision: String,
    metalContextAvailable: Bool,
    infernoPipelineAvailable: Bool,
    pollenPipelineAvailable: Bool,
    onePassInfernoPipelineAvailable: Bool,
    packedVideoPipelineAvailable: Bool,
    textureCacheAvailable: Bool,
    rasterOrderGroupsSupported: Bool
) -> String {
    "[SceneSurfaceCapability] supported=\(supported) " +
        "rendererRevision=\(rendererRevision) " +
        "metalContext=\(metalContextAvailable) " +
        "infernoPipeline=\(infernoPipelineAvailable) " +
        "pollenPipeline=\(pollenPipelineAvailable) " +
        "onePassInfernoPipeline=\(onePassInfernoPipelineAvailable) " +
        "packedVideoPipeline=\(packedVideoPipelineAvailable) " +
        "textureCache=\(textureCacheAvailable) " +
        "rasterOrderGroups=\(rasterOrderGroupsSupported)"
}

func sceneSurfaceVideoOutputPixelFormat(
    alphaMode: String,
    codecTypes: [FourCharCode],
    encodedWidths: [Int32],
    fullRangeVideoExtensions: [Any?]
) -> OSType {
    guard
        alphaMode == "normal" || alphaMode == "packedSideBySide",
        !codecTypes.isEmpty,
        codecTypes.allSatisfy({ $0 == kCMVideoCodecType_H264 })
    else {
        return kCVPixelFormatType_32BGRA
    }
    if alphaMode == "packedSideBySide" && (
        encodedWidths.count != codecTypes.count ||
        !encodedWidths.allSatisfy({ $0 > 0 && $0.isMultiple(of: 4) })
    ) {
        return kCVPixelFormatType_32BGRA
    }

    let sourceReliablyDeclaresFullRange =
        fullRangeVideoExtensions.count == codecTypes.count &&
        fullRangeVideoExtensions.allSatisfy { value in
            guard
                let number = value as? NSNumber,
                CFGetTypeID(number) == CFBooleanGetTypeID()
            else {
                return false
            }
            return number.boolValue
        }
    return sourceReliablyDeclaresFullRange
        ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
}

func prepareSceneVideoPixelBufferForAlphaMode(
    _ pixelBuffer: CVPixelBuffer,
    alphaMode: String
) {
    guard alphaMode == "straightAlpha" else { return }
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferAlphaChannelModeKey,
        kCVImageBufferAlphaChannelMode_StraightAlpha,
        .shouldPropagate
    )
}

private enum SceneSurfacePackedAlphaKernel {
    // Both samples are already in CI's working space, exactly as in the
    // previous color-matrix + alpha-mask blend. Unpremultiply the mask before
    // extracting red, so transformed crop edges do not apply coverage twice.
    static let unpack = CIColorKernel(source: """
        kernel vec4 sceneUnpackAlpha(__sample color, __sample mask) {
            return color * clamp(unpremultiply(mask).r, 0.0, 1.0);
        }
        """)
}

func normalizedSceneLayerAlpha(
    _ input: CIImage,
    mode: String
) -> CIImage? {
    switch mode {
    case "normal", "straightAlpha":
        return input
    case "packedSideBySide":
        let extent = input.extent.integral
        let halfWidth = floor(extent.width * 0.5)
        guard halfWidth >= 1, extent.height >= 1 else { return nil }
        let colorRect = CGRect(
            x: extent.minX,
            y: extent.minY,
            width: halfWidth,
            height: extent.height
        )
        let alphaRect = CGRect(
            x: extent.minX + halfWidth,
            y: extent.minY,
            width: halfWidth,
            height: extent.height
        )
        let color = input.cropped(to: colorRect)
        let alpha = input.cropped(to: alphaRect).transformed(
            by: CGAffineTransform(
                translationX: colorRect.minX - alphaRect.minX,
                y: 0
            )
        )
        return SceneSurfacePackedAlphaKernel.unpack?.apply(
            extent: colorRect, arguments: [color, alpha]
        )?.cropped(to: colorRect)
    default:
        return nil
    }
}

/// Reuses an immutable Core Image graph, not a rendered texture. Each owner
/// retains at most one source and result; replacing the source releases both.
final class SceneSurfaceImageGraphCache<Key: Equatable> {
    private var source: CIImage?
    private var key: Key?
    private var result: CIImage?

    func image(
        for source: CIImage,
        key: Key,
        build: () -> CIImage?
    ) -> CIImage? {
        if self.source === source, self.key == key, let result {
            return result
        }
        reset()
        guard let result = build() else { return nil }
        self.source = source
        self.key = key
        self.result = result
        return result
    }

    func reset() {
        result = nil
        source = nil
        key = nil
    }
}

struct SceneSurfaceLayerPreparationKey: Equatable {
    let targetRect: CGRect
    let rgbGain: Double
}

/// Document-owned accounting follows the actual texture, including CI graphs
/// retained after a layer reset. No cache lease can hide an outstanding reader.
final class SceneSurfaceStableRasterBudget {
    private struct Allocation {
        weak var texture: MTLTexture?
        let bytes: Int
    }
    let maximumBytes: Int
    private let lock = NSLock()
    private var allocations = [Allocation]()

    init(maximumBytes: Int = 64 * 1024 * 1024) {
        self.maximumBytes = max(0, maximumBytes)
    }

    var retainedBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        allocations.removeAll { $0.texture == nil }
        return allocations.reduce(0) { $0 + $1.bytes }
    }

    func makeTexture(device: MTLDevice, descriptor: MTLTextureDescriptor) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        allocations.removeAll { $0.texture == nil }
        let retained = allocations.reduce(0) { $0 + $1.bytes }
        let estimated = device.heapTextureSizeAndAlign(descriptor: descriptor).size
        guard estimated > 0, estimated <= maximumBytes - retained,
              allocations.count < 64,
              let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let bytes = max(estimated, texture.allocatedSize)
        guard bytes <= maximumBytes - retained else { return nil }
        allocations.append(Allocation(texture: texture, bytes: bytes))
        return texture
    }
}

/// Explicit, full-precision materialization, never Core Image's global cache.
/// Only the second use of an unchanged eligible graph allocates. Each returned
/// CIImage owns an immutable target; reset never makes that texture writable.
final class SceneSurfaceStableRasterCache {
    private let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let budget: SceneSurfaceStableRasterBudget
    private let colorSpace: CGColorSpace
    private var source: CIImage?
    private var bounds: CGRect?
    private var result: CIImage?
    private var attempted = false
    private(set) var materializationCount = 0
    private(set) var materializationGPUSeconds: CFTimeInterval = 0

    init(device: MTLDevice, context: CIContext, commandQueue: MTLCommandQueue,
         budget: SceneSurfaceStableRasterBudget) {
        self.device = device
        self.context = context
        self.commandQueue = commandQueue
        self.budget = budget
        colorSpace = context.workingColorSpace ??
            CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
    }

    func image(for source: CIImage, bounds: CGRect, eligible: Bool) -> CIImage {
        guard eligible, bounds.origin == .zero,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width <= 8192, bounds.height <= 8192,
              bounds == bounds.integral, source.extent == bounds else {
            reset()
            return source
        }
        guard self.source === source, self.bounds == bounds else {
            reset()
            self.source = source
            self.bounds = bounds
            return source
        }
        if let result { return result }
        // A failed allocation/render stays on the correct original graph for
        // this generation; do not repeat an expensive failure at sibling FPS.
        guard !attempted else { return source }
        attempted = true
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: Int(bounds.width), height: Int(bounds.height), mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        guard let texture = budget.makeTexture(device: device, descriptor: descriptor),
              let command = commandQueue.makeCommandBuffer() else { return source }
        command.label = "SceneSurface Stable Source Raster"
        context.render(source, to: texture, commandBuffer: command,
                       bounds: bounds, colorSpace: colorSpace)
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else {
            NSLog("[SceneSurface] stable source raster failed; original graph retained (status=%ld)",
                  command.status.rawValue)
            return source
        }
        guard let image = CIImage(mtlTexture: texture, options: [.colorSpace: colorSpace]) else {
            NSLog("[SceneSurface] stable source raster image unavailable; original graph retained")
            return source
        }
        result = image
        materializationCount += 1
        if command.gpuEndTime >= command.gpuStartTime, command.gpuStartTime > 0 {
            materializationGPUSeconds += command.gpuEndTime - command.gpuStartTime
        }
        return image
    }

    func reset() {
        result = nil
        source = nil
        bounds = nil
        attempted = false
    }
}

func sceneSurfaceLayerSemanticsAreExplicit(
    _ definition: [String: Any]
) -> Bool {
    definition["alphaMode"] is String && definition["audioReactive"] is Bool
}

/// A process-wide reservation precedes every V1 AVPlayer (including paused
/// candidates and the companion). Document admission remains a separate limit.
final class SceneSurfaceVideoReservations {
    static let shared = SceneSurfaceVideoReservations(capacity: SceneSurfaceVideoAdmission.maximumResidentPlayers)
    final class Lease {
        private let owner: SceneSurfaceVideoReservations
        fileprivate init(_ owner: SceneSurfaceVideoReservations) { self.owner = owner }
        deinit { owner.release() }
    }
    let capacity: Int
    private let lock = NSLock()
    private var count = 0
    private var peak = 0
    init(capacity: Int) { self.capacity = max(0, capacity) }
    var available: Int {
        lock.lock(); defer { lock.unlock() }
        return capacity - count
    }
    var diagnostics: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["resident": count, "peak": peak, "capacity": capacity]
    }
    func reserve() -> Lease? {
        lock.lock(); defer { lock.unlock() }
        guard count < capacity else { return nil }
        count += 1
        peak = max(peak, count)
        return Lease(self)
    }
    private func release() {
        lock.lock(); defer { lock.unlock() }
        precondition(count > 0)
        count -= 1
    }
}

func sceneSurfaceVideoLayerCountIsSupported(
    _ definitions: [[String: Any]],
    maximum: Int = 2,
    maximumAlpha: Int = 2,
    maximumAlphaWithPackedSource: Int = 2
) -> Bool {
    guard
        maximum >= 0,
        maximumAlpha >= 0,
        maximumAlphaWithPackedSource >= 0
    else { return false }
    let videoDefinitions = definitions.lazy.filter {
        $0["sourceKind"] as? String == "video"
    }
    guard videoDefinitions.count <= maximum else { return false }
    let alphaDefinitions = videoDefinitions.filter {
        ($0["alphaMode"] as? String ?? "normal") != "normal"
    }
    guard alphaDefinitions.count <= maximumAlpha else { return false }
    let includesPackedSource = alphaDefinitions.contains {
        ($0["alphaMode"] as? String) == "packedSideBySide"
    }
    return !includesPackedSource ||
        alphaDefinitions.count <= maximumAlphaWithPackedSource
}

/// Installed, device-specific admission. The remote catalog cannot extend it.
/// Larger documents must additionally pass the real-file range below.
enum SceneSurfaceVideoAdmission {
    static let revision = "ios-v1-h264-four-v1"
    static let maximumResidentPlayers = 4
    static let maximumEncodedPixelsPerSecond = 225_000_000.0
    static let current: (profileID: String, limit: Int) = {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        // Candidate profiles are exercised by the physical qualification run.
        let installedModels: Set<String> = ["iPhone15,2", "iPad13,4"]
        guard installedModels.contains(model), os.majorVersion == 27,
              os.minorVersion == 0 else { return ("ios-v1-unqualified-two", 2) }
        return ("\(revision):\(model):27.0", 4)
    }()

    static func supports(_ videos: [(SceneSurfaceVideoAssetInspection, String)]) -> Bool {
        guard videos.count <= current.limit else { return false }
        if videos.count <= 2 { return true }
        var pixelsPerSecond = 0.0
        for (media, alpha) in videos {
            guard !media.contentSHA256.isEmpty, media.isCurrent,
                  ["normal", "packedSideBySide"].contains(alpha),
                  media.nominalFrameRate.isFinite,
                  media.nominalFrameRate > 0, media.nominalFrameRate <= 30.01,
                  !media.formatDescriptions.isEmpty else { return false }
            var maximumPixels = 0
            for format in media.formatDescriptions {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                guard CMFormatDescriptionGetMediaSubType(format) == kCMVideoCodecType_H264,
                      dimensions.width > 0, dimensions.height > 0,
                      dimensions.width <= 3840, dimensions.height <= 2160,
                      dimensions.width.isMultiple(of: 2), dimensions.height.isMultiple(of: 2),
                      let atoms = CMFormatDescriptionGetExtension(format,
                        extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
                      let configuration = atoms["avcC"] as? Data,
                      configuration.count > 3,
                      [66, 77, 88, 100].contains(Int(configuration[1]))
                else { return false }
                let pixels = Int(dimensions.width) * Int(dimensions.height)
                guard pixels <= 1920 * 2160 else { return false }
                maximumPixels = max(maximumPixels, pixels)
            }
            pixelsPerSecond += Double(maximumPixels) * Double(media.nominalFrameRate)
        }
        return pixelsPerSecond <= maximumEncodedPixelsPerSecond
    }
}

func sceneSurfaceVideoFramesPerSecond(_ nominalFrameRate: Float) -> Int {
    guard nominalFrameRate.isFinite, nominalFrameRate > 0 else { return 30 }
    return min(max(Int(nominalFrameRate.rounded()), 12), 60)
}

let sceneSurfaceAnimatedImageResidentFrameLimit = 1

/// Work observed by one native layer at a scheduled scene tick.
///
/// Source cadence is independent from the scene's maximum cadence. A 24 fps
/// decoder inside a 30 fps scene therefore does not make an unchanged tick a
/// new frame. Time-driven programs and active effect envelopes remain eligible
/// on every authored tick, while a fresh audio frame invalidates reactive
/// transforms even when their media source has not advanced.
struct SceneSurfaceLayerFrameWork: Equatable {
    let sourceAdvanced: Bool
    let timeDriven: Bool
    let effectAnimating: Bool
    let audioAdvanced: Bool

    var requiresComposition: Bool {
        sourceAdvanced || timeDriven || effectAnimating || audioAdvanced
    }
}

/// Keeps a dynamic layer on its own authored cadence when the document timer
/// is faster because of a sibling. The deadline advances from its prior phase
/// instead of from the latest callback, avoiding drift at ratios such as
/// 24 fps inside a 60 fps document.
struct SceneSurfaceLayerCadenceClock {
    private var framesPerSecond = 0
    private var nextDueAt: CFTimeInterval?

    mutating func consumeIfDue(
        at hostTime: CFTimeInterval,
        framesPerSecond requestedFramesPerSecond: Int
    ) -> Bool {
        guard hostTime.isFinite else { return false }
        let resolvedFramesPerSecond = min(
            max(requestedFramesPerSecond, 1),
            60
        )
        let interval = 1.0 / Double(resolvedFramesPerSecond)
        if framesPerSecond != resolvedFramesPerSecond || nextDueAt == nil {
            framesPerSecond = resolvedFramesPerSecond
            nextDueAt = hostTime + interval
            return true
        }
        let tolerance = interval * 0.10
        guard let dueAt = nextDueAt,
              hostTime + tolerance >= dueAt else {
            return false
        }
        var followingDueAt = dueAt + interval
        while followingDueAt <= hostTime + tolerance {
            followingDueAt += interval
        }
        nextDueAt = followingDueAt
        return true
    }

    mutating func markEvaluated(
        at hostTime: CFTimeInterval,
        framesPerSecond requestedFramesPerSecond: Int
    ) {
        guard hostTime.isFinite else { return }
        let resolvedFramesPerSecond = min(
            max(requestedFramesPerSecond, 1),
            60
        )
        framesPerSecond = resolvedFramesPerSecond
        nextDueAt = hostTime + 1.0 / Double(resolvedFramesPerSecond)
    }

    mutating func reset() {
        framesPerSecond = 0
        nextDueAt = nil
    }
}

/// Samples the newest input only on the effect's authored cadence. Compositing
/// may still happen more frequently because of another layer; those passes
/// reuse the held effect state instead of advancing its envelope again.
@discardableResult
func sceneSurfaceSampleAndHoldEffectIfDue<Input>(
    cadenceClock: inout SceneSurfaceLayerCadenceClock,
    at hostTime: CFTimeInterval,
    framesPerSecond: Int,
    latestInput: Input,
    sample: (Input, CFTimeInterval) -> Void
) -> Bool {
    guard cadenceClock.consumeIfDue(
        at: hostTime,
        framesPerSecond: framesPerSecond
    ) else {
        return false
    }
    sample(latestInput, hostTime)
    return true
}

struct SceneSurfaceDynamicSourceCacheKey: Equatable {
    let width: Int
    let height: Int

    init?(width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
    }
}

struct SceneSurfaceCompositionRetryState {
    private(set) var isPending = false

    mutating func shouldCompose(observedWork: Bool) -> Bool {
        isPending = isPending || observedWork
        return isPending
    }

    mutating func didPublish() {
        isPending = false
    }
}

func sceneSurfaceProceduralSourceNeedsContinuousFrames(
    preset: String?,
    statefulStormActive: Bool
) -> Bool {
    guard let preset else { return false }
    if preset == "deep_void_v1" { return false }
    if preset == SceneSurfaceStatefulStormRecipeV1.preset {
        return statefulStormActive
    }
    return true
}

func sceneSurfaceScheduledDynamicSourceRefresh(
    sourceKind: String,
    sourceDue: Bool,
    intrinsicSourceAnimating: Bool,
    audioAdvanced: Bool,
    isAudioReactive: Bool
) -> Bool {
    if sourceDue { return true }
    return sourceKind == "realtimeRenderer" &&
        !intrinsicSourceAnimating &&
        audioAdvanced &&
        isAudioReactive
}

/// Reuses the backing allocation of CPU-authored procedural frames until the
/// target dimensions change. Programs still clear and redraw every authored
/// frame, so this changes allocation behavior only, never their pixels.
final class SceneSurfaceReusableBitmapCanvas {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var bitmapContext: CGContext?
    private var width = 0
    private var height = 0
    private(set) var allocationCount = 0

    func context(width: Int, height: Int) -> CGContext? {
        guard width >= 1, height >= 1 else { return nil }
        if bitmapContext == nil || self.width != width || self.height != height {
            guard let created = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return nil
            }
            bitmapContext = created
            self.width = width
            self.height = height
            allocationCount += 1
        }
        return bitmapContext
    }
}

@available(iOS 15.0, *)
enum SceneSurfaceDualRadialMode: UInt32, CaseIterable {
    case infernoAdditive = 0
    case pollenSourceOver = 1

    var pixelFormat: MTLPixelFormat {
        switch self {
        case .infernoAdditive:
            return .bgra8Unorm
        case .pollenSourceOver:
            return .rgba16Float
        }
    }
}

@available(iOS 15.0, *)
enum SceneSurfaceDualRadialRenderingPath: Equatable {
    case gpu
    case cpuReference
}

@available(iOS 15.0, *)
struct SceneSurfaceDualRadialInstance {
    var centerAndRadii: SIMD4<Float>
    var haloColorAndOpacity: SIMD4<Float>
    var coreColorAndOpacity: SIMD4<Float>
}

@available(iOS 15.0, *)
struct SceneSurfaceDualRadialGlobals {
    var viewport: SIMD2<Float>
    var mode: UInt32
    var padding: UInt32 = 0
}

@available(iOS 15.0, *)
enum SceneSurfaceDualRadialFalloff {
    static func infernoHalo(_ normalizedDistance: Float) -> Float {
        let distance = min(max(normalizedDistance, 0), 1)
        if distance <= 0.46 {
            return 1 + (0.32 - 1) * (distance / 0.46)
        }
        return 0.32 * (1 - (distance - 0.46) / 0.54)
    }

    static func pollenHalo(_ normalizedDistance: Float) -> Float {
        max(1 - normalizedDistance, 0)
    }

    static func pollenCore(_ normalizedDistance: Float) -> Float {
        guard normalizedDistance > 0.3 else { return 1 }
        return max(1 - (normalizedDistance - 0.3) / 0.7, 0)
    }

    static func sourceOver(
        foreground: SIMD4<Float>,
        background: SIMD4<Float>
    ) -> SIMD4<Float> {
        foreground + background * (1 - foreground.w)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceInfernoGPUColorTable {
    let signature: [CGFloat]
    let haloColors: [SIMD3<Float>]

    init(colors: [CIColor]) {
        signature = colors.flatMap { color in
            [color.red, color.green, color.blue]
        }
        let targetColorSpace = CGColorSpaceCreateDeviceRGB()
        haloColors = colors.map { color in
            Self.convertedComponents(
                red: color.red,
                green: color.green,
                blue: color.blue,
                targetColorSpace: targetColorSpace
            )
        }
    }

    private static func convertedComponents(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        targetColorSpace: CGColorSpace
    ) -> SIMD3<Float> {
        let source = CGColor(red: red, green: green, blue: blue, alpha: 1)
        let converted = source.converted(
            to: targetColorSpace,
            intent: .defaultIntent,
            options: nil
        ) ?? source
        guard let components = converted.components, components.count >= 3 else {
            return SIMD3(Float(red), Float(green), Float(blue))
        }
        return SIMD3(
            Float(components[0]),
            Float(components[1]),
            Float(components[2])
        )
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceRenderPathMetricsSnapshot: Equatable {
    let gpuSubmitted: UInt64
    let gpuCompleted: UInt64
    let topLevelGPUSubmitted: UInt64
    let topLevelGPUCompleted: UInt64
    let cpuReference: UInt64
    let fallback: UInt64
    let currentPath: String
    let metalPipelineAvailable: Bool
    let gpuFailureLatched: Bool
    let gpuFailureCount: UInt64
    let timedGPUCompletions: UInt64
    let gpuExecutionSeconds: Double
    let timedMetalCompletions: UInt64
    let timedCoreImageCompletions: UInt64
}

/// Passive, session-owned native composition cost. These durations cover only
/// completed Metal commands/Core Image kernels: not video decode, Flutter or
/// the OS compositor, CPU encoding, scheduling latency, or device utilization.
/// A partial frame never becomes a sample or an invented zero-cost measurement.
@available(iOS 15.0, *)
struct SceneSurfaceGPUFrameTiming {
    private(set) var completedFrameCount: UInt64 = 0
    private(set) var totalTimeMs = 0.0
    private(set) var lastFrameTimeMs: Double?
    private(set) var sampleTimeSeconds: CFTimeInterval?
    private(set) var timingSource: String?

    mutating func invalidateLatest() {
        lastFrameTimeMs = nil
        sampleTimeSeconds = nil
    }

    mutating func record(
        baseline: SceneSurfaceRenderPathMetricsSnapshot,
        snapshot: SceneSurfaceRenderPathMetricsSnapshot,
        completedAt: CFTimeInterval
    ) {
        invalidateLatest()
        guard snapshot.metalPipelineAvailable,
              !snapshot.gpuFailureLatched,
              snapshot.cpuReference == baseline.cpuReference,
              snapshot.fallback == baseline.fallback,
              snapshot.gpuSubmitted >= baseline.gpuSubmitted,
              snapshot.gpuCompleted >= baseline.gpuCompleted,
              snapshot.timedGPUCompletions >= baseline.timedGPUCompletions,
              snapshot.topLevelGPUCompleted > baseline.topLevelGPUCompleted,
              completedAt.isFinite, completedAt > 0 else { return }
        let submitted = snapshot.gpuSubmitted - baseline.gpuSubmitted
        let completed = snapshot.gpuCompleted - baseline.gpuCompleted
        let timed = snapshot.timedGPUCompletions - baseline.timedGPUCompletions
        let milliseconds = (snapshot.gpuExecutionSeconds -
            baseline.gpuExecutionSeconds) * 1_000
        guard submitted > 0, submitted == completed, completed == timed,
              snapshot.topLevelGPUCompleted - baseline.topLevelGPUCompleted == 1,
              milliseconds.isFinite, milliseconds >= 0 else { return }
        let hasMetal = snapshot.timedMetalCompletions > baseline.timedMetalCompletions
        let hasCoreImage = snapshot.timedCoreImageCompletions >
            baseline.timedCoreImageCompletions
        let source = hasMetal
            ? (hasCoreImage ? "metal_and_core_image_kernels" : "metal_command_buffer")
            : "core_image_kernels"
        guard completedFrameCount < UInt64.max,
              (totalTimeMs + milliseconds).isFinite else { return }
        completedFrameCount += 1
        totalTimeMs += milliseconds
        lastFrameTimeMs = milliseconds
        sampleTimeSeconds = completedAt
        // Cached native subpasses need not execute on every CI frame. Keep
        // cumulative counters monotonic and describe the union of measured work.
        timingSource = timingSource == nil || timingSource == source
            ? source : "metal_and_core_image_kernels"
    }

    var payload: [String: Any] {
        guard let lastFrameTimeMs, let sampleTimeSeconds, let timingSource else {
            return [:]
        }
        return [
            "gpuCompletedFrameCount": Int(min(completedFrameCount, UInt64(Int.max))),
            "gpuTotalTimeMs": totalTimeMs,
            "gpuLastFrameTimeMs": lastFrameTimeMs,
            "gpuSampleTimeSeconds": sampleTimeSeconds,
            "gpuTimingSource": timingSource,
        ]
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceRenderPathMetrics {
    static let sceneSurfaceCIGPUPath = "scene_surface_ci_gpu"

    private struct State {
        var gpuSubmitted: UInt64 = 0
        var gpuCompleted: UInt64 = 0
        var topLevelGPUSubmitted: UInt64 = 0
        var topLevelGPUCompleted: UInt64 = 0
        var cpuReference: UInt64 = 0
        var fallback: UInt64 = 0
        var currentPath = "uninitialized"
        var topLevelPath: String?
        var metalPipelineAvailable = false
        var gpuFailureLatched = false
        var gpuFailureCount: UInt64 = 0
        var timedGPUCompletions: UInt64 = 0
        var gpuExecutionSeconds = 0.0
        var timedMetalCompletions: UInt64 = 0
        var timedCoreImageCompletions: UInt64 = 0
    }

    private let lock = NSLock()
    private var aggregate = State()
    private var scoped = [String: State]()

    func setMetalPipelineAvailable(_ available: Bool) {
        lock.lock()
        aggregate.metalPipelineAvailable = available
        lock.unlock()
    }

    func recordGPUSubmission(
        path: String,
        scope: String? = nil,
        topLevel: Bool = false
    ) {
        lock.lock()
        mutate(scope: scope) { state in
            state.gpuSubmitted &+= 1
            state.currentPath = path
            if topLevel {
                state.topLevelGPUSubmitted &+= 1
            }
        }
        lock.unlock()
    }

    func recordGPUCompletion(
        path: String,
        failed: Bool,
        scope: String? = nil,
        topLevel: Bool = false,
        executionSeconds: Double? = nil,
        coreImage: Bool = false
    ) {
        lock.lock()
        mutate(scope: scope) { state in
            if failed {
                state.gpuFailureLatched = true
                state.gpuFailureCount &+= 1
                state.currentPath = "metal_failure"
                if topLevel { state.topLevelPath = nil }
            } else {
                state.gpuCompleted &+= 1
                if let executionSeconds,
                   executionSeconds.isFinite, executionSeconds >= 0,
                   (state.gpuExecutionSeconds + executionSeconds).isFinite {
                    state.timedGPUCompletions &+= 1
                    state.gpuExecutionSeconds += executionSeconds
                    if coreImage {
                        state.timedCoreImageCompletions &+= 1
                    } else {
                        state.timedMetalCompletions &+= 1
                    }
                }
                state.currentPath = path
                if topLevel {
                    state.topLevelGPUCompleted &+= 1
                    state.topLevelPath = path
                }
            }
        }
        lock.unlock()
    }

    func recordCPUReference(
        fallbackFromGPU: Bool,
        scope: String? = nil
    ) {
        lock.lock()
        mutate(scope: scope) { state in
            state.cpuReference &+= 1
            if fallbackFromGPU { state.fallback &+= 1 }
            state.currentPath = fallbackFromGPU
                ? "cpu_reference_fallback_ci"
                : "cpu_reference_ci"
        }
        lock.unlock()
    }

    @discardableResult
    func recordCIFallback(
        path: String = "v12_ci",
        scope: String? = nil,
        ifFallbackCountEquals expectedFallbackCount: UInt64? = nil
    ) -> Bool {
        lock.lock()
        let currentFallbackCount: UInt64
        if let scope {
            currentFallbackCount = scoped[scope]?.fallback ?? 0
        } else {
            currentFallbackCount = aggregate.fallback
        }
        if let expectedFallbackCount,
           currentFallbackCount != expectedFallbackCount {
            lock.unlock()
            return false
        }
        mutate(scope: scope) { state in
            state.fallback &+= 1
            state.currentPath = path
        }
        lock.unlock()
        return true
    }

    func snapshot(scope: String? = nil) -> SceneSurfaceRenderPathMetricsSnapshot {
        lock.lock()
        var state: State
        if let scope {
            state = scoped[scope] ?? State()
            state.metalPipelineAvailable = aggregate.metalPipelineAvailable
        } else {
            state = aggregate
        }
        let value = SceneSurfaceRenderPathMetricsSnapshot(
            gpuSubmitted: state.gpuSubmitted,
            gpuCompleted: state.gpuCompleted,
            topLevelGPUSubmitted: state.topLevelGPUSubmitted,
            topLevelGPUCompleted: state.topLevelGPUCompleted,
            cpuReference: state.cpuReference,
            fallback: state.fallback,
            currentPath: state.topLevelPath ?? state.currentPath,
            metalPipelineAvailable: state.metalPipelineAvailable,
            gpuFailureLatched: state.gpuFailureLatched,
            gpuFailureCount: state.gpuFailureCount,
            timedGPUCompletions: state.timedGPUCompletions,
            gpuExecutionSeconds: state.gpuExecutionSeconds,
            timedMetalCompletions: state.timedMetalCompletions,
            timedCoreImageCompletions: state.timedCoreImageCompletions
        )
        lock.unlock()
        return value
    }

    func removeScope(_ scope: String) {
        lock.lock()
        scoped.removeValue(forKey: scope)
        lock.unlock()
    }

    var scopedStateCount: Int {
        lock.lock()
        let count = scoped.count
        lock.unlock()
        return count
    }

    private func mutate(
        scope: String?,
        _ body: (inout State) -> Void
    ) {
        body(&aggregate)
        guard let scope else { return }
        var value = scoped[scope] ?? State(
            metalPipelineAvailable: aggregate.metalPipelineAvailable
        )
        body(&value)
        scoped[scope] = value
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceGPUCompletionRecorder {
    private let lock = NSLock()
    private let metrics: SceneSurfaceRenderPathMetrics
    private let path: String
    private let scope: String?
    private var recorded = false

    init(
        metrics: SceneSurfaceRenderPathMetrics,
        path: String,
        scope: String?
    ) {
        self.metrics = metrics
        self.path = path
        self.scope = scope
    }

    func record(commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard !recorded else {
            lock.unlock()
            return
        }
        recorded = true
        metrics.recordGPUCompletion(
            path: path,
            failed: commandBuffer.status != .completed,
            scope: scope,
            executionSeconds: commandBuffer.gpuStartTime > 0
                ? commandBuffer.gpuEndTime - commandBuffer.gpuStartTime : nil
        )
        lock.unlock()
    }
}

@available(iOS 15.0, *)
struct SceneSurfacePackedVideoGlobals {
    var targetSize: SIMD2<Float>
    var logicalSourceSize: SIMD2<Float>
    var yuvOffset: SIMD3<Float>
    var yuvToRGB0: SIMD3<Float>
    var yuvToRGB1: SIMD3<Float>
    var yuvToRGB2: SIMD3<Float>
}

@available(iOS 15.0, *)
struct SceneSurfacePreparedInfernoFrame {
    let hostTime: CFTimeInterval
    let size: CGSize
    let instances: [SceneSurfaceDualRadialInstance]
}

struct SceneSurfacePreparedImageCacheState {
    private(set) var preparedHostTime: CFTimeInterval?
    private(set) var materializedHostTime: CFTimeInterval?

    var needsMaterialization: Bool {
        preparedHostTime != nil && preparedHostTime != materializedHostTime
    }

    mutating func select(preparedHostTime: CFTimeInterval) {
        self.preparedHostTime = preparedHostTime
    }

    mutating func didMaterialize() {
        materializedHostTime = preparedHostTime
    }

    mutating func reset() {
        preparedHostTime = nil
        materializedHostTime = nil
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceMetalContext {
    static let shared = SceneSurfaceMetalContext()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let ciContext: CIContext
    let infernoPipeline: MTLRenderPipelineState?
    let pollenPipeline: MTLRenderPipelineState?
    let onePassInfernoPipeline: MTLRenderPipelineState?
    let packedVideoPipeline: MTLRenderPipelineState?
    let textureCache: CVMetalTextureCache?
    let renderPathMetrics = SceneSurfaceRenderPathMetrics()
    let onePassFastMathEnabled: Bool
    private let onePassCompositorLock = NSLock()
    private var storedOnePassCompositor: SceneSurfaceOnePassCompositor?

    var onePassCompositor: SceneSurfaceOnePassCompositor {
        onePassCompositorLock.lock()
        defer { onePassCompositorLock.unlock() }
        if let storedOnePassCompositor { return storedOnePassCompositor }
        let compositor = SceneSurfaceOnePassCompositor(context: self)
        storedOnePassCompositor = compositor
        return compositor
    }

    init?(
        device: MTLDevice? = MTLCreateSystemDefaultDevice(),
        shaderSource: String = SceneSurfaceMetalContext.dualRadialShaderSource,
        onePassShaderSource: String? = nil,
        onePassFastMathEnabled: Bool = true
    ) {
        guard
            let device,
            let commandQueue = device.makeCommandQueue()
        else {
            return nil
        }
        let baseCompileOptions = MTLCompileOptions()
        baseCompileOptions.fastMathEnabled = false
        baseCompileOptions.preprocessorMacros = [
            "SCENE_SURFACE_ENABLE_ONE_PASS": NSNumber(value: false),
        ]
        let baseLibrary = try? device.makeLibrary(
            source: shaderSource,
            options: baseCompileOptions
        )
        let baseVertexFunction = baseLibrary?.makeFunction(
            name: "sceneSurfaceDualRadialVertex"
        )
        let baseFragmentFunction = baseLibrary?.makeFunction(
            name: "sceneSurfaceDualRadialFragment"
        )
        let infernoPipeline: MTLRenderPipelineState?
        let pollenPipeline: MTLRenderPipelineState?
        if let baseVertexFunction, let baseFragmentFunction {
            infernoPipeline = Self.makePipeline(
                device: device,
                vertexFunction: baseVertexFunction,
                fragmentFunction: baseFragmentFunction,
                mode: .infernoAdditive
            )
            pollenPipeline = Self.makePipeline(
                device: device,
                vertexFunction: baseVertexFunction,
                fragmentFunction: baseFragmentFunction,
                mode: .pollenSourceOver
            )
        } else {
            infernoPipeline = nil
            pollenPipeline = nil
        }

        let onePassCompileOptions = MTLCompileOptions()
        onePassCompileOptions.fastMathEnabled = onePassFastMathEnabled
        onePassCompileOptions.preprocessorMacros = [
            "SCENE_SURFACE_ENABLE_ONE_PASS": NSNumber(value: true),
        ]
        let onePassLibrary = device.areRasterOrderGroupsSupported
            ? try? device.makeLibrary(
                source: onePassShaderSource ?? shaderSource,
                options: onePassCompileOptions
            )
            : nil
        let onePassInfernoPipeline: MTLRenderPipelineState?
        let packedVideoPipeline: MTLRenderPipelineState?
        if let onePassLibrary {
            onePassInfernoPipeline = Self.makeOnePassPipeline(
                device: device,
                vertexFunction: onePassLibrary.makeFunction(
                    name: "sceneSurfaceOnePassInfernoVertex"
                ),
                fragmentFunction: onePassLibrary.makeFunction(
                    name: "sceneSurfaceOnePassInfernoFragment"
                ),
                label: "Inferno"
            )
            packedVideoPipeline = Self.makeOnePassPipeline(
                device: device,
                vertexFunction: onePassLibrary.makeFunction(
                    name: "sceneSurfacePackedVideoVertex"
                ),
                fragmentFunction: onePassLibrary.makeFunction(
                    name: "sceneSurfacePackedVideoFragment"
                ),
                label: "PackedVideo"
            )
        } else {
            onePassInfernoPipeline = nil
            packedVideoPipeline = nil
        }
        var createdTextureCache: CVMetalTextureCache?
        let textureCacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &createdTextureCache
        )
        self.device = device
        self.commandQueue = commandQueue
        self.onePassFastMathEnabled = onePassFastMathEnabled
        self.ciContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: [.cacheIntermediates: false]
        )
        self.infernoPipeline = infernoPipeline
        self.pollenPipeline = pollenPipeline
        self.onePassInfernoPipeline = onePassInfernoPipeline
        self.packedVideoPipeline = packedVideoPipeline
        textureCache = textureCacheStatus == kCVReturnSuccess
            ? createdTextureCache
            : nil
        // This context always owns a Metal-backed CIContext on the same
        // command queue. Optional one-pass pipelines have their own exact
        // path/capability checks and must not make the generic SceneSurface
        // compositor look unavailable when only that optimization is absent.
        renderPathMetrics.setMetalPipelineAvailable(true)
    }

    var supportsDualRadialRendering: Bool {
        infernoPipeline != nil && pollenPipeline != nil
    }

    var supportsOnePassPackedVideoRendering: Bool {
        onePassInfernoPipeline != nil &&
            packedVideoPipeline != nil &&
            textureCache != nil &&
            device.areRasterOrderGroupsSupported
    }

    func pipeline(
        for mode: SceneSurfaceDualRadialMode
    ) -> MTLRenderPipelineState? {
        switch mode {
        case .infernoAdditive:
            return infernoPipeline
        case .pollenSourceOver:
            return pollenPipeline
        }
    }

    private static func makePipeline(
        device: MTLDevice,
        vertexFunction: MTLFunction,
        fragmentFunction: MTLFunction,
        mode: SceneSurfaceDualRadialMode
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SceneSurfaceDualRadial.\(mode.rawValue)"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        guard let attachment = descriptor.colorAttachments[0] else {
            return nil
        }
        attachment.pixelFormat = mode.pixelFormat
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        switch mode {
        case .infernoAdditive:
            attachment.destinationRGBBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .one
        case .pollenSourceOver:
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func makeOnePassPipeline(
        device: MTLDevice,
        vertexFunction: MTLFunction?,
        fragmentFunction: MTLFunction?,
        label: String
    ) -> MTLRenderPipelineState? {
        guard let vertexFunction, let fragmentFunction else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "SceneSurfaceOnePass.\(label)"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        guard let attachment = descriptor.colorAttachments[0] else {
            return nil
        }
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = false
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static let dualRadialShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct DualRadialInstance {
            float4 centerAndRadii;
            float4 haloColorAndOpacity;
            float4 coreColorAndOpacity;
        };

        struct DualRadialGlobals {
            float2 viewport;
            uint mode;
            uint padding;
        };

        struct DualRadialVertexOut {
            float4 position [[position]];
            float2 localPixel;
            float4 centerAndRadii [[flat]];
            float4 haloColorAndOpacity [[flat]];
            float4 coreColorAndOpacity [[flat]];
        };

        DualRadialVertexOut sceneSurfaceDualRadialVertexOutput(
            uint vertexId,
            DualRadialInstance instance,
            constant DualRadialGlobals &globals,
            bool flipVertical
        ) {
            const float2 corners[6] = {
                float2(-1.0, -1.0), float2(1.0, -1.0),
                float2(-1.0, 1.0), float2(-1.0, 1.0),
                float2(1.0, -1.0), float2(1.0, 1.0)
            };
            float extraCoverage = globals.mode == 0 ? 1.0 : 0.0;
            float drawRadius = max(
                instance.centerAndRadii.z,
                instance.centerAndRadii.w
            ) + extraCoverage;
            float2 localPixel = corners[vertexId] * drawRadius;
            float2 center = instance.centerAndRadii.xy;
            if (flipVertical) {
                center.y = globals.viewport.y - center.y;
            }
            float2 pixelPosition = center + localPixel;
            float2 normalized = pixelPosition / globals.viewport;

            DualRadialVertexOut output;
            output.position = float4(
                normalized.x * 2.0 - 1.0,
                1.0 - normalized.y * 2.0,
                0.0,
                1.0
            );
            output.localPixel = localPixel;
            output.centerAndRadii = instance.centerAndRadii;
            output.haloColorAndOpacity = instance.haloColorAndOpacity;
            output.coreColorAndOpacity = instance.coreColorAndOpacity;
            return output;
        }

        vertex DualRadialVertexOut sceneSurfaceDualRadialVertex(
            uint vertexId [[vertex_id]],
            uint instanceId [[instance_id]],
            constant DualRadialGlobals &globals [[buffer(0)]],
            device const DualRadialInstance *instances [[buffer(1)]]
        ) {
            return sceneSurfaceDualRadialVertexOutput(
                vertexId,
                instances[instanceId],
                globals,
                false
            );
        }

        #if SCENE_SURFACE_ENABLE_ONE_PASS
        vertex DualRadialVertexOut sceneSurfaceOnePassInfernoVertex(
            uint vertexId [[vertex_id]],
            uint instanceId [[instance_id]],
            constant DualRadialGlobals &globals [[buffer(0)]],
            device const DualRadialInstance *instances [[buffer(1)]]
        ) {
            return sceneSurfaceDualRadialVertexOutput(
                vertexId,
                instances[instanceId],
                globals,
                true
            );
        }
        #endif

        float4 sceneSurfaceInfernoSource(DualRadialVertexOut input) {
            float distanceFromCenter = length(input.localPixel);
            float haloRadius = max(input.centerAndRadii.z, 0.0001);
            float coreRadius = max(input.centerAndRadii.w, 0.0001);
            float haloDistance = clamp(
                distanceFromCenter / haloRadius,
                0.0,
                1.0
            );
            float haloShape = haloDistance <= 0.46
                ? mix(1.0, 0.32, haloDistance / 0.46)
                : mix(0.32, 0.0, (haloDistance - 0.46) / 0.54);
            haloShape *= distanceFromCenter <= haloRadius ? 1.0 : 0.0;
            float haloAlpha = haloShape * input.haloColorAndOpacity.a;
            float edgeWidth = max(fwidth(distanceFromCenter), 0.5);
            float coreCoverage = 1.0 - smoothstep(
                coreRadius - edgeWidth * 0.5,
                coreRadius + edgeWidth * 0.5,
                distanceFromCenter
            );
            float coreAlpha = coreCoverage * input.coreColorAndOpacity.a;
            return float4(
                input.haloColorAndOpacity.rgb * haloAlpha +
                    input.coreColorAndOpacity.rgb * coreAlpha,
                haloAlpha + coreAlpha
            );
        }

        fragment float4 sceneSurfaceDualRadialFragment(
            DualRadialVertexOut input [[stage_in]],
            constant DualRadialGlobals &globals [[buffer(0)]]
        ) {
            if (globals.mode == 0) {
                return sceneSurfaceInfernoSource(input);
            }

            float distanceFromCenter = length(input.localPixel);
            float haloRadius = max(input.centerAndRadii.z, 0.0001);
            float coreRadius = max(input.centerAndRadii.w, 0.0001);
            float haloShape = max(1.0 - distanceFromCenter / haloRadius, 0.0);
            float coreDistance = distanceFromCenter / coreRadius;
            float coreShape = coreDistance <= 0.3
                ? 1.0
                : max(1.0 - (coreDistance - 0.3) / 0.7, 0.0);
            float haloAlpha = haloShape * input.haloColorAndOpacity.a;
            float coreAlpha = coreShape * input.coreColorAndOpacity.a;
            float4 halo = float4(
                input.haloColorAndOpacity.rgb *
                    input.haloColorAndOpacity.a * haloAlpha,
                haloAlpha
            );
            float4 core = float4(
                input.coreColorAndOpacity.rgb *
                    input.coreColorAndOpacity.a * coreAlpha,
                coreAlpha
            );
            return core + halo * (1.0 - core.a);
        }

        #if SCENE_SURFACE_ENABLE_ONE_PASS
        float sceneSurfaceSRGBToLinear(float value) {
            float bounded = max(value, 0.0);
            return bounded <= 0.04045
                ? bounded / 12.92
                : pow((bounded + 0.055) / 1.055, 2.4);
        }

        float3 sceneSurfaceSRGBToLinear(float3 value) {
            return float3(
                sceneSurfaceSRGBToLinear(value.r),
                sceneSurfaceSRGBToLinear(value.g),
                sceneSurfaceSRGBToLinear(value.b)
            );
        }

        float sceneSurfaceLinearToSRGB(float value) {
            float bounded = max(value, 0.0);
            return bounded <= 0.0031308
                ? bounded * 12.92
                : 1.055 * pow(bounded, 1.0 / 2.4) - 0.055;
        }

        float3 sceneSurfaceLinearToSRGB(float3 value) {
            return float3(
                sceneSurfaceLinearToSRGB(value.r),
                sceneSurfaceLinearToSRGB(value.g),
                sceneSurfaceLinearToSRGB(value.b)
            );
        }

        struct SceneSurfaceOnePassColor {
            float4 value [[color(0), raster_order_group(0)]];
        };

        fragment SceneSurfaceOnePassColor sceneSurfaceOnePassInfernoFragment(
            DualRadialVertexOut input [[stage_in]],
            constant DualRadialGlobals &globals [[buffer(0)]],
            SceneSurfaceOnePassColor framebuffer
        ) {
            SceneSurfaceOnePassColor output;
            output.value = framebuffer.value +
                sceneSurfaceInfernoSource(input);
            return output;
        }

        struct PackedVideoGlobals {
            float2 targetSize;
            float2 logicalSourceSize;
            float3 yuvOffset;
            float3 yuvToRGB0;
            float3 yuvToRGB1;
            float3 yuvToRGB2;
        };

        struct PackedVideoVertexOut {
            float4 position [[position]];
            float2 logicalUV;
        };

        vertex PackedVideoVertexOut sceneSurfacePackedVideoVertex(
            uint vertexId [[vertex_id]],
            constant PackedVideoGlobals &globals [[buffer(0)]]
        ) {
            const float2 positions[6] = {
                float2(-1.0, -1.0), float2(1.0, -1.0),
                float2(-1.0, 1.0), float2(-1.0, 1.0),
                float2(1.0, -1.0), float2(1.0, 1.0)
            };
            const float2 coordinates[6] = {
                float2(0.0, 1.0), float2(1.0, 1.0),
                float2(0.0, 0.0), float2(0.0, 0.0),
                float2(1.0, 1.0), float2(1.0, 0.0)
            };
            PackedVideoVertexOut output;
            output.position = float4(positions[vertexId], 0.0, 1.0);
            float sourceAspect = globals.logicalSourceSize.x /
                globals.logicalSourceSize.y;
            float targetAspect = globals.targetSize.x / globals.targetSize.y;
            float2 logicalUV = coordinates[vertexId];
            if (sourceAspect > targetAspect) {
                float visible = targetAspect / sourceAspect;
                logicalUV.x = 0.5 + (logicalUV.x - 0.5) * visible;
            } else {
                float visible = sourceAspect / targetAspect;
                logicalUV.y = 0.5 + (logicalUV.y - 0.5) * visible;
            }
            output.logicalUV = logicalUV;
            return output;
        }

        float3 sceneSurfaceDecode709(
            float2 packedUV,
            texture2d<float> lumaTexture,
            texture2d<float> chromaTexture,
            sampler videoSampler,
            constant PackedVideoGlobals &globals
        ) {
            float y = lumaTexture.sample(videoSampler, packedUV).r;
            float2 chroma = chromaTexture.sample(videoSampler, packedUV).rg;
            float3 adjusted = float3(y, chroma) + globals.yuvOffset;
            float3 encoded = float3(
                dot(globals.yuvToRGB0, adjusted),
                dot(globals.yuvToRGB1, adjusted),
                dot(globals.yuvToRGB2, adjusted)
            );
            float3 extendedLinear = max(
                encoded / 16.0,
                pow(max(encoded, 0.0), float3(1.9609375))
            );
            return select(
                extendedLinear,
                encoded / 16.0,
                encoded < float3(0.0)
            );
        }

        float sceneSurfaceDecode709Red(
            float2 packedUV,
            texture2d<float> lumaTexture,
            texture2d<float> chromaTexture,
            sampler videoSampler,
            constant PackedVideoGlobals &globals
        ) {
            float y = lumaTexture.sample(videoSampler, packedUV).r;
            float2 chroma = chromaTexture.sample(videoSampler, packedUV).rg;
            float encoded = dot(
                globals.yuvToRGB0,
                float3(y, chroma) + globals.yuvOffset
            );
            if (encoded < 0.0) {
                return encoded / 16.0;
            }
            return max(
                encoded / 16.0,
                pow(encoded, 1.9609375)
            );
        }

        fragment SceneSurfaceOnePassColor sceneSurfacePackedVideoFragment(
            PackedVideoVertexOut input [[stage_in]],
            texture2d<float> lumaTexture [[texture(0)]],
            texture2d<float> chromaTexture [[texture(1)]],
            constant PackedVideoGlobals &globals [[buffer(0)]],
            sampler videoSampler [[sampler(0)]],
            SceneSurfaceOnePassColor framebuffer
        ) {
            float2 logicalUV = input.logicalUV;
            float2 colorUV = float2(logicalUV.x * 0.5, logicalUV.y);
            float2 alphaUV = float2(0.5 + logicalUV.x * 0.5, logicalUV.y);
            float3 linearColor = sceneSurfaceDecode709(
                colorUV,
                lumaTexture,
                chromaTexture,
                videoSampler,
                globals
            );
            float alpha = clamp(sceneSurfaceDecode709Red(
                alphaUV,
                lumaTexture,
                chromaTexture,
                videoSampler,
                globals
            ), 0.0, 1.0);
            float infernoAlpha = framebuffer.value.a;
            float3 linearInferno = infernoAlpha > 0.0
                ? sceneSurfaceSRGBToLinear(
                    framebuffer.value.rgb / infernoAlpha
                ) * infernoAlpha
                : float3(0.0);
            float3 composed = linearColor * alpha +
                linearInferno * (1.0 - alpha);
            SceneSurfaceOnePassColor output;
            output.value = float4(sceneSurfaceLinearToSRGB(composed), 1.0);
            return output;
        }
        #endif
        """
}

@available(iOS 15.0, *)
typealias SceneSurfaceCIRenderExecution = (
    CIContext,
    CIImage,
    CIRenderDestination,
    CGRect
) throws -> Void

/// Renders the final Core Image graph into the existing pixel-buffer target
/// and does not report completion until Core Image's render task has finished.
/// Keeping the CVPixelBuffer destination preserves the established IOSurface,
/// alpha, and color-space path used by Flutter textures and PiP sample buffers.
@available(iOS 15.0, *)
@discardableResult
func renderSceneSurfaceCIFinalFrame(
    image: CIImage,
    to pixelBuffer: CVPixelBuffer,
    bounds: CGRect,
    colorSpace: CGColorSpace,
    context: CIContext,
    metrics: SceneSurfaceRenderPathMetrics?,
    metricsScope: String?,
    execution: SceneSurfaceCIRenderExecution? = nil
) -> Bool {
    let path = SceneSurfaceRenderPathMetrics.sceneSurfaceCIGPUPath
    let destination = CIRenderDestination(pixelBuffer: pixelBuffer)
    destination.colorSpace = colorSpace
    metrics?.recordGPUSubmission(
        path: path,
        scope: metricsScope,
        topLevel: true
    )
    do {
        var kernelExecutionSeconds: TimeInterval?
        if let execution {
            try execution(context, image, destination, bounds)
        } else {
            let task = try context.startTask(
                toRender: image,
                from: bounds,
                to: destination,
                at: bounds.origin
            )
            let info = try task.waitUntilCompleted()
            kernelExecutionSeconds = info.kernelExecutionTime
        }
        metrics?.recordGPUCompletion(
            path: path,
            failed: false,
            scope: metricsScope,
            topLevel: true,
            executionSeconds: kernelExecutionSeconds,
            coreImage: true
        )
        return true
    } catch {
        metrics?.recordGPUCompletion(
            path: path,
            failed: true,
            scope: metricsScope,
            topLevel: true
        )
        return false
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceDualRadialRenderer {
    static let maximumInstanceCount = 288
    static let inFlightBufferCount = 3

    let mode: SceneSurfaceDualRadialMode
    let instanceBufferAllocationCount: Int
    private(set) var textureAllocationCount = 0
    private(set) var renderedFrameCount = 0
    private(set) var outputWidth = 0
    private(set) var outputHeight = 0

    private let context: SceneSurfaceMetalContext
    private let pipeline: MTLRenderPipelineState
    private let metricsScope: String?
    private let instanceBuffers: [MTLBuffer]
    private let inFlightSemaphore = DispatchSemaphore(
        value: SceneSurfaceDualRadialRenderer.inFlightBufferCount
    )
    private let failureLock = NSLock()
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private let colorSpace: CGColorSpace
    private var nextBufferIndex = 0
    private var outputTexture: MTLTexture?
    private var latestCommandBuffer: MTLCommandBuffer?
    private var latestCompletionRecorder: SceneSurfaceGPUCompletionRecorder?
    private var gpuFailureLatched = false
    private var warmupCompleted = false

    init?(
        context: SceneSurfaceMetalContext,
        mode: SceneSurfaceDualRadialMode,
        metricsScope: String? = nil
    ) {
        self.context = context
        self.mode = mode
        self.metricsScope = metricsScope
        guard let pipeline = context.pipeline(for: mode) else { return nil }
        self.pipeline = pipeline
        switch mode {
        case .infernoAdditive:
            colorSpace = CGColorSpaceCreateDeviceRGB()
        case .pollenSourceOver:
            guard let workingColorSpace = context.ciContext.workingColorSpace else {
                return nil
            }
            colorSpace = workingColorSpace
        }
        let bufferLength = Self.maximumInstanceCount *
            MemoryLayout<SceneSurfaceDualRadialInstance>.stride
        var buffers = [MTLBuffer]()
        buffers.reserveCapacity(Self.inFlightBufferCount)
        for _ in 0..<Self.inFlightBufferCount {
            guard
                let buffer = context.device.makeBuffer(
                    length: bufferLength,
                    options: .storageModeShared
                )
            else {
                return nil
            }
            buffers.append(buffer)
        }
        instanceBuffers = buffers
        instanceBufferAllocationCount = buffers.count
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
    }

    var hasOutputTexture: Bool { outputTexture != nil }

    var hasTrackedCommandBuffer: Bool {
        failureLock.lock()
        let isTracked = latestCommandBuffer != nil
        failureLock.unlock()
        return isTracked
    }

    /// The final CI render is queued after these subpasses on the same Metal
    /// queue. Once that final task completes, this status check makes receipt
    /// admission independent from completion-handler scheduling.
    var latestCommandSettledSuccessfully: Bool {
        failureLock.lock()
        guard let commandBuffer = latestCommandBuffer else {
            failureLock.unlock()
            return true
        }
        let completionRecorder = latestCompletionRecorder
        failureLock.unlock()
        commandBuffer.waitUntilCompleted()
        completionRecorder?.record(commandBuffer: commandBuffer)
        recordCommandCompletion(status: commandBuffer.status)
        let completed = commandBuffer.status == .completed
        return completed
    }

    var hasLatchedGPUFailure: Bool {
        failureLock.lock()
        if latestCommandBuffer?.status == .error {
            gpuFailureLatched = true
        }
        let failed = gpuFailureLatched
        failureLock.unlock()
        return failed
    }

    func image(
        targetRect: CGRect,
        instances: [SceneSurfaceDualRadialInstance]
    ) -> CIImage? {
        let width = Int(targetRect.width.rounded())
        let height = Int(targetRect.height.rounded())
        guard
            width >= 2,
            height >= 2,
            instances.count <= Self.maximumInstanceCount,
            !hasLatchedGPUFailure
        else {
            return nil
        }

        let texture: MTLTexture
        let replacesOutputTexture: Bool
        if let outputTexture,
           outputWidth == width,
           outputHeight == height {
            texture = outputTexture
            replacesOutputTexture = false
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: mode.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let created = context.device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            texture = created
            replacesOutputTexture = true
        }

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            return nil
        }
        commandBuffer.label = "SceneSurfaceDualRadialFrame"
        inFlightSemaphore.wait()
        let bufferIndex = nextBufferIndex
        nextBufferIndex = (nextBufferIndex + 1) % instanceBuffers.count
        let instanceBuffer = instanceBuffers[bufferIndex]
        if !instances.isEmpty {
            instances.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                instanceBuffer.contents().copyMemory(
                    from: source,
                    byteCount: bytes.count
                )
            }
        }

        renderPassDescriptor.colorAttachments[0].texture = texture
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
            )
        else {
            inFlightSemaphore.signal()
            return nil
        }
        var globals = SceneSurfaceDualRadialGlobals(
            viewport: SIMD2(Float(width), Float(height)),
            mode: mode.rawValue
        )
        encoder.label = "SceneSurfaceDualRadialEncoder"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(
            &globals,
            length: MemoryLayout<SceneSurfaceDualRadialGlobals>.stride,
            index: 0
        )
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(
            &globals,
            length: MemoryLayout<SceneSurfaceDualRadialGlobals>.stride,
            index: 0
        )
        if !instances.isEmpty {
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: instances.count
            )
        }
        encoder.endEncoding()

        guard var image = CIImage(
            mtlTexture: texture,
            options: [.colorSpace: colorSpace]
        ) else {
            inFlightSemaphore.signal()
            return nil
        }
        let completionRecorder = SceneSurfaceGPUCompletionRecorder(
            metrics: context.renderPathMetrics,
            path: "v12_gpu_ci",
            scope: metricsScope
        )
        commandBuffer.addCompletedHandler { [weak self, inFlightSemaphore] buffer in
            self?.recordCommandCompletion(status: buffer.status)
            completionRecorder.record(commandBuffer: buffer)
            inFlightSemaphore.signal()
        }
        failureLock.lock()
        latestCommandBuffer = commandBuffer
        latestCompletionRecorder = completionRecorder
        failureLock.unlock()
        context.renderPathMetrics.recordGPUSubmission(
            path: "v12_gpu_ci",
            scope: metricsScope
        )
        commandBuffer.commit()

        if !warmupCompleted {
            commandBuffer.waitUntilCompleted()
            completionRecorder.record(commandBuffer: commandBuffer)
            recordCommandCompletion(status: commandBuffer.status)
            guard !hasLatchedGPUFailure else { return nil }
            warmupCompleted = true
        }

        if replacesOutputTexture {
            outputTexture = texture
            outputWidth = width
            outputHeight = height
            textureAllocationCount += 1
        }
        renderedFrameCount += 1
        if targetRect.origin != .zero {
            image = image.transformed(
                by: CGAffineTransform(
                    translationX: targetRect.minX,
                    y: targetRect.minY
                )
            )
        }
        return image.cropped(to: targetRect)
    }

    func recordCommandCompletion(status: MTLCommandBufferStatus) {
        guard status == .error else { return }
        failureLock.lock()
        gpuFailureLatched = true
        failureLock.unlock()
    }

    func waitForLatestGPUExecutionDurationForTesting() -> CFTimeInterval? {
        failureLock.lock()
        let commandBuffer = latestCommandBuffer
        failureLock.unlock()
        commandBuffer?.waitUntilCompleted()
        guard
            let commandBuffer,
            commandBuffer.status == .completed,
            commandBuffer.gpuEndTime >= commandBuffer.gpuStartTime
        else {
            return nil
        }
        return commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
    }

    func tearDown() {
        failureLock.lock()
        let commandBuffer = latestCommandBuffer
        failureLock.unlock()
        commandBuffer?.waitUntilCompleted()
        for _ in 0..<Self.inFlightBufferCount {
            inFlightSemaphore.wait()
        }
        for _ in 0..<Self.inFlightBufferCount {
            inFlightSemaphore.signal()
        }
        outputTexture = nil
        outputWidth = 0
        outputHeight = 0
        renderPassDescriptor.colorAttachments[0].texture = nil
        failureLock.lock()
        latestCommandBuffer = nil
        latestCompletionRecorder = nil
        failureLock.unlock()
    }
}

@available(iOS 15.0, *)
enum SceneSurfaceOnePassRenderResult: Equatable {
    case rendered
    case unsupported
    case failed
}

@available(iOS 15.0, *)
struct SceneSurfaceOnePassRenderStats: Equatable {
    let commandBufferCount: Int
    let renderPassCount: Int
    let radialIntermediateTextureCount: Int
    let ciFinalRenderCount: Int
    let instanceCount: Int
}

@available(iOS 15.0, *)
final class SceneSurfaceOnePassCompositor {
    static let maximumInstanceCount = SceneSurfaceDualRadialRenderer.maximumInstanceCount

    private let context: SceneSurfaceMetalContext
    private let renderLock = NSLock()
    private let instanceBuffer: MTLBuffer?
    private let sampler: MTLSamplerState?
    private(set) var lastRenderStats: SceneSurfaceOnePassRenderStats?
    private(set) var hasLatchedGPUFailure = false
    private(set) var retainedFrameResourceCount = 0
    private(set) var lastGPUExecutionDuration: CFTimeInterval?

    init(context: SceneSurfaceMetalContext) {
        self.context = context
        instanceBuffer = context.device.makeBuffer(
            length: Self.maximumInstanceCount *
                MemoryLayout<SceneSurfaceDualRadialInstance>.stride,
            options: .storageModeShared
        )
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerDescriptor.normalizedCoordinates = true
        sampler = context.device.makeSamplerState(descriptor: samplerDescriptor)
    }

    func render(
        infernoFrame: SceneSurfacePreparedInfernoFrame,
        packedVideoBuffer: CVPixelBuffer,
        targetBuffer: CVPixelBuffer,
        metricsScope: String? = nil,
        forceCommandFailureForTesting: Bool = false
    ) -> SceneSurfaceOnePassRenderResult {
        renderLock.lock()
        defer { renderLock.unlock() }
        lastRenderStats = nil
        lastGPUExecutionDuration = nil
        guard !hasLatchedGPUFailure else {
            context.renderPathMetrics.recordGPUCompletion(
                path: "one_pass_gpu",
                failed: true,
                scope: metricsScope,
                topLevel: true
            )
            return .failed
        }
        guard
            context.supportsOnePassPackedVideoRendering,
            let textureCache = context.textureCache,
            let infernoPipeline = context.onePassInfernoPipeline,
            let packedVideoPipeline = context.packedVideoPipeline,
            let instanceBuffer,
            let sampler,
            infernoFrame.instances.count <= Self.maximumInstanceCount,
            CVPixelBufferGetPlaneCount(packedVideoBuffer) == 2,
            sceneSurfacePackedVideoColorMetadataIsSupported(packedVideoBuffer),
            CVPixelBufferGetPixelFormatType(targetBuffer) ==
                kCVPixelFormatType_32BGRA
        else {
            return .unsupported
        }

        let sourceWidth = CVPixelBufferGetWidth(packedVideoBuffer)
        let sourceHeight = CVPixelBufferGetHeight(packedVideoBuffer)
        let targetWidth = CVPixelBufferGetWidth(targetBuffer)
        let targetHeight = CVPixelBufferGetHeight(targetBuffer)
        guard
            sourceWidth >= 4,
            sourceWidth.isMultiple(of: 4),
            sourceHeight >= 2,
            targetWidth >= 2,
            targetHeight >= 2,
            Int(infernoFrame.size.width.rounded()) == targetWidth,
            Int(infernoFrame.size.height.rounded()) == targetHeight,
            let yTextureRef = makeTexture(
                cache: textureCache,
                buffer: packedVideoBuffer,
                pixelFormat: .r8Unorm,
                width: CVPixelBufferGetWidthOfPlane(packedVideoBuffer, 0),
                height: CVPixelBufferGetHeightOfPlane(packedVideoBuffer, 0),
                plane: 0
            ),
            let chromaTextureRef = makeTexture(
                cache: textureCache,
                buffer: packedVideoBuffer,
                pixelFormat: .rg8Unorm,
                width: CVPixelBufferGetWidthOfPlane(packedVideoBuffer, 1),
                height: CVPixelBufferGetHeightOfPlane(packedVideoBuffer, 1),
                plane: 1
            ),
            let targetTextureRef = makeTexture(
                cache: textureCache,
                buffer: targetBuffer,
                pixelFormat: .bgra8Unorm,
                width: targetWidth,
                height: targetHeight,
                plane: 0
            ),
            let yTexture = CVMetalTextureGetTexture(yTextureRef),
            let chromaTexture = CVMetalTextureGetTexture(chromaTextureRef),
            let targetTexture = CVMetalTextureGetTexture(targetTextureRef),
            let commandBuffer = context.commandQueue.makeCommandBuffer()
        else {
            return .failed
        }

        if !infernoFrame.instances.isEmpty {
            infernoFrame.instances.withUnsafeBytes { bytes in
                guard let source = bytes.baseAddress else { return }
                instanceBuffer.contents().copyMemory(
                    from: source,
                    byteCount: bytes.count
                )
            }
        }
        let passDescriptor = MTLRenderPassDescriptor()
        guard let attachment = passDescriptor.colorAttachments[0] else {
            return .failed
        }
        attachment.texture = targetTexture
        attachment.loadAction = .clear
        attachment.storeAction = .store
        attachment.clearColor = MTLClearColor(
            red: 0,
            green: 0,
            blue: 0,
            alpha: 0
        )
        guard let encoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: passDescriptor
        ) else {
            return .failed
        }
        commandBuffer.label = "SceneSurfaceOnePassFrame"
        encoder.label = "SceneSurfaceOnePassEncoder"
        var radialGlobals = SceneSurfaceDualRadialGlobals(
            viewport: SIMD2(Float(targetWidth), Float(targetHeight)),
            mode: SceneSurfaceDualRadialMode.infernoAdditive.rawValue
        )
        encoder.setRenderPipelineState(infernoPipeline)
        encoder.setVertexBytes(
            &radialGlobals,
            length: MemoryLayout<SceneSurfaceDualRadialGlobals>.stride,
            index: 0
        )
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(
            &radialGlobals,
            length: MemoryLayout<SceneSurfaceDualRadialGlobals>.stride,
            index: 0
        )
        if !infernoFrame.instances.isEmpty {
            encoder.drawPrimitives(
                type: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: infernoFrame.instances.count
            )
        }

        var videoGlobals = Self.videoGlobals(
            packedVideoBuffer,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        encoder.setRenderPipelineState(packedVideoPipeline)
        encoder.setVertexBytes(
            &videoGlobals,
            length: MemoryLayout<SceneSurfacePackedVideoGlobals>.stride,
            index: 0
        )
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(chromaTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(
            &videoGlobals,
            length: MemoryLayout<SceneSurfacePackedVideoGlobals>.stride,
            index: 0
        )
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6
        )
        encoder.endEncoding()

        context.renderPathMetrics.recordGPUSubmission(
            path: "one_pass_gpu",
            scope: metricsScope,
            topLevel: true
        )
        commandBuffer.commit()
        retainedFrameResourceCount = 5
        commandBuffer.waitUntilCompleted()
        let failed = forceCommandFailureForTesting ||
            commandBuffer.status != .completed
        if failed { hasLatchedGPUFailure = true }
        context.renderPathMetrics.recordGPUCompletion(
            path: "one_pass_gpu",
            failed: failed,
            scope: metricsScope,
            topLevel: true,
            executionSeconds: commandBuffer.gpuStartTime > 0
                ? commandBuffer.gpuEndTime - commandBuffer.gpuStartTime : nil
        )
        withExtendedLifetime((
            packedVideoBuffer,
            targetBuffer,
            yTextureRef,
            chromaTextureRef,
            targetTextureRef
        )) {}
        retainedFrameResourceCount = 0
        if !failed {
            if commandBuffer.gpuEndTime >= commandBuffer.gpuStartTime {
                lastGPUExecutionDuration = commandBuffer.gpuEndTime -
                    commandBuffer.gpuStartTime
            }
            lastRenderStats = SceneSurfaceOnePassRenderStats(
                commandBufferCount: 1,
                renderPassCount: 1,
                radialIntermediateTextureCount: 0,
                ciFinalRenderCount: 0,
                instanceCount: infernoFrame.instances.count
            )
        }
        return failed ? .failed : .rendered
    }

    private func makeTexture(
        cache: CVMetalTextureCache,
        buffer: CVPixelBuffer,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int,
        plane: Int
    ) -> CVMetalTexture? {
        var texture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            buffer,
            nil,
            pixelFormat,
            width,
            height,
            plane,
            &texture
        )
        guard status == kCVReturnSuccess else { return nil }
        return texture
    }

    private static func videoGlobals(
        _ buffer: CVPixelBuffer,
        targetWidth: Int,
        targetHeight: Int
    ) -> SceneSurfacePackedVideoGlobals {
        let fullRange = CVPixelBufferGetPixelFormatType(buffer) ==
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let yScale: Float = fullRange ? 1 : 255.0 / 219.0
        let chromaScale: Float = fullRange
            ? 255.0 / 254.0
            : 255.0 / 224.0
        let yOffset: Float = fullRange ? 0 : -16.0 / 255.0
        let chromaOffset: Float = -128.0 / 255.0
        return SceneSurfacePackedVideoGlobals(
            targetSize: SIMD2(Float(targetWidth), Float(targetHeight)),
            logicalSourceSize: SIMD2(
                Float(CVPixelBufferGetWidth(buffer) / 2),
                Float(CVPixelBufferGetHeight(buffer))
            ),
            yuvOffset: SIMD3(yOffset, chromaOffset, chromaOffset),
            yuvToRGB0: SIMD3(yScale, 0, 1.5748 * chromaScale),
            yuvToRGB1: SIMD3(
                yScale,
                -0.187324 * chromaScale,
                -0.468124 * chromaScale
            ),
            yuvToRGB2: SIMD3(yScale, 1.8556 * chromaScale, 0)
        )
    }
}

@available(iOS 15.0, *)
func sceneSurfaceCleanApertureIsSupported(
    _ attachment: Any?,
    width: Int,
    height: Int
) -> Bool {
    guard let attachment else { return true }
    guard let cleanAperture = attachment as? NSDictionary else {
        return false
    }
    func value(_ key: CFString) -> Double? {
        (cleanAperture[key] as? NSNumber)?.doubleValue
    }
    return value(kCVImageBufferCleanApertureWidthKey) == Double(width) &&
        value(kCVImageBufferCleanApertureHeightKey) == Double(height) &&
        value(kCVImageBufferCleanApertureHorizontalOffsetKey) == 0 &&
        value(kCVImageBufferCleanApertureVerticalOffsetKey) == 0
}

@available(iOS 15.0, *)
func sceneSurfacePixelAspectIsSupported(_ attachment: Any?) -> Bool {
    guard let attachment else { return true }
    guard let pixelAspect = attachment as? NSDictionary else { return false }
    let horizontal = (pixelAspect[
        kCVImageBufferPixelAspectRatioHorizontalSpacingKey
    ] as? NSNumber)?.doubleValue
    let vertical = (pixelAspect[
        kCVImageBufferPixelAspectRatioVerticalSpacingKey
    ] as? NSNumber)?.doubleValue
    guard
        let horizontal,
        let vertical,
        horizontal.isFinite,
        vertical.isFinite,
        horizontal > 0,
        horizontal == vertical
    else {
        return false
    }
    return true
}

@available(iOS 15.0, *)
func sceneSurfacePackedVideoColorMetadataIsSupported(
    _ buffer: CVPixelBuffer
) -> Bool {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    guard
        format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
            format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    else {
        return false
    }
    func attachment(_ key: CFString) -> String? {
        guard let value = CVBufferCopyAttachment(buffer, key, nil) else {
            return nil
        }
        return value as? String
    }
    guard
        sceneSurfaceCleanApertureIsSupported(
            CVBufferCopyAttachment(
                buffer,
                kCVImageBufferCleanApertureKey,
                nil
            ),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer)
        ),
        sceneSurfacePixelAspectIsSupported(
            CVBufferCopyAttachment(
                buffer,
                kCVImageBufferPixelAspectRatioKey,
                nil
            )
        )
    else {
        return false
    }
    let chromaTop = attachment(kCVImageBufferChromaLocationTopFieldKey)
    let chromaBottom = attachment(kCVImageBufferChromaLocationBottomFieldKey)
    guard
        chromaTop == (kCVImageBufferChromaLocation_Left as String),
        (chromaBottom == nil || chromaBottom ==
            (kCVImageBufferChromaLocation_Left as String))
    else {
        return false
    }
    return attachment(kCVImageBufferYCbCrMatrixKey) ==
            (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) &&
        attachment(kCVImageBufferColorPrimariesKey) ==
            (kCVImageBufferColorPrimaries_ITU_R_709_2 as String) &&
        attachment(kCVImageBufferTransferFunctionKey) ==
            (kCVImageBufferTransferFunction_ITU_R_709_2 as String)
}

/// Playback clock for decoded animated images.
///
/// The first rendered frame establishes the host-time origin, so native
/// handoff always begins at animation time zero even when another layer needs
/// time to preroll. Pausing commits only elapsed foreground time and resuming
/// establishes a new origin on the next rendered frame.
struct SceneSurfaceAnimatedImageClock {
    private(set) var accumulatedElapsed: CFTimeInterval = 0
    private var startedAt: CFTimeInterval?
    private(set) var isPlaying = false

    mutating func play() {
        guard !isPlaying else { return }
        isPlaying = true
        startedAt = nil
    }

    mutating func pause(at hostTime: CFTimeInterval) {
        guard isPlaying else { return }
        if let startedAt, hostTime.isFinite {
            accumulatedElapsed += max(0, hostTime - startedAt)
        }
        startedAt = nil
        isPlaying = false
    }

    mutating func elapsed(at hostTime: CFTimeInterval) -> CFTimeInterval {
        guard isPlaying, hostTime.isFinite else { return accumulatedElapsed }
        guard let startedAt else {
            self.startedAt = hostTime
            return accumulatedElapsed
        }
        return accumulatedElapsed + max(0, hostTime - startedAt)
    }

    mutating func reset() {
        accumulatedElapsed = 0
        startedAt = nil
        isPlaying = false
    }
}

func sceneSurfacePlaybackRate(_ value: Any?) -> Float {
    guard
        let parsed = (value as? NSNumber)?.doubleValue,
        parsed.isFinite
    else {
        return 1
    }
    return Float(min(max(parsed, 0.1), 4))
}

enum PictureInPicturePendingStartStopAction: Equatable {
    case ignore
    case beginStopping
    case forceIdle
}

func pictureInPicturePendingStartStopAction(
    isCurrentController: Bool,
    lifecycleIsStarting: Bool,
    stopRequested: Bool,
    controllerIsActive: Bool
) -> PictureInPicturePendingStartStopAction {
    guard isCurrentController, lifecycleIsStarting, stopRequested else {
        return .ignore
    }
    return controllerIsActive ? .beginStopping : .forceIdle
}

func pictureInPictureStartFailureRequiresControllerReset(
    _ reason: String
) -> Bool {
    reason == "native_start_timeout"
}

func sceneSurfaceColor(fromARGB argb: UInt32) -> CIColor {
    CIColor(
        red: CGFloat((argb >> 16) & 0xFF) / 255,
        green: CGFloat((argb >> 8) & 0xFF) / 255,
        blue: CGFloat(argb & 0xFF) / 255,
        alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
}

struct SceneSurfaceFirefliesRecipeV1 {
    static let preset = "enchanted_fireflies_v1"
    static let allowedKeys: Set<String> = [
        "schemaVersion",
        "seed",
        "particleCount",
        "framesPerSecond",
        "motionScale",
        "glowScale",
        "flowResponse",
        "sparkResponse",
    ]

    let seed: UInt64
    let particleCount: Int
    let framesPerSecond: Int
    let motionScale: Double
    let glowScale: Double
    let flowResponse: Double
    let sparkResponse: Double

    init?(_ definition: [String: Any]) {
        guard
            Set(definition.keys).isSubset(of: Self.allowedKeys),
            Self.integer(definition["schemaVersion"]) == 1,
            let seed = Self.integer(
                definition["seed"],
                minimum: 0,
                maximum: 0x7fff_ffff
            ),
            let particleCount = Self.integer(
                definition["particleCount"],
                minimum: 8,
                maximum: 44
            ),
            let framesPerSecond = Self.integer(
                definition["framesPerSecond"],
                minimum: 12,
                maximum: 30
            ),
            let motionScale = Self.number(
                definition["motionScale"],
                minimum: 0.5,
                maximum: 1.5
            ),
            let glowScale = Self.number(
                definition["glowScale"],
                minimum: 0.5,
                maximum: 1.4
            ),
            let flowResponse = Self.number(
                definition["flowResponse"],
                minimum: 0,
                maximum: 1
            ),
            let sparkResponse = Self.number(
                definition["sparkResponse"],
                minimum: 0,
                maximum: 1
            )
        else {
            return nil
        }
        self.seed = UInt64(seed)
        self.particleCount = particleCount
        self.framesPerSecond = framesPerSecond
        self.motionScale = motionScale
        self.glowScale = glowScale
        self.flowResponse = flowResponse
        self.sparkResponse = sparkResponse
    }

    private static func integer(
        _ value: Any?,
        minimum: Int = Int.min,
        maximum: Int = Int.max
    ) -> Int? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.rounded() == parsed,
              parsed >= Double(minimum),
              parsed <= Double(maximum) else {
            return nil
        }
        return Int(parsed)
    }

    private static func number(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.isFinite, parsed >= minimum, parsed <= maximum else {
            return nil
        }
        return parsed
    }

    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}

func sceneSurfaceFirefliesRecipeIsSupported(
    _ definition: [String: Any]
) -> Bool {
    SceneSurfaceFirefliesRecipeV1(definition) != nil
}

struct SceneSurfaceInfernoEmbersRecipeV1 {
    static let preset = "inferno_embers_v1"
    static let allowedKeys: Set<String> = [
        "schemaVersion",
        "seed",
        "particleCount",
        "framesPerSecond",
        "motionScale",
        "glowScale",
        "sparkResponse",
    ]

    let seed: UInt64
    let particleCount: Int
    let framesPerSecond: Int
    let motionScale: Double
    let glowScale: Double
    let sparkResponse: Double

    init?(_ definition: [String: Any]) {
        guard
            Set(definition.keys).isSubset(of: Self.allowedKeys),
            Self.integer(definition["schemaVersion"]) == 1,
            let seed = Self.integer(
                definition["seed"],
                minimum: 0,
                maximum: 0x7fff_ffff
            ),
            let particleCount = Self.integer(
                definition["particleCount"],
                minimum: 72,
                maximum: 288
            ),
            let framesPerSecond = Self.integer(
                definition["framesPerSecond"],
                minimum: 18,
                maximum: 30
            ),
            let motionScale = Self.number(
                definition["motionScale"],
                minimum: 0.5,
                maximum: 1.2
            ),
            let glowScale = Self.number(
                definition["glowScale"],
                minimum: 0.6,
                maximum: 1.4
            ),
            let sparkResponse = Self.number(
                definition["sparkResponse"],
                minimum: 0,
                maximum: 1
            )
        else {
            return nil
        }
        self.seed = UInt64(seed)
        self.particleCount = particleCount
        self.framesPerSecond = framesPerSecond
        self.motionScale = motionScale
        self.glowScale = glowScale
        self.sparkResponse = sparkResponse
    }

    private static func integer(
        _ value: Any?,
        minimum: Int = Int.min,
        maximum: Int = Int.max
    ) -> Int? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.rounded() == parsed,
              parsed >= Double(minimum),
              parsed <= Double(maximum) else {
            return nil
        }
        return Int(parsed)
    }

    private static func number(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.isFinite, parsed >= minimum, parsed <= maximum else {
            return nil
        }
        return parsed
    }

    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}

func sceneSurfaceInfernoEmbersRecipeIsSupported(
    _ definition: [String: Any]
) -> Bool {
    SceneSurfaceInfernoEmbersRecipeV1(definition) != nil
}

struct SceneSurfaceWildflowerPollenRecipeV1 {
    static let preset = "wildflower_pollen_v1"
    static let allowedKeys: Set<String> = [
        "schemaVersion",
        "seed",
        "particleCount",
        "framesPerSecond",
        "travelSpeed",
        "convergence",
        "targetX",
        "targetY",
        "motionScale",
        "glowScale",
        "flowResponse",
        "sparkResponse",
    ]

    let seed: UInt64
    let particleCount: Int
    let framesPerSecond: Int
    let travelSpeed: Double
    let convergence: Double
    let targetX: Double
    let targetY: Double
    let motionScale: Double
    let glowScale: Double
    let flowResponse: Double
    let sparkResponse: Double

    init?(_ definition: [String: Any]) {
        guard
            Set(definition.keys).isSubset(of: Self.allowedKeys),
            Self.integer(definition["schemaVersion"]) == 1,
            let seed = Self.integer(
                definition["seed"],
                minimum: 0,
                maximum: 0x7fff_ffff
            ),
            let particleCount = Self.integer(
                definition["particleCount"],
                minimum: 12,
                maximum: 48
            ),
            let framesPerSecond = Self.integer(
                definition["framesPerSecond"],
                minimum: 12,
                maximum: 30
            ),
            let travelSpeed = Self.number(
                definition["travelSpeed"],
                minimum: 0.04,
                maximum: 0.16
            ),
            let convergence = Self.number(
                definition["convergence"],
                minimum: 0.75,
                maximum: 0.98
            ),
            let targetX = Self.number(
                definition["targetX"],
                minimum: 0.35,
                maximum: 0.65
            ),
            let targetY = Self.number(
                definition["targetY"],
                minimum: 0.18,
                maximum: 0.55
            ),
            let motionScale = Self.number(
                definition["motionScale"],
                minimum: 0.5,
                maximum: 1.5
            ),
            let glowScale = Self.number(
                definition["glowScale"],
                minimum: 0.5,
                maximum: 1.4
            ),
            let flowResponse = Self.number(
                definition["flowResponse"],
                minimum: 0,
                maximum: 1
            ),
            let sparkResponse = Self.number(
                definition["sparkResponse"],
                minimum: 0,
                maximum: 1
            )
        else {
            return nil
        }
        self.seed = UInt64(seed)
        self.particleCount = particleCount
        self.framesPerSecond = framesPerSecond
        self.travelSpeed = travelSpeed
        self.convergence = convergence
        self.targetX = targetX
        self.targetY = targetY
        self.motionScale = motionScale
        self.glowScale = glowScale
        self.flowResponse = flowResponse
        self.sparkResponse = sparkResponse
    }

    private static func integer(
        _ value: Any?,
        minimum: Int = Int.min,
        maximum: Int = Int.max
    ) -> Int? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.rounded() == parsed,
              parsed >= Double(minimum),
              parsed <= Double(maximum) else {
            return nil
        }
        return Int(parsed)
    }

    private static func number(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.isFinite, parsed >= minimum, parsed <= maximum else {
            return nil
        }
        return parsed
    }

    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}

func sceneSurfaceWildflowerPollenRecipeIsSupported(
    _ definition: [String: Any]
) -> Bool {
    SceneSurfaceWildflowerPollenRecipeV1(definition) != nil
}

struct SceneSurfaceRadialWarpRecipeV1 {
    static let preset = "radial_warp_field_v1"
    static let allowedKeys: Set<String> = [
        "schemaVersion",
        "seed",
        "particleCount",
        "framesPerSecond",
        "travelSpeed",
        "streakScale",
        "centerX",
        "centerY",
        "glowScale",
        "flowResponse",
        "bassResponse",
        "sparkResponse",
    ]

    let seed: UInt64
    let particleCount: Int
    let framesPerSecond: Int
    let travelSpeed: Double
    let streakScale: Double
    let centerX: Double
    let centerY: Double
    let glowScale: Double
    let flowResponse: Double
    let bassResponse: Double
    let sparkResponse: Double

    init?(_ definition: [String: Any]) {
        guard
            Set(definition.keys).isSubset(of: Self.allowedKeys),
            Self.integer(definition["schemaVersion"]) == 1,
            let seed = Self.integer(
                definition["seed"],
                minimum: 0,
                maximum: 0x7fff_ffff
            ),
            let particleCount = Self.integer(
                definition["particleCount"],
                minimum: 240,
                maximum: 640
            ),
            let framesPerSecond = Self.integer(
                definition["framesPerSecond"],
                minimum: 18,
                maximum: 30
            ),
            let travelSpeed = Self.number(
                definition["travelSpeed"],
                minimum: 0.06,
                maximum: 0.16
            ),
            let streakScale = Self.number(
                definition["streakScale"],
                minimum: 0.6,
                maximum: 1.4
            ),
            let centerX = Self.number(
                definition["centerX"],
                minimum: 0.42,
                maximum: 0.58
            ),
            let centerY = Self.number(
                definition["centerY"],
                minimum: 0.42,
                maximum: 0.58
            ),
            let glowScale = Self.number(
                definition["glowScale"],
                minimum: 0.6,
                maximum: 1.35
            ),
            let flowResponse = Self.number(
                definition["flowResponse"],
                minimum: 0,
                maximum: 1
            ),
            let bassResponse = Self.number(
                definition["bassResponse"],
                minimum: 0,
                maximum: 1
            ),
            let sparkResponse = Self.number(
                definition["sparkResponse"],
                minimum: 0,
                maximum: 1
            )
        else {
            return nil
        }
        self.seed = UInt64(seed)
        self.particleCount = particleCount
        self.framesPerSecond = framesPerSecond
        self.travelSpeed = travelSpeed
        self.streakScale = streakScale
        self.centerX = centerX
        self.centerY = centerY
        self.glowScale = glowScale
        self.flowResponse = flowResponse
        self.bassResponse = bassResponse
        self.sparkResponse = sparkResponse
    }

    private static func integer(
        _ value: Any?,
        minimum: Int = Int.min,
        maximum: Int = Int.max
    ) -> Int? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.rounded() == parsed,
              parsed >= Double(minimum),
              parsed <= Double(maximum) else {
            return nil
        }
        return Int(parsed)
    }

    private static func number(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.isFinite, parsed >= minimum, parsed <= maximum else {
            return nil
        }
        return parsed
    }

    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}

func sceneSurfaceRadialWarpRecipeIsSupported(
    _ definition: [String: Any]
) -> Bool {
    SceneSurfaceRadialWarpRecipeV1(definition) != nil
}

enum SceneSurfaceStatefulStormFamily: Int, CaseIterable {
    case longVertical
    case longOblique
    case occluded
    case sparsePair
}

struct SceneSurfaceStatefulStormSnapshot: Equatable {
    let family: SceneSurfaceStatefulStormFamily?
    let broadOpacity: Double
    let coreOpacity: Double
    let flashOpacity: Double
    let revealProgress: Double
    let boltLuminanceGain: Double

    static let idle = SceneSurfaceStatefulStormSnapshot(
        family: nil,
        broadOpacity: 0,
        coreOpacity: 0,
        flashOpacity: 0,
        revealProgress: 0,
        boltLuminanceGain: 0
    )
}

struct SceneSurfaceStatefulStormRecipeV1 {
    struct MasterAsset: Equatable {
        let asset: String
        let package: String
    }

    static let preset = "stateful_storm_energy_v1"
    static let expectedMasterAssets = [
        "assets/audiovisuals/transparents/stateful_storm_energy/master_a.png",
        "assets/audiovisuals/transparents/stateful_storm_energy/master_b.png",
        "assets/audiovisuals/transparents/stateful_storm_energy/master_c.png",
        "assets/audiovisuals/transparents/stateful_storm_energy/master_d.png",
    ]
    static let allowedKeys: Set<String> = [
        "schemaVersion",
        "seed",
        "framesPerSecond",
        "episodeQuietGraceMs",
        "familyLockMs",
        "chargeScale",
        "strokeScale",
        "flashScale",
        "masterAssets",
    ]

    let seed: UInt64
    let framesPerSecond: Int
    let episodeQuietGraceMs: Int
    let familyLockMs: Int
    let chargeScale: Double
    let strokeScale: Double
    let flashScale: Double
    let visibleLightningProbability = 0.20
    let boltHaloPassScale = 0.72
    let boltCorePassScale = 0.58
    let minimumBoltLuminanceGain = 0.12
    let minimumBoltStrength = 0.42
    let maximumBoltStrength = 0.90
    let masterAssets: [MasterAsset]

    init?(_ definition: [String: Any]) {
        guard
            Set(definition.keys).isSubset(of: Self.allowedKeys),
            Self.integer(definition["schemaVersion"]) == 1,
            let seed = Self.integer(
                definition["seed"],
                minimum: 0,
                maximum: 0x7fff_ffff
            ),
            let framesPerSecond = Self.integer(
                definition["framesPerSecond"],
                minimum: 18,
                maximum: 30
            ),
            let episodeQuietGraceMs = Self.integer(
                definition["episodeQuietGraceMs"],
                minimum: 800,
                maximum: 1_600
            ),
            let familyLockMs = Self.integer(
                definition["familyLockMs"],
                minimum: 600,
                maximum: 1_200
            ),
            let chargeScale = Self.number(
                definition["chargeScale"],
                minimum: 0.7,
                maximum: 1.2
            ),
            let strokeScale = Self.number(
                definition["strokeScale"],
                minimum: 0.7,
                maximum: 1.15
            ),
            let flashScale = Self.number(
                definition["flashScale"],
                minimum: 0.55,
                maximum: 0.9
            ),
            let rawMasterAssets = definition["masterAssets"] as? [[String: Any]],
            rawMasterAssets.count == Self.expectedMasterAssets.count
        else {
            return nil
        }

        var decodedMasterAssets = [MasterAsset]()
        for (index, rawAsset) in rawMasterAssets.enumerated() {
            guard
                Set(rawAsset.keys) == Set(["asset", "assetPackage"]),
                let asset = rawAsset["asset"] as? String,
                asset == Self.expectedMasterAssets[index],
                let package = rawAsset["assetPackage"] as? String,
                package == "audiovisuals"
            else {
                return nil
            }
            decodedMasterAssets.append(
                MasterAsset(asset: asset, package: package)
            )
        }

        self.seed = UInt64(seed)
        self.framesPerSecond = framesPerSecond
        self.episodeQuietGraceMs = episodeQuietGraceMs
        self.familyLockMs = familyLockMs
        self.chargeScale = chargeScale
        self.strokeScale = strokeScale
        self.flashScale = flashScale
        self.masterAssets = decodedMasterAssets
    }

    private static func integer(
        _ value: Any?,
        minimum: Int = Int.min,
        maximum: Int = Int.max
    ) -> Int? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.rounded() == parsed,
              parsed >= Double(minimum),
              parsed <= Double(maximum) else {
            return nil
        }
        return Int(parsed)
    }

    private static func number(
        _ value: Any?,
        minimum: Double,
        maximum: Double
    ) -> Double? {
        guard let number = numeric(value) else { return nil }
        let parsed = number.doubleValue
        guard parsed.isFinite, parsed >= minimum, parsed <= maximum else {
            return nil
        }
        return parsed
    }

    private static func numeric(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        return number
    }
}

func sceneSurfaceStatefulStormRecipeIsSupported(
    _ definition: [String: Any]
) -> Bool {
    SceneSurfaceStatefulStormRecipeV1(definition) != nil
}

struct SceneSurfaceStatefulStormField {
    let recipe: SceneSurfaceStatefulStormRecipeV1

    private(set) var family: SceneSurfaceStatefulStormFamily?
    private var previousFamily: SceneSurfaceStatefulStormFamily?
    private var audioSessionId = -1
    private var lastImpactSerial = 0
    private var lastFlashSerial = 0
    private var lastEventTime: CFTimeInterval?
    private var lastStepTime: CFTimeInterval?
    private var eventStrength = 0.0
    private var level = 0.0
    private var bass = 0.0
    private var body = 0.0
    private var spark = 0.0
    private var flow = 0.0
    private var charge = 0.0
    private var boltLuminanceGain = 0.0
    private var eventWasFlash = false
    private var previousEventWasVisibleLightning = false

    var hasActiveEpisode: Bool { lastEventTime != nil }

    init(recipe: SceneSurfaceStatefulStormRecipeV1) {
        self.recipe = recipe
    }

    @discardableResult
    mutating func update(
        arguments: [String: Any],
        hostTime: CFTimeInterval
    ) -> SceneSurfaceStatefulStormSnapshot {
        guard arguments["shouldReact"] as? Bool == true else {
            reset()
            return .idle
        }
        let nextSessionId = Self.integer(arguments["audioSessionId"])
        guard nextSessionId > 0 else {
            reset()
            return .idle
        }
        if nextSessionId != audioSessionId {
            reset()
            audioSessionId = nextSessionId
        }

        let impactSerial = Self.integer(arguments["impactSerial"])
        let impactActive = arguments["impactActive"] as? Bool == true
        let newImpact = impactActive && impactSerial > lastImpactSerial
        if newImpact { lastImpactSerial = impactSerial }

        let flashSerial = Self.integer(arguments["flashSerial"])
        let flashActive = arguments["flashActive"] as? Bool == true
        let newFlash = flashActive && flashSerial > lastFlashSerial
        if newFlash { lastFlashSerial = flashSerial }

        level = Self.unit(arguments["level"])
        bass = Self.unit(arguments["bassDrive"])
        body = Self.unit(arguments["bodyDrive"])
        spark = Self.unit(arguments["sparkDrive"])
        flow = Self.unit(arguments["flowDrive"])

        if newImpact || newFlash {
            let impactStrength = newImpact
                ? Self.unit(arguments["impactStrength"])
                : 0
            let flashStrength = newFlash
                ? Self.unit(arguments["flashStrength"])
                : 0
            let eventSerial = max(impactSerial, flashSerial)
            let visibleLightning = selectVisibleLightning(
                eventSerial: eventSerial
            )
            if visibleLightning {
                let selected = selectFamily(
                    impactStrength: impactStrength,
                    flashStrength: flashStrength,
                    newFlash: newFlash,
                    eventSerial: eventSerial
                )
                family = selected
                previousFamily = selected
            } else {
                // Cloud-only events replace, rather than retain, a previous
                // visible master so no stale bolt can leak into the new event.
                family = nil
            }
            previousEventWasVisibleLightning = visibleLightning
            eventStrength = max(
                max(impactStrength, flashStrength),
                recipe.minimumBoltStrength
            )
            boltLuminanceGain = visibleLightning
                ? Self.boltLuminanceGain(
                    for: eventStrength,
                    recipe: recipe
                )
                : 0
            eventWasFlash = newFlash
            lastEventTime = hostTime
        }
        return snapshot(at: hostTime)
    }

    mutating func snapshot(
        at hostTime: CFTimeInterval
    ) -> SceneSurfaceStatefulStormSnapshot {
        guard let lastEventTime else { return .idle }
        let delta = lastStepTime.map {
            min(max(hostTime - $0, 0), 0.1)
        } ?? (1.0 / 30.0)
        lastStepTime = hostTime

        let targetCharge = min(
            (0.06 + level * 0.08 + body * 0.11 + flow * 0.10) *
                recipe.chargeScale,
            0.32
        )
        charge = Self.follow(
            charge,
            target: targetCharge,
            delta: delta,
            attack: 0.16,
            release: 0.90
        )

        let elapsedMs = max((hostTime - lastEventTime) * 1_000, 0)
        let reveal = min(max(elapsedMs / 90, 0), 1)
        let leader = elapsedMs < 90
            ? eventStrength * 0.54 * Self.smoothstep(reveal)
            : 0
        let returnStroke = elapsedMs >= 90 && elapsedMs < 156
            ? eventStrength * recipe.strokeScale *
                (1 - ((elapsedMs - 90) / 66) * 0.22)
            : 0
        let afterglowElapsed = max(elapsedMs - 156, 0)
        let releaseMs = 420 + flow * 520 + eventStrength * 160
        let afterglowProgress = min(
            max(afterglowElapsed / max(releaseMs, 1), 0),
            1
        )
        let afterglow = elapsedMs < 90
            ? 0
            : eventStrength * 0.46 *
                (1 - Self.smoothstep(afterglowProgress))
        let flash = eventWasFlash
            ? Self.flashEnvelope(elapsedMs) * recipe.flashScale * eventStrength
            : 0
        let core = family == nil
            ? 0
            : min(max(max(leader, returnStroke), 0), 1)
        let broad = min(charge + afterglow + flash * 0.72, 0.82)
        let boundedFlash = min(max(flash, 0), 0.82)

        if elapsedMs >= Double(recipe.episodeQuietGraceMs),
           max(max(core, afterglow), boundedFlash) < 0.015 {
            clearEpisode()
            return .idle
        }
        return SceneSurfaceStatefulStormSnapshot(
            family: family,
            broadOpacity: broad,
            coreOpacity: core,
            flashOpacity: boundedFlash,
            revealProgress: reveal,
            boltLuminanceGain: family == nil ? 0 : boltLuminanceGain
        )
    }

    mutating func reset() {
        audioSessionId = -1
        lastImpactSerial = 0
        lastFlashSerial = 0
        previousFamily = nil
        previousEventWasVisibleLightning = false
        clearEpisode()
    }

    private mutating func clearEpisode() {
        family = nil
        lastEventTime = nil
        lastStepTime = nil
        eventStrength = 0
        level = 0
        bass = 0
        body = 0
        spark = 0
        flow = 0
        charge = 0
        boltLuminanceGain = 0
        eventWasFlash = false
    }

    static func boltLuminanceGain(
        for strength: Double,
        recipe: SceneSurfaceStatefulStormRecipeV1
    ) -> Double {
        let progress = min(
            max(
                (min(max(strength, 0), 1) - recipe.minimumBoltStrength) /
                    (recipe.maximumBoltStrength - recipe.minimumBoltStrength),
                0
            ),
            1
        )
        let eased = smoothstep(progress)
        return recipe.minimumBoltLuminanceGain +
            (1 - recipe.minimumBoltLuminanceGain) * eased
    }

    private func selectFamily(
        impactStrength: Double,
        flashStrength: Double,
        newFlash: Bool,
        eventSerial: Int
    ) -> SceneSurfaceStatefulStormFamily {
        let preferred: SceneSurfaceStatefulStormFamily
        if newFlash,
           flashStrength >= 0.72,
           max(impactStrength, spark) >= 0.62 {
            preferred = .sparsePair
        } else if impactStrength >= 0.62, bass >= body, bass >= spark {
            preferred = .longVertical
        } else if spark > bass + 0.08 {
            preferred = .longOblique
        } else if impactStrength >= 0.50, abs(bass - spark) <= 0.08 {
            let selector = (
                audioSessionId * 31 + eventSerial * 17 + Int(recipe.seed)
            ) % 3
            switch selector {
            case 0: preferred = .longVertical
            case 1: preferred = .longOblique
            default: preferred = .occluded
            }
        } else {
            preferred = .occluded
        }
        guard preferred == previousFamily else { return preferred }
        let alternatives = SceneSurfaceStatefulStormFamily.allCases.filter {
            $0 != previousFamily
        }
        let selector = Int(
            entropy32(eventSerial: eventSerial, salt: 0x0051_f15e)
        ) % alternatives.count
        return alternatives[selector]
    }

    private func selectVisibleLightning(eventSerial: Int) -> Bool {
        guard !previousEventWasVisibleLightning else { return false }
        let probability = min(
            max(recipe.visibleLightningProbability, 0),
            0.49
        )
        let eligibleProbability = probability / (1 - probability)
        let entropy = Double(
            entropy32(eventSerial: eventSerial, salt: 0x0713_7a11)
        ) / 4_294_967_296.0
        return entropy < eligibleProbability
    }

    private func entropy32(eventSerial: Int, salt: UInt32) -> UInt32 {
        var value = UInt32(truncatingIfNeeded: recipe.seed)
        value ^= UInt32(truncatingIfNeeded: audioSessionId) &* 0x045d_9f3b
        value ^= UInt32(truncatingIfNeeded: eventSerial) &* 0x27d4_eb2d
        value ^= salt
        value ^= value >> 16
        value = value &* 0x7feb_352d
        value ^= value >> 15
        value = value &* 0x846c_a68b
        value ^= value >> 16
        return value
    }

    private static func integer(_ value: Any?) -> Int {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return 0
        }
        return number.intValue
    }

    private static func unit(_ value: Any?) -> Double {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            return 0
        }
        return min(max(number.doubleValue, 0), 1)
    }

    private static func follow(
        _ value: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        let time = target > value ? attack : release
        let amount = 1 - exp(-delta / max(time, 0.001))
        return value + (target - value) * amount
    }

    private static func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private static func flashEnvelope(_ elapsedMs: Double) -> Double {
        guard elapsedMs > 34 else { return 1 }
        return exp(-(elapsedMs - 34) / 150)
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceFirefliesRuntime {
    private struct Particle {
        let x: CGFloat
        let y: CGFloat
        let depthBand: Int
        let radius: CGFloat
        let luminance: CGFloat
    }

    private struct RandomSource {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Double(value >> 11) / Double(1 << 53)
        }
    }

    private struct Zone {
        let minimumX: Double
        let maximumX: Double
        let minimumY: Double
        let maximumY: Double
        let weight: Double
    }

    private static let zones = [
        Zone(minimumX: 0.05, maximumX: 0.31, minimumY: 0.55, maximumY: 0.93, weight: 0.25),
        Zone(minimumX: 0.69, maximumX: 0.95, minimumY: 0.54, maximumY: 0.93, weight: 0.25),
        Zone(minimumX: 0.31, maximumX: 0.69, minimumY: 0.43, maximumY: 0.90, weight: 0.35),
        Zone(minimumX: 0.23, maximumX: 0.77, minimumY: 0.25, maximumY: 0.53, weight: 0.15),
    ]

    let recipe: SceneSurfaceFirefliesRecipeV1
    private let particles: [Particle]
    private var cachedSize = CGSize.zero
    private var cachedMask: CIImage?
    private var lastHostTime: CFTimeInterval?
    private var elapsed = 0.0
    private var flow = 0.0
    private var spark = 0.0

    init(recipe: SceneSurfaceFirefliesRecipeV1) {
        self.recipe = recipe
        particles = (0..<recipe.particleCount).map { index in
            var random = RandomSource(
                seed: recipe.seed &+ UInt64(index) &* 7_919
            )
            let zone = Self.zone(for: random.nextUnit())
            let depthBand = index >= 42 ? 1 : index % 3
            let depth: Double
            switch depthBand {
            case 0: depth = 0.12 + random.nextUnit() * 0.26
            case 1: depth = 0.40 + random.nextUnit() * 0.30
            default: depth = 0.72 + random.nextUnit() * 0.28
            }
            return Particle(
                x: CGFloat(
                    zone.minimumX + random.nextUnit() *
                        (zone.maximumX - zone.minimumX)
                ),
                y: CGFloat(
                    zone.minimumY + random.nextUnit() *
                        (zone.maximumY - zone.minimumY)
                ),
                depthBand: depthBand,
                radius: CGFloat(
                    0.82 + depth * 0.52 + random.nextUnit() * 0.20
                ),
                luminance: CGFloat(0.56 + random.nextUnit() * 0.22)
            )
        }
    }

    func image(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        sparkDrive: Double,
        palette: [CIColor]
    ) -> CIImage? {
        guard targetRect.width >= 2, targetRect.height >= 2 else { return nil }
        let delta = min(max(hostTime - (lastHostTime ?? hostTime - 1.0 / 30.0), 0), 0.1)
        lastHostTime = hostTime
        flow = Self.follow(
            flow,
            target: musicActive ? flowDrive * recipe.flowResponse : 0,
            delta: delta,
            attack: 0.32,
            release: 1.15
        )
        spark = Self.follow(
            spark,
            target: musicActive ? sparkDrive * recipe.sparkResponse : 0,
            delta: delta,
            attack: 0.08,
            release: 0.48
        )
        elapsed += delta * (1 + flow * 0.24)

        if cachedMask == nil || cachedSize != targetRect.size {
            cachedMask = makeMask(size: targetRect.size)
            cachedSize = targetRect.size
        }
        guard let mask = cachedMask else { return nil }
        let colors = palette.isEmpty
            ? [
                CIColor(red: 0.92, green: 0.95, blue: 0.74),
                CIColor(red: 1.00, green: 0.85, blue: 0.47),
                CIColor(red: 1.00, green: 0.79, blue: 0.36),
            ]
            : palette
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: targetRect)
        let orbitScale = recipe.motionScale * (1 + flow * 0.16)

        for group in 0..<3 {
            let phase = Double(group) * 2.17
            let twinkle = 0.5 + 0.5 * sin(elapsed * (0.57 + Double(group) * 0.16) + phase)
            let opacity = min(
                max(0.72 + twinkle * 0.16 + spark * (0.08 + twinkle * 0.12), 0),
                1
            )
            let dx = sin(elapsed * (0.43 + Double(group) * 0.04) + phase) *
                Double(targetRect.width) * 0.006 * orbitScale
            let dy = cos(elapsed * (0.36 + Double(group) * 0.035) + phase) *
                Double(targetRect.height) * 0.0045 * orbitScale
            let color = colors[group % colors.count]
            let selector: (CGFloat, CGFloat, CGFloat) = switch group {
            case 0: (1, 0, 0)
            case 1: (0, 1, 0)
            default: (0, 0, 1)
            }
            let red = CIVector(
                x: selector.0 * color.red * opacity,
                y: selector.1 * color.red * opacity,
                z: selector.2 * color.red * opacity,
                w: 0
            )
            let green = CIVector(
                x: selector.0 * color.green * opacity,
                y: selector.1 * color.green * opacity,
                z: selector.2 * color.green * opacity,
                w: 0
            )
            let blue = CIVector(
                x: selector.0 * color.blue * opacity,
                y: selector.1 * color.blue * opacity,
                z: selector.2 * color.blue * opacity,
                w: 0
            )
            let alpha = CIVector(
                x: selector.0 * opacity,
                y: selector.1 * opacity,
                z: selector.2 * opacity,
                w: 0
            )
            let groupImage = mask.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": red,
                    "inputGVector": green,
                    "inputBVector": blue,
                    "inputAVector": alpha,
                ]
            ).transformed(
                by: CGAffineTransform(translationX: dx, y: dy)
            ).cropped(to: targetRect)
            composed = groupImage.applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: composed]
            ).cropped(to: targetRect)
        }
        return composed
    }

    private func makeMask(size: CGSize) -> CIImage? {
        let width = max(Int(size.width.rounded()), 2)
        let height = max(Int(size.height.rounded()), 2)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.plusLighter)
        let pixelScale = min(
            max(Double(width) / 390.0, 0.75),
            4.0
        )

        for particle in particles {
            let center = CGPoint(
                x: particle.x * CGFloat(width),
                y: (1 - particle.y) * CGFloat(height)
            )
            let haloRadius = CGFloat(
                (6.6 + Double(particle.depthBand) * 0.8) *
                    Double(particle.radius) * pixelScale * recipe.glowScale
            )
            let channel: (CGFloat, CGFloat, CGFloat) = switch particle.depthBand {
            case 0: (particle.luminance, 0, 0)
            case 1: (0, particle.luminance, 0)
            default: (0, 0, particle.luminance)
            }
            let inner = CGColor(
                red: channel.0,
                green: channel.1,
                blue: channel.2,
                alpha: 1
            )
            let outer = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [inner, outer] as CFArray,
                locations: [0, 1]
            ) else {
                continue
            }
            context.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: haloRadius,
                options: [.drawsAfterEndLocation]
            )
            let coreRadius = max(CGFloat(pixelScale) * particle.radius * 0.72, 0.8)
            context.setFillColor(inner)
            context.fillEllipse(
                in: CGRect(
                    x: center.x - coreRadius,
                    y: center.y - coreRadius,
                    width: coreRadius * 2,
                    height: coreRadius * 2
                )
            )
        }
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    private static func zone(for value: Double) -> Zone {
        var cumulative = 0.0
        for zone in zones {
            cumulative += zone.weight
            if value <= cumulative { return zone }
        }
        return zones[zones.count - 1]
    }

    private static func follow(
        _ current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0 else { return current }
        let timeConstant = target > current ? attack : release
        let alpha = 1 - exp(-delta / timeConstant)
        return min(max(current + (target - current) * alpha, 0), 1)
    }
}

struct SceneSurfaceInfernoEmbersReactionTransfer {
    let sustained: Double
    let accent: Double
    let visibilityGain: Double
    let travelSpeedMultiplier: Double

    static func resolve(
        musicActive: Bool,
        sustained: Double,
        accent: Double,
        motionScale: Double
    ) -> SceneSurfaceInfernoEmbersReactionTransfer {
        let boundedSustained = unit(sustained)
        let boundedAccent = unit(accent)
        let boundedMotion = min(max(motionScale, 0.5), 1.2)
        return SceneSurfaceInfernoEmbersReactionTransfer(
            sustained: boundedSustained,
            accent: boundedAccent,
            visibilityGain: musicActive
                ? 0.08 + boundedSustained * 0.92
                : 0.88,
            travelSpeedMultiplier: min(
                1 + (
                    boundedSustained * 0.22 + boundedAccent * 0.43
                ) * boundedMotion,
                1.78
            )
        )
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceInfernoEmbersSignalEnvelope {
    private(set) var sustained = 0.0
    private(set) var accent = 0.0

    mutating func update(
        musicActive: Bool,
        flowDrive: Double,
        bodyDrive: Double,
        sparkDrive: Double,
        sparkResponse: Double,
        motionScale: Double,
        delta: Double
    ) -> SceneSurfaceInfernoEmbersReactionTransfer {
        let sustainedTarget = musicActive
            ? Self.shape(
                max(flowDrive, bodyDrive * 0.88),
                lower: 0.24,
                upper: 0.78
            )
            : 0
        let accentTarget = musicActive
            ? Self.shape(
                sparkDrive,
                lower: 0.04,
                upper: 0.60
            ) * min(max(sparkResponse, 0), 1)
            : 0
        sustained = Self.follow(
            sustained,
            target: sustainedTarget,
            delta: delta,
            attack: 0.14,
            release: 0.55
        )
        accent = Self.follow(
            accent,
            target: accentTarget,
            delta: delta,
            attack: 0.015,
            release: 0.08
        )
        return SceneSurfaceInfernoEmbersReactionTransfer.resolve(
            musicActive: musicActive,
            sustained: sustained,
            accent: accent,
            motionScale: motionScale
        )
    }

    private static func shape(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        guard value.isFinite, upper > lower else { return 0 }
        let normalized = min(max((value - lower) / (upper - lower), 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private static func follow(
        _ current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0 else { return current }
        let timeConstant = target > current ? attack : release
        let alpha = 1 - exp(-delta / timeConstant)
        return min(max(current + (target - current) * alpha, 0), 1)
    }
}

@available(iOS 15.0, *)
final class SceneSurfaceInfernoEmbersRuntime {
    private struct Particle {
        let sourceX: CGFloat
        let sourceY: CGFloat
        let horizontalTravel: CGFloat
        let verticalTravel: CGFloat
        let thermalLift: CGFloat
        let travelSpeed: Double
        let cycleOffset: Double
        let swayAmplitude: CGFloat
        let swayFrequency: Double
        let phase: Double
        let group: Int
        let radius: CGFloat
        let haloRadius: CGFloat
        let luminance: CGFloat
        let sparkWeight: CGFloat
    }

    private struct RandomSource {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Double(value >> 11) / Double(1 << 53)
        }
    }

    let recipe: SceneSurfaceInfernoEmbersRecipeV1
    private static let defaultColors = [
        CIColor(red: 1.00, green: 0.23, blue: 0.04),
        CIColor(red: 1.00, green: 0.54, blue: 0.09),
        CIColor(red: 1.00, green: 0.82, blue: 0.42),
    ]
    private let particles: [Particle]
    private var renderingPath: SceneSurfaceDualRadialRenderingPath
    private let radialRenderer: SceneSurfaceDualRadialRenderer?
    private let renderPathMetrics: SceneSurfaceRenderPathMetrics?
    private let metricsScope: String?
    private let bitmapCanvas = SceneSurfaceReusableBitmapCanvas()
    private var cachedGradientComponents = [CGFloat]()
    private var cachedHaloGradients = [CGGradient?]()
    private var cachedGPUColorTable: SceneSurfaceInfernoGPUColorTable?
    private var radialInstances = [SceneSurfaceDualRadialInstance]()
    private(set) var lastRenderedInstanceCount = 0
    private(set) var lastParticleEvaluationCount = 0
    private(set) var gpuFrameCount = 0
    private(set) var cpuReferenceFrameCount = 0
    private(set) var gpuFallbackFrameCount = 0
    private(set) var particleEvaluationPassCount = 0
    private var lastHostTime: CFTimeInterval?
    private var elapsed = 0.0
    private var travelTime = 0.0
    private var signalEnvelope = SceneSurfaceInfernoEmbersSignalEnvelope()
    private var cachedPreparedFrame: SceneSurfacePreparedInfernoFrame?
    private var reusePreparedFrameForNextImage = false

    var radialInstanceStorageAddressForTesting: UInt {
        radialInstances.withUnsafeBufferPointer { buffer in
            UInt(bitPattern: buffer.baseAddress)
        }
    }

    init?(
        recipe: SceneSurfaceInfernoEmbersRecipeV1,
        metalContext: SceneSurfaceMetalContext?,
        renderingPath: SceneSurfaceDualRadialRenderingPath = .gpu,
        metricsScope: String? = nil
    ) {
        self.recipe = recipe
        renderPathMetrics = metalContext?.renderPathMetrics
        self.metricsScope = metricsScope
        switch renderingPath {
        case .gpu:
            let renderer = metalContext.flatMap { context in
                SceneSurfaceDualRadialRenderer(
                    context: context,
                    mode: .infernoAdditive,
                    metricsScope: metricsScope
                )
            }
            radialRenderer = renderer
            self.renderingPath = renderer == nil ? .cpuReference : .gpu
        case .cpuReference:
            radialRenderer = nil
            self.renderingPath = .cpuReference
        }
        particles = (0..<recipe.particleCount).map { index in
            var random = RandomSource(
                seed: recipe.seed &+ UInt64(index) &* 7_919
            )
            let depth = index % 3
            let angle =
                Double(index) / Double(recipe.particleCount) * .pi * 2 +
                (random.nextUnit() - 0.5) * 0.16
            let sourceX = 0.47 + random.nextUnit() * 0.06
            let sourceY = 0.46 + random.nextUnit() * 0.08
            let directionX = cos(angle)
            let directionY = -sin(angle)
            let horizontalDistance = abs(directionX) < 0.0001
                ? Double.infinity
                : (directionX > 0 ? 1 - sourceX : sourceX) /
                    abs(directionX)
            let verticalDistance = abs(directionY) < 0.0001
                ? Double.infinity
                : (directionY > 0 ? 1 - sourceY : sourceY) /
                    abs(directionY)
            let radialTravel = min(horizontalDistance, verticalDistance) *
                (0.96 + random.nextUnit() * 0.08)
            let paletteRoll = random.nextUnit()
            let radius = CGFloat(
                1.80 + Double(depth) * 0.50 + random.nextUnit() * 0.90
            )
            var haloRandom = RandomSource(
                seed: recipe.seed &+ UInt64(index) &* 10_007 &+ 0x51A7
            )
            let haloRadius = radius * CGFloat(
                2.5 + haloRandom.nextUnit() * 2.0
            )
            let luminance = CGFloat(0.70 + random.nextUnit() * 0.18)
            let sparkWeight = index % 4 == 0
                ? CGFloat(0.55 + random.nextUnit() * 0.45)
                : 0
            return Particle(
                sourceX: CGFloat(sourceX),
                sourceY: CGFloat(sourceY),
                horizontalTravel: CGFloat(directionX * radialTravel),
                verticalTravel: CGFloat(-directionY * radialTravel),
                thermalLift: CGFloat(0.05 + random.nextUnit() * 0.10),
                travelSpeed: 0.07 + random.nextUnit() * 0.06,
                cycleOffset: (
                    Double(index % 16) + random.nextUnit()
                ) / 16.0,
                swayAmplitude: CGFloat(0.002 + random.nextUnit() * 0.008),
                swayFrequency: 0.9 + random.nextUnit() * 1.1,
                phase: random.nextUnit() * .pi * 2,
                group: paletteRoll < 0.56 ? 0 : (paletteRoll < 0.88 ? 1 : 2),
                radius: radius,
                haloRadius: haloRadius,
                luminance: luminance,
                sparkWeight: sparkWeight
            )
        }
        radialInstances.reserveCapacity(recipe.particleCount)
    }

    func image(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bodyDrive: Double,
        sparkDrive: Double,
        palette: [CIColor]
    ) -> CIImage? {
        let prepared: SceneSurfacePreparedInfernoFrame?
        if reusePreparedFrameForNextImage,
           let cachedPreparedFrame,
           cachedPreparedFrame.size == targetRect.size {
            reusePreparedFrameForNextImage = false
            prepared = cachedPreparedFrame
        } else {
            prepared = prepareOnePassFrame(
                targetRect: CGRect(origin: .zero, size: targetRect.size),
                hostTime: hostTime,
                musicActive: musicActive,
                flowDrive: flowDrive,
                bodyDrive: bodyDrive,
                sparkDrive: sparkDrive,
                palette: palette,
                forceRefresh: true,
                reserveForFallback: false
            )
        }
        guard let prepared else {
            return nil
        }
        let rendered: CIImage?
        switch renderingPath {
        case .gpu:
            if let gpuImage = makeGPUImage(
                preparedFrame: prepared
            ) {
                rendered = gpuImage
                gpuFrameCount += 1
            } else {
                rendered = makeCPUReferenceImage(
                    preparedFrame: prepared
                )
                if rendered != nil {
                    cpuReferenceFrameCount += 1
                    gpuFallbackFrameCount += 1
                    renderPathMetrics?.recordCPUReference(
                        fallbackFromGPU: true,
                        scope: metricsScope
                    )
                }
                radialRenderer?.tearDown()
                renderingPath = .cpuReference
            }
        case .cpuReference:
            rendered = makeCPUReferenceImage(
                preparedFrame: prepared
            )
            if rendered != nil {
                cpuReferenceFrameCount += 1
                renderPathMetrics?.recordCPUReference(
                    fallbackFromGPU: false,
                    scope: metricsScope
                )
            }
        }
        guard var image = rendered else { return nil }
        if targetRect.origin != .zero {
            image = image.transformed(
                by: CGAffineTransform(
                    translationX: targetRect.minX,
                    y: targetRect.minY
                )
            )
        }
        return image.cropped(to: targetRect)
    }


    func prepareOnePassFrame(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bodyDrive: Double,
        sparkDrive: Double,
        palette: [CIColor],
        forceRefresh: Bool,
        reserveForFallback: Bool = false
    ) -> SceneSurfacePreparedInfernoFrame? {
        guard targetRect.width >= 2, targetRect.height >= 2 else { return nil }
        if let cachedPreparedFrame,
           cachedPreparedFrame.size == targetRect.size,
           (cachedPreparedFrame.hostTime == hostTime || !forceRefresh) {
            if reserveForFallback { reusePreparedFrameForNextImage = true }
            return cachedPreparedFrame
        }
        let delta = min(
            max(hostTime - (lastHostTime ?? hostTime - 1.0 / 24.0), 0),
            0.1
        )
        lastHostTime = hostTime
        let response = signalEnvelope.update(
            musicActive: musicActive,
            flowDrive: flowDrive,
            bodyDrive: bodyDrive,
            sparkDrive: sparkDrive,
            sparkResponse: recipe.sparkResponse,
            motionScale: recipe.motionScale,
            delta: delta
        )
        elapsed += delta
        travelTime += delta * response.travelSpeedMultiplier
        let colors = palette.isEmpty ? Self.defaultColors : palette
        let width = max(Int(targetRect.width.rounded()), 2)
        let height = max(Int(targetRect.height.rounded()), 2)
        let pixelScale = min(max(Double(width) / 390.0, 0.75), 4.0)
        let normalizedGlowScale = recipe.glowScale / 1.4
        let gpuColorTable = gpuColorTable(for: colors)
        // A selected frame shares Array storage with radialInstances. Release
        // that sample-and-hold owner before mutating on a genuinely due frame,
        // otherwise Swift must copy all particles every 1/24 s.
        cachedPreparedFrame = nil
        reusePreparedFrameForNextImage = false
        radialInstances.removeAll(keepingCapacity: true)
        lastParticleEvaluationCount = 0
        particleEvaluationPassCount += 1

        for particle in particles {
            lastParticleEvaluationCount += 1
            let progress = (
                particle.cycleOffset + travelTime * particle.travelSpeed
            ).truncatingRemainder(dividingBy: 1)
            let travel = pow(progress, 0.38)
            let sway = sin(
                particle.phase +
                    elapsed * particle.swayFrequency +
                    progress * .pi * 2
            ) * Double(particle.swayAmplitude) * (0.25 + progress * 0.75)
            let x = particle.sourceX +
                particle.horizontalTravel * CGFloat(travel) + CGFloat(sway)
            let y = particle.sourceY -
                particle.verticalTravel * CGFloat(travel) -
                particle.thermalLift * CGFloat(progress * progress)
            guard x >= -0.08, x <= 1.08, y >= -0.08, y <= 1.08 else {
                continue
            }
            let fadeIn = min(max(progress / 0.07, 0), 1)
            let fadeOut = min(max((1 - progress) / 0.10, 0), 1)
            let visibility = CGFloat(min(fadeIn, fadeOut))
            let sustained = CGFloat(response.sustained)
            let accent = CGFloat(response.accent) * particle.sparkWeight
            let twinkle = CGFloat(
                0.5 + 0.5 * sin(particle.phase * 1.7 + elapsed * 0.7)
            )
            let luminance = min(
                (particle.luminance + twinkle * 0.10) *
                    CGFloat(response.visibilityGain) + accent * 1.65,
                1
            ) * visibility
            let colorIndex = particle.group % colors.count
            let color = colors[colorIndex]
            let haloColor = gpuColorTable.haloColors[colorIndex]
            let haloAlpha = min(
                max(
                    luminance *
                        (0.40 + sustained * 0.24 + accent * 0.55),
                    0
                ),
                1
            )
            let haloRadius = CGFloat(
                Double(particle.haloRadius) * pixelScale * 1.05 *
                    normalizedGlowScale *
                    Double(1 + sustained * 0.18 + accent * 0.55)
            )
            let coreRadius = max(
                CGFloat(pixelScale) * particle.radius * 1.12 *
                    (1 + sustained * 0.08 + accent * 0.22),
                0.35
            )
            let whiteMix = min(
                0.58 + sustained * 0.08 + accent * 0.24,
                1
            )
            radialInstances.append(
                SceneSurfaceDualRadialInstance(
                    centerAndRadii: SIMD4(
                        Float(x * CGFloat(width)),
                        Float((1 - y) * CGFloat(height)),
                        Float(haloRadius),
                        Float(coreRadius)
                    ),
                    haloColorAndOpacity: SIMD4(
                        haloColor.x,
                        haloColor.y,
                        haloColor.z,
                        Float(haloAlpha)
                    ),
                    coreColorAndOpacity: SIMD4(
                        Float(color.red + (1 - color.red) * whiteMix),
                        Float(color.green + (1 - color.green) * whiteMix),
                        Float(color.blue + (1 - color.blue) * whiteMix),
                        Float(luminance)
                    )
                )
            )
        }
        lastRenderedInstanceCount = radialInstances.count
        let prepared = SceneSurfacePreparedInfernoFrame(
            hostTime: hostTime,
            size: targetRect.size,
            instances: radialInstances
        )
        cachedPreparedFrame = prepared
        if reserveForFallback { reusePreparedFrameForNextImage = true }
        return prepared
    }

    private func makeGPUImage(
        preparedFrame: SceneSurfacePreparedInfernoFrame
    ) -> CIImage? {
        let targetRect = CGRect(origin: .zero, size: preparedFrame.size)
        return radialRenderer?.image(
            targetRect: targetRect,
            instances: preparedFrame.instances
        )
    }

    private func gpuColorTable(
        for colors: [CIColor]
    ) -> SceneSurfaceInfernoGPUColorTable {
        let signature = colors.flatMap { color in
            [color.red, color.green, color.blue]
        }
        if let cachedGPUColorTable,
           cachedGPUColorTable.signature == signature {
            return cachedGPUColorTable
        }
        let table = SceneSurfaceInfernoGPUColorTable(colors: colors)
        cachedGPUColorTable = table
        return table
    }

    private func makeCPUReferenceImage(
        preparedFrame: SceneSurfacePreparedInfernoFrame
    ) -> CIImage? {
        let width = max(Int(preparedFrame.size.width.rounded()), 2)
        let height = max(Int(preparedFrame.size.height.rounded()), 2)
        guard let context = bitmapCanvas.context(width: width, height: height) else {
            return nil
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setBlendMode(.plusLighter)
        context.setAlpha(1)
        for instance in preparedFrame.instances {
            let center = CGPoint(
                x: CGFloat(instance.centerAndRadii.x),
                y: CGFloat(instance.centerAndRadii.y)
            )
            let haloComponents = [
                CGFloat(instance.haloColorAndOpacity.x),
                CGFloat(instance.haloColorAndOpacity.y),
                CGFloat(instance.haloColorAndOpacity.z),
            ]
            guard
                let haloColor = CGColor(
                    colorSpace: bitmapCanvas.colorSpace,
                    components: haloComponents + [1]
                ),
                let middle = CGColor(
                    colorSpace: bitmapCanvas.colorSpace,
                    components: haloComponents + [0.32]
                ),
                let transparent = CGColor(
                    colorSpace: bitmapCanvas.colorSpace,
                    components: haloComponents + [0]
                )
            else {
                continue
            }
            if let gradient = CGGradient(
                colorsSpace: bitmapCanvas.colorSpace,
                colors: [haloColor, middle, transparent] as CFArray,
                locations: [0, 0.46, 1]
            ) {
                context.setAlpha(CGFloat(instance.haloColorAndOpacity.w))
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: CGFloat(instance.centerAndRadii.z),
                    options: [.drawsAfterEndLocation]
                )
                context.setAlpha(1)
            }
            let coreComponents = [
                CGFloat(instance.coreColorAndOpacity.x),
                CGFloat(instance.coreColorAndOpacity.y),
                CGFloat(instance.coreColorAndOpacity.z),
                CGFloat(instance.coreColorAndOpacity.w),
            ]
            guard let coreColor = CGColor(
                colorSpace: bitmapCanvas.colorSpace,
                components: coreComponents
            ) else {
                continue
            }
            context.setFillColor(coreColor)
            let coreRadius = CGFloat(instance.centerAndRadii.w)
            context.fillEllipse(
                in: CGRect(
                    x: center.x - coreRadius,
                    y: center.y - coreRadius,
                    width: coreRadius * 2,
                    height: coreRadius * 2
                )
            )
        }
        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    private func gradients(for colors: [CIColor]) -> [CGGradient?] {
        let components = colors.flatMap { color in
            [color.red, color.green, color.blue]
        }
        if components == cachedGradientComponents,
           cachedHaloGradients.count == colors.count {
            return cachedHaloGradients
        }
        cachedGradientComponents = components
        cachedHaloGradients = colors.map { color in
            let inner = CGColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 1
            )
            let middle = CGColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0.32
            )
            let transparent = CGColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0
            )
            return CGGradient(
                colorsSpace: bitmapCanvas.colorSpace,
                colors: [inner, middle, transparent] as CFArray,
                locations: [0, 0.46, 1]
            )
        }
        return cachedHaloGradients
    }

    var gpuSubpassSettledSuccessfully: Bool {
        renderingPath != .gpu ||
            radialRenderer?.latestCommandSettledSuccessfully == true
    }

    func recoverFromGPUCommandFailure() -> Bool {
        guard
            renderingPath == .gpu,
            radialRenderer?.hasLatchedGPUFailure == true
        else {
            return false
        }
        radialRenderer?.tearDown()
        renderingPath = .cpuReference
        gpuFallbackFrameCount += 1
        return true
    }

    func tearDown() {
        radialRenderer?.tearDown()
        radialInstances.removeAll(keepingCapacity: false)
        cachedPreparedFrame = nil
        reusePreparedFrameForNextImage = false
    }

}

@available(iOS 15.0, *)
final class SceneSurfaceWildflowerPollenRuntime {
    private struct Particle {
        let startX: Double
        let startY: Double
        let progressOffset: Double
        let speedScale: Double
        let driftPhase: Double
        let driftScale: Double
        let radius: Double
        let luminance: Double
        let colorIndex: Int
    }

    private struct RandomSource {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Double(value >> 11) / Double(1 << 53)
        }
    }

    let recipe: SceneSurfaceWildflowerPollenRecipeV1
    private let particles: [Particle]
    private var renderingPath: SceneSurfaceDualRadialRenderingPath
    private let radialRenderer: SceneSurfaceDualRadialRenderer?
    private let halo: CIImage?
    private let core: CIImage?
    private var radialInstances = [SceneSurfaceDualRadialInstance]()
    private(set) var lastRenderedInstanceCount = 0
    private(set) var lastParticleEvaluationCount = 0
    private(set) var gpuFrameCount = 0
    private(set) var cpuReferenceFrameCount = 0
    private(set) var gpuFallbackFrameCount = 0
    private var lastHostTime: CFTimeInterval?
    private var elapsed = 0.0
    private var travelPhase = 0.0
    private var flow = 0.0
    private var spark = 0.0

    init?(
        recipe: SceneSurfaceWildflowerPollenRecipeV1,
        metalContext: SceneSurfaceMetalContext?,
        renderingPath: SceneSurfaceDualRadialRenderingPath = .gpu,
        metricsScope: String? = nil
    ) {
        self.recipe = recipe
        let renderer = renderingPath == .gpu
            ? metalContext.flatMap { context in
                SceneSurfaceDualRadialRenderer(
                    context: context,
                    mode: .pollenSourceOver,
                    metricsScope: metricsScope
                )
            }
            : nil
        radialRenderer = renderer
        self.renderingPath = renderer == nil ? .cpuReference : renderingPath
        guard
            let halo = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: 16, y: 16),
                    "inputRadius0": 0,
                    "inputRadius1": 16,
                    "inputColor0": CIColor(
                        red: 1,
                        green: 1,
                        blue: 1,
                        alpha: 1
                    ),
                    "inputColor1": CIColor(
                        red: 1,
                        green: 1,
                        blue: 1,
                        alpha: 0
                    ),
                ]
            )?.outputImage?.cropped(
                to: CGRect(x: 0, y: 0, width: 32, height: 32)
            ),
            let core = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: 8, y: 8),
                    "inputRadius0": 2.4,
                    "inputRadius1": 8,
                    "inputColor0": CIColor(
                        red: 1,
                        green: 1,
                        blue: 1,
                        alpha: 1
                    ),
                    "inputColor1": CIColor(
                        red: 1,
                        green: 1,
                        blue: 1,
                        alpha: 0
                    ),
                ]
            )?.outputImage?.cropped(
                to: CGRect(x: 0, y: 0, width: 16, height: 16)
            )
        else {
            return nil
        }
        self.halo = halo
        self.core = core
        particles = (0..<recipe.particleCount).map { index in
            var random = RandomSource(
                seed: recipe.seed &+ UInt64(index) &* 10_007
            )
            let edgePosition = 0.04 + random.nextUnit() * 0.92
            let edgeInset = 0.02 + random.nextUnit() * 0.08
            let startX: Double
            let startY: Double
            switch index % 4 {
            case 0:
                startX = edgePosition
                startY = 1 - edgeInset
            case 1:
                startX = 1 - edgeInset
                startY = edgePosition
            case 2:
                startX = edgePosition
                startY = edgeInset
            default:
                startX = edgeInset
                startY = edgePosition
            }
            return Particle(
                startX: startX,
                startY: startY,
                progressOffset: random.nextUnit(),
                speedScale: 0.78 + random.nextUnit() * 0.44,
                driftPhase: random.nextUnit() * Double.pi * 2,
                driftScale: 0.45 + random.nextUnit() * 0.55,
                radius: 0.86 + random.nextUnit() * 0.82,
                luminance: 0.58 + random.nextUnit() * 0.28,
                colorIndex: index % 3
            )
        }
        radialInstances.reserveCapacity(recipe.particleCount)
    }

    func image(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        sparkDrive: Double,
        palette: [CIColor]
    ) -> CIImage? {
        guard targetRect.width >= 2, targetRect.height >= 2 else { return nil }
        let delta = min(
            max(hostTime - (lastHostTime ?? hostTime - 1.0 / 24.0), 0),
            0.1
        )
        lastHostTime = hostTime
        flow = Self.follow(
            flow,
            target: musicActive ? flowDrive * recipe.flowResponse : 0,
            delta: delta,
            attack: 0.22,
            release: 0.72
        )
        spark = Self.follow(
            spark,
            target: musicActive ? sparkDrive * recipe.sparkResponse : 0,
            delta: delta,
            attack: 0.04,
            release: 0.24
        )
        elapsed += delta
        travelPhase += delta * recipe.travelSpeed * (
            1 + flow * 0.75 + spark * 0.18
        )

        let colors = palette.isEmpty
            ? [
                CIColor(red: 1.00, green: 0.96, blue: 0.70),
                CIColor(red: 1.00, green: 0.84, blue: 0.42),
                CIColor(red: 1.00, green: 0.73, blue: 0.24),
            ]
            : palette
        let rendered: CIImage?
        switch renderingPath {
        case .gpu:
            if let gpuImage = makeGPUImage(
                targetRect: targetRect,
                colors: colors
            ) {
                rendered = gpuImage
                gpuFrameCount += 1
            } else {
                rendered = makeCPUReferenceImage(
                    targetRect: targetRect,
                    colors: colors
                )
                if rendered != nil {
                    cpuReferenceFrameCount += 1
                    gpuFallbackFrameCount += 1
                }
                radialRenderer?.tearDown()
                renderingPath = .cpuReference
            }
        case .cpuReference:
            rendered = makeCPUReferenceImage(
                targetRect: targetRect,
                colors: colors
            )
            if rendered != nil { cpuReferenceFrameCount += 1 }
        }
        return rendered
    }

    private func makeGPUImage(
        targetRect: CGRect,
        colors: [CIColor]
    ) -> CIImage? {
        let targetX = targetRect.width * recipe.targetX
        let targetY = targetRect.height * (1 - recipe.targetY)
        let pixelScale = min(max(Double(targetRect.width) / 390.0, 0.75), 4.0)
        radialInstances.removeAll(keepingCapacity: true)
        lastParticleEvaluationCount = 0

        for particle in particles {
            lastParticleEvaluationCount += 1
            let rawProgress = (
                particle.progressOffset +
                    travelPhase * particle.speedScale
            ).truncatingRemainder(dividingBy: 1)
            let progress = Self.smoothstep(rawProgress)
            let contraction = pow(1 - progress, recipe.convergence)
            let startX = targetRect.width * particle.startX
            let startY = targetRect.height * (1 - particle.startY)
            let drift = sin(
                elapsed * (0.72 + particle.speedScale * 0.16) +
                    particle.driftPhase
            ) * Double(targetRect.width) * 0.012 * particle.driftScale *
                contraction * recipe.motionScale
            let centerX = targetX + (startX - targetX) * contraction + drift
            let centerY = targetY + (startY - targetY) * contraction

            let perspective = 0.28 + contraction * 0.72
            let fadeIn = Self.smoothstep(min(rawProgress / 0.08, 1))
            let fadeOut = 1 - Self.smoothstep(
                min(max((rawProgress - 0.76) / 0.24, 0), 1)
            )
            let glintPhase = max(
                sin(elapsed * 4.2 + particle.driftPhase),
                0
            )
            let glint = spark * (0.18 + pow(glintPhase, 8) * 0.34)
            let visibility = 0.78 + particle.luminance * 0.22
            let opacity = min(
                max(
                    fadeIn * fadeOut *
                        (0.62 + flow * 0.18 + glint) * visibility,
                    0
                ),
                1
            )
            guard opacity > 0.004 else { continue }

            let haloRadius = (
                7.0 * particle.radius * perspective * recipe.glowScale *
                    (1 + flow * 0.12 + spark * 0.48) * pixelScale
            )
            let coreRadius = (
                3.4 * particle.radius * perspective *
                    (1 + flow * 0.22 + spark * 0.72) * pixelScale
            )
            let coreOpacity = min(
                fadeIn * fadeOut * (0.78 + flow * 0.10 + spark * 0.34),
                1
            )
            let color = colors[particle.colorIndex % colors.count]
            radialInstances.append(
                SceneSurfaceDualRadialInstance(
                    centerAndRadii: SIMD4(
                        Float(centerX),
                        Float(centerY),
                        Float(haloRadius),
                        Float(coreRadius)
                    ),
                    haloColorAndOpacity: SIMD4(
                        Float(color.red),
                        Float(color.green),
                        Float(color.blue),
                        Float(opacity)
                    ),
                    coreColorAndOpacity: SIMD4(
                        Float(0.66 + color.red * 0.34),
                        Float(0.66 + color.green * 0.34),
                        Float(0.66 + color.blue * 0.34),
                        Float(coreOpacity)
                    )
                )
            )
        }
        lastRenderedInstanceCount = radialInstances.count
        return radialRenderer?.image(
            targetRect: targetRect,
            instances: radialInstances
        )
    }

    private func makeCPUReferenceImage(
        targetRect: CGRect,
        colors: [CIColor]
    ) -> CIImage? {
        guard let halo, let core else { return nil }
        let targetX = targetRect.minX + targetRect.width * recipe.targetX
        let targetY = targetRect.minY + targetRect.height * (1 - recipe.targetY)
        let pixelScale = min(max(Double(targetRect.width) / 390.0, 0.75), 4.0)
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: targetRect)

        for particle in particles {
            let rawProgress = (
                particle.progressOffset +
                    travelPhase * particle.speedScale
            ).truncatingRemainder(dividingBy: 1)
            let progress = Self.smoothstep(rawProgress)
            let contraction = pow(1 - progress, recipe.convergence)
            let startX = targetRect.minX + targetRect.width * particle.startX
            let startY = targetRect.minY + targetRect.height * (1 - particle.startY)
            let drift = sin(
                elapsed * (0.72 + particle.speedScale * 0.16) +
                    particle.driftPhase
            ) * Double(targetRect.width) * 0.012 * particle.driftScale *
                contraction * recipe.motionScale
            let centerX = targetX + (startX - targetX) * contraction + drift
            let centerY = targetY + (startY - targetY) * contraction

            let perspective = 0.28 + contraction * 0.72
            let fadeIn = Self.smoothstep(min(rawProgress / 0.08, 1))
            let fadeOut = 1 - Self.smoothstep(
                min(max((rawProgress - 0.76) / 0.24, 0), 1)
            )
            let glintPhase = max(
                sin(elapsed * 4.2 + particle.driftPhase),
                0
            )
            let glint = spark * (0.18 + pow(glintPhase, 8) * 0.34)
            let visibility = 0.78 + particle.luminance * 0.22
            let opacity = min(
                max(
                    fadeIn * fadeOut *
                        (0.62 + flow * 0.18 + glint) * visibility,
                    0
                ),
                1
            )
            guard opacity > 0.004 else { continue }

            let haloRadius = (
                7.0 * particle.radius * perspective * recipe.glowScale *
                    (1 + flow * 0.12 + spark * 0.48) * pixelScale
            )
            let scale = haloRadius / 16.0
            let positioned = halo.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            ).transformed(
                by: CGAffineTransform(
                    translationX: centerX - 16 * scale,
                    y: centerY - 16 * scale
                )
            )
            let color = colors[particle.colorIndex % colors.count]
            let tinted = positioned.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(
                        x: color.red * opacity,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                    "inputGVector": CIVector(
                        x: 0,
                        y: color.green * opacity,
                        z: 0,
                        w: 0
                    ),
                    "inputBVector": CIVector(
                        x: 0,
                        y: 0,
                        z: color.blue * opacity,
                        w: 0
                    ),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
                ]
            )
            composed = tinted.applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: composed]
            ).cropped(to: targetRect)

            let coreRadius = (
                3.4 * particle.radius * perspective *
                    (1 + flow * 0.22 + spark * 0.72) * pixelScale
            )
            let coreScale = coreRadius / 8.0
            let positionedCore = core.transformed(
                by: CGAffineTransform(scaleX: coreScale, y: coreScale)
            ).transformed(
                by: CGAffineTransform(
                    translationX: centerX - 8 * coreScale,
                    y: centerY - 8 * coreScale
                )
            )
            let coreOpacity = min(
                fadeIn * fadeOut * (0.78 + flow * 0.10 + spark * 0.34),
                1
            )
            let coreTint = CIColor(
                red: 0.66 + color.red * 0.34,
                green: 0.66 + color.green * 0.34,
                blue: 0.66 + color.blue * 0.34
            )
            let tintedCore = positionedCore.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(
                        x: coreTint.red * coreOpacity,
                        y: 0,
                        z: 0,
                        w: 0
                    ),
                    "inputGVector": CIVector(
                        x: 0,
                        y: coreTint.green * coreOpacity,
                        z: 0,
                        w: 0
                    ),
                    "inputBVector": CIVector(
                        x: 0,
                        y: 0,
                        z: coreTint.blue * coreOpacity,
                        w: 0
                    ),
                    "inputAVector": CIVector(
                        x: 0,
                        y: 0,
                        z: 0,
                        w: coreOpacity
                    ),
                ]
            )
            composed = tintedCore.applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: composed]
            ).cropped(to: targetRect)
        }
        return composed
    }

    var gpuSubpassSettledSuccessfully: Bool {
        renderingPath != .gpu ||
            radialRenderer?.latestCommandSettledSuccessfully == true
    }

    func recoverFromGPUCommandFailure() -> Bool {
        guard
            renderingPath == .gpu,
            radialRenderer?.hasLatchedGPUFailure == true
        else {
            return false
        }
        radialRenderer?.tearDown()
        renderingPath = .cpuReference
        gpuFallbackFrameCount += 1
        return true
    }

    func tearDown() {
        radialRenderer?.tearDown()
        radialInstances.removeAll(keepingCapacity: false)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let bounded = min(max(value, 0), 1)
        return bounded * bounded * (3 - 2 * bounded)
    }

    private static func follow(
        _ current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0 else { return current }
        let timeConstant = target > current ? attack : release
        let alpha = 1 - exp(-delta / timeConstant)
        return min(max(current + (target - current) * alpha, 0), 1)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceRadialWarpReactionTransfer {
    let travelSpeedMultiplier: Double
    let trailLengthMultiplier: Double
    let nearCometScale: Double
    let luminanceMultiplier: Double
    let bloomIntensity: Double

    static func resolve(
        flow: Double,
        bass: Double,
        spark: Double
    ) -> SceneSurfaceRadialWarpReactionTransfer {
        let boundedFlow = unit(flow)
        let boundedBass = unit(bass)
        let boundedSpark = unit(spark)
        return SceneSurfaceRadialWarpReactionTransfer(
            travelSpeedMultiplier: min(
                1 + boundedFlow * 0.55 + boundedBass * 2.5,
                2.5
            ),
            trailLengthMultiplier: min(
                1 + boundedFlow * 0.25 + boundedBass * 1.35,
                1.7
            ),
            nearCometScale: min(
                1 + boundedBass * 1.1 + boundedSpark * 0.4,
                1.5
            ),
            luminanceMultiplier: min(
                1 + boundedFlow * 0.05 + boundedBass * 0.28 +
                    boundedSpark * 0.42,
                1.3
            ),
            bloomIntensity: min(
                0.82 + boundedFlow * 0.04 + boundedBass * 0.22 +
                    boundedSpark * 0.38,
                1.12
            )
        )
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceRadialWarpSignalEnvelope {
    private var flow = 0.0
    private var bass = 0.0
    private(set) var spark = 0.0

    mutating func update(
        musicActive: Bool,
        flowTarget: Double,
        bassTarget: Double,
        sparkTarget: Double,
        delta: Double
    ) -> SceneSurfaceRadialWarpReactionTransfer {
        flow = Self.follow(
            flow,
            target: musicActive ? flowTarget : 0,
            delta: delta,
            attack: 0.20,
            release: 0.72
        )
        bass = Self.follow(
            bass,
            target: musicActive ? bassTarget : 0,
            delta: delta,
            attack: 0.035,
            release: 0.13
        )
        spark = Self.follow(
            spark,
            target: musicActive ? sparkTarget : 0,
            delta: delta,
            attack: 0.025,
            release: 0.12
        )
        return SceneSurfaceRadialWarpReactionTransfer.resolve(
            flow: flow,
            bass: bass,
            spark: spark
        )
    }

    private static func follow(
        _ current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0 else { return current }
        let timeConstant = target > current ? attack : release
        let alpha = 1 - exp(-delta / timeConstant)
        return min(max(current + (target - current) * alpha, 0), 1)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceRadialWarpTransportClock {
    private(set) var phase: Double

    init(phase: Double = 0) {
        self.phase = phase.isFinite ? phase : 0
    }

    mutating func advance(
        delta: Double,
        travelSpeed: Double,
        speedMultiplier: Double
    ) {
        guard delta.isFinite,
              travelSpeed.isFinite,
              speedMultiplier.isFinite else {
            return
        }
        phase += max(delta, 0) * max(travelSpeed, 0) *
            max(speedMultiplier, 0)
    }

    func progress(offset: Double, speedScale: Double) -> Double {
        guard offset.isFinite, speedScale.isFinite else { return 0 }
        let value = (offset + phase * speedScale)
            .truncatingRemainder(dividingBy: 1)
        return value >= 0 ? value : value + 1
    }
}

@available(iOS 15.0, *)
private final class SceneSurfaceRadialWarpRuntime {
    private struct Particle {
        let angle: Double
        let progressOffset: Double
        let speedScale: Double
        let sizeScale: Double
        let luminance: Double
        let colorIndex: Int
        let glintPhase: Double
        let glintEligible: Bool
        let cometEligible: Bool
    }

    private struct RandomSource {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func nextUnit() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Double(value >> 11) / Double(1 << 53)
        }
    }

    let recipe: SceneSurfaceRadialWarpRecipeV1
    private let particles: [Particle]
    private let bitmapCanvas = SceneSurfaceReusableBitmapCanvas()
    private var lastHostTime: CFTimeInterval?
    private var elapsed = 0.0
    private var transportClock = SceneSurfaceRadialWarpTransportClock()
    private var signalEnvelope = SceneSurfaceRadialWarpSignalEnvelope()

    init(recipe: SceneSurfaceRadialWarpRecipeV1) {
        self.recipe = recipe
        particles = (0..<recipe.particleCount).map { index in
            var random = RandomSource(
                seed: recipe.seed &+ UInt64(index) &* 12_289
            )
            let goldenAngle = Double(index) * 2.399_963_229_728_653
            let colorRoll = random.nextUnit()
            let colorIndex: Int
            if colorRoll < 0.30 {
                colorIndex = 2
            } else if colorRoll < 0.59 {
                colorIndex = 0
            } else if colorRoll < 0.84 {
                colorIndex = 1
            } else if colorRoll < 0.91 {
                colorIndex = 3
            } else if colorRoll < 0.96 {
                colorIndex = 4
            } else {
                colorIndex = 5
            }
            return Particle(
                angle: goldenAngle + (random.nextUnit() - 0.5) * 0.62,
                progressOffset: random.nextUnit(),
                speedScale: 0.90 + random.nextUnit() * 0.20,
                sizeScale: 0.72 + random.nextUnit() * 0.56,
                luminance: 0.68 + random.nextUnit() * 0.32,
                colorIndex: colorIndex,
                glintPhase: random.nextUnit() * Double.pi * 2,
                glintEligible: index % 9 == 0,
                cometEligible: index % 7 == 0
            )
        }
    }

    func image(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bassDrive: Double,
        sparkDrive: Double,
        palette: [CIColor]
    ) -> CIImage? {
        guard targetRect.width >= 2, targetRect.height >= 2 else { return nil }
        let fallbackDelta = 1.0 / Double(recipe.framesPerSecond)
        let delta = min(
            max(hostTime - (lastHostTime ?? hostTime - fallbackDelta), 0),
            0.1
        )
        lastHostTime = hostTime
        let reaction = signalEnvelope.update(
            musicActive: musicActive,
            flowTarget: flowDrive * recipe.flowResponse,
            bassTarget: bassDrive * recipe.bassResponse,
            sparkTarget: sparkDrive * recipe.sparkResponse,
            delta: delta
        )
        elapsed += delta
        transportClock.advance(
            delta: delta,
            travelSpeed: recipe.travelSpeed,
            speedMultiplier: reaction.travelSpeedMultiplier
        )

        let renderWidth = min(max(Int(targetRect.width.rounded()), 2), 720)
        let aspect = Double(targetRect.height / targetRect.width)
        let renderHeight = max(Int((Double(renderWidth) * aspect).rounded()), 2)
        guard let context = context(width: renderWidth, height: renderHeight) else {
            return nil
        }
        let bounds = CGRect(x: 0, y: 0, width: renderWidth, height: renderHeight)
        context.clear(bounds)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineCap(.butt)
        context.setBlendMode(.plusLighter)

        let colors = palette.isEmpty
            ? [
                CIColor(red: 0.19, green: 0.85, blue: 1.00),
                CIColor(red: 0.17, green: 0.36, blue: 1.00),
                CIColor(red: 0.96, green: 0.98, blue: 1.00),
                CIColor(red: 1.00, green: 0.70, blue: 0.23),
                CIColor(red: 0.55, green: 0.92, blue: 0.33),
                CIColor(red: 1.00, green: 0.42, blue: 0.80),
            ]
            : palette
        let center = CGPoint(
            x: Double(renderWidth) * recipe.centerX,
            y: Double(renderHeight) * (1 - recipe.centerY)
        )
        let pixelScale = min(max(Double(renderWidth) / 390.0, 0.75), 2.2)

        for particle in particles {
            let rawProgress = transportClock.progress(
                offset: particle.progressOffset,
                speedScale: particle.speedScale
            )
            let easedProgress = pow(rawProgress, 1.75)
            let direction = CGPoint(
                x: cos(particle.angle),
                y: sin(particle.angle)
            )
            let edgeDistance = Self.distanceToEdge(
                center: center,
                direction: direction,
                width: Double(renderWidth),
                height: Double(renderHeight)
            ) * 1.06
            let baseTrail = (
                0.0015 + pow(rawProgress, 2.05) * 0.075
            ) * recipe.streakScale * reaction.trailLengthMultiplier
            let nearTrailScale = rawProgress >= 0.84
                ? (particle.cometEligible ? 3.0 : 1.35)
                : 1
            let trailSpan = min(baseTrail * nearTrailScale, 0.19)
            let tailProgress = max(rawProgress - trailSpan, 0)
            let tailEased = pow(tailProgress, 1.75)
            let head = CGPoint(
                x: center.x + direction.x * edgeDistance * easedProgress,
                y: center.y + direction.y * edgeDistance * easedProgress
            )
            let tail = CGPoint(
                x: center.x + direction.x * edgeDistance * tailEased,
                y: center.y + direction.y * edgeDistance * tailEased
            )
            let fadeIn = Self.smoothstep(min(rawProgress / 0.018, 1))
            let fadeOut = 1 - Self.smoothstep(
                min(max((rawProgress - 0.968) / 0.032, 0), 1)
            )
            let glintWave = max(
                sin(elapsed * 4.1 + particle.glintPhase),
                0
            )
            let localGlint = particle.glintEligible
                ? min(
                    signalEnvelope.spark * pow(glintWave, 6) * 2.2,
                    1
                )
                : 0
            let visibility = min(
                max(
                    fadeIn * fadeOut * particle.luminance *
                        (0.42 + rawProgress * 0.58 + localGlint * 0.68) *
                        reaction.luminanceMultiplier,
                    0
                ),
                1
            )
            guard visibility > 0.003 else { continue }

            let color = colors[particle.colorIndex % colors.count]
            if rawProgress < 0.28 {
                let radius = (
                    0.20 + rawProgress * 0.88
                ) * particle.sizeScale * pixelScale
                Self.fillPoint(
                    context,
                    at: head,
                    radius: radius,
                    color: color,
                    alpha: visibility
                )
                continue
            }

            if rawProgress >= 0.84 && particle.cometEligible {
                let near = Self.smoothstep((rawProgress - 0.84) / 0.16)
                let headWidth = (
                    1.45 + near * 4.4
                ) * particle.sizeScale * pixelScale * reaction.nearCometScale
                Self.drawComet(
                    context,
                    from: tail,
                    to: head,
                    headWidth: headWidth,
                    color: color,
                    visibility: visibility,
                    localGlint: localGlint
                )
                continue
            }

            let rayDepth = Self.smoothstep((rawProgress - 0.28) / 0.72)
            let coreWidth = (
                0.26 + rayDepth * 0.92
            ) * particle.sizeScale * pixelScale
            Self.drawRay(
                context,
                from: tail,
                to: head,
                coreWidth: coreWidth,
                color: color,
                visibility: visibility,
                localGlint: localGlint
            )
        }

        guard let image = context.makeImage() else { return nil }
        let baseImage = CIImage(cgImage: image)
        let bloomRadius = 5.0 * recipe.glowScale * pixelScale
        let renderedImage = baseImage.clampedToExtent().applyingFilter(
            "CIBloom",
            parameters: [
                kCIInputRadiusKey: bloomRadius,
                kCIInputIntensityKey: reaction.bloomIntensity,
            ]
        ).cropped(to: bounds)
        let scaleX = targetRect.width / CGFloat(renderWidth)
        let scaleY = targetRect.height / CGFloat(renderHeight)
        return renderedImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        ).transformed(
            by: CGAffineTransform(
                translationX: targetRect.minX,
                y: targetRect.minY
            )
        ).cropped(to: targetRect)
    }

    private func context(width: Int, height: Int) -> CGContext? {
        bitmapCanvas.context(width: width, height: height)
    }

    private static func fillPoint(
        _ context: CGContext,
        at point: CGPoint,
        radius: Double,
        color: CIColor,
        alpha: Double
    ) {
        fillEllipse(
            context,
            at: point,
            radius: max(radius, 0.22),
            color: color,
            alpha: alpha * 0.74
        )
        fillEllipse(
            context,
            at: point,
            radius: max(radius * 0.34, 0.16),
            color: brightened(color, amount: 0.62),
            alpha: min(alpha * 1.08, 1)
        )
    }

    private static func drawRay(
        _ context: CGContext,
        from: CGPoint,
        to: CGPoint,
        coreWidth: Double,
        color: CIColor,
        visibility: Double,
        localGlint: Double
    ) {
        drawTaperedStreak(
            context,
            from: from,
            to: to,
            tailWidth: max(coreWidth * 0.08, 0.06),
            headWidth: max(coreWidth, 0.32),
            color: color,
            alpha: min(visibility * (0.70 + localGlint * 0.18), 1)
        )
        let innerStart = CGPoint(
            x: from.x + (to.x - from.x) * 0.24,
            y: from.y + (to.y - from.y) * 0.24
        )
        drawTaperedStreak(
            context,
            from: innerStart,
            to: to,
            tailWidth: max(coreWidth * 0.025, 0.03),
            headWidth: max(coreWidth * 0.34, 0.16),
            color: brightened(color, amount: 0.58),
            alpha: min(visibility * (0.90 + localGlint * 0.35), 1)
        )
    }

    private static func drawComet(
        _ context: CGContext,
        from: CGPoint,
        to: CGPoint,
        headWidth: Double,
        color: CIColor,
        visibility: Double,
        localGlint: Double
    ) {
        drawTaperedStreak(
            context,
            from: from,
            to: to,
            tailWidth: headWidth * 0.10,
            headWidth: headWidth,
            color: color,
            alpha: min(visibility * (0.74 + localGlint * 0.18), 1)
        )
        let innerStart = CGPoint(
            x: from.x + (to.x - from.x) * 0.34,
            y: from.y + (to.y - from.y) * 0.34
        )
        drawTaperedStreak(
            context,
            from: innerStart,
            to: to,
            tailWidth: headWidth * 0.04,
            headWidth: headWidth * 0.34,
            color: brightened(color, amount: 0.72),
            alpha: min(visibility * (0.94 + localGlint * 0.34), 1)
        )
        fillEllipse(
            context,
            at: to,
            radius: headWidth * 0.27,
            color: brightened(color, amount: 0.78),
            alpha: min(visibility * (0.92 + localGlint * 0.40), 1)
        )
    }

    private static func drawTaperedStreak(
        _ context: CGContext,
        from: CGPoint,
        to: CGPoint,
        tailWidth: Double,
        headWidth: Double,
        color: CIColor,
        alpha: Double
    ) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.001 else { return }
        let normalX = -dy / length
        let normalY = dx / length
        let tailHalf = tailWidth * 0.5
        let headHalf = headWidth * 0.5
        let path = CGMutablePath()
        path.move(to: CGPoint(
            x: from.x + normalX * tailHalf,
            y: from.y + normalY * tailHalf
        ))
        path.addLine(to: CGPoint(
            x: to.x + normalX * headHalf,
            y: to.y + normalY * headHalf
        ))
        path.addLine(to: CGPoint(
            x: to.x - normalX * headHalf,
            y: to.y - normalY * headHalf
        ))
        path.addLine(to: CGPoint(
            x: from.x - normalX * tailHalf,
            y: from.y - normalY * tailHalf
        ))
        path.closeSubpath()
        context.setFillColor(cgColor(color, alpha: alpha))
        context.addPath(path)
        context.fillPath()
    }

    private static func fillEllipse(
        _ context: CGContext,
        at point: CGPoint,
        radius: Double,
        color: CIColor,
        alpha: Double
    ) {
        context.setFillColor(cgColor(color, alpha: alpha))
        context.fillEllipse(
            in: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
    }

    private static func brightened(
        _ color: CIColor,
        amount: Double
    ) -> CIColor {
        let mix = min(max(amount, 0), 1)
        return CIColor(
            red: color.red + (1 - color.red) * mix,
            green: color.green + (1 - color.green) * mix,
            blue: color.blue + (1 - color.blue) * mix
        )
    }

    private static func cgColor(_ color: CIColor, alpha: Double) -> CGColor {
        CGColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: min(max(alpha, 0), 1)
        )
    }

    private static func distanceToEdge(
        center: CGPoint,
        direction: CGPoint,
        width: Double,
        height: Double
    ) -> Double {
        let horizontal = direction.x >= 0
            ? (width - center.x) / max(abs(direction.x), 0.0001)
            : center.x / max(abs(direction.x), 0.0001)
        let vertical = direction.y >= 0
            ? (height - center.y) / max(abs(direction.y), 0.0001)
            : center.y / max(abs(direction.y), 0.0001)
        return min(horizontal, vertical)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let bounded = min(max(value, 0), 1)
        return bounded * bounded * (3 - 2 * bounded)
    }

}

@available(iOS 15.0, *)
final class SceneSurfaceStatefulStormRuntime {
    let recipe: SceneSurfaceStatefulStormRecipeV1

    private let sourceMasters: [CIImage]
    private let palette: [CIColor]
    private var field: SceneSurfaceStatefulStormField
    private var cachedTargetRect = CGRect.null
    private var cachedBroadMasters = [CIImage]()
    private var cachedCoreMasters = [CIImage]()

    init?(
        recipe: SceneSurfaceStatefulStormRecipeV1,
        palette: [CIColor]
    ) {
        var decoded = [CIImage]()
        for master in recipe.masterAssets {
            let lookupKey = FlutterDartProject.lookupKey(
                forAsset: master.asset,
                fromPackage: master.package
            )
            guard
                let path = Bundle.main.path(forResource: lookupKey, ofType: nil),
                let image = CIImage(contentsOf: URL(fileURLWithPath: path))
            else {
                return nil
            }
            decoded.append(image.oriented(.up))
        }
        guard decoded.count == SceneSurfaceStatefulStormFamily.allCases.count else {
            return nil
        }
        self.recipe = recipe
        self.palette = palette
        sourceMasters = decoded
        field = SceneSurfaceStatefulStormField(recipe: recipe)
    }

    var needsContinuousRendering: Bool { field.hasActiveEpisode }

    func updateAudioFrame(_ arguments: [String: Any]) {
        updateAudioFrame(arguments, hostTime: CACurrentMediaTime())
    }

    func updateAudioFrame(
        _ arguments: [String: Any],
        hostTime: CFTimeInterval
    ) {
        field.update(arguments: arguments, hostTime: hostTime)
    }

    func reset() {
        field.reset()
    }

    func image(
        targetRect: CGRect,
        hostTime: CFTimeInterval
    ) -> CIImage? {
        guard targetRect.width >= 2, targetRect.height >= 2 else { return nil }
        prepareCacheIfNeeded(targetRect: targetRect)
        let state = field.snapshot(at: hostTime)
        var composed = transparentImage(targetRect)
        let cloudOpacity = min(
            max(state.broadOpacity * 0.58 + state.flashOpacity * 0.16, 0),
            0.48
        )
        if cloudOpacity > 0.001 {
            let cloudColor = paletteColor(
                at: 1,
                fallback: CIColor(red: 0.67, green: 0.71, blue: 1.0)
            )
            composed = sourceOver(
                cloudIllumination(
                    targetRect: targetRect,
                    color: cloudColor,
                    opacity: cloudOpacity
                ),
                background: composed,
                targetRect: targetRect
            )
        }

        guard
            let family = state.family,
            family.rawValue < cachedCoreMasters.count,
            family.rawValue < cachedBroadMasters.count
        else {
            if state.flashOpacity > 0.001 {
                composed = sourceOver(
                    flashImage(
                        targetRect: targetRect,
                        opacity: state.flashOpacity
                    ),
                    background: composed,
                    targetRect: targetRect
                )
            }
            return composed.cropped(to: targetRect)
        }

        if state.broadOpacity > 0.001 {
            composed = sourceOver(
                applyOpacity(
                    cachedBroadMasters[family.rawValue],
                    opacity: state.broadOpacity
                ),
                background: composed,
                targetRect: targetRect
            )
            let haloOpacity = state.broadOpacity *
                recipe.boltHaloPassScale * state.boltLuminanceGain
            if haloOpacity > 0.001 {
                composed = sourceOver(
                    applyOpacity(
                        cachedBroadMasters[family.rawValue],
                        opacity: haloOpacity
                    ),
                    background: composed,
                    targetRect: targetRect
                )
            }
        }
        if state.coreOpacity > 0.001, state.revealProgress > 0.001 {
            let revealHeight = targetRect.height * CGFloat(
                min(max(state.revealProgress, 0), 1)
            )
            let revealRect = CGRect(
                x: targetRect.minX,
                y: targetRect.maxY - revealHeight,
                width: targetRect.width,
                height: revealHeight
            )
            let revealedCore = applyOpacity(
                cachedCoreMasters[family.rawValue].cropped(to: revealRect),
                opacity: state.coreOpacity
            )
            composed = sourceOver(
                revealedCore,
                background: composed,
                targetRect: targetRect
            )
            let glowCoreOpacity = state.coreOpacity *
                recipe.boltCorePassScale * state.boltLuminanceGain
            if glowCoreOpacity > 0.001 {
                composed = sourceOver(
                    applyOpacity(
                        cachedCoreMasters[family.rawValue]
                            .cropped(to: revealRect),
                        opacity: glowCoreOpacity
                    ),
                    background: composed,
                    targetRect: targetRect
                )
            }
        }
        if state.flashOpacity > 0.001 {
            composed = sourceOver(
                flashImage(
                    targetRect: targetRect,
                    opacity: state.flashOpacity
                ),
                background: composed,
                targetRect: targetRect
            )
        }
        return composed.cropped(to: targetRect)
    }

    private func cloudIllumination(
        targetRect: CGRect,
        color: CIColor,
        opacity: Double
    ) -> CIImage {
        guard let gradient = CIFilter(name: "CILinearGradient") else {
            return transparentImage(targetRect)
        }
        gradient.setValue(
            CIVector(x: targetRect.midX, y: targetRect.maxY),
            forKey: "inputPoint0"
        )
        gradient.setValue(
            CIVector(
                x: targetRect.midX,
                y: targetRect.minY + targetRect.height * 0.18
            ),
            forKey: "inputPoint1"
        )
        gradient.setValue(
            CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: CGFloat(opacity)
            ),
            forKey: "inputColor0"
        )
        gradient.setValue(
            CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0),
            forKey: "inputColor1"
        )
        return (gradient.outputImage ?? transparentImage(targetRect))
            .cropped(to: targetRect)
    }

    private func flashImage(
        targetRect: CGRect,
        opacity: Double
    ) -> CIImage {
        let color = paletteColor(
            at: 2,
            fallback: CIColor(red: 0.61, green: 0.66, blue: 1.0)
        )
        return CIImage(
            color: CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: CGFloat(opacity * 0.18)
            )
        ).cropped(to: targetRect)
    }

    private func prepareCacheIfNeeded(targetRect: CGRect) {
        guard cachedTargetRect != targetRect else { return }
        cachedTargetRect = targetRect
        cachedBroadMasters.removeAll(keepingCapacity: true)
        cachedCoreMasters.removeAll(keepingCapacity: true)

        let broadColor = paletteColor(
            at: 1,
            fallback: CIColor(red: 0.78, green: 0.81, blue: 1.0)
        )
        let coreColor = paletteColor(
            at: 0,
            fallback: CIColor(red: 0.97, green: 0.96, blue: 1.0)
        )
        for source in sourceMasters {
            let fitted = aspectFill(source, targetRect: targetRect)
            let mask = fitted.applyingFilter("CIMaskToAlpha")
            cachedBroadMasters.append(tint(mask, color: broadColor))
            cachedCoreMasters.append(tint(mask, color: coreColor))
        }
    }

    private func paletteColor(at index: Int, fallback: CIColor) -> CIColor {
        guard index >= 0, index < palette.count else { return fallback }
        return palette[index]
    }

    private func tint(_ image: CIImage, color: CIColor) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: color.red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: color.green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: color.blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]
        )
    }

    private func applyOpacity(_ image: CIImage, opacity: Double) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: CGFloat(min(max(opacity, 0), 1))
                ),
            ]
        )
    }

    private func sourceOver(
        _ foreground: CIImage,
        background: CIImage,
        targetRect: CGRect
    ) -> CIImage {
        foreground.applyingFilter(
            "CISourceOverCompositing",
            parameters: [kCIInputBackgroundImageKey: background]
        ).cropped(to: targetRect)
    }

    private func transparentImage(_ targetRect: CGRect) -> CIImage {
        CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: targetRect)
    }

    private func aspectFill(
        _ image: CIImage,
        targetRect: CGRect
    ) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image.cropped(to: targetRect)
        }
        let scale = max(
            targetRect.width / extent.width,
            targetRect.height / extent.height
        )
        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        return scaled.transformed(
            by: CGAffineTransform(
                translationX: targetRect.midX - scaled.extent.midX,
                y: targetRect.midY - scaled.extent.midY
            )
        ).cropped(to: targetRect)
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceOnePassLayerShape: Equatable {
    let role: String
    let sourceKind: String
    let proceduralPreset: String?
    let alphaMode: String
    let blendMode: String
    let opacity: CGFloat
    let transformIsIdentity: Bool
    let hasExternalEffect: Bool
    let hasExternalAudioBinding: Bool
    let explicitlyAudioReactive: Bool
}

@available(iOS 15.0, *)
enum SceneSurfaceDocumentConstructionMode {
    case runtime
    case preflight
}

@available(iOS 15.0, *)
struct SceneSurfaceVideoAssetInspection {
    let path: String
    let asset: AVURLAsset
    let formatDescriptions: [CMFormatDescription]
    let fileAttributes: NSDictionary
    let nominalFrameRate: Float
    let supportsOnePassGeometry: Bool
    let supportsOnePassPixelFormat: Bool
    var contentSHA256: String = ""

    var supportsOnePass: Bool {
        supportsOnePassGeometry && supportsOnePassPixelFormat
    }

    var isCurrent: Bool {
        guard let current = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return fileAttributes.isEqual(to: current)
    }
}

/// A cancelled inspection releases its worker immediately and also cancels the
/// underlying AVAsset load. Only the inspection worker may wait, never rendering.
final class SceneSurfaceInspectionContext {
    let deadline: CFTimeInterval
    private let lock = NSLock()
    private var cancelled = false
    private var loaders = [UUID: () -> Void]()

    init(timeout: TimeInterval) { deadline = CACurrentMediaTime() + max(0, timeout) }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled || CACurrentMediaTime() >= deadline
    }

    func cancel() {
        lock.lock()
        guard !cancelled else { lock.unlock(); return }
        cancelled = true
        let pending = Array(loaders.values)
        loaders.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }

    func waitForLoad(start: (@escaping () -> Void) -> Void, cancel: @escaping () -> Void) -> Bool {
        let ready = DispatchSemaphore(value: 0), identity = UUID()
        lock.lock()
        let remaining = deadline - CACurrentMediaTime()
        guard !cancelled, remaining > 0 else { lock.unlock(); return false }
        loaders[identity] = { cancel(); ready.signal() }
        // Register and start atomically with respect to cancellation: a cancelled
        // asset must not start loading again after cancelLoading returned.
        start { ready.signal() }
        lock.unlock()
        let completed = ready.wait(timeout: .now() + remaining) == .success
        if !completed { self.cancel() }
        lock.lock()
        loaders.removeValue(forKey: identity)
        let valid = completed && !cancelled && CACurrentMediaTime() < deadline
        lock.unlock()
        return valid
    }

    func load(_ source: AVAsynchronousKeyValueLoading, keys: [String], cancel: @escaping () -> Void) -> Bool {
        guard waitForLoad(start: { source.loadValuesAsynchronously(forKeys: keys, completionHandler: $0) },
                          cancel: cancel) else { return false }
        return keys.allSatisfy { source.statusOfValue(forKey: $0, error: nil) == .loaded }
    }
}

/// Completion and cancellation belong to the render queue; inspection never
/// blocks it. A late worker result cannot revive a cancelled/expired operation.
final class SceneSurfaceInspectionOperation<Value> {
    private let queue: DispatchQueue
    private var work: DispatchWorkItem?
    private var deadline: DispatchWorkItem?
    private var completion: ((Value?, String?) -> Void)?
    private var context: SceneSurfaceInspectionContext?

    init(queue: DispatchQueue, completion: @escaping (Value?, String?) -> Void) {
        self.queue = queue
        self.completion = completion
    }

    func start(on worker: DispatchQueue, timeout: TimeInterval, inspect: @escaping (SceneSurfaceInspectionContext) -> Value?) {
        let context = SceneSurfaceInspectionContext(timeout: timeout)
        self.context = context
        let work = DispatchWorkItem { [weak self] in
            guard !context.isCancelled else { return }
            let value = inspect(context)
            self?.queue.async { [weak self] in
                self?.finish(value, error: value == nil ? "scene_document_invalid" : nil)
            }
        }
        self.work = work
        let deadline = DispatchWorkItem { [weak self] in
            self?.finish(nil, error: "scene_inspection_timeout")
        }
        self.deadline = deadline
        queue.asyncAfter(deadline: .now() + max(0, timeout), execute: deadline)
        worker.async(execute: work)
    }

    func cancel() { finish(nil, error: "scene_inspection_cancelled") }

    private func finish(_ value: Value?, error: String?) {
        guard let completion else { return }
        self.completion = nil
        if error != nil { context?.cancel() }
        context = nil
        deadline?.cancel()
        deadline = nil
        work?.cancel()
        work = nil
        completion(value, error)
    }
}

@available(iOS 15.0, *)
enum SceneSurfaceOnePassGraphCapability {
    static func supports(
        layers: [SceneSurfaceOnePassLayerShape],
        hasFilter: Bool
    ) -> Bool {
        guard !hasFilter, layers.count == 2 else { return false }
        let inferno = layers[0]
        let packedVideo = layers[1]
        return (inferno.role == "background" || inferno.role == "overlay") &&
            inferno.sourceKind == "procedural" &&
            inferno.proceduralPreset == SceneSurfaceInfernoEmbersRecipeV1.preset &&
            inferno.alphaMode == "normal" &&
            inferno.blendMode == "sourceOver" &&
            abs(inferno.opacity - 1) < 0.000_001 &&
            inferno.transformIsIdentity &&
            !inferno.hasExternalEffect &&
            !inferno.hasExternalAudioBinding &&
            inferno.explicitlyAudioReactive &&
            packedVideo.role == "overlay" &&
            packedVideo.sourceKind == "video" &&
            packedVideo.proceduralPreset == nil &&
            packedVideo.alphaMode == "packedSideBySide" &&
            packedVideo.blendMode == "sourceOver" &&
            abs(packedVideo.opacity - 1) < 0.000_001 &&
            packedVideo.transformIsIdentity &&
            !packedVideo.hasExternalEffect &&
            !packedVideo.hasExternalAudioBinding &&
            !packedVideo.explicitlyAudioReactive
    }
}

@available(iOS 15.0, *)
private final class PictureInPictureSceneLayerRuntime {
    struct Transform {
        let width: CGFloat
        let height: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        let scale: CGFloat
        let rotation: CGFloat
        let flipped: Bool
    }

    struct AudioBinding {
        let pulseBass: Double
        let pulseImpact: Double
        let brightnessLevel: Double
        let contrastImpact: Double
        let saturationBody: Double
        let bloomSpark: Double
        let flashStrength: Double

        static let none = AudioBinding(
            pulseBass: 0,
            pulseImpact: 0,
            brightnessLevel: 0,
            contrastImpact: 0,
            saturationBody: 0,
            bloomSpark: 0,
            flashStrength: 0
        )

        var isReactive: Bool {
            pulseBass != 0 ||
                pulseImpact != 0 ||
                brightnessLevel != 0 ||
                contrastImpact != 0 ||
                saturationBody != 0 ||
                bloomSpark != 0 ||
                flashStrength != 0
        }
    }

    let id: String
    let role: String
    let sourceKind: String
    private(set) var opacity: CGFloat
    let blendMode: String
    private(set) var transform: Transform
    let audioBinding: AudioBinding
    let proceduralPreset: String?
    let palette: [CIColor]
    let rendererSessionId: String?
    let alphaMode: String
    let rgbGainEffect: SceneSurfaceRGBGainEffectRuntime?
    let naturalReactiveLightEffect: SceneSurfaceNaturalReactiveLightEffectRuntime?
    private(set) var explicitlyAudioReactive: Bool
    let playbackRate: Float

    private let renderEngine: MusicVibeRenderEngine
    private var image: CIImage? {
        willSet {
            // Reusable bitmap/Metal sources must release their old graphs
            // before the producer mutates its backing storage.
            alphaPreparationCache.reset()
            compositionPreparationCache.reset()
            stableRasterCache?.reset()
        }
    }
    private let alphaPreparationCache = SceneSurfaceImageGraphCache<String>()
    private let compositionPreparationCache =
        SceneSurfaceImageGraphCache<SceneSurfaceLayerPreparationKey>()
    private var stableRasterCache: SceneSurfaceStableRasterCache?
    private var dynamicSourceCacheKey: SceneSurfaceDynamicSourceCacheKey?
    private var preparedImageCacheState = SceneSurfacePreparedImageCacheState()
    private var animatedImageSource: CGImageSource?
    private var animatedFrameEndTimes = [Double]()
    private var animatedFrameIndex = -1
    private var animationDuration: Double = 0
    private var animatedImageClock = SceneSurfaceAnimatedImageClock()
    private(set) var videoPlayer: AVPlayer?
    private var videoReservation: SceneSurfaceVideoReservations.Lease?
    private(set) var videoInspection: SceneSurfaceVideoAssetInspection?
    private var videoRestorePending = false
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoPixelBuffer: CVPixelBuffer?
    private var videoEndObserver: NSObjectProtocol?
    private let videoStateLock = NSRecursiveLock()
    private var videoPlaybackGeneration = UUID()
    private var videoPlaybackRequested = false
    private var hasDecodedVideoFrame = false
    var videoDiagnostics: [String: Any]? {
        guard sourceKind == "video" else { return nil }
        return ["id": id, "sourceIdentity": videoPlayer.map { String(describing: ObjectIdentifier($0)) } ?? "retired",
                "hasFrame": hasDecodedVideoFrame,
                "playerStatus": videoPlayer?.status.rawValue ?? -1,
                "itemStatus": videoPlayer?.currentItem?.status.rawValue ?? -1,
                "timeControlStatus": videoPlayer?.timeControlStatus.rawValue ?? -1,
                "playbackRequested": videoPlaybackRequested,
                "position": videoPlayer?.currentTime().seconds ?? 0,
                "contentSHA256": videoInspection?.contentSHA256 ?? "",
                "sourceFPS": videoInspection?.nominalFrameRate ?? 0]
    }
    private var videoGeometrySupportsOnePass = false
    private(set) var videoAssetSupportsOnePass = false
    private var rendererRetained = false
    private var dynamicFramesPerSecond = 30
    private var sourceCadenceClock = SceneSurfaceLayerCadenceClock()
    private var effectCadenceClock = SceneSurfaceLayerCadenceClock()
    private var scheduledDynamicSourceRefresh = false
    private var firefliesRuntime: SceneSurfaceFirefliesRuntime?
    private var infernoEmbersRuntime: SceneSurfaceInfernoEmbersRuntime?
    private var wildflowerPollenRuntime: SceneSurfaceWildflowerPollenRuntime?
    private var radialWarpRuntime: SceneSurfaceRadialWarpRuntime?
    private var statefulStormRuntime: SceneSurfaceStatefulStormRuntime?
    private var nativeProgram: SceneSurfaceNativeProgram?

    var onePassShape: SceneSurfaceOnePassLayerShape {
        SceneSurfaceOnePassLayerShape(
            role: role,
            sourceKind: sourceKind,
            proceduralPreset: proceduralPreset,
            alphaMode: alphaMode,
            blendMode: blendMode,
            opacity: opacity,
            transformIsIdentity:
                abs(transform.width - 1) < 0.000_001 &&
                abs(transform.height - 1) < 0.000_001 &&
                abs(transform.offsetX) < 0.000_001 &&
                abs(transform.offsetY) < 0.000_001 &&
                abs(transform.scale - 1) < 0.000_001 &&
                abs(transform.rotation) < 0.000_001 &&
                !transform.flipped,
            hasExternalEffect:
                rgbGainEffect != nil || naturalReactiveLightEffect != nil,
            hasExternalAudioBinding: audioBinding.isReactive,
            explicitlyAudioReactive: explicitlyAudioReactive
        )
    }

    init?(
        definition: [String: Any],
        renderEngine: MusicVibeRenderEngine,
        metalContext: SceneSurfaceMetalContext?,
        metricsScope: String? = nil,
        constructionMode: SceneSurfaceDocumentConstructionMode = .runtime,
        stableRasterBudget: SceneSurfaceStableRasterBudget? = nil,
        inspectedVideos: [String: SceneSurfaceVideoAssetInspection]? = nil,
        inspectionContext: SceneSurfaceInspectionContext? = nil
    ) {
        guard
            let id = definition["id"] as? String,
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let role = definition["role"] as? String,
            role == "background" || role == "overlay",
            let sourceKind = definition["sourceKind"] as? String,
            let transformDefinition = definition["transform"] as? [String: Any]
        else {
            return nil
        }

        self.id = id
        self.role = role
        self.sourceKind = sourceKind
        self.opacity = CGFloat(
            Self.bounded(definition["opacity"], fallback: 1, minimum: 0, maximum: 1)
        )
        self.blendMode = definition["blendMode"] as? String ?? "sourceOver"
        self.transform = Transform(
            width: CGFloat(
                Self.bounded(
                    transformDefinition["width"],
                    fallback: 1,
                    minimum: 0.01,
                    maximum: 4
                )
            ),
            height: CGFloat(
                Self.bounded(
                    transformDefinition["height"],
                    fallback: 1,
                    minimum: 0.01,
                    maximum: 4
                )
            ),
            offsetX: CGFloat(
                Self.bounded(
                    transformDefinition["offsetX"],
                    fallback: 0,
                    minimum: -4,
                    maximum: 4
                )
            ),
            offsetY: CGFloat(
                Self.bounded(
                    transformDefinition["offsetY"],
                    fallback: 0,
                    minimum: -4,
                    maximum: 4
                )
            ),
            scale: CGFloat(
                Self.bounded(
                    transformDefinition["scale"],
                    fallback: 1,
                    minimum: 0.05,
                    maximum: 10
                )
            ),
            rotation: CGFloat(
                Self.bounded(
                    transformDefinition["rotation"],
                    fallback: 0,
                    minimum: -Double.pi * 8,
                    maximum: Double.pi * 8
                )
            ),
            flipped: transformDefinition["flipped"] as? Bool ?? false
        )
        self.audioBinding = Self.decodeAudioBinding(
            definition["audioBinding"] as? [String: Any]
        )
        self.proceduralPreset = definition["proceduralPreset"] as? String
        self.palette = Self.decodePalette(definition["palette"])
        self.renderEngine = renderEngine
        self.explicitlyAudioReactive =
            definition["audioReactive"] as? Bool ?? false
        self.playbackRate = sceneSurfacePlaybackRate(
            definition["playbackRate"]
        )

        let requestedAlphaMode = definition["alphaMode"] as? String ?? "normal"
        guard
            ["normal", "straightAlpha", "packedSideBySide"].contains(
                requestedAlphaMode
            ),
            requestedAlphaMode == "normal" || sourceKind == "video"
        else {
            return nil
        }
        alphaMode = requestedAlphaMode
        if let effectDefinition = definition["effect"] as? [String: Any] {
            if SceneSurfaceRGBGainEffectRuntime.isNone(effectDefinition) {
                rgbGainEffect = nil
                naturalReactiveLightEffect = nil
            } else if let effect = SceneSurfaceRGBGainEffectRuntime.decode(
                effectDefinition
            ) {
                rgbGainEffect = effect
                naturalReactiveLightEffect = nil
            } else if let effect = SceneSurfaceNaturalReactiveLightEffectRuntime.decode(
                effectDefinition
            ) {
                rgbGainEffect = nil
                naturalReactiveLightEffect = effect
            } else {
                return nil
            }
        } else {
            rgbGainEffect = nil
            naturalReactiveLightEffect = nil
        }

        let requestedRendererSessionId =
            definition["rendererSessionId"] as? String
        let ownsRendererControls =
            (definition["proceduralParameters"] as? [String: Any])?["visualControls"] != nil
        // Data-only native sources belong to this layer, never the outgoing
        // document. Preparing a replacement must not alter its options or clock.
        self.rendererSessionId = ownsRendererControls
            ? requestedRendererSessionId.map { "\($0):\(UUID().uuidString)" }
            : requestedRendererSessionId

        switch sourceKind {
        case "image":
            guard let path = Self.resolvePath(definition) else { return nil }
            if constructionMode == .runtime {
                guard let loaded = CIImage(
                    contentsOf: URL(fileURLWithPath: path)
                ) else {
                    return nil
                }
                image = loaded.oriented(.up)
            }
        case "animatedImage":
            guard let path = Self.resolvePath(definition) else { return nil }
            if constructionMode == .runtime,
               !loadAnimatedImage(path: path) {
                return nil
            }
        case "video":
            guard let path = Self.resolvePath(definition) else { return nil }
            let inspection: SceneSurfaceVideoAssetInspection?
            if let inspectedVideos {
                // Supplied metadata is authoritative. Never fall back to slow
                // AVAsset inspection on the render queue if a file changed.
                inspection = inspectedVideos[path]
            } else {
                inspection = Self.inspectVideoAsset(path: path, context: inspectionContext)
            }
            guard let inspection, inspection.isCurrent else { return nil }
            videoAssetSupportsOnePass = inspection.supportsOnePass
            videoInspection = inspection
            if constructionMode == .runtime,
               !configureVideo(inspection: inspection) {
                return nil
            }
        case "procedural":
            guard let proceduralPreset else { return nil }
            switch proceduralPreset {
            case "native_program_v1":
                guard let parameters = definition["proceduralParameters"] as? [String: Any],
                      SceneSurfaceNativeProgram.validate(parameters: parameters)
                else { return nil }
                if constructionMode == .runtime {
                    guard let program = SceneSurfaceNativeProgram(
                        parameters: parameters,
                        renderEngine: renderEngine,
                        metalContext: metalContext
                    ) else { return nil }
                    nativeProgram = program
                    if program.supportsStableSourceRasterReuse,
                       let metalContext, let stableRasterBudget {
                        stableRasterCache = SceneSurfaceStableRasterCache(
                            device: metalContext.device, context: metalContext.ciContext,
                            commandQueue: metalContext.commandQueue, budget: stableRasterBudget
                        )
                    }
                    dynamicFramesPerSecond = program.preferredFramesPerSecond
                }
            case "liquid_lava", "aurora", "deep_void_v1":
                guard definition["proceduralParameters"] == nil else {
                    return nil
                }
            case SceneSurfaceFirefliesRecipeV1.preset:
                guard
                    let parameters =
                        definition["proceduralParameters"] as? [String: Any],
                    let recipe = SceneSurfaceFirefliesRecipeV1(parameters)
                else {
                    return nil
                }
                if constructionMode == .runtime {
                    firefliesRuntime = SceneSurfaceFirefliesRuntime(
                        recipe: recipe
                    )
                }
                dynamicFramesPerSecond = recipe.framesPerSecond
            case SceneSurfaceInfernoEmbersRecipeV1.preset:
                guard
                    let parameters =
                        definition["proceduralParameters"] as? [String: Any],
                    let recipe = SceneSurfaceInfernoEmbersRecipeV1(parameters)
                else {
                    return nil
                }
                if constructionMode == .runtime {
                    guard let runtime = SceneSurfaceInfernoEmbersRuntime(
                        recipe: recipe,
                        metalContext: metalContext,
                        metricsScope: metricsScope
                    ) else {
                        return nil
                    }
                    infernoEmbersRuntime = runtime
                }
                dynamicFramesPerSecond = recipe.framesPerSecond
            case SceneSurfaceWildflowerPollenRecipeV1.preset:
                guard
                    let parameters =
                        definition["proceduralParameters"] as? [String: Any],
                    let recipe = SceneSurfaceWildflowerPollenRecipeV1(parameters)
                else {
                    return nil
                }
                if constructionMode == .runtime {
                    guard let runtime = SceneSurfaceWildflowerPollenRuntime(
                        recipe: recipe,
                        metalContext: metalContext,
                        metricsScope: metricsScope
                    ) else {
                        return nil
                    }
                    wildflowerPollenRuntime = runtime
                }
                dynamicFramesPerSecond = recipe.framesPerSecond
            case SceneSurfaceRadialWarpRecipeV1.preset:
                guard
                    let parameters =
                        definition["proceduralParameters"] as? [String: Any],
                    let recipe = SceneSurfaceRadialWarpRecipeV1(parameters)
                else {
                    return nil
                }
                if constructionMode == .runtime {
                    radialWarpRuntime = SceneSurfaceRadialWarpRuntime(
                        recipe: recipe
                    )
                }
                dynamicFramesPerSecond = recipe.framesPerSecond
            case SceneSurfaceStatefulStormRecipeV1.preset:
                guard
                    let parameters =
                        definition["proceduralParameters"] as? [String: Any],
                    let recipe = SceneSurfaceStatefulStormRecipeV1(parameters)
                else {
                    return nil
                }
                if constructionMode == .runtime {
                    guard let runtime = SceneSurfaceStatefulStormRuntime(
                        recipe: recipe,
                        palette: palette
                    ) else {
                        return nil
                    }
                    statefulStormRuntime = runtime
                }
                dynamicFramesPerSecond = recipe.framesPerSecond
            default:
                return nil
            }
        case "realtimeRenderer":
            let controlParameters = definition["proceduralParameters"] as? [String: Any] ?? [:]
            guard Set(controlParameters.keys).isSubset(of: ["visualControls"]),
                let controls = controlParameters["visualControls"] as? [String: Any] ??
                    (controlParameters["visualControls"] == nil ? [:] : nil),
                let rendererOptions = MusicVibeRenderEngine.sceneVisualOptions(controls)
            else { return nil }
            guard
                let requestedRendererSessionId,
                !requestedRendererSessionId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                let rendererSessionId = self.rendererSessionId,
                !rendererSessionId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                let rendererProgramId =
                    definition["rendererProgramId"] as? String,
                !rendererProgramId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            else {
                return nil
            }
            if constructionMode == .runtime {
                guard renderEngine.retainForPictureInPicture(
                    sessionId: rendererSessionId,
                    programId: rendererProgramId,
                    seed: (definition["rendererSeed"] as? NSNumber)?.uint64Value ?? 1
                ) else {
                    return nil
                }
                rendererRetained = true
                renderEngine.setRetainedProgramOptions(sessionId: rendererSessionId, options: rendererOptions)
            }
        default:
            return nil
        }
    }

    func normalizedImage(_ source: CIImage) -> CIImage? {
        alphaPreparationCache.image(for: source, key: alphaMode) {
            normalizedSceneLayerAlpha(source, mode: alphaMode)
        }
    }

    func preparedCompositionImage(
        _ source: CIImage,
        targetRect: CGRect,
        build: () -> CIImage
    ) -> CIImage? {
        // NativeProgram publishes immutable source images. Their dependent
        // graphs are released by image.willSet before the next source render.
        // External render engines can still expose mutable backing storage.
        guard
            sourceKind == "image" || sourceKind == "video" ||
                sourceKind == "animatedImage" || nativeProgram != nil,
            !audioBinding.isReactive,
            naturalReactiveLightEffect == nil
        else {
            return build()
        }
        let key = SceneSurfaceLayerPreparationKey(
            targetRect: targetRect,
            rgbGain: rgbGainEffect?.gain ?? 1
        )
        guard let prepared = compositionPreparationCache.image(
            for: source,
            key: key,
            build: build
        ) else { return nil }
        // Rasterizing a transformed procedural graph can change CI's sampling.
        // Keep every such edit on the original graph, with no quality change.
        let rasterEligible = alphaMode == "normal" && blendMode == "sourceOver" &&
            opacity == 1 && rgbGainEffect == nil &&
            !explicitlyAudioReactive && !audioBinding.isReactive &&
            naturalReactiveLightEffect == nil &&
            transform.width == 1 && transform.height == 1 &&
            transform.offsetX == 0 && transform.offsetY == 0 &&
            transform.scale == 1 && transform.rotation == 0 && !transform.flipped
        return stableRasterCache?.image(
            for: prepared, bounds: targetRect, eligible: rasterEligible
        ) ?? prepared
    }

    func currentImage(
        forcePoster: Bool,
        hostTime: CFTimeInterval,
        width: Int,
        height: Int,
        refreshSource: Bool = true
    ) -> CIImage? {
        switch sourceKind {
        case "image":
            return image
        case "animatedImage":
            if refreshSource {
                _ = prepareAnimatedFrame(hostTime: hostTime)
            }
            return image
        case "video":
            guard !forcePoster, let output = videoOutput else { return image }
            if refreshSource {
                _ = prepareVideoFrame(output: output, hostTime: hostTime)
            }
            return image
        case "realtimeRenderer":
            guard !forcePoster, let rendererSessionId else { return nil }
            let targetCacheKey = SceneSurfaceDynamicSourceCacheKey(
                width: width,
                height: height
            )
            if refreshSource || scheduledDynamicSourceRefresh || image == nil ||
                dynamicSourceCacheKey != targetCacheKey {
                // Release a prior raw snapshot before asking the renderer for
                // its replacement. This also prevents reusable bitmap-backed
                // programs from retaining a stale copy-on-write generation.
                image = nil
                dynamicSourceCacheKey = nil
                guard let buffer = renderEngine.renderPictureInPictureFrame(
                    sessionId: rendererSessionId,
                    width: width,
                    height: height
                ) else {
                    return nil
                }
                image = CIImage(cvPixelBuffer: buffer)
                dynamicSourceCacheKey = targetCacheKey
            }
            scheduledDynamicSourceRefresh = false
            return image
        default:
            return nil
        }
    }

    func currentProceduralImage(
        forceRefresh: Bool,
        width: Int,
        height: Int,
        render: () -> CIImage?
    ) -> CIImage? {
        let targetCacheKey = SceneSurfaceDynamicSourceCacheKey(
            width: width,
            height: height
        )
        let preparedInfernoNeedsMaterialization =
            preparedImageCacheState.needsMaterialization
        if forceRefresh || scheduledDynamicSourceRefresh ||
            preparedInfernoNeedsMaterialization || image == nil ||
            dynamicSourceCacheKey != targetCacheKey {
            // Drop the previous immutable snapshot before the reusable bitmap
            // context is mutated, allowing Core Graphics to keep its backing
            // allocation instead of preserving an old copy-on-write surface.
            image = nil
            dynamicSourceCacheKey = nil
            guard let rendered = render() else { return nil }
            image = rendered
            dynamicSourceCacheKey = targetCacheKey
            preparedImageCacheState.didMaterialize()
        }
        scheduledDynamicSourceRefresh = false
        return image
    }

    /// Refreshes only source state needed by a scheduled compositor tick and
    /// reports whether this layer can change the resulting scene frame.
    func prepareScheduledFrame(
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame,
        audioAdvanced: Bool
    ) -> SceneSurfaceLayerFrameWork {
        let sourceAdvanced: Bool
        switch sourceKind {
        case "animatedImage":
            sourceAdvanced = prepareAnimatedFrame(hostTime: hostTime)
        case "video":
            if let output = videoOutput {
                sourceAdvanced = prepareVideoFrame(
                    output: output,
                    hostTime: hostTime
                ).advanced
            } else {
                sourceAdvanced = false
            }
        default:
            sourceAdvanced = false
        }
        let authoredDynamicSourceAnimating =
            intrinsicSourceNeedsContinuousRendering &&
            (sourceKind == "procedural" || sourceKind == "realtimeRenderer")
        let rgbGainAnimating = rgbGainEffect?.needsFrames(for: frame) ?? false
        let naturalLightAnimating =
            naturalReactiveLightEffect?.needsFrames(for: frame) ?? false
        let sourceDue = authoredDynamicSourceAnimating &&
            sourceCadenceClock.consumeIfDue(
                at: hostTime,
                framesPerSecond: intrinsicSourceFramesPerSecond
            )
        var activeEffectFramesPerSecond = 0
        if rgbGainAnimating {
            activeEffectFramesPerSecond = max(
                activeEffectFramesPerSecond,
                rgbGainEffect?.framesPerSecond ?? 0
            )
        }
        if naturalLightAnimating {
            activeEffectFramesPerSecond = max(
                activeEffectFramesPerSecond,
                naturalReactiveLightEffect?.framesPerSecond ?? 0
            )
        }
        let rgbEffect = rgbGainEffect
        let naturalLightEffect = naturalReactiveLightEffect
        let effectAnimating = activeEffectFramesPerSecond > 0 &&
            sceneSurfaceSampleAndHoldEffectIfDue(
                cadenceClock: &effectCadenceClock,
                at: hostTime,
                framesPerSecond: activeEffectFramesPerSecond,
                latestInput: frame
            ) { sampledFrame, sampledAt in
                rgbEffect?.sample(frame: sampledFrame, hostTime: sampledAt)
                naturalLightEffect?.sample(
                    frame: sampledFrame,
                    hostTime: sampledAt
                )
            }
        let timeDriven = sourceDue
        // A signal can dirty an event-driven native source before this tick.
        // Keep that work pending until currentProceduralImage materializes it.
        scheduledDynamicSourceRefresh =
            scheduledDynamicSourceRefresh ||
            sceneSurfaceScheduledDynamicSourceRefresh(
                sourceKind: sourceKind,
                sourceDue: timeDriven,
                intrinsicSourceAnimating: authoredDynamicSourceAnimating,
                audioAdvanced: audioAdvanced,
                isAudioReactive: isAudioReactive
            )
        return SceneSurfaceLayerFrameWork(
            sourceAdvanced: sourceAdvanced || scheduledDynamicSourceRefresh,
            timeDriven: timeDriven,
            effectAnimating: effectAnimating,
            audioAdvanced: audioAdvanced && isAudioReactive
        )
    }

    func prepareForcedFrame(
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame
    ) {
        rgbGainEffect?.sample(frame: frame, hostTime: hostTime)
        naturalReactiveLightEffect?.sample(frame: frame, hostTime: hostTime)
    }

    func markForcedFrameRendered(hostTime: CFTimeInterval) {
        sourceCadenceClock.markEvaluated(
            at: hostTime,
            framesPerSecond: intrinsicSourceFramesPerSecond
        )
        if configuredEffectFramesPerSecond > 0 {
            effectCadenceClock.markEvaluated(
                at: hostTime,
                framesPerSecond: configuredEffectFramesPerSecond
            )
        }
        scheduledDynamicSourceRefresh = false
    }

    func updateAudioFrame(arguments: [String: Any]) {
        statefulStormRuntime?.updateAudioFrame(arguments)
        guard sourceKind == "realtimeRenderer", let rendererSessionId else {
            return
        }
        renderEngine.updateAudioFrame(
            sessionId: rendererSessionId,
            arguments: arguments
        )
    }

    @discardableResult
    func updateSignalFrame(_ frame: SceneRenderSignalFrameV2) -> Bool {
        guard let nativeProgram else { return false }
        let changed = nativeProgram.consume(frame)
        if changed { scheduledDynamicSourceRefresh = true }
        return changed
    }

    func nativeProgramImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval
    ) -> CIImage? {
        nativeProgram?.render(target: targetRect, hostTime: hostTime)
    }

    func didPublishNativeProgram(hostTime: CFTimeInterval) {
        nativeProgram?.didPublish(hostTime: hostTime)
    }

    var creatorMetrics: [String: Any]? { nativeProgram?.creatorMetrics }

    var usesAuthoredSourceOver: Bool { nativeProgram?.usesAuthoredSourceOver == true }

    func prepareCatalogControlUpdate(parameters: [String: Any]) -> SceneCatalogControlUpdate? {
        let prepared: SceneCatalogControlUpdate?
        if sourceKind == "realtimeRenderer", let rendererSessionId,
            Set(parameters.keys) == ["visualControls"],
            let controls = parameters["visualControls"] as? [String: Any],
            let options = MusicVibeRenderEngine.sceneVisualOptions(controls) {
            prepared = renderEngine.prepareRetainedProgramOptions(sessionId: rendererSessionId, options: options)
        } else {
            prepared = nativeProgram?.prepareCatalogControlUpdate(parameters: parameters)
        }
        guard let update = prepared else { return nil }
        let previousReaction = explicitlyAudioReactive
        let nextReaction = SceneCatalogControlUpdatePlan.isStatefulCreator(parameters)
          ? SceneCatalogNativeDescriptor.parse(parameters)?.audioReactive : nil
        return SceneCatalogControlUpdate(
            apply: { [weak self] in
                update.apply()
                if let nextReaction { self?.explicitlyAudioReactive = nextReaction }
                self?.image = nil
                self?.scheduledDynamicSourceRefresh = true
            },
            rollback: { [weak self] in
                update.rollback()
                self?.explicitlyAudioReactive = previousReaction
                self?.image = nil
                self?.scheduledDynamicSourceRefresh = true
            }
        )
    }

    func firefliesImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        sparkDrive: Double
    ) -> CIImage? {
        firefliesRuntime?.image(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            sparkDrive: sparkDrive,
            palette: palette
        )
    }

    func infernoEmbersImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bodyDrive: Double,
        sparkDrive: Double
    ) -> CIImage? {
        infernoEmbersRuntime?.image(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            bodyDrive: bodyDrive,
            sparkDrive: sparkDrive,
            palette: palette
        )
    }

    func prepareInfernoOnePassFrame(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bodyDrive: Double,
        sparkDrive: Double,
        sourcesPrepared: Bool
    ) -> SceneSurfacePreparedInfernoFrame? {
        guard let infernoEmbersRuntime else { return nil }
        let prepared = infernoEmbersRuntime.prepareOnePassFrame(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            bodyDrive: bodyDrive,
            sparkDrive: sparkDrive,
            palette: palette,
            forceRefresh: !sourcesPrepared || scheduledDynamicSourceRefresh,
            reserveForFallback: true
        )
        if let prepared {
            preparedImageCacheState.select(
                preparedHostTime: prepared.hostTime
            )
            scheduledDynamicSourceRefresh = false
        }
        return prepared
    }

    func packedVideoPixelBuffer(
        hostTime: CFTimeInterval,
        refreshSource: Bool
    ) -> CVPixelBuffer? {
        guard
            sourceKind == "video",
            videoGeometrySupportsOnePass,
            let output = videoOutput
        else {
            return nil
        }
        if refreshSource {
            _ = prepareVideoFrame(output: output, hostTime: hostTime)
        }
        return videoPixelBuffer
    }

    func wildflowerPollenImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        sparkDrive: Double
    ) -> CIImage? {
        wildflowerPollenRuntime?.image(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            sparkDrive: sparkDrive,
            palette: palette
        )
    }

    func radialWarpImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        musicActive: Bool,
        flowDrive: Double,
        bassDrive: Double,
        sparkDrive: Double
    ) -> CIImage? {
        radialWarpRuntime?.image(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            bassDrive: bassDrive,
            sparkDrive: sparkDrive,
            palette: palette
        )
    }

    func statefulStormImage(
        targetRect: CGRect,
        hostTime: CFTimeInterval
    ) -> CIImage? {
        statefulStormRuntime?.image(
            targetRect: targetRect,
            hostTime: hostTime
        )
    }

    var intrinsicSourceNeedsContinuousRendering: Bool {
        switch sourceKind {
        case "animatedImage", "video":
            return true
        case "procedural":
            if let nativeProgram { return nativeProgram.needsContinuousRendering }
            return sceneSurfaceProceduralSourceNeedsContinuousFrames(
                preset: proceduralPreset,
                statefulStormActive:
                    statefulStormRuntime?.needsContinuousRendering == true
            )
        case "realtimeRenderer":
            guard let rendererSessionId else { return false }
            return renderEngine.pictureInPictureNeedsContinuousFrames(
                sessionId: rendererSessionId
            )
        default:
            return false
        }
    }

    var intrinsicSourceFramesPerSecond: Int {
        if sourceKind == "realtimeRenderer", let rendererSessionId {
            return renderEngine.pictureInPictureFramesPerSecond(
                sessionId: rendererSessionId
            )
        }
        return min(max(nativeProgram?.preferredFramesPerSecond ?? dynamicFramesPerSecond, 1), 60)
    }

    var nativeProgramEventFramesPerSecond: Int {
        nativeProgram != nil && isAudioReactive ? intrinsicSourceFramesPerSecond : 0
    }

    var configuredEffectFramesPerSecond: Int {
        max(
            rgbGainEffect?.framesPerSecond ?? 0,
            naturalReactiveLightEffect?.framesPerSecond ?? 0
        )
    }

    var isAudioReactive: Bool {
        explicitlyAudioReactive || audioBinding.isReactive ||
            rgbGainEffect != nil ||
            naturalReactiveLightEffect != nil ||
            sourceKind == "realtimeRenderer"
    }

    func play() {
        nativeProgram?.setPlaying(true, hostTime: CACurrentMediaTime())
        if sourceKind == "animatedImage" {
            animatedImageClock.play()
        }
        videoStateLock.lock()
        videoPlaybackRequested = true
        if !videoRestorePending { videoPlayer?.playImmediately(atRate: playbackRate) }
        videoStateLock.unlock()
    }

    /// Advances a video layer to a decoded frame without exposing its poster
    /// as a completed native scene frame. The poster remains a bounded fallback
    /// for unavailable decoders, while foreground handoff can wait briefly for
    /// the real frame produced by AVPlayerItemVideoOutput.
    func prepareInitialVideoFrame(hostTime: CFTimeInterval) -> Bool {
        guard sourceKind == "video" else { return true }
        videoStateLock.lock()
        let restoring = videoRestorePending
        videoStateLock.unlock()
        guard !restoring else { return false }
        guard let output = videoOutput else { return false }
        return prepareVideoFrame(output: output, hostTime: hostTime).ready
    }

    func pause() {
        nativeProgram?.setPlaying(false, hostTime: CACurrentMediaTime())
        if sourceKind == "animatedImage" {
            animatedImageClock.pause(at: CACurrentMediaTime())
        }
        videoStateLock.lock()
        videoPlaybackRequested = false
        videoPlayer?.pause()
        videoStateLock.unlock()
        statefulStormRuntime?.reset()
    }

    func resetEffects() {
        rgbGainEffect?.reset()
        naturalReactiveLightEffect?.reset()
        statefulStormRuntime?.reset()
    }

    var gpuSubpassesSettledSuccessfully: Bool {
        (infernoEmbersRuntime?.gpuSubpassSettledSuccessfully ?? true) &&
            (wildflowerPollenRuntime?.gpuSubpassSettledSuccessfully ?? true)
    }

    func recoverFromGPUCommandFailure() -> Bool {
        let infernoRecovered =
            infernoEmbersRuntime?.recoverFromGPUCommandFailure() ?? false
        let pollenRecovered =
            wildflowerPollenRuntime?.recoverFromGPUCommandFailure() ?? false
        guard infernoRecovered || pollenRecovered else { return false }
        image = nil
        dynamicSourceCacheKey = nil
        scheduledDynamicSourceRefresh = true
        return true
    }

    func invalidateStableSourceRaster() {
        stableRasterCache?.reset()
    }

    func preparePresentationUpdate(definition: [String: Any]) -> SceneCatalogControlUpdate? {
        guard SceneCatalogControlUpdatePlan.validPresentation(definition),
              let opacity = definition["opacity"] as? NSNumber,
              let value = definition["transform"] as? [String: Any],
              let width = value["width"] as? NSNumber, let height = value["height"] as? NSNumber,
              let x = value["offsetX"] as? NSNumber, let y = value["offsetY"] as? NSNumber,
              let scale = value["scale"] as? NSNumber, let rotation = value["rotation"] as? NSNumber,
              let flipped = value["flipped"] as? Bool else { return nil }
        let nextTransform = Transform(width: CGFloat(width.doubleValue), height: CGFloat(height.doubleValue),
            offsetX: CGFloat(x.doubleValue), offsetY: CGFloat(y.doubleValue), scale: CGFloat(scale.doubleValue),
            rotation: CGFloat(rotation.doubleValue), flipped: flipped)
        let oldOpacity = self.opacity, oldTransform = transform
        let install: (CGFloat, Transform) -> Void = { [weak self] opacity, transform in
            self?.opacity = opacity
            self?.transform = transform
            self?.compositionPreparationCache.reset()
        }
        return SceneCatalogControlUpdate(
            apply: { install(CGFloat(opacity.doubleValue), nextTransform) },
            rollback: { install(oldOpacity, oldTransform) })
    }

    var stableSourceRasterCountForTesting: Int {
        stableRasterCache?.materializationCount ?? 0
    }

    func tearDown() {
        pause()
        retireVideo()
        animatedImageSource = nil
        animatedFrameEndTimes.removeAll(keepingCapacity: false)
        animatedFrameIndex = -1
        animatedImageClock.reset()
        sourceCadenceClock.reset()
        effectCadenceClock.reset()
        scheduledDynamicSourceRefresh = false
        dynamicSourceCacheKey = nil
        preparedImageCacheState.reset()
        image = nil
        nativeProgram = nil
        infernoEmbersRuntime?.tearDown()
        wildflowerPollenRuntime?.tearDown()
        statefulStormRuntime?.reset()
        if rendererRetained, let rendererSessionId {
            rendererRetained = false
            renderEngine.releasePictureInPicture(sessionId: rendererSessionId)
        }
    }

    /// Retire the decoder before releasing its reservation. The layer and its
    /// logical state can survive a bounded replacement/rollback.
    private func retireVideo() {
        videoStateLock.lock()
        videoPlaybackGeneration = UUID()
        videoRestorePending = false
        let retiringPlayer = videoPlayer
        videoPlayer = nil
        videoStateLock.unlock()
        retiringPlayer?.pause()
        retiringPlayer?.cancelPendingPrerolls()
        retiringPlayer?.currentItem?.cancelPendingSeeks()
        if let output = videoOutput { retiringPlayer?.currentItem?.remove(output) }
        retiringPlayer?.replaceCurrentItem(with: nil)
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
        }
        videoEndObserver = nil
        videoOutput = nil
        videoPixelBuffer = nil
        hasDecodedVideoFrame = false
        videoGeometrySupportsOnePass = false
        videoReservation = nil
    }

    func suspendVideoForReplacement() -> CMTime? {
        guard let player = videoPlayer else { return nil }
        let time = player.currentTime()
        retireVideo()
        return time.isValid && time.isNumeric ? time : .zero
    }

    func restoreVideo(at time: CMTime) -> Bool {
        guard videoPlayer == nil, let inspection = videoInspection,
              configureVideo(inspection: inspection) else { return false }
        videoStateLock.lock()
        let generation = videoPlaybackGeneration
        videoRestorePending = true
        let player = videoPlayer
        videoStateLock.unlock()
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] completed in
            guard let self, let player else { return }
            self.videoStateLock.lock()
            defer { self.videoStateLock.unlock() }
            guard generation == self.videoPlaybackGeneration, self.videoPlayer === player else { return }
            // Failed seeks remain unready and expire under the shared deadline.
            guard completed else { return }
            self.videoRestorePending = false
            if self.videoPlaybackRequested { player.playImmediately(atRate: self.playbackRate) }
        }
        return true
    }

    private static func inspectVideoAsset(
        path: String, context suppliedContext: SceneSurfaceInspectionContext? = nil
    ) -> SceneSurfaceVideoAssetInspection? {
        let context = suppliedContext ?? SceneSurfaceInspectionContext(timeout: 2)
        guard !context.isCancelled else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let asset = AVURLAsset(url: url)
        guard context.load(asset, keys: ["tracks"], cancel: { asset.cancelLoading() }) else { return nil }
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            return nil
        }
        guard context.load(videoTrack, keys: ["preferredTransform", "formatDescriptions", "nominalFrameRate"],
                           cancel: { asset.cancelLoading() }) else { return nil }
        let preferredTransform = videoTrack.preferredTransform
        let geometrySupported =
            abs(preferredTransform.a - 1) < 0.000_001 &&
            abs(preferredTransform.b) < 0.000_001 &&
            abs(preferredTransform.c) < 0.000_001 &&
            abs(preferredTransform.d - 1) < 0.000_001 &&
            abs(preferredTransform.tx) < 0.000_001 &&
            abs(preferredTransform.ty) < 0.000_001
        let formatDescriptions = videoTrack.formatDescriptions
            .compactMap { value -> CMFormatDescription? in
                guard
                    CFGetTypeID(value as CFTypeRef) ==
                        CMFormatDescriptionGetTypeID()
                else {
                    return nil
                }
                return (value as! CMFormatDescription)
            }
        let codecTypes = formatDescriptions.map(
            CMFormatDescriptionGetMediaSubType
        )
        let encodedWidths = formatDescriptions.map {
            CMVideoFormatDescriptionGetDimensions($0).width
        }
        let pixelFormatSupported = !codecTypes.isEmpty &&
            codecTypes.allSatisfy { $0 == kCMVideoCodecType_H264 } &&
            encodedWidths.count == codecTypes.count &&
            encodedWidths.allSatisfy { $0 > 0 && $0.isMultiple(of: 4) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                guard !context.isCancelled else { return nil }
                hasher.update(data: chunk)
            }
        } catch { return nil }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        let inspection = SceneSurfaceVideoAssetInspection(
            path: path,
            asset: asset,
            formatDescriptions: formatDescriptions,
            fileAttributes: attributes as NSDictionary,
            nominalFrameRate: videoTrack.nominalFrameRate,
            supportsOnePassGeometry: geometrySupported,
            supportsOnePassPixelFormat: pixelFormatSupported,
            contentSHA256: digest
        )
        return !context.isCancelled && inspection.isCurrent ? inspection : nil
    }

    private func configureVideo(
        inspection: SceneSurfaceVideoAssetInspection
    ) -> Bool {
        guard inspection.isCurrent else { return false }
        guard let reservation = SceneSurfaceVideoReservations.shared.reserve() else { return false }
        videoGeometrySupportsOnePass = inspection.supportsOnePassGeometry
        let formatDescriptions = inspection.formatDescriptions
        let outputPixelFormat = sceneSurfaceVideoOutputPixelFormat(
            alphaMode: alphaMode,
            codecTypes: formatDescriptions.map(
                CMFormatDescriptionGetMediaSubType
            ),
            encodedWidths: formatDescriptions.map {
                CMVideoFormatDescriptionGetDimensions($0).width
            },
            fullRangeVideoExtensions: formatDescriptions.map { description in
                let extensions = CMFormatDescriptionGetExtensions(description)
                    as NSDictionary?
                return extensions?[
                    kCMFormatDescriptionExtension_FullRangeVideo
                ]
            }
        )
        let item = AVPlayerItem(asset: inspection.asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String:
                outputPixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        videoReservation = reservation
        player.actionAtItemEnd = .none
        player.isMuted = true
        let generation = UUID()
        videoStateLock.lock()
        videoPlaybackGeneration = generation
        videoPlayer = player
        videoStateLock.unlock()
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            guard let self, let player else { return }
            self.videoStateLock.lock()
            defer { self.videoStateLock.unlock() }
            guard self.videoPlaybackGeneration == generation, self.videoPlayer === player else { return }
            player.seek(to: .zero) { [weak self, weak player] completed in
                guard completed, let self, let player else { return }
                self.videoStateLock.lock()
                defer { self.videoStateLock.unlock() }
                guard self.videoPlaybackGeneration == generation, self.videoPlayer === player,
                    self.videoPlaybackRequested else { return }
                player.playImmediately(atRate: self.playbackRate)
            }
        }
        videoOutput = output
        let nominalFrameRate = inspection.nominalFrameRate
        if nominalFrameRate.isFinite,
           nominalFrameRate > 0 {
            dynamicFramesPerSecond = sceneSurfaceVideoFramesPerSecond(
                nominalFrameRate * playbackRate
            )
        }
        // The owning transaction waits for the decoded frame. Generating a
        // thumbnail here used another decoder and blocked pause/cancellation.
        return true
    }

    private func prepareAnimatedFrame(hostTime: CFTimeInterval) -> Bool {
        guard !animatedFrameEndTimes.isEmpty, animationDuration > 0 else {
            return false
        }
        let elapsed = animatedImageClock.elapsed(at: hostTime)
        let position = (elapsed * Double(playbackRate))
            .truncatingRemainder(dividingBy: animationDuration)
        let index = animatedFrameEndTimes.firstIndex(where: {
            position < $0
        }) ?? (animatedFrameEndTimes.count - 1)
        guard index != animatedFrameIndex,
              let decoded = decodeAnimatedFrame(at: index) else {
            return false
        }
        image = decoded
        animatedFrameIndex = index
        return true
    }

    private func prepareVideoFrame(
        output: AVPlayerItemVideoOutput,
        hostTime: CFTimeInterval
    ) -> (ready: Bool, advanced: Bool) {
        let itemTime = output.itemTime(forHostTime: hostTime)
        var advanced = false
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = output.copyPixelBuffer(
                forItemTime: itemTime,
                itemTimeForDisplay: nil
           ) {
            prepareSceneVideoPixelBufferForAlphaMode(
                buffer,
                alphaMode: alphaMode
            )
            image = CIImage(cvPixelBuffer: buffer)
            videoPixelBuffer = buffer
            hasDecodedVideoFrame = true
            advanced = true
        }
        return (hasDecodedVideoFrame, advanced)
    }

    private func loadAnimatedImage(path: String) -> Bool {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard
            let source = CGImageSourceCreateWithURL(
                url,
                sourceOptions as CFDictionary
            ),
            CGImageSourceGetCount(source) > 0
        else {
            return false
        }

        animatedFrameEndTimes.removeAll(keepingCapacity: true)
        animatedFrameIndex = -1
        animatedImageClock.reset()
        var elapsed = 0.0
        let frameCount = min(CGImageSourceGetCount(source), 600)
        for index in 0..<frameCount {
            let properties =
                CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                    as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
            let unclamped =
                (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?
                    .doubleValue
            let clamped =
                (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
            let duration = max(unclamped ?? clamped ?? 0.1, 0.02)
            elapsed += duration
            animatedFrameEndTimes.append(elapsed)
        }
        animationDuration = elapsed
        animatedImageSource = source
        if let first = decodeAnimatedFrame(at: 0) {
            image = first
            animatedFrameIndex = 0
        }
        if let minimumDuration = animatedFrameEndTimes.enumerated().map({ index, endTime in
            endTime - (index == 0 ? 0 : animatedFrameEndTimes[index - 1])
        }).min(), minimumDuration > 0 {
            dynamicFramesPerSecond = min(
                max(Int((Double(playbackRate) / minimumDuration).rounded()), 12),
                60
            )
        }
        return image != nil && !animatedFrameEndTimes.isEmpty
    }

    /// Keeps one decoded frame resident. The compressed ImageIO source stays
    /// available, but leaving an animation never retains every RGBA frame.
    private func decodeAnimatedFrame(at index: Int) -> CIImage? {
        guard
            let source = animatedImageSource,
            index >= 0,
            index < animatedFrameEndTimes.count
        else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1440,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let frame = CGImageSourceCreateThumbnailAtIndex(
            source,
            index,
            options as CFDictionary
        ) else {
            return nil
        }
        return CIImage(cgImage: frame).oriented(.up)
    }

    private static func resolvePath(
        _ definition: [String: Any]
    ) -> String? {
        if let path = definition["path"] as? String, !path.isEmpty {
            guard FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            return path
        }
        guard
            let asset = definition["asset"] as? String,
            !asset.isEmpty
        else {
            return nil
        }
        let package = definition["assetPackage"] as? String
        let lookupKey: String
        if let package, !package.isEmpty {
            lookupKey = FlutterDartProject.lookupKey(
                forAsset: asset,
                fromPackage: package
            )
        } else {
            lookupKey = FlutterDartProject.lookupKey(forAsset: asset)
        }
        return Bundle.main.path(forResource: lookupKey, ofType: nil)
    }

    private static func decodeAudioBinding(
        _ value: [String: Any]?
    ) -> AudioBinding {
        guard let value else { return .none }
        return AudioBinding(
            pulseBass: bounded(
                value["pulseBass"],
                fallback: 0,
                minimum: 0,
                maximum: 2
            ),
            pulseImpact: bounded(
                value["pulseImpact"],
                fallback: 0,
                minimum: 0,
                maximum: 2
            ),
            brightnessLevel: bounded(
                value["brightnessLevel"],
                fallback: 0,
                minimum: 0,
                maximum: 1
            ),
            contrastImpact: bounded(
                value["contrastImpact"],
                fallback: 0,
                minimum: 0,
                maximum: 1
            ),
            saturationBody: bounded(
                value["saturationBody"],
                fallback: 0,
                minimum: 0,
                maximum: 2
            ),
            bloomSpark: bounded(
                value["bloomSpark"],
                fallback: 0,
                minimum: 0,
                maximum: 2
            ),
            flashStrength: bounded(
                value["flashStrength"],
                fallback: 0,
                minimum: 0,
                maximum: 1
            )
        )
    }

    private static func decodePalette(_ value: Any?) -> [CIColor] {
        guard let values = value as? [NSNumber] else { return [] }
        return values.prefix(4).map { number in
            let argb = UInt32(truncating: number)
            return sceneSurfaceColor(fromARGB: argb)
        }
    }

    private static func bounded(
        _ value: Any?,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard let parsed = (value as? NSNumber)?.doubleValue,
              parsed.isFinite else {
            return fallback
        }
        return min(max(parsed, minimum), maximum)
    }
}

@available(iOS 15.0, *)
private typealias SceneSurfaceOnePassLayers = (
    inferno: PictureInPictureSceneLayerRuntime,
    packedVideo: PictureInPictureSceneLayerRuntime
)

/// Resolve only when immutable layer definitions are installed or replaced.
/// Decoder state and per-frame color/format checks remain in the render path.
@available(iOS 15.0, *)
private func sceneSurfaceOnePassLayers(
    _ layers: [PictureInPictureSceneLayerRuntime],
    hasFilter: Bool
) -> SceneSurfaceOnePassLayers? {
    guard
        SceneSurfaceOnePassGraphCapability.supports(
            layers: layers.map(\.onePassShape),
            hasFilter: hasFilter
        )
    else {
        return nil
    }
    return (layers[0], layers[1])
}

@available(iOS 15.0, *)
private func renderSceneSurfaceOnePass(
    graph: SceneSurfaceOnePassLayers?,
    targetRect: CGRect,
    targetBuffer: CVPixelBuffer,
    hostTime: CFTimeInterval,
    musicActive: Bool,
    flowDrive: Double,
    bodyDrive: Double,
    sparkDrive: Double,
    sourcesPrepared: Bool,
    compositor: SceneSurfaceOnePassCompositor?,
    metricsScope: String? = nil
) -> SceneSurfaceOnePassRenderResult {
    guard
        let compositor,
        let graph,
        let infernoFrame = graph.inferno.prepareInfernoOnePassFrame(
            targetRect: targetRect,
            hostTime: hostTime,
            musicActive: musicActive,
            flowDrive: flowDrive,
            bodyDrive: bodyDrive,
            sparkDrive: sparkDrive,
            sourcesPrepared: sourcesPrepared
        ),
        let packedVideoBuffer = graph.packedVideo.packedVideoPixelBuffer(
            hostTime: hostTime,
            refreshSource: !sourcesPrepared
        )
    else {
        return .unsupported
    }
    return compositor.render(
        infernoFrame: infernoFrame,
        packedVideoBuffer: packedVideoBuffer,
        targetBuffer: targetBuffer,
        metricsScope: metricsScope
    )
}

@available(iOS 15.0, *)
private struct PictureInPictureSceneFilterRuntime {
    let intensity: Double
    let exposure: Double
    let contrast: Double
    let saturation: Double
    let vibrance: Double
    let temperature: Double
    let tint: Double
    let blackLift: Double
    let vignette: Double
    let vignetteSoftness: Double

    init?(definition: [String: Any]) {
        guard
            let parameters = definition["parameters"] as? [String: Any]
        else {
            return nil
        }
        intensity = Self.bounded(
            definition["intensity"],
            fallback: 1,
            minimum: 0,
            maximum: 1
        )
        exposure = Self.bounded(
            parameters["exposure"],
            fallback: 0,
            minimum: -1,
            maximum: 1
        )
        contrast = Self.bounded(
            parameters["contrast"],
            fallback: 1,
            minimum: 0.5,
            maximum: 1.5
        )
        saturation = Self.bounded(
            parameters["saturation"],
            fallback: 1,
            minimum: 0,
            maximum: 1.8
        )
        vibrance = Self.bounded(
            parameters["vibrance"],
            fallback: 0,
            minimum: -1,
            maximum: 1
        )
        temperature = Self.bounded(
            parameters["temperature"],
            fallback: 0,
            minimum: -1,
            maximum: 1
        )
        tint = Self.bounded(
            parameters["tint"],
            fallback: 0,
            minimum: -1,
            maximum: 1
        )
        blackLift = Self.bounded(
            parameters["blackLift"],
            fallback: 0,
            minimum: -0.2,
            maximum: 0.2
        )
        vignette = Self.bounded(
            parameters["vignette"],
            fallback: 0,
            minimum: 0,
            maximum: 1
        )
        vignetteSoftness = Self.bounded(
            parameters["vignetteSoftness"],
            fallback: 0.7,
            minimum: 0.2,
            maximum: 1
        )
    }

    private static func bounded(
        _ value: Any?,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard let parsed = (value as? NSNumber)?.doubleValue,
              parsed.isFinite else {
            return fallback
        }
        return min(max(parsed, minimum), maximum)
    }
}

struct PictureInPicturePlaybackIntentGate {
    static func shouldForward(
        lifecycleActive: Bool,
        foregroundStopRequested: Bool,
        stopRequestedDuringStart: Bool
    ) -> Bool {
        lifecycleActive &&
            !foregroundStopRequested &&
            !stopRequestedDuringStart
    }
}

/// Source selection never constructs another V2 session. An unavailable or
/// ambiguous foreground authority can only use the declared V1 companion.
enum PictureInPicturePreparationIdentity {
    static func isCurrent(
        generation: Int,
        currentGeneration: Int,
        sessionID: String,
        currentSessionID: String?
    ) -> Bool {
        generation == currentGeneration && sessionID == currentSessionID
    }
}

enum PictureInPictureCompositionSource: Equatable {
    case sharedV2(sessionID: String)
    case documentV1
    case unavailable

    static func canRetainWithoutSignalContinuation(
        scenePlan: [String: Any]
    ) -> Bool {
        guard
            let document = scenePlan["sceneDocumentV2"] as? [String: Any],
            let layers = document["layers"] as? [[String: Any]],
            !layers.isEmpty
        else { return false }
        var nodes: [[String: Any]] = []
        for layer in layers {
            guard let node = layer["node"] as? [String: Any] else { return false }
            nodes.append(node)
        }
        if let filter = document["filterNode"] {
            guard let node = filter as? [String: Any] else { return false }
            nodes.append(node)
        }
        return nodes.allSatisfy { node in
            guard
                let bindings = node["signalBindings"] as? [[String: Any]],
                let parameters = node["parameters"] as? [String: Any]
            else { return false }
            return bindings.isEmpty && parameters["audioReactive"] as? Bool != true
        }
    }

    static func resolve(
        retainSharedV2: () -> String?,
        configureDocumentV1: () -> Bool
    ) -> Self {
        if let sessionID = retainSharedV2() {
            return .sharedV2(sessionID: sessionID)
        }
        return configureDocumentV1() ? .documentV1 : .unavailable
    }
}

@available(iOS 15.0, *)
final class PictureInPictureHandler: NSObject {
    private enum LifecycleState: String {
        case idle
        case starting
        case active
        case stopping
    }

    private struct ReactiveFrame {
        var timestampMicros: Int64 = 0
        var level: Double = 0
        var impact: Double = 0
        var hitStrength: Double = 0
        var bassDrive: Double = 0
        var bodyDrive: Double = 0
        var sparkDrive: Double = 0
        var flowDrive: Double = 0
        var reactivity: Double = 0
    }

    private let methodChannelName = "com.chic.dev/picture_in_picture"
    private let eventChannelName = "com.chic.dev/picture_in_picture/events"
    private let renderQueue = DispatchQueue(
        label: "com.chic.dev.picture-in-picture.render",
        qos: .userInteractive
    )
    private let stateLock = NSLock()
    private let sampleLayer = AVSampleBufferDisplayLayer()
    private let windowProvider: () -> UIWindow?
    private let renderEngine: MusicVibeRenderEngine
    private let v2ImageRuntime: SceneRenderV2ImageSurfaceRuntime
    private let sceneSurfaceEngine: SceneSurfaceRenderEngine
    private var v1SharedSource: SceneSurfacePictureInPictureSource?
    private var v1ConvertedRevision: UInt64?
    private var v1ConvertedBuffer: CVPixelBuffer?
    private let metalContext: SceneSurfaceMetalContext?
    private let ciContext: CIContext
    private let outputColorSpace = CGColorSpaceCreateDeviceRGB()
    private var sourceHostView: UIView?

    private var eventSink: FlutterEventSink?
    private var pictureInPictureController: AVPictureInPictureController?
    private var renderTimer: DispatchSourceTimer?
    private var currentRenderFramesPerSecond = 0
    private var renderTimerUsesPosterOnly = false
    private var pixelBufferPool: CVPixelBufferPool?
    private let publishedBufferBudget = SceneSurfacePublishedBufferBudget()
    private var formatDescription: CMVideoFormatDescription?
    private var timebase: CMTimebase?
    private var posterImage: CIImage?
    private var videoPlayer: AVPlayer?
    private var videoReservation: SceneSurfaceVideoReservations.Lease?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoEndObserver: NSObjectProtocol?
    private var sourceKind = "poster"
    private var rendererSessionId: String?
    private var v2SharedSessionId: String?
    private var continuationIdentity: [String: String]?
    private var lastReleasedContinuationIdentity: [String: String]?
    private var continuationReleasePending = false
    private var proceduralPreset: String?
    private var palette = [CIColor]()
    private var sceneLayers = [PictureInPictureSceneLayerRuntime]()
    private var sceneFilter: PictureInPictureSceneFilterRuntime?
    private var sceneOnePassLayers: SceneSurfaceOnePassLayers?
    private var sceneMetricsScope: String?
    private var sessionId: String?
    private var width = 360
    private var height = 640
    private var preferredFramesPerSecond = 20
    private var degradedFramesPerSecond = 12
    private var playbackActive = true
    private var dynamicSourcesPlaybackRequested = false
    private var prepared = false
    private var automaticStartEnabled = false
    private var latestFrame = ReactiveFrame()
    private var latestHitMicros: Int64 = 0
    private var latestHitStrength: Double = 0
    private var droppedFrames = 0
    private var renderedFrames = 0
    private var lastStatsEmittedAt: CFTimeInterval = 0
    private var stoppingReason = "requested"
    private var possibilityObservation: NSKeyValueObservation?
    private var startTimeoutWorkItem: DispatchWorkItem?
    private var pendingStartResult: FlutterResult?
    private var startRequestGeneration = 0
    private var prepareGeneration = 0
    private var lifecycleState = LifecycleState.idle
    private var stopRequestedDuringStart = false
    private var observedBackgroundSinceStart = false
    private var stopWatchdog: DispatchWorkItem?
    private var stopWatchdogAttempts = 0
    private var stopCompletionPending = false
    private var foregroundStopRequested = false
    private var v2FairDeadlineWorkItem: DispatchWorkItem?
    private var v2CriticalDeadlineWorkItem: DispatchWorkItem?
    private var v2RecoveryWorkItem: DispatchWorkItem?
    private var v2EmergencyRecoveryActive = false
    private var v2QualityTransitionInFlight = false

    init(
        windowProvider: @escaping () -> UIWindow?,
        renderEngine: MusicVibeRenderEngine,
        v2ImageRuntime: SceneRenderV2ImageSurfaceRuntime,
        sceneSurfaceEngine: SceneSurfaceRenderEngine
    ) {
        self.windowProvider = windowProvider
        self.renderEngine = renderEngine
        self.v2ImageRuntime = v2ImageRuntime
        self.sceneSurfaceEngine = sceneSurfaceEngine
        let metalContext = SceneSurfaceMetalContext.shared
        self.metalContext = metalContext
        if let metalContext {
            ciContext = metalContext.ciContext
        } else {
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        super.init()

        sampleLayer.videoGravity = .resizeAspectFill
        sampleLayer.backgroundColor = UIColor.black.cgColor

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerOrThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePowerOrThermalStateChange),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePrimarySceneWillEnterForeground(_:)),
            name: UIScene.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleApplicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        tearDown()
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(false)
                return
            }
            switch call.method {
            case "isSupported":
                result(AVPictureInPictureController.isPictureInPictureSupported())
            case "prepare":
                self.prepare(arguments: call.arguments, result: result)
            case "prepareWithSceneContinuation":
                self.prepareWithSceneContinuation(arguments: call.arguments, result: result)
            case "releaseSceneContinuation":
                self.releaseSceneContinuation(arguments: call.arguments, result: result)
            case "start":
                self.start(result: result)
            case "stop":
                let arguments = call.arguments as? [String: Any]
                result(
                    self.stop(
                        reason: arguments?["reason"] as? String ?? "requested"
                    )
                )
            case "release":
                self.releasePreparedContent()
                result(nil)
            case "setAutomaticStartEnabled":
                let arguments = call.arguments as? [String: Any]
                self.setAutomaticStartEnabled(arguments?["enabled"] as? Bool ?? false)
                result(nil)
            case "setPlaybackActive":
                let arguments = call.arguments as? [String: Any]
                self.setPlaybackActive(arguments?["active"] as? Bool ?? true)
                result(nil)
            case "updateReactiveFrame":
                self.updateReactiveFrame(arguments: call.arguments)
                result(nil)
            case "dispose":
                self.tearDown()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(self)
    }

    private func prepareWithSceneContinuation(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let pipID = arguments["sessionId"] as? String,
            let sceneID = arguments["sceneSessionId"] as? String,
            !sceneID.isEmpty,
            let plan = (arguments["sceneSurfaceIdentity"] ?? arguments["scenePlanV2"]) as? [String: Any],
            let hash = plan["semanticPlanHash"] as? String,
            arguments["sourceKind"] as? String == "sceneComposition"
        else { result(nil); return }
        guard continuationIdentity == nil, !continuationReleasePending else {
            result(FlutterError(code: "continuation_owned", message: "Previous scene ownership is unresolved.", details: nil))
            return
        }
        guard lifecycleState == .idle,
              pictureInPictureController?.isPictureInPictureActive != true else {
            result(nil)
            return
        }
        let identity = ["pipSessionId": pipID, "sceneSessionId": sceneID, "semanticPlanHash": hash]
        // The prior source may have been automatically armed. A new native
        // reservation must not start before Dart commits its exact authority.
        setAutomaticStartEnabled(false)
        continuationIdentity = identity
        prepare(arguments: arguments, continuationSessionID: sceneID) { [weak self] value in
            guard let self else {
                result(FlutterError(code: "continuation_owner_lost", message: "PiP owner was lost.", details: nil))
                return
            }
            if value as? Bool == true,
               self.continuationIdentity == identity,
               !self.continuationReleasePending,
               (self.v2SharedSessionId == sceneID || self.v1SharedSource?.sessionID == sceneID) {
                result(identity)
                return
            }
            // False is only a clean rejection after all earlier releases ACK.
            if self.continuationIdentity == identity && !self.continuationReleasePending {
                self.clearPreparedContent()
            }
            self.acknowledgeContinuationCleanup {
                if self.continuationIdentity == identity && !self.continuationReleasePending {
                    self.continuationIdentity = nil
                    self.lastReleasedContinuationIdentity = identity
                }
                result(nil)
            }
        }
    }

    private func releaseSceneContinuation(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let pipID = arguments["pipSessionId"] as? String,
            let sceneID = arguments["sceneSessionId"] as? String
        else {
            result(FlutterError(code: "continuation_identity_invalid", message: "Exact scene ownership is required.", details: nil))
            return
        }
        let matches: ([String: String]?) -> Bool = {
            $0?["pipSessionId"] == pipID && $0?["sceneSessionId"] == sceneID
        }
        if matches(lastReleasedContinuationIdentity) && !matches(continuationIdentity) {
            result(lastReleasedContinuationIdentity)
            return
        }
        guard matches(continuationIdentity), let identity = continuationIdentity else {
            result(FlutterError(code: "continuation_identity_mismatch", message: "Cannot release another scene.", details: nil))
            return
        }
        guard lifecycleState == .idle,
              pictureInPictureController?.isPictureInPictureActive != true else {
            result(FlutterError(code: "continuation_still_active", message: "Stop PiP before releasing its scene.", details: nil))
            return
        }
        if !continuationReleasePending {
            continuationReleasePending = true
            clearPreparedContent()
        }
        acknowledgeContinuationCleanup { [weak self] in
            guard let self else {
                result(FlutterError(code: "continuation_owner_lost", message: "PiP owner was lost.", details: nil))
                return
            }
            if self.continuationIdentity == identity {
                self.continuationIdentity = nil
                self.continuationReleasePending = false
                self.lastReleasedContinuationIdentity = identity
            }
            result(identity)
        }
    }

    private func prepare(arguments: Any?, continuationSessionID: String? = nil, result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    result(false)
                    return
                }
                self.prepare(arguments: arguments, continuationSessionID: continuationSessionID, result: result)
            }
            return
        }
        guard
            AVPictureInPictureController.isPictureInPictureSupported(),
            let arguments = arguments as? [String: Any],
            let rawSessionId = arguments["sessionId"] as? String,
            !rawSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let typedData = arguments["posterBytes"] as? FlutterStandardTypedData,
            let image = UIImage(data: typedData.data),
            let ciImage = CIImage(image: image)
        else {
            result(false)
            return
        }

        let requestedWidth = (arguments["width"] as? NSNumber)?.intValue ?? 360
        let requestedHeight = (arguments["height"] as? NSNumber)?.intValue ?? 640
        let requestedFPS = (arguments["framesPerSecond"] as? NSNumber)?.intValue ?? 20
        let requestedDegradedFPS =
            (arguments["degradedFramesPerSecond"] as? NSNumber)?.intValue ?? 12

        guard
            !continuationReleasePending,
            continuationIdentity == nil || continuationSessionID != nil,
            lifecycleState == .idle,
            pictureInPictureController?.isPictureInPictureActive != true
        else {
            NSLog(
                "[MusicVibePiP] prepare rejected state=%@ active=%@",
                lifecycleState.rawValue,
                pictureInPictureController?.isPictureInPictureActive == true
                    ? "true"
                    : "false"
            )
            result(false)
            return
        }

        prepareGeneration += 1
        let generation = prepareGeneration
        cancelPendingStart()
        stopRenderTimer()
        // A cancelled timer can still have one render in flight. Drain it before
        // replacing the frame resources consumed by the render queue.
        renderQueue.sync {}
        tearDownVideo()
        releaseRendererSessionIfNeeded()
        releaseV2SharedSourceIfNeeded()
        tearDownSceneDocument()
        sampleLayer.flushAndRemoveImage()
        sessionId = rawSessionId
        sceneMetricsScope = "pip:\(rawSessionId)"
        width = min(max(requestedWidth, 180), 720)
        height = min(max(requestedHeight, 320), 1280)
        preferredFramesPerSecond = min(max(requestedFPS, 12), 30)
        degradedFramesPerSecond = min(
            max(requestedDegradedFPS, 8),
            preferredFramesPerSecond
        )
        sourceKind = arguments["sourceKind"] as? String ?? "poster"
        if sourceKind == "sceneComposition", let identity = arguments["sceneSurfaceIdentity"] as? [String: Any] {
            guard let exactSession = continuationSessionID,
                  let retained = sceneSurfaceEngine.retainPictureInPictureSource(
                    sessionID: exactSession, consumerID: rawSessionId, identity: identity
                  ) else { result(false); return }
            v1SharedSource = retained
            sourceKind = "sceneV1Shared"
        } else if sourceKind == "sceneComposition" {
            let compositionSource = PictureInPictureCompositionSource.resolve(
                retainSharedV2: {
                    guard let scenePlanV2 = arguments["scenePlanV2"] as? [String: Any]
                    else { return nil }
                    guard continuationSessionID != nil || PictureInPictureCompositionSource
                        .canRetainWithoutSignalContinuation(scenePlan: scenePlanV2)
                    else { return nil }
                    return v2ImageRuntime.retainPictureInPictureSource(
                        scenePlan: scenePlanV2,
                        expectedSessionID: continuationSessionID
                    )
                },
                configureDocumentV1: {
                    guard continuationSessionID == nil else { return false }
                    return configureSceneDocument(arguments["sceneDocument"])
                }
            )
            switch compositionSource {
            case .sharedV2(let retainedSessionId):
                sourceKind = "sceneV2Shared"
                v2SharedSessionId = retainedSessionId
            case .documentV1:
                break
            case .unavailable:
                sourceKind = "poster"
                emit(type: "error", message: "scene_source_unavailable")
                result(false)
                return
            }
        } else if sourceKind == "realtimeRenderer" {
            guard
                let requestedRendererSessionId = arguments["rendererSessionId"] as? String,
                !requestedRendererSessionId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                let rendererProgramId = arguments["rendererProgramId"] as? String,
                !rendererProgramId.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty,
                renderEngine.retainForPictureInPicture(
                    sessionId: requestedRendererSessionId,
                    programId: rendererProgramId,
                    seed: (arguments["rendererSeed"] as? NSNumber)?.uint64Value ?? 1
                )
            else {
                sourceKind = "poster"
                result(false)
                return
            }
            rendererSessionId = requestedRendererSessionId
        }
        proceduralPreset = arguments["proceduralPreset"] as? String
        palette = Self.decodePalette(arguments["palette"])
        posterImage = ciImage.oriented(.up)
        droppedFrames = 0
        renderedFrames = 0
        playbackActive = true
        prepared = false
        latestFrame = ReactiveFrame()
        latestHitMicros = 0
        latestHitStrength = 0
        lastStatsEmittedAt = 0

        guard configurePixelBufferPool() else {
            releaseRendererSessionIfNeeded()
            releaseV2SharedSourceIfNeeded()
            tearDownSceneDocument()
            emit(type: "error", message: "pixel_buffer_pool_failed")
            result(false)
            return
        }
        configureTimebase()
        guard attachSampleLayer() else {
            releaseRendererSessionIfNeeded()
            releaseV2SharedSourceIfNeeded()
            tearDownSceneDocument()
            NSLog("[MusicVibePiP] prepare failed: no active host window")
            emit(type: "error", message: "sample_layer_window_unavailable")
            result(false)
            return
        }
        NSLog(
            "[MusicVibePiP] source poster=%dx%d target=%dx%d layer=%@",
            Int(ciImage.extent.width),
            Int(ciImage.extent.height),
            width,
            height,
            NSCoder.string(for: sampleLayer.frame)
        )
        if sourceKind == "video" {
            configureVideoIfAvailable(
                path: arguments["videoPath"] as? String,
                asset: arguments["videoAsset"] as? String,
                package: arguments["videoAssetPackage"] as? String
            )
        }

        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result(false) }
                return
            }
            let rendered = autoreleasepool {
                self.renderFrame(forcePoster: self.sourceKind != "sceneV2Shared" && self.sourceKind != "sceneV1Shared")
            }
            DispatchQueue.main.async {
                guard
                    PictureInPicturePreparationIdentity.isCurrent(
                        generation: generation,
                        currentGeneration: self.prepareGeneration,
                        sessionID: rawSessionId,
                        currentSessionID: self.sessionId
                    )
                else {
                    result(false)
                    return
                }
                guard rendered else {
                    self.releaseRendererSessionIfNeeded()
                    self.releaseV2SharedSourceIfNeeded()
                    self.tearDownSceneDocument()
                    self.detachSampleLayer()
                    self.emit(type: "error", message: "initial_frame_failed")
                    result(false)
                    return
                }
                let controller: AVPictureInPictureController
                if let existingController = self.pictureInPictureController {
                    controller = existingController
                } else {
                    let contentSource = AVPictureInPictureController.ContentSource(
                        sampleBufferDisplayLayer: self.sampleLayer,
                        playbackDelegate: self
                    )
                    controller = AVPictureInPictureController(
                        contentSource: contentSource
                    )
                    controller.delegate = self
                    self.pictureInPictureController = controller
                }
                controller.requiresLinearPlayback = true
                controller.canStartPictureInPictureAutomaticallyFromInline =
                    self.automaticStartEnabled
                controller.invalidatePlaybackState()
                self.prepared = true
                self.prewarmAutomaticPictureInPictureIfNeeded()
                NSLog(
                    "[MusicVibePiP] prepared possible=%@ source=%@",
                    controller.isPictureInPicturePossible ? "true" : "false",
                    self.sourceKind
                )
                self.emit(type: "prepared")
                result(true)
            }
        }
    }

    private func start(result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    result(false)
                    return
                }
                self.start(result: result)
            }
            return
        }
        guard prepared, let controller = pictureInPictureController else {
            NSLog("[MusicVibePiP] start rejected: content is not prepared")
            result(false)
            return
        }
        guard lifecycleState != .stopping else {
            NSLog("[MusicVibePiP] start rejected: PiP is stopping")
            result(false)
            return
        }
        guard
            lifecycleState != .active,
            !controller.isPictureInPictureActive
        else {
            result(true)
            return
        }
        guard lifecycleState != .starting, pendingStartResult == nil else {
            NSLog("[MusicVibePiP] start rejected: request already pending")
            result(false)
            return
        }
        guard sampleLayer.superlayer != nil || attachSampleLayer() else {
            NSLog("[MusicVibePiP] start rejected: no active host window")
            emit(type: "startFailed", message: "sample_layer_window_unavailable")
            result(false)
            return
        }

        guard controller.isPictureInPicturePossible else {
            waitForPictureInPictureAvailability(controller, result: result)
            return
        }

        beginPictureInPicture(controller, result: result)
    }

    private func waitForPictureInPictureAvailability(
        _ controller: AVPictureInPictureController,
        result: @escaping FlutterResult
    ) {
        startRequestGeneration += 1
        let generation = startRequestGeneration
        pendingStartResult = result
        NSLog("[MusicVibePiP] waiting for isPictureInPicturePossible")

        possibilityObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.initial, .new]
        ) { [weak self] observedController, change in
            guard change.newValue == true else { return }
            DispatchQueue.main.async {
                self?.startWhenAvailable(
                    observedController,
                    generation: generation
                )
            }
        }

        let timeout = DispatchWorkItem { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.failPendingStartIfNeeded(
                controller,
                generation: generation,
                reason: "not_possible_after_wait"
            )
        }
        startTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(1200),
            execute: timeout
        )
    }

    private func startWhenAvailable(
        _ controller: AVPictureInPictureController,
        generation: Int
    ) {
        guard
            generation == startRequestGeneration,
            controller === pictureInPictureController,
            controller.isPictureInPicturePossible,
            let result = takePendingStartResult()
        else { return }

        NSLog("[MusicVibePiP] availability became ready")
        beginPictureInPicture(controller, result: result)
    }

    private func failPendingStartIfNeeded(
        _ controller: AVPictureInPictureController,
        generation: Int,
        reason: String
    ) {
        guard
            generation == startRequestGeneration,
            controller === pictureInPictureController,
            let result = takePendingStartResult()
        else { return }

        NSLog(
            "[MusicVibePiP] start failed: %@ possible=%@ layerAttached=%@",
            reason,
            controller.isPictureInPicturePossible ? "true" : "false",
            sampleLayer.superlayer == nil ? "false" : "true"
        )
        if pictureInPictureStartFailureRequiresControllerReset(reason) {
            // A timeout does not cancel AVKit's pending start request. Stop it
            // and retire this controller so a late didStart cannot resurrect
            // a native PiP session after Dart has accepted the failure.
            controller.stopPictureInPicture()
            controller.delegate = nil
            pictureInPictureController = nil
            prepared = false
        }
        stopRenderTimer()
        pauseDynamicSources()
        detachSampleLayer()
        stopWatchdog?.cancel()
        stopWatchdog = nil
        stopWatchdogAttempts = 0
        lifecycleState = .idle
        stopRequestedDuringStart = false
        stopCompletionPending = false
        observedBackgroundSinceStart = false
        emit(type: "startFailed", message: reason)
        result(false)
    }

    private func beginPictureInPicture(
        _ controller: AVPictureInPictureController,
        result: @escaping FlutterResult
    ) {
        possibilityObservation?.invalidate()
        possibilityObservation = nil
        startTimeoutWorkItem?.cancel()
        startRequestGeneration += 1
        let generation = startRequestGeneration
        pendingStartResult = result

        let timeout = DispatchWorkItem { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.failPendingStartIfNeeded(
                controller,
                generation: generation,
                reason: "native_start_timeout"
            )
        }
        startTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(5),
            execute: timeout
        )

        lifecycleState = .starting
        stopRequestedDuringStart = false
        observedBackgroundSinceStart = false
        stopRenderTimer()
        startRenderTimer()
        if playbackActive { playDynamicSources() }
        NSLog("[MusicVibePiP] requesting start")
        controller.startPictureInPicture()
    }

    private func takePendingStartResult() -> FlutterResult? {
        guard let result = pendingStartResult else { return nil }
        pendingStartResult = nil
        possibilityObservation?.invalidate()
        possibilityObservation = nil
        startTimeoutWorkItem?.cancel()
        startTimeoutWorkItem = nil
        return result
    }

    private func cancelPendingStart() {
        startRequestGeneration += 1
        let result = takePendingStartResult()
        result?(false)
    }

    @discardableResult
    private func stop(reason: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        cancelPendingStart()
        stoppingReason = reason
        setAutomaticStartEnabled(false)
        guard let controller = pictureInPictureController else {
            stopRenderTimer()
            pauseDynamicSources()
            detachSampleLayer()
            lifecycleState = .idle
            return false
        }

        if lifecycleState == .stopping {
            if stopWatchdog == nil {
                scheduleStopWatchdog(for: controller)
            }
            return true
        }

        if lifecycleState == .starting && !controller.isPictureInPictureActive {
            stopRequestedDuringStart = true
            stopCompletionPending = true
            stopRenderTimer()
            pauseDynamicSources()
            // AVKit does not expose a cancellable start token. Request the
            // stop immediately and keep a separate watchdog because
            // cancelPendingStart() consumed the original start watchdog.
            controller.stopPictureInPicture()
            schedulePendingStartStopWatchdog(for: controller)
            NSLog(
                "[MusicVibePiP] stop deferred until start completes reason=%@",
                reason
            )
            return true
        }

        guard lifecycleState == .active || controller.isPictureInPictureActive else {
            stopRenderTimer()
            pauseDynamicSources()
            detachSampleLayer()
            lifecycleState = .idle
            stopRequestedDuringStart = false
            observedBackgroundSinceStart = false
            return false
        }

        beginStopping(controller, reason: reason)
        return true
    }

    private func schedulePendingStartStopWatchdog(
        for controller: AVPictureInPictureController
    ) {
        stopWatchdog?.cancel()
        let watchdog = DispatchWorkItem { [weak self, weak controller] in
            guard let self, let controller else { return }
            switch pictureInPicturePendingStartStopAction(
                isCurrentController:
                    controller === self.pictureInPictureController,
                lifecycleIsStarting: self.lifecycleState == .starting,
                stopRequested: self.stopRequestedDuringStart,
                controllerIsActive: controller.isPictureInPictureActive
            ) {
            case .ignore:
                return
            case .beginStopping:
                self.beginStopping(controller, reason: self.stoppingReason)
            case .forceIdle:
                NSLog(
                    "[MusicVibePiP] pending start produced no delegate callback; forcing idle"
                )
                controller.stopPictureInPicture()
                controller.delegate = nil
                self.pictureInPictureController = nil
                self.stopWatchdog = nil
                self.stopWatchdogAttempts = 0
                self.stopCompletionPending = false
                self.lifecycleState = .idle
                self.stopRequestedDuringStart = false
                self.observedBackgroundSinceStart = false
                self.foregroundStopRequested = false
                self.prepared = false
                self.stopRenderTimer()
                self.pauseDynamicSources()
                self.detachSampleLayer()
                self.emit(type: "stopped", message: self.stoppingReason)
                self.stoppingReason = "system"
            }
        }
        stopWatchdog = watchdog
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(1500),
            execute: watchdog
        )
    }

    private func beginStopping(
        _ controller: AVPictureInPictureController,
        reason: String
    ) {
        guard lifecycleState != .stopping else { return }
        lifecycleState = .stopping
        stopRequestedDuringStart = false
        stopCompletionPending = true
        stopWatchdogAttempts = 0
        stopRenderTimer()
        pauseDynamicSources()
        NSLog("[MusicVibePiP] requesting stop reason=%@", reason)
        controller.stopPictureInPicture()
        scheduleStopWatchdog(for: controller)
    }

    private func scheduleStopWatchdog(
        for controller: AVPictureInPictureController
    ) {
        stopWatchdog?.cancel()
        stopWatchdogAttempts += 1
        let watchdog = DispatchWorkItem { [weak self, weak controller] in
            guard
                let self,
                let controller,
                self.lifecycleState == .stopping
            else { return }
            if controller.isPictureInPictureActive {
                NSLog(
                    "[MusicVibePiP] stop still pending attempt=%d; requesting stop again",
                    self.stopWatchdogAttempts
                )
                controller.stopPictureInPicture()
            } else {
                NSLog(
                    "[MusicVibePiP] stop awaits didStop attempt=%d",
                    self.stopWatchdogAttempts
                )
            }
            if self.stopWatchdogAttempts < 3 {
                self.scheduleStopWatchdog(for: controller)
            } else {
                // isPictureInPictureActive can become false before AVKit removes
                // its window. Only didStop is allowed to detach the source layer.
                self.stopWatchdog = nil
                NSLog("[MusicVibePiP] stop delegate still pending")
            }
        }
        stopWatchdog = watchdog
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(1500),
            execute: watchdog
        )
    }

    private func completeStop(reason: String) {
        guard stopCompletionPending || lifecycleState != .idle else { return }
        stopWatchdog?.cancel()
        stopWatchdog = nil
        stopWatchdogAttempts = 0
        stopCompletionPending = false
        lifecycleState = .idle
        stopRequestedDuringStart = false
        observedBackgroundSinceStart = false
        foregroundStopRequested = false
        stopRenderTimer()
        pauseDynamicSources()
        detachSampleLayer()
        emit(type: "stopped", message: reason)
        stoppingReason = "system"
    }

    @objc private func handleApplicationDidEnterBackground() {
        if lifecycleState == .starting || lifecycleState == .active {
            observedBackgroundSinceStart = true
        }
        if sourceKind == "sceneV2Shared", lifecycleState == .active {
            handleSharedV2ThermalStateChange()
        }
    }

    @objc private func handlePrimarySceneWillEnterForeground(
        _ notification: Notification
    ) {
        guard
            let foregroundScene = notification.object as? UIWindowScene,
            let primaryScene = windowProvider()?.windowScene
        else {
            return
        }
        guard foregroundScene === primaryScene else {
            NSLog("[MusicVibePiP] ignored non-primary foreground scene")
            return
        }
        requestForegroundStop(source: "primary_scene")
    }

    @objc private func handleApplicationWillEnterForeground() {
        requestForegroundStop(source: "application")
    }

    private func requestForegroundStop(source: String) {
        guard
            lifecycleState != .idle ||
                pictureInPictureController?.isPictureInPictureActive == true
        else { return }
        foregroundStopRequested = true
        setAutomaticStartEnabled(false)
        NSLog(
            "[MusicVibePiP] foreground source=%@ state=%@; stopping",
            source,
            lifecycleState.rawValue
        )
        // The app's UIWindowScene notification arrives before the application
        // notification. Filtering by identity avoids reacting to AVKit's own
        // PiP scene while still dismissing its window before the first input.
        _ = stop(reason: "foreground_restored_native")
    }

    @objc private func handleApplicationDidBecomeActive() {
        guard
            foregroundStopRequested ||
                (observedBackgroundSinceStart &&
                    (lifecycleState != .idle ||
                        pictureInPictureController?.isPictureInPictureActive == true))
        else {
            return
        }
        NSLog(
            "[MusicVibePiP] foreground fallback state=%@; stopping",
            lifecycleState.rawValue
        )
        foregroundStopRequested = false
        DispatchQueue.main.async { [weak self] in
            _ = self?.stop(reason: "foreground_restored_native")
        }
    }

    private func releasePreparedContent() {
        guard
            lifecycleState == .idle,
            pictureInPictureController?.isPictureInPictureActive != true
        else {
            return
        }
        clearPreparedContent()
    }

    private func setAutomaticStartEnabled(_ enabled: Bool) {
        automaticStartEnabled = enabled
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = enabled
        pictureInPictureController?.invalidatePlaybackState()
        if enabled {
            prewarmAutomaticPictureInPictureIfNeeded()
        } else if
            lifecycleState == .idle,
            pictureInPictureController?.isPictureInPictureActive != true
        {
            stopRenderTimer()
            pauseDynamicSources()
        }
    }

    private func setPlaybackActive(
        _ active: Bool,
        emitPlaybackIntent: Bool = false
    ) {
        playbackActive = active
        if active {
            if v2EmergencyRecoveryActive {
                pictureInPictureController?.invalidatePlaybackState()
                if emitPlaybackIntent {
                    emit(type: "playbackChanged", playing: active)
                }
                return
            }
            if
                !stopRequestedDuringStart,
                lifecycleState == .starting ||
                    lifecycleState == .active
            {
                startRenderTimer()
                playDynamicSources()
            } else {
                prewarmAutomaticPictureInPictureIfNeeded()
            }
        } else {
            stopRenderTimer()
            pauseDynamicSources()
        }
        pictureInPictureController?.invalidatePlaybackState()
        if emitPlaybackIntent {
            emit(type: "playbackChanged", playing: active)
        }
    }

    private func prewarmAutomaticPictureInPictureIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard
            automaticStartEnabled,
            prepared,
            playbackActive,
            lifecycleState == .idle,
            pictureInPictureController?.isPictureInPictureActive != true
        else {
            return
        }
        guard sampleLayer.superlayer != nil || attachSampleLayer() else {
            stopRenderTimer()
            pauseDynamicSources()
            pictureInPictureController?
                .canStartPictureInPictureAutomaticallyFromInline = false
            NSLog(
                "[MusicVibePiP] automatic prewarm deferred: no active host window"
            )
            return
        }
        pictureInPictureController?
            .canStartPictureInPictureAutomaticallyFromInline = true
        stopRenderTimer()
        pauseDynamicSources()
        startRenderTimer(
            framesPerSecond: 2,
            posterOnly: sourceKind != "sceneV2Shared" && sourceKind != "sceneV1Shared"
        )
    }

    private func updateReactiveFrame(arguments: Any?) {
        guard let arguments = arguments as? [String: Any] else { return }
        let timestamp = (arguments["timestampMicros"] as? NSNumber)?.int64Value ?? 0
        let nowMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
        guard timestamp > 0, nowMicros - timestamp <= 250_000 else {
            incrementDroppedFrames()
            return
        }
        if
            sourceKind == "realtimeRenderer",
            let rendererSessionId
        {
            renderEngine.updateAudioFrame(
                sessionId: rendererSessionId,
                arguments: arguments
            )
        } else if sourceKind == "sceneComposition" {
            sceneLayers.forEach { $0.updateAudioFrame(arguments: arguments) }
        }
        let shouldReact = arguments["shouldReact"] as? Bool ?? false
        var frame = ReactiveFrame(
            timestampMicros: timestamp,
            level: shouldReact ? Self.unit(arguments["level"]) : 0,
            impact: shouldReact ? Self.unit(arguments["impactStrength"]) : 0,
            hitStrength: shouldReact ? Self.unit(arguments["flashStrength"]) : 0,
            bassDrive: shouldReact ? Self.unit(arguments["bassDrive"]) : 0,
            bodyDrive: shouldReact ? Self.unit(arguments["bodyDrive"]) : 0,
            sparkDrive: shouldReact ? Self.unit(arguments["sparkDrive"]) : 0,
            flowDrive: shouldReact ? Self.unit(arguments["flowDrive"]) : 0,
            reactivity: shouldReact ? Self.unit(arguments["reactivity"]) : 0
        )
        if !shouldReact || arguments["flashActive"] as? Bool != true {
            frame.hitStrength = min(frame.hitStrength, 0.32)
        }
        stateLock.lock()
        if frame.timestampMicros >= latestFrame.timestampMicros {
            latestFrame = frame
            if !shouldReact {
                latestHitMicros = 0
                latestHitStrength = 0
            } else if
                arguments["flashActive"] as? Bool == true,
                timestamp > latestHitMicros
            {
                latestHitMicros = timestamp
                latestHitStrength = frame.hitStrength
            }
        }
        stateLock.unlock()
    }

    private func configurePixelBufferPool() -> Bool {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey: 1] as CFDictionary,
            attributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else { return false }
        pixelBufferPool = pool
        guard let pixelBuffer = makeBoundedPixelBuffer(pool) else { return false }
        var description: CMVideoFormatDescription?
        guard
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &description
            ) == noErr
        else { return false }
        formatDescription = description
        return true
    }

    private func makeBoundedPixelBuffer(_ pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let limit = publishedBufferBudget.allocationLimit(width: width, height: height, pool: pool)
        guard limit > 0 else { return nil }
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, pool,
            [kCVPixelBufferPoolAllocationThresholdKey: limit] as CFDictionary,
            &buffer
        ) == kCVReturnSuccess,
              let buffer, publishedBufferBudget.track(buffer, pool: pool) else { return nil }
        return buffer
    }

    private func configureTimebase() {
        var createdTimebase: CMTimebase?
        let hostClock = CMClockGetHostTimeClock()
        guard
            CMTimebaseCreateWithSourceClock(
                allocator: kCFAllocatorDefault,
                sourceClock: hostClock,
                timebaseOut: &createdTimebase
            ) == noErr,
            let createdTimebase
        else { return }
        let now = CMClockGetTime(hostClock)
        CMTimebaseSetTime(createdTimebase, time: now)
        CMTimebaseSetRate(createdTimebase, rate: 1)
        timebase = createdTimebase
        sampleLayer.controlTimebase = createdTimebase
    }

    private func attachSampleLayer() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let window = windowProvider() else { return false }
        guard let rootView = window.rootViewController?.view else {
            return false
        }

        let hostView: UIView
        if let existingHost = sourceHostView {
            hostView = existingHost
        } else {
            let createdHost = UIView(frame: window.bounds)
            createdHost.backgroundColor = .clear
            createdHost.isUserInteractionEnabled = false
            createdHost.accessibilityElementsHidden = true
            createdHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            sourceHostView = createdHost
            hostView = createdHost
        }

        if hostView.superview !== window {
            hostView.removeFromSuperview()
            if rootView.superview === window {
                window.insertSubview(hostView, belowSubview: rootView)
            } else {
                window.insertSubview(hostView, at: 0)
            }
        }
        hostView.frame = window.bounds

        sampleLayer.removeFromSuperlayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // AVKit derives source geometry from this layer. Keep it at the real
        // portrait size, but host it behind Flutter so its black background can
        // never cover the app while a new scene is prepared.
        sampleLayer.frame = hostView.bounds
        sampleLayer.isHidden = false
        hostView.layer.addSublayer(sampleLayer)
        CATransaction.commit()
        return sampleLayer.superlayer === hostView.layer
    }

    private func detachSampleLayer() {
        dispatchPrecondition(condition: .onQueue(.main))
        sampleLayer.removeFromSuperlayer()
        sourceHostView?.removeFromSuperview()
    }

    private func configureSceneDocument(_ value: Any?) -> Bool {
        guard
            let document = value as? [String: Any],
            (document["schemaVersion"] as? NSNumber)?.intValue == 1,
            let layerDefinitions = document["layers"] as? [[String: Any]],
            !layerDefinitions.isEmpty,
            layerDefinitions.count <= 12,
            sceneSurfaceVideoLayerCountIsSupported(layerDefinitions)
        else {
            return false
        }

        var parsedLayers = [PictureInPictureSceneLayerRuntime]()
        var layerIds = Set<String>()
        var backgroundCount = 0
        var encounteredOverlay = false

        for definition in layerDefinitions {
            guard
                let layer = PictureInPictureSceneLayerRuntime(
                    definition: definition,
                    renderEngine: renderEngine,
                    metalContext: metalContext,
                    metricsScope: sceneMetricsScope
                ),
                layerIds.insert(layer.id).inserted
            else {
                parsedLayers.forEach { $0.tearDown() }
                return false
            }
            if layer.role == "background" {
                backgroundCount += 1
                if backgroundCount > 1 || encounteredOverlay {
                    layer.tearDown()
                    parsedLayers.forEach { $0.tearDown() }
                    return false
                }
            } else {
                encounteredOverlay = true
            }
            parsedLayers.append(layer)
        }

        let parsedFilter: PictureInPictureSceneFilterRuntime?
        if let filterDefinition = document["filter"] as? [String: Any] {
            guard
                let filter = PictureInPictureSceneFilterRuntime(
                    definition: filterDefinition
                )
            else {
                parsedLayers.forEach { $0.tearDown() }
                return false
            }
            parsedFilter = filter
        } else {
            parsedFilter = nil
        }

        sceneLayers = parsedLayers
        sceneFilter = parsedFilter
        sceneOnePassLayers = sceneSurfaceOnePassLayers(
            parsedLayers,
            hasFilter: parsedFilter != nil
        )
        return true
    }

    private func playDynamicSources() {
        guard
            playbackActive,
            !stopRequestedDuringStart,
            lifecycleState == .starting ||
                lifecycleState == .active
        else {
            pauseDynamicSources()
            return
        }
        dynamicSourcesPlaybackRequested = true
        videoPlayer?.play()
        sceneLayers.forEach { $0.play() }
        if let v1SharedSource {
            sceneSurfaceEngine.setPictureInPictureSourcePlaying(v1SharedSource, playing: true)
        }
        if let v2SharedSessionId, !v2EmergencyRecoveryActive {
            v2ImageRuntime.setPictureInPictureSourcePlaying(
                sessionID: v2SharedSessionId,
                playing: true
            )
        }
    }

    private func pauseDynamicSources() {
        dynamicSourcesPlaybackRequested = false
        videoPlayer?.pause()
        sceneLayers.forEach { $0.pause() }
        if let v1SharedSource {
            sceneSurfaceEngine.setPictureInPictureSourcePlaying(v1SharedSource, playing: false)
        }
        if let v2SharedSessionId {
            v2ImageRuntime.setPictureInPictureSourcePlaying(
                sessionID: v2SharedSessionId,
                playing: false
            )
        }
    }

    private func tearDownSceneDocument() {
        sceneOnePassLayers = nil
        sceneLayers.forEach { $0.tearDown() }
        sceneLayers.removeAll(keepingCapacity: false)
        sceneFilter = nil
        if let sceneMetricsScope {
            metalContext?.renderPathMetrics.removeScope(sceneMetricsScope)
            self.sceneMetricsScope = nil
        }
    }

    private func configureVideoIfAvailable(
        path: String?,
        asset: String?,
        package: String?
    ) {
        guard sourceKind == "video" else { return }
        let resolvedPath: String?
        if let path, !path.isEmpty {
            resolvedPath = path
        } else if let asset, !asset.isEmpty {
            let lookupKey: String
            if let package, !package.isEmpty {
                lookupKey = FlutterDartProject.lookupKey(
                    forAsset: asset,
                    fromPackage: package
                )
            } else {
                lookupKey = FlutterDartProject.lookupKey(forAsset: asset)
            }
            resolvedPath = Bundle.main.path(forResource: lookupKey, ofType: nil)
        } else {
            resolvedPath = nil
        }
        guard let resolvedPath else {
            sourceKind = "poster"
            return
        }
        let url = URL(fileURLWithPath: resolvedPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            sourceKind = "poster"
            return
        }
        guard let reservation = SceneSurfaceVideoReservations.shared.reserve() else {
            sourceKind = "poster"
            return
        }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        videoReservation = reservation
        player.actionAtItemEnd = .none
        player.isMuted = true
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak player] _ in
            guard let self, let player, self.videoPlayer === player else { return }
            player.seek(to: .zero) { [weak self, weak player] completed in
                DispatchQueue.main.async {
                    guard completed, let self, let player, self.videoPlayer === player,
                          self.dynamicSourcesPlaybackRequested else { return }
                    player.play()
                }
            }
        }
        videoOutput = output
        videoPlayer = player
    }

    private func tearDownVideo() {
        videoPlayer?.pause()
        videoPlayer?.cancelPendingPrerolls()
        videoPlayer?.currentItem?.cancelPendingSeeks()
        if let output = videoOutput { videoPlayer?.currentItem?.remove(output) }
        videoPlayer?.replaceCurrentItem(with: nil)
        dynamicSourcesPlaybackRequested = false
        if let observer = videoEndObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        videoEndObserver = nil
        videoOutput = nil
        videoPlayer = nil
        videoReservation = nil
    }

    private func startRenderTimer(
        framesPerSecond requestedFPS: Int? = nil,
        posterOnly: Bool = false
    ) {
        guard renderTimer == nil, playbackActive else { return }
        let fps = requestedFPS ?? effectiveFramesPerSecond
        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(1_000_000_000 / max(fps, 1)),
            leeway: .milliseconds(3)
        )
        timer.setEventHandler { [weak self] in
            autoreleasepool {
                _ = self?.renderFrame(forcePoster: posterOnly)
            }
        }
        renderTimer = timer
        currentRenderFramesPerSecond = fps
        renderTimerUsesPosterOnly = posterOnly
        timer.resume()
        emit(
            type: "thermalStateChanged",
            message: thermalStateName,
            framesPerSecond: fps
        )
    }

    private func stopRenderTimer() {
        renderTimer?.setEventHandler {}
        renderTimer?.cancel()
        renderTimer = nil
        currentRenderFramesPerSecond = 0
        renderTimerUsesPosterOnly = false
    }

    private var effectiveFramesPerSecond: Int {
        if
            sourceKind == "sceneV2Shared",
            let v2SharedSessionId,
            let framesPerSecond = v2ImageRuntime.pictureInPictureFramesPerSecond(
                sessionID: v2SharedSessionId
            )
        {
            return min(max(framesPerSecond, 1), 30)
        }
        let processInfo = ProcessInfo.processInfo
        if processInfo.isLowPowerModeEnabled || processInfo.thermalState == .serious {
            return degradedFramesPerSecond
        }
        return preferredFramesPerSecond
    }

    private var thermalStateName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    @objc private func handlePowerOrThermalStateChange() {
        let critical = ProcessInfo.processInfo.thermalState == .critical
        if sourceKind == "sceneV2Shared", v2SharedSessionId != nil {
            handleSharedV2ThermalStateChange()
            return
        }
        if critical {
            emit(type: "error", message: "thermal_critical")
            DispatchQueue.main.async { [weak self] in
                self?.stop(reason: "thermal_critical")
            }
            return
        }
        let wasRunning = renderTimer != nil
        if wasRunning {
            let wasPrewarming = currentRenderFramesPerSecond == 2
            let wasPosterOnly = renderTimerUsesPosterOnly
            stopRenderTimer()
            startRenderTimer(
                framesPerSecond: wasPrewarming ? 2 : nil,
                posterOnly: wasPosterOnly
            )
        }
    }

    private func handleSharedV2ThermalStateChange() {
        guard
            lifecycleState == .active ||
                pictureInPictureController?.isPictureInPictureActive == true
        else { return }
        let state = ProcessInfo.processInfo.thermalState
        if state == .critical {
            v2FairDeadlineWorkItem?.cancel()
            v2FairDeadlineWorkItem = nil
            v2RecoveryWorkItem?.cancel()
            v2RecoveryWorkItem = nil
            guard
                !v2EmergencyRecoveryActive,
                v2CriticalDeadlineWorkItem == nil,
                !v2QualityTransitionInFlight,
                let v2SharedSessionId
            else { return }
            v2QualityTransitionInFlight = true
            v2ImageRuntime.ensurePictureInPictureMinimumFunctional(
                sessionID: v2SharedSessionId
            ) { [weak self] accepted, activeSeconds in
                guard let self, self.v2SharedSessionId == v2SharedSessionId else {
                    return
                }
                self.v2QualityTransitionInFlight = false
                guard ProcessInfo.processInfo.thermalState == .critical else {
                    self.handleSharedV2ThermalStateChange()
                    return
                }
                guard accepted else {
                    self.enterSharedV2EmergencyRecovery(
                        reason: "minimum_functional_unavailable"
                    )
                    return
                }
                if self.renderTimer != nil {
                    self.stopRenderTimer()
                    self.startRenderTimer()
                }
                if activeSeconds >= 30 {
                    self.enterSharedV2EmergencyRecovery(
                        reason: "critical_after_minimum_functional"
                    )
                    return
                }
                let deadline = DispatchWorkItem { [weak self] in
                    guard
                        let self,
                        ProcessInfo.processInfo.thermalState == .critical
                    else { return }
                    self.v2CriticalDeadlineWorkItem = nil
                    self.enterSharedV2EmergencyRecovery(
                        reason: "critical_not_stabilized"
                    )
                }
                self.v2CriticalDeadlineWorkItem = deadline
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .seconds(15),
                    execute: deadline
                )
            }
            emit(type: "thermalStateChanged", message: thermalStateName)
            return
        }

        v2CriticalDeadlineWorkItem?.cancel()
        v2CriticalDeadlineWorkItem = nil
        v2QualityTransitionInFlight = false
        guard v2EmergencyRecoveryActive else {
            handleSharedV2NormalAdaptation(state: state)
            return
        }

        guard state == .nominal || state == .fair else {
            v2RecoveryWorkItem?.cancel()
            v2RecoveryWorkItem = nil
            return
        }
        guard v2RecoveryWorkItem == nil else { return }
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.v2RecoveryWorkItem = nil
            let current = ProcessInfo.processInfo.thermalState
            guard
                current == .nominal || current == .fair,
                self.v2EmergencyRecoveryActive,
                let v2SharedSessionId = self.v2SharedSessionId
            else { return }
            self.v2ImageRuntime.ensurePictureInPictureMinimumFunctional(
                sessionID: v2SharedSessionId
            ) { [weak self] accepted, _ in
                guard let self, accepted else { return }
                self.v2EmergencyRecoveryActive = false
                if self.playbackActive {
                    self.dynamicSourcesPlaybackRequested = true
                    self.v2ImageRuntime.setPictureInPictureSourcePlaying(
                        sessionID: v2SharedSessionId,
                        playing: true
                    )
                    self.startRenderTimer()
                }
                self.emit(
                    type: "thermalStateChanged",
                    message: self.thermalStateName,
                    framesPerSecond: self.currentRenderFramesPerSecond
                )
            }
        }
        v2RecoveryWorkItem = recovery
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(60),
            execute: recovery
        )
    }

    private func handleSharedV2NormalAdaptation(
        state: ProcessInfo.ThermalState
    ) {
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if state == .serious {
            v2FairDeadlineWorkItem?.cancel()
            v2FairDeadlineWorkItem = nil
            requestSharedV2QualityCap("minimumFunctional")
        } else if lowPowerMode {
            v2FairDeadlineWorkItem?.cancel()
            v2FairDeadlineWorkItem = nil
            requestSharedV2QualityCap("sustained")
        } else if state == .fair {
            if v2FairDeadlineWorkItem == nil {
                let deadline = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.v2FairDeadlineWorkItem = nil
                    guard
                        ProcessInfo.processInfo.thermalState == .fair,
                        !self.v2EmergencyRecoveryActive
                    else { return }
                    self.requestSharedV2QualityCap("sustained")
                }
                v2FairDeadlineWorkItem = deadline
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .seconds(30),
                    execute: deadline
                )
            }
        } else {
            v2FairDeadlineWorkItem?.cancel()
            v2FairDeadlineWorkItem = nil
        }
        emit(
            type: "thermalStateChanged",
            message: thermalStateName,
            framesPerSecond: currentRenderFramesPerSecond
        )
    }

    private func requestSharedV2QualityCap(_ maximumQuality: String) {
        guard
            !v2QualityTransitionInFlight,
            let v2SharedSessionId
        else { return }
        v2QualityTransitionInFlight = true
        v2ImageRuntime.capPictureInPictureQuality(
            sessionID: v2SharedSessionId,
            maximumQuality: maximumQuality
        ) { [weak self] accepted, _ in
            guard let self, self.v2SharedSessionId == v2SharedSessionId else {
                return
            }
            self.v2QualityTransitionInFlight = false
            if ProcessInfo.processInfo.thermalState == .critical {
                self.handleSharedV2ThermalStateChange()
                return
            }
            if accepted, self.renderTimer != nil {
                self.stopRenderTimer()
                self.startRenderTimer()
            } else if !accepted, maximumQuality == "minimumFunctional" {
                self.enterSharedV2EmergencyRecovery(
                    reason: "minimum_functional_unavailable"
                )
            }
        }
    }

    private func enterSharedV2EmergencyRecovery(reason: String) {
        guard !v2EmergencyRecoveryActive, let v2SharedSessionId else { return }
        v2FairDeadlineWorkItem?.cancel()
        v2FairDeadlineWorkItem = nil
        v2CriticalDeadlineWorkItem?.cancel()
        v2CriticalDeadlineWorkItem = nil
        v2QualityTransitionInFlight = false
        v2EmergencyRecoveryActive = true
        stopRenderTimer()
        dynamicSourcesPlaybackRequested = false
        v2ImageRuntime.setPictureInPictureSourcePlaying(
            sessionID: v2SharedSessionId,
            playing: false
        )
        // AVSampleBufferDisplayLayer retains the last valid frame while the
        // musical timeline and controls remain owned by Dart.
        emit(type: "error", message: "emergency_recovery:\(reason)")
    }

    @discardableResult
    private func renderFrame(forcePoster: Bool) -> Bool {
        guard
            let pool = pixelBufferPool,
            let formatDescription,
            let posterImage
        else { return false }
        guard sampleLayer.isReadyForMoreMediaData else {
            incrementDroppedFrames()
            return false
        }

        let outputBuffer: CVPixelBuffer
        if sourceKind == "realtimeRenderer", !forcePoster {
            guard
                let rendererSessionId,
                let rendered = renderEngine.renderPictureInPictureFrame(
                sessionId: rendererSessionId,
                width: width,
                height: height
            )
            else {
                incrementDroppedFrames()
                return false
            }
            outputBuffer = rendered
        } else if !forcePoster, sourceKind == "sceneV1Shared" {
            guard let v1SharedSource,
                  let frame = sceneSurfaceEngine.copyPictureInPictureFrame(v1SharedSource) else {
                incrementDroppedFrames()
                return false
            }
            if v1ConvertedRevision == frame.revision, let cached = v1ConvertedBuffer {
                outputBuffer = cached
            } else {
                guard let converted = makeBoundedPixelBuffer(pool) else {
                    incrementDroppedFrames()
                    return false
                }
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                guard renderSceneSurfaceCIFinalFrame(
                    image: aspectFill(CIImage(cvPixelBuffer: frame.buffer), targetRect: rect),
                    to: converted, bounds: rect, colorSpace: outputColorSpace,
                    context: ciContext, metrics: metalContext?.renderPathMetrics,
                    metricsScope: sceneMetricsScope
                ) else { incrementDroppedFrames(); return false }
                // The cached scaled result remains immutable while AVKit owns
                // it. A repeated source revision does no GPU conversion.
                v1ConvertedRevision = frame.revision
                v1ConvertedBuffer = converted
                outputBuffer = converted
            }
        } else {
            guard let allocatedBuffer = makeBoundedPixelBuffer(pool) else {
                incrementDroppedFrames()
                return false
            }
            let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
            var renderedImage: CIImage?
            var sceneRenderInput: (
                hostTime: CFTimeInterval,
                frame: ReactiveFrame,
                attemptedOnePass: Bool,
                result: SceneSurfaceOnePassRenderResult,
                fallbackBaseline: UInt64
            )?
            if forcePoster {
                renderedImage = aspectFill(
                    posterImage,
                    targetRect: targetRect
                )
            } else if sourceKind == "sceneV2Shared" {
                guard
                    let v2SharedSessionId,
                    let sharedBuffer = v2ImageRuntime
                        .copyPictureInPictureFrame(
                            sessionID: v2SharedSessionId
                        )
                else {
                    // Keep the last valid AVSampleBufferDisplayLayer frame.
                    // A missing shared frame is never replaced with a poster or
                    // black frame during an active PiP session.
                    incrementDroppedFrames()
                    return false
                }
                renderedImage = aspectFill(
                    CIImage(cvPixelBuffer: sharedBuffer),
                    targetRect: targetRect
                )
            } else if sourceKind == "sceneComposition" {
                let hostTime = CACurrentMediaTime()
                let frame = freshReactiveFrame()
                let graphEligible = sceneOnePassLayers != nil
                let attemptedOnePass = graphEligible && metalContext != nil
                let fallbackBaseline = metalContext?.renderPathMetrics
                    .snapshot(scope: sceneMetricsScope).fallback ?? 0
                let onePassResult = renderSceneSurfaceOnePass(
                    graph: sceneOnePassLayers,
                    targetRect: targetRect,
                    targetBuffer: allocatedBuffer,
                    hostTime: hostTime,
                    musicActive: frame.reactivity > 0.001,
                    flowDrive: frame.flowDrive,
                    bodyDrive: frame.bodyDrive,
                    sparkDrive: frame.sparkDrive,
                    sourcesPrepared: false,
                    compositor: graphEligible ? metalContext?.onePassCompositor : nil,
                    metricsScope: sceneMetricsScope
                )
                sceneRenderInput = (
                    hostTime,
                    frame,
                    attemptedOnePass,
                    onePassResult,
                    fallbackBaseline
                )
                if onePassResult == .rendered {
                    renderedImage = nil
                } else {
                    renderedImage = renderSceneDocument(
                        targetRect: targetRect,
                        hostTime: hostTime,
                        frame: frame,
                        sourcesPrepared: attemptedOnePass
                    )
                        ?? aspectFill(posterImage, targetRect: targetRect)
                }
            } else {
                // Legacy poster and video sources remain visually honest. Audio
                // reaction is only applied by an explicit layer binding or a
                // shared realtime/procedural renderer.
                renderedImage = sourceImage(
                    poster: posterImage,
                    targetRect: targetRect,
                    forcePoster: false
                )
            }
            if let renderedImage {
                let completed: Bool
                if sceneRenderInput != nil {
                    completed = renderSceneSurfaceCIFinalFrame(
                        image: renderedImage,
                        to: allocatedBuffer,
                        bounds: targetRect,
                        colorSpace: outputColorSpace,
                        context: ciContext,
                        metrics: metalContext?.renderPathMetrics,
                        metricsScope: sceneMetricsScope
                    )
                } else {
                    ciContext.render(
                        renderedImage,
                        to: allocatedBuffer,
                        bounds: targetRect,
                        colorSpace: outputColorSpace
                    )
                    completed = true
                }
                guard completed else {
                    incrementDroppedFrames()
                    return false
                }
            }
            if let sceneRenderInput,
               sceneRenderInput.result != .rendered {
                if sceneRenderInput.attemptedOnePass {
                    metalContext?.renderPathMetrics.recordCIFallback(
                        path: sceneRenderInput.result == .failed
                            ? "pip_one_pass_failure_v12_ci"
                            : "pip_one_pass_unsupported_v12_ci",
                        scope: sceneMetricsScope,
                        ifFallbackCountEquals:
                            sceneRenderInput.fallbackBaseline
                    )
                }
                var remainingGPURecoveries = sceneLayers.count
                while recoverSceneLayersFromGPUCommandFailure() {
                    guard
                        remainingGPURecoveries > 0,
                        let recoveredImage = renderSceneDocument(
                            targetRect: targetRect,
                            hostTime: sceneRenderInput.hostTime,
                            frame: sceneRenderInput.frame,
                            sourcesPrepared: true
                        )
                    else {
                        incrementDroppedFrames()
                        return false
                    }
                    guard renderSceneSurfaceCIFinalFrame(
                        image: recoveredImage,
                        to: allocatedBuffer,
                        bounds: targetRect,
                        colorSpace: outputColorSpace,
                        context: ciContext,
                        metrics: metalContext?.renderPathMetrics,
                        metricsScope: sceneMetricsScope
                    ) else {
                        incrementDroppedFrames()
                        return false
                    }
                    remainingGPURecoveries -= 1
                }
            }
            outputBuffer = allocatedBuffer
        }

        let presentationTime = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(effectiveFramesPerSecond)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: outputBuffer,
                formatDescription: formatDescription,
                sampleTiming: &timing,
                sampleBufferOut: &sampleBuffer
            ) == noErr,
            let sampleBuffer
        else {
            incrementDroppedFrames()
            return false
        }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: true
        ).map { unsafeBitCast($0, to: NSMutableArray.self) }
        if let dictionary = attachments?.firstObject as? NSMutableDictionary {
            dictionary[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        if sampleLayer.status == .failed {
            sampleLayer.flush()
        }
        sampleLayer.enqueue(sampleBuffer)
        renderedFrames += 1
        let statsTime = CACurrentMediaTime()
        if statsTime - lastStatsEmittedAt >= 1 {
            lastStatsEmittedAt = statsTime
            emit(
                type: "stats",
                framesPerSecond: currentRenderFramesPerSecond
            )
        }
        return true
    }

    private func sourceImage(
        poster: CIImage,
        targetRect: CGRect,
        forcePoster: Bool
    ) -> CIImage {
        var image = poster
        if !forcePoster,
           sourceKind == "video",
           videoPlayer != nil,
           let output = videoOutput {
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: itemTime),
               let videoBuffer = output.copyPixelBuffer(
                    forItemTime: itemTime,
                    itemTimeForDisplay: nil
               ) {
                image = CIImage(cvPixelBuffer: videoBuffer)
            }
        }
        image = aspectFill(image, targetRect: targetRect)
        guard !forcePoster, sourceKind == "procedural" else { return image }
        return applyProceduralOverlay(to: image, targetRect: targetRect)
    }

    private func aspectFill(_ image: CIImage, targetRect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image.cropped(to: targetRect)
        }
        let scale = max(
            targetRect.width / extent.width,
            targetRect.height / extent.height
        )
        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        let translated = scaled.transformed(
            by: CGAffineTransform(
                translationX: targetRect.midX - scaled.extent.midX,
                y: targetRect.midY - scaled.extent.midY
            )
        )
        return translated.cropped(to: targetRect)
    }

    private func renderSceneDocument(
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        frame: ReactiveFrame,
        sourcesPrepared: Bool = false
    ) -> CIImage? {
        guard !sceneLayers.isEmpty else { return nil }
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ).cropped(to: targetRect)

        for layer in sceneLayers {
            let source: CIImage?
            if layer.sourceKind == "procedural" {
                source = proceduralSceneLayerImage(
                    layer,
                    targetRect: targetRect,
                    hostTime: hostTime,
                    frame: frame
                )
            } else {
                source = layer.currentImage(
                    forcePoster: false,
                    hostTime: hostTime,
                    width: width,
                    height: height,
                    refreshSource: !sourcesPrepared
                )
            }
            guard
                let source,
                let normalizedSource = normalizedSceneLayerAlpha(
                    source,
                    mode: layer.alphaMode
                )
            else {
                return nil
            }

            var renderedLayer = transformSceneLayer(
                normalizedSource,
                layer: layer,
                targetRect: targetRect,
                frame: frame
            )
            renderedLayer = applySceneLayerAudio(
                renderedLayer,
                layer: layer,
                targetRect: targetRect,
                frame: frame
            )
            renderedLayer = applyOpacity(
                renderedLayer,
                opacity: layer.opacity
            )
            if layer.usesAuthoredSourceOver && layer.blendMode == "sourceOver" {
                guard let authored = try? SceneCatalogBlendKernel.sourceOver(
                    renderedLayer, background: composed, target: targetRect
                ) else { return nil }
                composed = authored
            } else {
                composed = blend(
                    renderedLayer,
                    over: composed,
                    mode: layer.blendMode,
                    targetRect: targetRect
                )
            }
        }

        return applySceneFilter(to: composed, targetRect: targetRect)
    }

    private func recoverSceneLayersFromGPUCommandFailure() -> Bool {
        var recovered = false
        for layer in sceneLayers {
            if layer.recoverFromGPUCommandFailure() {
                recovered = true
            }
        }
        return recovered
    }

    private func transformSceneLayer(
        _ input: CIImage,
        layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        frame: ReactiveFrame
    ) -> CIImage {
        let transform = layer.transform
        let width = targetRect.width * transform.width
        let height = targetRect.height * transform.height
        let layerRect = CGRect(
            x: targetRect.midX - width * 0.5 +
                targetRect.width * transform.offsetX,
            y: targetRect.midY - height * 0.5 -
                targetRect.height * transform.offsetY,
            width: width,
            height: height
        )
        var image = aspectFill(input, targetRect: layerRect)
        let binding = layer.audioBinding
        let reaction = frame.reactivity
        let pulse = min(
            max(
                1 +
                    reaction *
                    (
                        frame.bassDrive * binding.pulseBass +
                            frame.impact * binding.pulseImpact
                    ),
                0.75
            ),
            1.5
        )
        let scale = transform.scale * CGFloat(pulse)
        let horizontalScale = transform.flipped ? -scale : scale
        let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
        var affine = CGAffineTransform(
            translationX: center.x,
            y: center.y
        )
        affine = affine.rotated(by: -transform.rotation)
        affine = affine.scaledBy(x: horizontalScale, y: scale)
        affine = affine.translatedBy(x: -center.x, y: -center.y)
        image = image.transformed(by: affine)
        return image.cropped(to: targetRect)
    }

    private func applySceneLayerAudio(
        _ input: CIImage,
        layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        frame: ReactiveFrame
    ) -> CIImage {
        let binding = layer.audioBinding
        guard binding.isReactive else { return input }

        let reaction = frame.reactivity
        let brightness =
            frame.level * binding.brightnessLevel * reaction
        let contrast =
            1 + frame.impact * binding.contrastImpact * reaction
        let saturation =
            1 + frame.bodyDrive * binding.saturationBody * reaction
        var image = input.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: min(brightness, 0.35),
                kCIInputContrastKey: min(contrast, 1.8),
                kCIInputSaturationKey: min(saturation, 2.2),
            ]
        ).cropped(to: targetRect)

        let bloom =
            frame.sparkDrive * binding.bloomSpark * reaction +
            frame.hitStrength * binding.flashStrength
        if bloom > 0.01 {
            image = image.applyingFilter(
                "CIBloom",
                parameters: [
                    kCIInputRadiusKey: 3 + min(bloom, 1.5) * 10,
                    kCIInputIntensityKey: min(0.08 + bloom * 0.6, 0.9),
                ]
            ).cropped(to: targetRect)
        }
        return image
    }

    private func applyOpacity(
        _ input: CIImage,
        opacity: CGFloat
    ) -> CIImage {
        guard opacity < 0.999 else { return input }
        return input.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(
                    x: 0,
                    y: 0,
                    z: 0,
                    w: opacity
                ),
            ]
        )
    }

    private func blend(
        _ foreground: CIImage,
        over background: CIImage,
        mode: String,
        targetRect: CGRect
    ) -> CIImage {
        let filterName: String
        switch mode {
        case "screen":
            filterName = "CIScreenBlendMode"
        case "add":
            filterName = "CIAdditionCompositing"
        case "multiply":
            filterName = "CIMultiplyBlendMode"
        default:
            filterName = "CISourceOverCompositing"
        }
        return foreground.applyingFilter(
            filterName,
            parameters: [kCIInputBackgroundImageKey: background]
        ).cropped(to: targetRect)
    }

    private func proceduralSceneLayerImage(
        _ layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        frame: ReactiveFrame
    ) -> CIImage? {
        let colors = layer.palette.isEmpty
            ? [
                CIColor(red: 0.10, green: 0.86, blue: 0.92),
                CIColor(red: 0.94, green: 0.16, blue: 0.58),
                CIColor(red: 0.42, green: 0.31, blue: 1.00),
            ]
            : layer.palette
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: targetRect)

        switch layer.proceduralPreset {
        case "native_program_v1":
            return layer.nativeProgramImage(targetRect: targetRect, hostTime: hostTime)
        case "deep_void_v1":
            return CIImage(
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            ).cropped(to: targetRect)
        case SceneSurfaceStatefulStormRecipeV1.preset:
            return layer.statefulStormImage(
                targetRect: targetRect,
                hostTime: hostTime
            )
        case SceneSurfaceFirefliesRecipeV1.preset:
            return layer.firefliesImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.reactivity > 0.001,
                flowDrive: frame.flowDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceInfernoEmbersRecipeV1.preset:
            return layer.infernoEmbersImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.reactivity > 0.001,
                flowDrive: frame.flowDrive,
                bodyDrive: frame.bodyDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceRadialWarpRecipeV1.preset:
            return layer.radialWarpImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.reactivity > 0.001,
                flowDrive: frame.flowDrive,
                bassDrive: frame.bassDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceWildflowerPollenRecipeV1.preset:
            return layer.wildflowerPollenImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.reactivity > 0.001,
                flowDrive: frame.flowDrive,
                sparkDrive: frame.sparkDrive
            )
        case "aurora":
            for index in 0..<3 {
                let phase =
                    hostTime * (0.20 + Double(index) * 0.035) +
                    Double(index) * 2.1
                let wave = CGFloat((sin(phase) + 1) * 0.5)
                let color = colors[index % colors.count]
                guard let band = CIFilter(
                    name: "CILinearGradient",
                    parameters: [
                        "inputPoint0": CIVector(
                            x: -targetRect.width * 0.2,
                            y: targetRect.height * (0.18 + wave * 0.62)
                        ),
                        "inputPoint1": CIVector(
                            x: targetRect.width * 1.2,
                            y: targetRect.height * (0.72 - wave * 0.42)
                        ),
                        "inputColor0": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0
                        ),
                        "inputColor1": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0.24 +
                                CGFloat(frame.flowDrive) * 0.13
                        ),
                    ]
                )?.outputImage?.cropped(to: targetRect) else {
                    continue
                }
                composed = band.applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: composed]
                ).cropped(to: targetRect)
            }
        case "liquid_lava":
            for index in 0..<4 {
                let phase =
                    hostTime * (0.15 + Double(index) * 0.018) +
                    Double(index) * 1.7
                let xWave = CGFloat((sin(phase * 0.73) + 1) * 0.5)
                let yWave = CGFloat((cos(phase) + 1) * 0.5)
                let radiusWave = CGFloat(sin(phase * 1.3))
                let radius = targetRect.width * (
                    0.28 +
                        0.06 * radiusWave +
                        CGFloat(frame.bassDrive) * 0.07
                )
                let color = colors[index % colors.count]
                guard let blob = CIFilter(
                    name: "CIRadialGradient",
                    parameters: [
                        "inputCenter": CIVector(
                            x: targetRect.width * (0.18 + 0.64 * xWave),
                            y: targetRect.height * (0.12 + 0.76 * yWave)
                        ),
                        "inputRadius0": radius * 0.12,
                        "inputRadius1": radius,
                        "inputColor0": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0.38 +
                                CGFloat(frame.flowDrive) * 0.12
                        ),
                        "inputColor1": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0
                        ),
                    ]
                )?.outputImage?.cropped(to: targetRect) else {
                    continue
                }
                composed = blob.applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: composed]
                ).cropped(to: targetRect)
            }
        default:
            return nil
        }
        return composed
    }

    private func applySceneFilter(
        to input: CIImage,
        targetRect: CGRect
    ) -> CIImage {
        guard let filter = sceneFilter, filter.intensity > 0 else {
            return input
        }
        let amount = filter.intensity
        var image = input.applyingFilter(
            "CIExposureAdjust",
            parameters: [
                kCIInputEVKey: filter.exposure * amount,
            ]
        ).cropped(to: targetRect)
        image = image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputContrastKey:
                    1 + (filter.contrast - 1) * amount,
                kCIInputSaturationKey:
                    1 + (filter.saturation - 1) * amount,
            ]
        ).cropped(to: targetRect)
        if filter.vibrance != 0 {
            image = image.applyingFilter(
                "CIVibrance",
                parameters: [
                    "inputAmount": filter.vibrance * amount,
                ]
            ).cropped(to: targetRect)
        }
        if filter.temperature != 0 || filter.tint != 0 {
            image = image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 + filter.temperature * amount * 2200,
                        y: filter.tint * amount * 140
                    ),
                ]
            ).cropped(to: targetRect)
        }
        if filter.blackLift != 0 {
            let lift = filter.blackLift * amount
            image = image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputBiasVector": CIVector(
                        x: lift,
                        y: lift,
                        z: lift,
                        w: 0
                    ),
                ]
            ).cropped(to: targetRect)
        }
        if filter.vignette > 0 {
            image = image.applyingFilter(
                "CIVignette",
                parameters: [
                    kCIInputIntensityKey:
                        filter.vignette * amount,
                    kCIInputRadiusKey:
                        min(targetRect.width, targetRect.height) *
                        filter.vignetteSoftness,
                ]
            ).cropped(to: targetRect)
        }
        return image
    }

    private func freshReactiveFrame() -> ReactiveFrame {
        let nowMicros = Int64(Date().timeIntervalSince1970 * 1_000_000)
        stateLock.lock()
        var frame = latestFrame
        let hitMicros = latestHitMicros
        let hitStrength = latestHitStrength
        stateLock.unlock()

        let age = max(
            0,
            Double(nowMicros - frame.timestampMicros) / 1_000_000
        )
        let freshness =
            age <= 0.25 ? 1.0 : max(0, 1 - ((age - 0.25) / 0.5))
        frame.level *= freshness
        frame.impact *= freshness
        frame.bassDrive *= freshness
        frame.bodyDrive *= freshness
        frame.sparkDrive *= freshness
        frame.flowDrive *= freshness
        frame.reactivity *= freshness
        let hitAge = max(
            0,
            Double(nowMicros - hitMicros) / 1_000_000
        )
        frame.hitStrength =
            hitAge < 0.13
                ? hitStrength * (1 - hitAge / 0.13) * freshness
                : 0
        return frame
    }

    private func applyProceduralOverlay(
        to image: CIImage,
        targetRect: CGRect
    ) -> CIImage {
        let now = CACurrentMediaTime()
        stateLock.lock()
        let flow = latestFrame.flowDrive
        let bass = latestFrame.bassDrive
        stateLock.unlock()

        switch proceduralPreset {
        case "liquid_lava":
            return applyLiquidLavaOverlay(
                to: image,
                targetRect: targetRect,
                time: now,
                flow: flow,
                bass: bass
            )
        case "aurora":
            return applyAuroraOverlay(
                to: image,
                targetRect: targetRect,
                time: now,
                flow: flow
            )
        case SceneSurfaceWildflowerPollenRecipeV1.preset,
             SceneSurfaceRadialWarpRecipeV1.preset,
             "deep_void_v1":
            // This program is rendered only as a layer in the complete
            // SceneSurface graph. Legacy single-visual PiP keeps its poster.
            return image
        default:
            return applyAuroraOverlay(
                to: image,
                targetRect: targetRect,
                time: now,
                flow: flow * 0.5
            )
        }
    }

    private func applyAuroraOverlay(
        to image: CIImage,
        targetRect: CGRect,
        time: CFTimeInterval,
        flow: Double
    ) -> CIImage {
        var composed = image
        let colors = resolvedPalette
        for index in 0..<3 {
            let phase = time * (0.20 + Double(index) * 0.035) + Double(index) * 2.1
            let wave = CGFloat((sin(phase) + 1) * 0.5)
            let color = colors[index % colors.count]
            let transparent = CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0
            )
            let luminous = CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0.24 + CGFloat(flow) * 0.13
            )
            guard let band = CIFilter(
                name: "CILinearGradient",
                parameters: [
                    "inputPoint0": CIVector(
                        x: -targetRect.width * 0.2,
                        y: targetRect.height * (0.18 + wave * 0.62)
                    ),
                    "inputPoint1": CIVector(
                        x: targetRect.width * 1.2,
                        y: targetRect.height * (0.72 - wave * 0.42)
                    ),
                    "inputColor0": transparent,
                    "inputColor1": luminous,
                ]
            )?.outputImage?.cropped(to: targetRect) else { continue }
            composed = band.applyingFilter(
                "CIScreenBlendMode",
                parameters: [kCIInputBackgroundImageKey: composed]
            ).cropped(to: targetRect)
        }
        return composed
    }

    private func applyLiquidLavaOverlay(
        to image: CIImage,
        targetRect: CGRect,
        time: CFTimeInterval,
        flow: Double,
        bass: Double
    ) -> CIImage {
        var composed = image
        let colors = resolvedPalette
        for index in 0..<4 {
            let phase = time * (0.15 + Double(index) * 0.018) + Double(index) * 1.7
            let xWave = CGFloat((sin(phase * 0.73) + 1) * 0.5)
            let yWave = CGFloat((cos(phase) + 1) * 0.5)
            let radiusWave = CGFloat(sin(phase * 1.3))
            let x = targetRect.width * (0.18 + 0.64 * xWave)
            let y = targetRect.height * (0.12 + 0.76 * yWave)
            let radius = targetRect.width * (
                0.28 + 0.06 * radiusWave + CGFloat(bass) * 0.07
            )
            let color = colors[index % colors.count]
            let core = CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0.38 + CGFloat(flow) * 0.12
            )
            let edge = CIColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: 0
            )
            guard let blob = CIFilter(
                name: "CIRadialGradient",
                parameters: [
                    "inputCenter": CIVector(x: x, y: y),
                    "inputRadius0": radius * 0.12,
                    "inputRadius1": radius,
                    "inputColor0": core,
                    "inputColor1": edge,
                ]
            )?.outputImage?.cropped(to: targetRect) else { continue }
            composed = blob.applyingFilter(
                "CIScreenBlendMode",
                parameters: [kCIInputBackgroundImageKey: composed]
            ).cropped(to: targetRect)
        }
        return composed
    }

    private var resolvedPalette: [CIColor] {
        if !palette.isEmpty { return palette }
        return [
            CIColor(red: 0.10, green: 0.86, blue: 0.92),
            CIColor(red: 0.94, green: 0.16, blue: 0.58),
            CIColor(red: 0.42, green: 0.31, blue: 1.00),
        ]
    }

    private func clearPreparedContent() {
        prepareGeneration += 1
        cancelPendingStart()
        stopWatchdog?.cancel()
        stopWatchdog = nil
        stopWatchdogAttempts = 0
        stopCompletionPending = false
        stopRenderTimer()
        pauseDynamicSources()
        renderQueue.sync {}
        tearDownVideo()
        releaseRendererSessionIfNeeded()
        releaseV2SharedSourceIfNeeded()
        tearDownSceneDocument()
        sampleLayer.flushAndRemoveImage()
        detachSampleLayer()
        pixelBufferPool = nil
        formatDescription = nil
        timebase = nil
        posterImage = nil
        sourceKind = "poster"
        prepared = false
        sessionId = nil
        lifecycleState = .idle
        stopRequestedDuringStart = false
        observedBackgroundSinceStart = false
        foregroundStopRequested = false
    }

    private func releaseRendererSessionIfNeeded() {
        guard let rendererSessionId else { return }
        self.rendererSessionId = nil
        renderEngine.releasePictureInPicture(sessionId: rendererSessionId)
    }

    private func releaseV2SharedSourceIfNeeded() {
        if let v1SharedSource {
            self.v1SharedSource = nil
            v1ConvertedBuffer = nil
            v1ConvertedRevision = nil
            sceneSurfaceEngine.releasePictureInPictureSource(v1SharedSource)
        }
        guard let v2SharedSessionId else { return }
        v2FairDeadlineWorkItem?.cancel()
        v2FairDeadlineWorkItem = nil
        v2CriticalDeadlineWorkItem?.cancel()
        v2CriticalDeadlineWorkItem = nil
        v2QualityTransitionInFlight = false
        v2RecoveryWorkItem?.cancel()
        v2RecoveryWorkItem = nil
        v2EmergencyRecoveryActive = false
        self.v2SharedSessionId = nil
        v2ImageRuntime.setPictureInPictureSourcePlaying(
            sessionID: v2SharedSessionId,
            playing: false
        )
        v2ImageRuntime.releasePictureInPictureSource(
            sessionID: v2SharedSessionId
        )
    }

    private func acknowledgeContinuationCleanup(_ completion: @escaping () -> Void) {
        sceneSurfaceEngine.acknowledgePictureInPictureCleanup { [weak self] in
            guard let self else { completion(); return }
            self.v2ImageRuntime.acknowledgePictureInPictureCleanup(completion: completion)
        }
    }

    private func tearDown() {
        clearPreparedContent()
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
    }

    private func emit(
        type: String,
        message: String? = nil,
        playing: Bool? = nil,
        framesPerSecond: Int? = nil
    ) {
        stateLock.lock()
        let droppedFrameCount = droppedFrames
        stateLock.unlock()
        var event: [String: Any] = [
            "type": type,
            "droppedFrames": droppedFrameCount,
            // The shared V2 backend is still a scene composition on the wire;
            // its internal identity must not become an unknown Dart enum case.
            "sourceKind": (sourceKind == "sceneV2Shared" || sourceKind == "sceneV1Shared") ? "sceneComposition" : sourceKind,
        ]
        if let sessionId { event["sessionId"] = sessionId }
        if let message { event["message"] = message }
        if let playing { event["playing"] = playing }
        if let framesPerSecond { event["framesPerSecond"] = framesPerSecond }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    private static func unit(_ value: Any?) -> Double {
        min(max((value as? NSNumber)?.doubleValue ?? 0, 0), 1)
    }

    private func incrementDroppedFrames() {
        stateLock.lock()
        droppedFrames += 1
        stateLock.unlock()
    }

    private static func decodePalette(_ value: Any?) -> [CIColor] {
        guard let values = value as? [NSNumber] else { return [] }
        return values.prefix(4).map { number in
            let argb = UInt32(truncating: number)
            return sceneSurfaceColor(fromARGB: argb)
        }
    }
}

@available(iOS 15.0, *)
extension PictureInPictureHandler: FlutterStreamHandler {
    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

@available(iOS 15.0, *)
extension PictureInPictureHandler: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        lifecycleState = .starting
        NSLog("[MusicVibePiP] will start")
        stopRenderTimer()
        if playbackActive && !stopRequestedDuringStart {
            startRenderTimer()
            playDynamicSources()
        } else {
            pauseDynamicSources()
        }
        emit(type: "willStart")
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        lifecycleState = .active
        if sourceKind == "sceneV2Shared" {
            handleSharedV2ThermalStateChange()
        }
        NSLog("[MusicVibePiP] did start")
        let result = takePendingStartResult()
        emit(
            type: "started",
            playing: playbackActive,
            framesPerSecond: effectiveFramesPerSecond
        )
        result?(true)
        if stopRequestedDuringStart {
            beginStopping(pictureInPictureController, reason: stoppingReason)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        NSLog(
            "[MusicVibePiP] native start failed: %@",
            error.localizedDescription
        )
        stopRenderTimer()
        pauseDynamicSources()
        detachSampleLayer()
        stopWatchdog?.cancel()
        stopWatchdog = nil
        stopWatchdogAttempts = 0
        lifecycleState = .idle
        let wasStopping = stopRequestedDuringStart
        stopRequestedDuringStart = false
        stopCompletionPending = false
        observedBackgroundSinceStart = false
        emit(type: "startFailed", message: error.localizedDescription)
        takePendingStartResult()?(false)
        if wasStopping {
            emit(type: "stopped", message: stoppingReason)
            stoppingReason = "system"
        }
    }

    func pictureInPictureControllerWillStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        guard
            lifecycleState != .idle ||
                pictureInPictureController.isPictureInPictureActive
        else { return }
        lifecycleState = .stopping
        stopCompletionPending = true
        stopRenderTimer()
        pauseDynamicSources()
        NSLog("[MusicVibePiP] will stop reason=%@", stoppingReason)
        emit(type: "willStop", message: stoppingReason)
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        NSLog("[MusicVibePiP] did stop reason=%@", stoppingReason)
        cancelPendingStart()
        completeStop(reason: stoppingReason)
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        emit(type: "restoreRequested")
        completionHandler(true)
    }
}

@available(iOS 15.0, *)
extension PictureInPictureHandler: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        let shouldForwardIntent = PictureInPicturePlaybackIntentGate.shouldForward(
            lifecycleActive: lifecycleState == .active,
            foregroundStopRequested: foregroundStopRequested,
            stopRequestedDuringStart: stopRequestedDuringStart
        )
        setPlaybackActive(playing, emitPlaybackIntent: shouldForwardIntent)
        if !shouldForwardIntent {
            NSLog(
                "[MusicVibePiP] ignored playback callback during transition " +
                    "state=%@ foregroundStop=%@ startStop=%@ playing=%@",
                lifecycleState.rawValue,
                foregroundStopRequested.description,
                stopRequestedDuringStart.description,
                playing.description
            )
        }
    }

    func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        !playbackActive
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {
        emit(
            type: "thermalStateChanged",
            message: "render_\(newRenderSize.width)x\(newRenderSize.height)",
            framesPerSecond: effectiveFramesPerSecond
        )
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

final class PictureInPictureHandlerUnavailable: NSObject, FlutterStreamHandler {
    func register(with messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(
            name: "com.chic.dev/picture_in_picture",
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "isSupported", "prepare", "start", "stop": result(false)
            case "prepareWithSceneContinuation": result(nil)
            case "releaseSceneContinuation":
                result(FlutterError(code: "continuation_unavailable", message: "Native continuation is unavailable.", details: nil))
            case "release", "setAutomaticStartEnabled", "setPlaybackActive",
                 "updateReactiveFrame", "dispose": result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        }
        FlutterEventChannel(
            name: "com.chic.dev/picture_in_picture/events",
            binaryMessenger: messenger
        ).setStreamHandler(self)
    }

    func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? { nil }

    func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}

// MARK: - Foreground scene surface renderer

@available(iOS 15.0, *)
private final class SceneSurfaceRGBGainEffectRuntime {
    let flowGain: Double
    let sparkGain: Double
    let maxGain: Double
    let flowAttack: Double
    let flowRelease: Double
    let sparkAttack: Double
    let sparkRelease: Double
    let framesPerSecond: Int

    private var flowEnvelope = 0.0
    private var sparkEnvelope = 0.0
    private var lastUpdateTime: CFTimeInterval = 0

    private init(
        flowGain: Double,
        sparkGain: Double,
        maxGain: Double,
        flowAttack: Double,
        flowRelease: Double,
        sparkAttack: Double,
        sparkRelease: Double,
        framesPerSecond: Int
    ) {
        self.flowGain = flowGain
        self.sparkGain = sparkGain
        self.maxGain = maxGain
        self.flowAttack = flowAttack
        self.flowRelease = flowRelease
        self.sparkAttack = sparkAttack
        self.sparkRelease = sparkRelease
        self.framesPerSecond = framesPerSecond
    }

    static func isNone(_ definition: [String: Any]) -> Bool {
        effectKind(definition) == "none"
    }

    static func decode(
        _ definition: [String: Any]
    ) -> SceneSurfaceRGBGainEffectRuntime? {
        guard effectKind(definition) == "rgb_gain_v1" else { return nil }
        let values = definition["parameters"] as? [String: Any] ?? definition
        let flowGain = bounded(
            values["flowGain"],
            fallback: 0.04,
            minimum: 0,
            maximum: 0.10
        )
        let sparkGain = bounded(
            values["sparkGain"],
            fallback: 0.08,
            minimum: 0,
            maximum: 0.10
        )
        let maxGain = bounded(
            values["maxGain"],
            fallback: 0.10,
            minimum: 0,
            maximum: 0.10
        )
        guard maxGain > 0, flowGain > 0 || sparkGain > 0 else { return nil }
        return SceneSurfaceRGBGainEffectRuntime(
            flowGain: flowGain,
            sparkGain: sparkGain,
            maxGain: maxGain,
            flowAttack: milliseconds(
                values["flowAttackMs"],
                fallback: 400
            ),
            flowRelease: milliseconds(
                values["flowReleaseMs"],
                fallback: 1400
            ),
            sparkAttack: milliseconds(
                values["sparkAttackMs"],
                fallback: 80
            ),
            sparkRelease: milliseconds(
                values["sparkReleaseMs"],
                fallback: 550
            ),
            framesPerSecond: integer(
                values["framesPerSecond"],
                fallback: 30,
                minimum: 1,
                maximum: 60
            )
        )
    }

    var atRest: Bool {
        flowEnvelope == 0 && sparkEnvelope == 0
    }

    func needsFrames(for frame: SceneSurfaceReactiveFrame) -> Bool {
        frame.shouldReact || !atRest
    }

    func sample(
        frame: SceneSurfaceReactiveFrame,
        hostTime: CFTimeInterval
    ) {
        let rawDelta = lastUpdateTime == 0
            ? 1 / Double(framesPerSecond)
            : hostTime - lastUpdateTime
        lastUpdateTime = hostTime
        let delta = rawDelta.isFinite ? min(max(rawDelta, 0), 0.25) : 0
        let flowTarget = frame.shouldReact ? Self.unit(frame.flowDrive) : 0
        let sparkTarget = frame.shouldReact ? Self.unit(frame.sparkDrive) : 0
        flowEnvelope = smooth(
            current: flowEnvelope,
            target: flowTarget,
            delta: delta,
            attack: flowAttack,
            release: flowRelease
        )
        sparkEnvelope = smooth(
            current: sparkEnvelope,
            target: sparkTarget,
            delta: delta,
            attack: sparkAttack,
            release: sparkRelease
        )
        if flowTarget == 0, flowEnvelope < 0.0001 { flowEnvelope = 0 }
        if sparkTarget == 0, sparkEnvelope < 0.0001 { sparkEnvelope = 0 }
    }

    var gain: Double {
        1 + min(
            maxGain,
            flowEnvelope * flowGain + sparkEnvelope * sparkGain
        )
    }

    func reset() {
        flowEnvelope = 0
        sparkEnvelope = 0
        lastUpdateTime = 0
    }

    private func smooth(
        current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0, current != target else { return current }
        let timeConstant = max(target > current ? attack : release, 0.001)
        let amount = 1 - exp(-delta / timeConstant)
        return current + (target - current) * amount
    }

    private static func effectKind(_ definition: [String: Any]) -> String? {
        (definition["kind"] as? String) ?? (definition["engine"] as? String)
    }

    private static func milliseconds(_ value: Any?, fallback: Int) -> Double {
        Double(integer(value, fallback: fallback, minimum: 16, maximum: 5000))
            / 1000
    }

    private static func integer(
        _ value: Any?,
        fallback: Int,
        minimum: Int,
        maximum: Int
    ) -> Int {
        let parsed: Int
        if let number = value as? NSNumber {
            parsed = number.intValue
        } else if let text = value as? String, let number = Int(text) {
            parsed = number
        } else {
            parsed = fallback
        }
        return min(max(parsed, minimum), maximum)
    }

    private static func bounded(
        _ value: Any?,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let parsed: Double
        if let number = value as? NSNumber {
            parsed = number.doubleValue
        } else if let text = value as? String, let number = Double(text) {
            parsed = number
        } else {
            parsed = fallback
        }
        let finite = parsed.isFinite ? parsed : fallback
        return min(max(finite, minimum), maximum)
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

@available(iOS 15.0, *)
private final class SceneSurfaceNaturalReactiveLightEffectRuntime {
    let framesPerSecond = 30

    private static let kernel = CIColorKernel(source: """
        kernel vec4 naturalReactiveLight(
            __sample source,
            vec2 origin,
            vec2 size,
            float flow,
            float spark,
            float auroraTop,
            float auroraBottom,
            float waveTop,
            float waveBottom,
            float auroraGreenThreshold,
            float waveCyanThreshold,
            float waveBlueMinimum,
            float profile,
            float celestialTop,
            float celestialBottom,
            float nebulaLumaThreshold,
            float nebulaChromaThreshold,
            float starLumaThreshold
        ) {
            vec2 uv = (destCoord() - origin) / size;
            uv.y = 1.0 - uv.y;
            vec4 color = unpremultiply(source);
            float auroraZone = smoothstep(auroraTop, auroraTop + 0.065, uv.y) *
                (1.0 - smoothstep(auroraBottom - 0.065, auroraBottom, uv.y));
            float waveZone = smoothstep(waveTop, waveTop + 0.055, uv.y) *
                (1.0 - smoothstep(waveBottom - 0.055, waveBottom, uv.y));
            float aurora = smoothstep(
                auroraGreenThreshold,
                auroraGreenThreshold + 0.185,
                color.g - color.r
            );
            aurora *= smoothstep(-0.08, 0.15, color.g - color.b);
            aurora *= smoothstep(0.16, 0.68, color.g) * auroraZone;
            float wave = smoothstep(
                waveCyanThreshold,
                waveCyanThreshold + 0.24,
                color.b - color.r
            );
            wave *= smoothstep(0.025, 0.18, color.g - color.r);
            wave *= smoothstep(
                waveBlueMinimum,
                min(waveBlueMinimum + 0.50, 1.0),
                color.b
            ) * waveZone;
            float celestialZone = smoothstep(
                celestialTop,
                celestialTop + 0.065,
                uv.y
            ) * (1.0 - smoothstep(
                celestialBottom - 0.065,
                celestialBottom,
                uv.y
            ));
            float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            float peak = max(max(color.r, color.g), color.b);
            float trough = min(min(color.r, color.g), color.b);
            float nebula = smoothstep(
                nebulaLumaThreshold,
                min(nebulaLumaThreshold + 0.34, 1.0),
                luma
            );
            nebula *= smoothstep(
                nebulaChromaThreshold,
                min(nebulaChromaThreshold + 0.24, 1.0),
                peak - trough
            ) * celestialZone;
            float warmCore = smoothstep(
                0.02,
                0.14,
                color.r - max(color.g, color.b)
            );
            float highlightProtection = 1.0 - smoothstep(0.62, 0.82, luma);
            nebula *= (1.0 - warmCore) * highlightProtection;
            float star = smoothstep(
                starLumaThreshold,
                min(starLumaThreshold + 0.20, 1.0),
                peak
            );
            star *= smoothstep(
                starLumaThreshold * 0.72,
                starLumaThreshold,
                luma
            );
            float starNeutral = 1.0 - smoothstep(
                0.12,
                0.35,
                peak - trough
            );
            float starHighlightProtection = 1.0 - smoothstep(
                0.82,
                0.96,
                luma
            );
            star *= starNeutral * starHighlightProtection * celestialZone;
            if (profile > 0.5) {
                float celestialField = smoothstep(0.06, 0.24, luma) *
                    (1.0 - smoothstep(0.48, 0.72, luma)) * celestialZone;
                float auroraDrive = flow * 1.10 + spark * 0.70;
                float nebulaDrive = flow * 0.50 + spark * 0.65;
                color.rgb += aurora * auroraDrive * vec3(0.060, 0.850, 0.300);
                color.rgb += nebula * nebulaDrive * vec3(0.180, 0.110, 0.260);
                color.rgb *= 1.0 + celestialField * spark * 0.42;
                color.rgb *= 1.0 + nebula * spark * 0.18;
                color.rgb *= 1.0 + star * (spark * 1.25 + flow * 0.15);
                color.rgb += star * spark * vec3(0.080, 0.120, 0.180);
                color.rgb = clamp(color.rgb, 0.0, 1.0);
                return premultiply(color);
            }
            float waveGain = wave * (flow * 0.75 + spark * 1.60);
            color.rgb *= 1.0 + waveGain;
            color.rgb += wave * spark * vec3(0.040, 0.160, 0.250);
            color.rgb += aurora * flow * vec3(0.120, 0.950, 0.400);
            color.rgb = clamp(color.rgb, 0.0, 1.0);
            return premultiply(color);
        }
        """)

    private let flowGain: Double
    private let sparkGain: Double
    private let flowAttack: Double
    private let flowRelease: Double
    private let sparkAttack: Double
    private let sparkRelease: Double
    private let auroraTop: Double
    private let auroraBottom: Double
    private let waveTop: Double
    private let waveBottom: Double
    private let auroraGreenThreshold: Double
    private let waveCyanThreshold: Double
    private let waveBlueMinimum: Double
    private let celestialProfile: Bool
    private let celestialTop: Double
    private let celestialBottom: Double
    private let nebulaLumaThreshold: Double
    private let nebulaChromaThreshold: Double
    private let starLumaThreshold: Double
    private var flowEnvelope = 0.0
    private var sparkEnvelope = 0.0
    private var lastUpdateTime: CFTimeInterval = 0

    private init(
        flowGain: Double,
        sparkGain: Double,
        flowAttack: Double,
        flowRelease: Double,
        sparkAttack: Double,
        sparkRelease: Double,
        auroraTop: Double,
        auroraBottom: Double,
        waveTop: Double,
        waveBottom: Double,
        auroraGreenThreshold: Double,
        waveCyanThreshold: Double,
        waveBlueMinimum: Double,
        celestialProfile: Bool,
        celestialTop: Double,
        celestialBottom: Double,
        nebulaLumaThreshold: Double,
        nebulaChromaThreshold: Double,
        starLumaThreshold: Double
    ) {
        self.flowGain = flowGain
        self.sparkGain = sparkGain
        self.flowAttack = flowAttack
        self.flowRelease = flowRelease
        self.sparkAttack = sparkAttack
        self.sparkRelease = sparkRelease
        self.auroraTop = auroraTop
        self.auroraBottom = auroraBottom
        self.waveTop = waveTop
        self.waveBottom = waveBottom
        self.auroraGreenThreshold = auroraGreenThreshold
        self.waveCyanThreshold = waveCyanThreshold
        self.waveBlueMinimum = waveBlueMinimum
        self.celestialProfile = celestialProfile
        self.celestialTop = celestialTop
        self.celestialBottom = celestialBottom
        self.nebulaLumaThreshold = nebulaLumaThreshold
        self.nebulaChromaThreshold = nebulaChromaThreshold
        self.starLumaThreshold = starLumaThreshold
    }

    static func decode(
        _ definition: [String: Any]
    ) -> SceneSurfaceNaturalReactiveLightEffectRuntime? {
        guard effectKind(definition) == "natural_reactive_light_v1" else {
            return nil
        }
        let values = definition["parameters"] as? [String: Any] ?? definition
        let profile = values["profile"] as? String ?? "coastal"
        guard profile == "coastal" || profile == "celestial" else {
            return nil
        }
        let flowGain = bounded(
            values["flowGain"], fallback: 0.13, minimum: 0, maximum: 0.24
        )
        let sparkGain = bounded(
            values["sparkGain"], fallback: 0.26, minimum: 0, maximum: 0.65
        )
        let auroraTop = bounded(
            values["auroraTop"], fallback: 0.20, minimum: 0, maximum: 0.9
        )
        let auroraBottom = bounded(
            values["auroraBottom"], fallback: 0.58, minimum: 0.1, maximum: 1
        )
        let waveTop = bounded(
            values["waveTop"], fallback: 0.59, minimum: 0, maximum: 0.95
        )
        let waveBottom = bounded(
            values["waveBottom"], fallback: 1, minimum: 0.1, maximum: 1
        )
        let celestialTop = bounded(
            values["celestialTop"], fallback: 0, minimum: 0, maximum: 0.9
        )
        let celestialBottom = bounded(
            values["celestialBottom"], fallback: 0.75, minimum: 0.1, maximum: 1
        )
        guard
            flowGain > 0 || sparkGain > 0,
            auroraTop < auroraBottom,
            waveTop < waveBottom,
            celestialTop < celestialBottom
        else {
            return nil
        }
        return SceneSurfaceNaturalReactiveLightEffectRuntime(
            flowGain: flowGain,
            sparkGain: sparkGain,
            flowAttack: milliseconds(values["flowAttackMs"], fallback: 280),
            flowRelease: milliseconds(values["flowReleaseMs"], fallback: 1100),
            sparkAttack: milliseconds(values["sparkAttackMs"], fallback: 55),
            sparkRelease: milliseconds(values["sparkReleaseMs"], fallback: 420),
            auroraTop: auroraTop,
            auroraBottom: auroraBottom,
            waveTop: waveTop,
            waveBottom: waveBottom,
            auroraGreenThreshold: bounded(
                values["auroraGreenThreshold"],
                fallback: 0.055,
                minimum: 0,
                maximum: 0.5
            ),
            waveCyanThreshold: bounded(
                values["waveCyanThreshold"],
                fallback: 0.13,
                minimum: 0,
                maximum: 0.6
            ),
            waveBlueMinimum: bounded(
                values["waveBlueMinimum"],
                fallback: 0.32,
                minimum: 0,
                maximum: 0.8
            ),
            celestialProfile: profile == "celestial",
            celestialTop: celestialTop,
            celestialBottom: celestialBottom,
            nebulaLumaThreshold: bounded(
                values["nebulaLumaThreshold"],
                fallback: 0.18,
                minimum: 0.02,
                maximum: 0.8
            ),
            nebulaChromaThreshold: bounded(
                values["nebulaChromaThreshold"],
                fallback: 0.10,
                minimum: 0,
                maximum: 0.8
            ),
            starLumaThreshold: bounded(
                values["starLumaThreshold"],
                fallback: 0.70,
                minimum: 0.2,
                maximum: 0.98
            )
        )
    }

    var atRest: Bool {
        flowEnvelope == 0 && sparkEnvelope == 0
    }

    func needsFrames(for frame: SceneSurfaceReactiveFrame) -> Bool {
        frame.shouldReact || !atRest
    }

    func sample(
        frame: SceneSurfaceReactiveFrame,
        hostTime: CFTimeInterval
    ) {
        update(frame: frame, hostTime: hostTime)
    }

    func apply(to input: CIImage) -> CIImage {
        let flowSignal = celestialProfile
            ? flowEnvelope * flowEnvelope
            : flowEnvelope
        let sparkSignal = celestialProfile
            ? sparkEnvelope * sparkEnvelope
            : sparkEnvelope
        let flow = flowSignal * flowGain
        let spark = sparkSignal * sparkGain
        guard flow > 0.00001 || spark > 0.00001 else { return input }
        guard let kernel = Self.kernel else {
            return input.applyingFilter(
                "CIExposureAdjust",
                parameters: [kCIInputEVKey: min(flow + spark, 0.18)]
            ).cropped(to: input.extent)
        }
        let extent = input.extent
        return kernel.apply(
            extent: extent,
            arguments: [
                input,
                CIVector(x: extent.minX, y: extent.minY),
                CIVector(x: extent.width, y: extent.height),
                flow,
                spark,
                auroraTop,
                auroraBottom,
                waveTop,
                waveBottom,
                auroraGreenThreshold,
                waveCyanThreshold,
                waveBlueMinimum,
                celestialProfile ? 1.0 : 0.0,
                celestialTop,
                celestialBottom,
                nebulaLumaThreshold,
                nebulaChromaThreshold,
                starLumaThreshold,
            ]
        )?.cropped(to: extent) ?? input
    }

    func reset() {
        flowEnvelope = 0
        sparkEnvelope = 0
        lastUpdateTime = 0
    }

    private func update(
        frame: SceneSurfaceReactiveFrame,
        hostTime: CFTimeInterval
    ) {
        let rawDelta = lastUpdateTime == 0
            ? 1 / Double(framesPerSecond)
            : hostTime - lastUpdateTime
        lastUpdateTime = hostTime
        let delta = rawDelta.isFinite ? min(max(rawDelta, 0), 0.25) : 0
        let flowTarget = frame.shouldReact
            ? shapedTarget(frame.flowDrive, flowSignal: true)
            : 0
        let sparkTarget = frame.shouldReact
            ? shapedTarget(frame.sparkDrive, flowSignal: false)
            : 0
        flowEnvelope = Self.smooth(
            current: flowEnvelope,
            target: flowTarget,
            delta: delta,
            attack: flowAttack,
            release: flowRelease
        )
        sparkEnvelope = Self.smooth(
            current: sparkEnvelope,
            target: sparkTarget,
            delta: delta,
            attack: sparkAttack,
            release: sparkRelease
        )
        if flowTarget == 0, flowEnvelope < 0.0001 { flowEnvelope = 0 }
        if sparkTarget == 0, sparkEnvelope < 0.0001 { sparkEnvelope = 0 }
    }

    private func shapedTarget(
        _ value: Double,
        flowSignal: Bool
    ) -> Double {
        let unit = Self.unit(value)
        guard celestialProfile else { return unit }
        let lower = flowSignal ? 0.30 : 0.10
        let upper = flowSignal ? 0.50 : 0.70
        let normalized = min(max((unit - lower) / (upper - lower), 0), 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private static func effectKind(_ definition: [String: Any]) -> String? {
        (definition["kind"] as? String) ?? (definition["engine"] as? String)
    }

    private static func milliseconds(_ value: Any?, fallback: Int) -> Double {
        Double(integer(value, fallback: fallback, minimum: 16, maximum: 5000))
            / 1000
    }

    private static func integer(
        _ value: Any?,
        fallback: Int,
        minimum: Int,
        maximum: Int
    ) -> Int {
        let parsed = (value as? NSNumber)?.intValue ??
            (value as? String).flatMap(Int.init) ?? fallback
        return min(max(parsed, minimum), maximum)
    }

    private static func bounded(
        _ value: Any?,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let parsed = (value as? NSNumber)?.doubleValue ??
            (value as? String).flatMap(Double.init) ?? fallback
        return min(max(parsed.isFinite ? parsed : fallback, minimum), maximum)
    }

    private static func unit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func smooth(
        current: Double,
        target: Double,
        delta: Double,
        attack: Double,
        release: Double
    ) -> Double {
        guard delta > 0, current != target else { return current }
        let timeConstant = max(target > current ? attack : release, 0.001)
        return current + (target - current) *
            (1 - exp(-delta / timeConstant))
    }
}

@available(iOS 15.0, *)
private struct SceneSurfaceReactiveFrame {
    var timestampMicros: Int64 = 0
    var shouldReact = false
    var level = 0.0
    var impact = 0.0
    var hitStrength = 0.0
    var bassDrive = 0.0
    var bodyDrive = 0.0
    var sparkDrive = 0.0
    var flowDrive = 0.0
    var reactivity = 0.0

    init() {}

    init(arguments: [String: Any]) {
        timestampMicros =
            (arguments["timestampMicros"] as? NSNumber)?.int64Value ?? 0
        shouldReact = arguments["shouldReact"] as? Bool ?? false
        guard shouldReact else { return }
        level = Self.unit(arguments["level"])
        impact = Self.unit(arguments["impactStrength"])
        hitStrength = Self.unit(arguments["flashStrength"])
        bassDrive = Self.unit(arguments["bassDrive"])
        bodyDrive = Self.unit(arguments["bodyDrive"])
        sparkDrive = Self.unit(arguments["sparkDrive"])
        flowDrive = Self.unit(arguments["flowDrive"])
        reactivity = Self.unit(arguments["reactivity"])
        if arguments["flashActive"] as? Bool != true {
            hitStrength = min(hitStrength, 0.32)
        }
    }

    func freshened(nowMicros: Int64) -> SceneSurfaceReactiveFrame {
        guard timestampMicros > 1_000_000_000_000 else { return self }
        let age = max(0, Double(nowMicros - timestampMicros) / 1_000_000)
        let freshness = age <= 0.25
            ? 1.0
            : max(0, 1 - ((age - 0.25) / 0.5))
        var frame = self
        frame.level *= freshness
        frame.impact *= freshness
        frame.hitStrength *= freshness
        frame.bassDrive *= freshness
        frame.bodyDrive *= freshness
        frame.sparkDrive *= freshness
        frame.flowDrive *= freshness
        frame.reactivity *= freshness
        if freshness == 0 { frame.shouldReact = false }
        return frame
    }

    private static func unit(_ value: Any?) -> Double {
        guard let parsed = (value as? NSNumber)?.doubleValue,
              parsed.isFinite else {
            return 0
        }
        return min(max(parsed, 0), 1)
    }
}

@available(iOS 15.0, *)
private final class SceneSurfaceLayerLease {
    let layer: PictureInPictureSceneLayerRuntime
    var sourceIdentity: Data

    init(layer: PictureInPictureSceneLayerRuntime, sourceIdentity: Data) {
        self.layer = layer
        self.sourceIdentity = sourceIdentity
    }

    deinit { layer.tearDown() }
}

/// Presentation edits never change a source. Local-file metadata is included
/// so replacing a downloaded file at the same path cannot reuse its old player.
enum SceneSurfaceLayerSourceIdentity {
    static func key(_ definition: [String: Any]) -> Data? {
        var source = definition
        source.removeValue(forKey: "opacity")
        source.removeValue(forKey: "transform")
        if let path = source["path"] as? String {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date,
                  let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
            source["localFileIdentity"] = ["bytes": size, "inode": inode,
                "modified": modified.timeIntervalSinceReferenceDate]
        }
        return try? JSONSerialization.data(withJSONObject: source, options: [.sortedKeys])
    }
}

@available(iOS 15.0, *)
private final class SceneSurfaceDocumentRuntime {
    struct SuspendedVideo {
        let layer: PictureInPictureSceneLayerRuntime
        let time: CMTime
    }
    let sceneId: String
    private(set) var layers: [PictureInPictureSceneLayerRuntime]
    var filterState: SceneRenderV2ImageSurfaceRuntime.NativeFilterTransition
    private var unfilteredOnePassLayers: SceneSurfaceOnePassLayers?
    var onePassLayers: SceneSurfaceOnePassLayers? {
        filterState.needsGrade ? nil : unfilteredOnePassLayers
    }
    private var definition: [String: Any]
    private var sourceLeases = [SceneSurfaceLayerLease]()
    private var borrowedPresentationUpdates = [SceneCatalogControlUpdate]()
    private var borrowedPresentationApplied = false

    init?(
        definition: [String: Any],
        renderEngine: MusicVibeRenderEngine,
        metalContext: SceneSurfaceMetalContext?,
        metricsScope: String? = nil,
        constructionMode: SceneSurfaceDocumentConstructionMode = .runtime,
        reusing previous: SceneSurfaceDocumentRuntime? = nil,
        inspectedVideos: [String: SceneSurfaceVideoAssetInspection]? = nil,
        inspectionContext suppliedContext: SceneSurfaceInspectionContext? = nil
    ) {
        guard
            (definition["schemaVersion"] as? NSNumber)?.intValue == 1,
            let sceneId = definition["sceneId"] as? String,
            !sceneId.isEmpty,
            let layerDefinitions = definition["layers"] as? [[String: Any]],
            !layerDefinitions.isEmpty,
            layerDefinitions.count <= 32,
            layerDefinitions.allSatisfy(sceneSurfaceLayerSemanticsAreExplicit),
            sceneSurfaceVideoLayerCountIsSupported(layerDefinitions,
                maximum: SceneSurfaceVideoAdmission.current.limit,
                maximumAlpha: SceneSurfaceVideoAdmission.current.limit,
                maximumAlphaWithPackedSource: SceneSurfaceVideoAdmission.current.limit)
        else {
            return nil
        }

        var parsedLayers = [PictureInPictureSceneLayerRuntime]()
        var parsedLeases = [SceneSurfaceLayerLease]()
        var presentationUpdates = [SceneCatalogControlUpdate]()
        var layerIds = Set<String>()
        var backgroundCount = 0
        var encounteredOverlay = false

        let stableRasterBudget = SceneSurfaceStableRasterBudget()
        let inspectionContext = suppliedContext ?? SceneSurfaceInspectionContext(timeout: 2)
        for layerDefinition in layerDefinitions {
            guard !inspectionContext.isCancelled else { return nil }
            guard
                let blendMode = layerDefinition["blendMode"] as? String,
                ["sourceOver", "screen", "add", "multiply"].contains(
                    blendMode
                ),
                let id = layerDefinition["id"] as? String,
                layerIds.insert(id).inserted,
                let identity = SceneSurfaceLayerSourceIdentity.key(layerDefinition)
            else { return nil }
            let lease: SceneSurfaceLayerLease
            if previous?.sceneId == sceneId,
               let retained = previous?.sourceLeases.first(where: {
                   $0.layer.id == id && $0.sourceIdentity == identity
               }),
               let presentation = retained.layer.preparePresentationUpdate(definition: layerDefinition) {
                lease = retained
                presentationUpdates.append(presentation)
            } else {
                guard let layer = PictureInPictureSceneLayerRuntime(
                    definition: layerDefinition,
                    renderEngine: renderEngine,
                    metalContext: metalContext,
                    metricsScope: metricsScope,
                    constructionMode: constructionMode,
                    stableRasterBudget: stableRasterBudget,
                    inspectedVideos: inspectedVideos,
                    inspectionContext: inspectionContext
                ) else { return nil }
                lease = SceneSurfaceLayerLease(layer: layer, sourceIdentity: identity)
            }
            let layer = lease.layer
            if layer.role == "background" {
                backgroundCount += 1
                if backgroundCount > 1 || encounteredOverlay {
                    return nil
                }
            } else {
                encounteredOverlay = true
            }
            parsedLayers.append(layer)
            parsedLeases.append(lease)
        }

        guard SceneSurfaceVideoAdmission.supports(parsedLayers.compactMap { layer in
            layer.videoInspection.map { ($0, layer.alphaMode) }
        }) else { return nil }

        let parsedFilter: SceneRenderV2ImageSurfaceRuntime.NativeFilter
        if let filterDefinition = definition["filter"] as? [String: Any] {
            guard
                let filter = SceneRenderV2ImageSurfaceRuntime.NativeFilter(
                    definition: filterDefinition
                )
            else {
                return nil
            }
            parsedFilter = filter
        } else {
            guard definition["filter"] == nil else {
                return nil
            }
            parsedFilter = .identity
        }
        self.sceneId = sceneId
        self.definition = definition
        layers = parsedLayers
        sourceLeases = parsedLeases
        borrowedPresentationUpdates = presentationUpdates
        filterState = .init(parsedFilter)
        unfilteredOnePassLayers = sceneSurfaceOnePassLayers(
            parsedLayers,
            hasFilter: false
        )
    }

    func applyBorrowedPresentation() {
        guard !borrowedPresentationApplied else { return }
        borrowedPresentationUpdates.forEach { $0.apply() }
        borrowedPresentationApplied = true
        unfilteredOnePassLayers = sceneSurfaceOnePassLayers(layers, hasFilter: false)
    }

    func commitBorrowedPresentation() {
        borrowedPresentationUpdates.removeAll()
        borrowedPresentationApplied = false
    }

    /// The published buffer stays retained by the texture. Only decoders that
    /// the candidate cannot borrow are relinquished; unaffected layers survive.
    func suspendReplacedVideosIfNeeded(for next: [String: Any]) -> [SuspendedVideo] {
        guard let definitions = next["layers"] as? [[String: Any]] else { return [] }
        let reusable = Set(definitions.compactMap { definition -> String? in
            guard next["sceneId"] as? String == sceneId,
                  let id = definition["id"] as? String,
                  let key = SceneSurfaceLayerSourceIdentity.key(definition),
                  sourceLeases.contains(where: { $0.layer.id == id && $0.sourceIdentity == key })
            else { return nil }
            return id
        })
        let needed = definitions.filter {
            $0["sourceKind"] as? String == "video" && !reusable.contains($0["id"] as? String ?? "")
        }.count
        guard needed > SceneSurfaceVideoReservations.shared.available else { return [] }
        return layers.compactMap { layer in
            guard !reusable.contains(layer.id), let time = layer.suspendVideoForReplacement() else { return nil }
            return SuspendedVideo(layer: layer, time: time)
        }
    }

    func restoreVideos(_ videos: [SuspendedVideo]) -> Bool {
        var restored = true
        for video in videos {
            if !video.layer.restoreVideo(at: video.time) { restored = false }
        }
        return restored
    }

    func prepareCatalogControlUpdate(to next: [String: Any]) -> SceneCatalogControlUpdate? {
        guard let changes = SceneCatalogControlUpdatePlan.presentationChanges(from: definition, to: next),
              let nextLayers = next["layers"] as? [[String: Any]],
              let previousDefinitions = definition["layers"] as? [[String: Any]],
              zip(layers, previousDefinitions).allSatisfy({ layer, value in
                  sourceLeases.contains {
                      $0.layer === layer && $0.sourceIdentity == SceneSurfaceLayerSourceIdentity.key(value)
                  }
              })
        else { return nil }
        let nextFilter: SceneRenderV2ImageSurfaceRuntime.NativeFilter
        if let raw = next["filter"] as? [String: Any] {
            guard let parsed = SceneRenderV2ImageSurfaceRuntime.NativeFilter(definition: raw)
            else { return nil }
            nextFilter = parsed
        } else {
            guard next["filter"] == nil else { return nil }
            nextFilter = .identity
        }
        var updates = [SceneCatalogControlUpdate]()
        for (index, parameters) in changes.controls {
            guard let update = layers[index].prepareCatalogControlUpdate(parameters: parameters)
            else { return nil }
            updates.append(update)
        }
        for (position, index) in changes.order.enumerated() {
            guard let update = layers[index].preparePresentationUpdate(definition: nextLayers[position]) else { return nil }
            updates.append(update)
        }
        let previous = definition
        let previousFilter = filterState
        let previousLayers = layers
        let nextOrder = changes.order.map { layers[$0] }
        let previousOnePass = unfilteredOnePassLayers
        let previousSourceIdentities = sourceLeases.map(\.sourceIdentity)
        let orderedLeases = changes.order.compactMap { index in
            sourceLeases.first { $0.layer === layers[index] }
        }
        let nextSourceIdentities = nextLayers.compactMap(SceneSurfaceLayerSourceIdentity.key)
        guard nextSourceIdentities.count == nextLayers.count,
              orderedLeases.count == nextLayers.count else { return nil }
        return SceneCatalogControlUpdate(
            apply: { [weak self] in
                updates.forEach { $0.apply() }
                for (lease, identity) in zip(orderedLeases, nextSourceIdentities) {
                    lease.sourceIdentity = identity
                }
                self?.layers = nextOrder
                self?.unfilteredOnePassLayers = sceneSurfaceOnePassLayers(nextOrder, hasFilter: false)
                self?.definition = next
                self?.filterState.update(to: nextFilter, at: CACurrentMediaTime())
            },
            rollback: { [weak self] in
                updates.reversed().forEach { $0.rollback() }
                self?.layers = previousLayers
                self?.unfilteredOnePassLayers = previousOnePass
                self?.definition = previous
                self?.filterState = previousFilter
                if let self {
                    for (lease, identity) in zip(self.sourceLeases, previousSourceIdentities) {
                        lease.sourceIdentity = identity
                    }
                }
            }
        )
    }

    var supportsOnePassGraph: Bool {
        onePassLayers?.packedVideo.videoAssetSupportsOnePass ?? false
    }

    var requiresInfernoPipeline: Bool {
        layers.contains {
            $0.proceduralPreset == SceneSurfaceInfernoEmbersRecipeV1.preset
        }
    }

    var requiresPollenPipeline: Bool {
        layers.contains {
            $0.proceduralPreset == SceneSurfaceWildflowerPollenRecipeV1.preset
        }
    }

    var isAudioReactive: Bool {
        layers.contains(where: \.isAudioReactive)
    }

    func needsContinuousRendering(frame: SceneSurfaceReactiveFrame) -> Bool {
        filterState.active || layers.contains { layer in
            layer.intrinsicSourceNeedsContinuousRendering ||
                (layer.rgbGainEffect?.needsFrames(for: frame) ?? false) ||
                (layer.naturalReactiveLightEffect?.needsFrames(for: frame) ?? false)
        }
    }

    func preferredFramesPerSecond(frame: SceneSurfaceReactiveFrame) -> Int {
        var requested = filterState.active ? 60 : 0
        for layer in layers {
            requested = max(requested, layer.nativeProgramEventFramesPerSecond)
            if layer.intrinsicSourceNeedsContinuousRendering {
                requested = max(
                    requested,
                    layer.intrinsicSourceFramesPerSecond
                )
            }
            if layer.rgbGainEffect?.needsFrames(for: frame) == true {
                requested = max(
                    requested,
                    layer.rgbGainEffect?.framesPerSecond ?? 0
                )
            }
            if layer.naturalReactiveLightEffect?.needsFrames(for: frame) == true {
                requested = max(
                    requested,
                    layer.naturalReactiveLightEffect?.framesPerSecond ?? 0
                )
            }
        }
        return min(max(requested == 0 ? 30 : requested, 1), 60)
    }

    func play() {
        layers.forEach { $0.play() }
    }

    func prepareInitialVideoFrames(hostTime: CFTimeInterval) -> Bool {
        var allReady = true
        for layer in layers {
            if !layer.prepareInitialVideoFrame(hostTime: hostTime) {
                allReady = false
            }
        }
        return allReady
    }

    /// Polls every media source exactly once for a scheduled scene tick.
    /// Layers retain their last decoded image, so composition can combine a
    /// newly advanced source with unchanged siblings without polling twice.
    func prepareScheduledFrame(
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame,
        audioAdvanced: Bool
    ) -> Bool {
        var requiresComposition = filterState.active
        for layer in layers {
            let work = layer.prepareScheduledFrame(
                hostTime: hostTime,
                frame: frame,
                audioAdvanced: audioAdvanced
            )
            if work.requiresComposition {
                requiresComposition = true
            }
        }
        return requiresComposition
    }

    func prepareForcedFrame(
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame
    ) {
        layers.forEach { layer in
            layer.prepareForcedFrame(hostTime: hostTime, frame: frame)
        }
    }

    func markForcedFrameRendered(hostTime: CFTimeInterval) {
        layers.forEach { layer in
            layer.markForcedFrameRendered(hostTime: hostTime)
        }
    }

    func pause() {
        layers.forEach { $0.pause() }
    }

    func updateAudioFrame(_ frame: [String: Any]) {
        layers.forEach { $0.updateAudioFrame(arguments: frame) }
    }

    @discardableResult
    func updateSignalFrame(_ frame: SceneRenderSignalFrameV2) -> Bool {
        var changed = false
        for layer in layers {
            // Do not short-circuit: every program must receive every event.
            if layer.updateSignalFrame(frame) { changed = true }
        }
        return changed
    }

    func resetEffects() {
        layers.forEach { $0.resetEffects() }
    }

    var gpuSubpassesSettledSuccessfully: Bool {
        layers.allSatisfy(\.gpuSubpassesSettledSuccessfully)
    }

    func recoverFromGPUCommandFailure() -> Bool {
        var recovered = false
        for layer in layers {
            if layer.recoverFromGPUCommandFailure() {
                recovered = true
            }
        }
        return recovered
    }

    func tearDown() {
        if borrowedPresentationApplied {
            borrowedPresentationUpdates.reversed().forEach { $0.rollback() }
        }
        borrowedPresentationUpdates.removeAll()
        borrowedPresentationApplied = false
        unfilteredOnePassLayers = nil
        layers.removeAll()
        sourceLeases.removeAll()
    }
}

@available(iOS 15.0, *)
private final class SceneSurfaceFlutterTexture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var pixelBuffer: CVPixelBuffer?

    func publish(_ buffer: CVPixelBuffer) {
        lock.lock()
        pixelBuffer = buffer
        lock.unlock()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        guard let pixelBuffer else {
            lock.unlock()
            return nil
        }
        let retained = Unmanaged.passRetained(pixelBuffer)
        lock.unlock()
        return retained
    }

    func onTextureUnregistered(_ texture: FlutterTexture) {
        lock.lock()
        pixelBuffer = nil
        lock.unlock()
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceBackendCapabilities: Equatable {
    static let protocolVersion = 1

    let metalContextAvailable: Bool
    let genericCIGPUAvailable: Bool
    let infernoPipelineAvailable: Bool
    let pollenPipelineAvailable: Bool
    let onePassInfernoPipelineAvailable: Bool
    let packedVideoPipelineAvailable: Bool
    let textureCacheAvailable: Bool
    let rasterOrderGroupsSupported: Bool

    init(
        metalContextAvailable: Bool,
        genericCIGPUAvailable: Bool,
        infernoPipelineAvailable: Bool,
        pollenPipelineAvailable: Bool,
        onePassInfernoPipelineAvailable: Bool,
        packedVideoPipelineAvailable: Bool,
        textureCacheAvailable: Bool,
        rasterOrderGroupsSupported: Bool
    ) {
        self.metalContextAvailable = metalContextAvailable
        self.genericCIGPUAvailable = genericCIGPUAvailable
        self.infernoPipelineAvailable = infernoPipelineAvailable
        self.pollenPipelineAvailable = pollenPipelineAvailable
        self.onePassInfernoPipelineAvailable =
            onePassInfernoPipelineAvailable
        self.packedVideoPipelineAvailable = packedVideoPipelineAvailable
        self.textureCacheAvailable = textureCacheAvailable
        self.rasterOrderGroupsSupported = rasterOrderGroupsSupported
    }

    init(metalContext: SceneSurfaceMetalContext?) {
        self.init(
            metalContextAvailable: metalContext != nil,
            genericCIGPUAvailable: metalContext != nil,
            infernoPipelineAvailable: metalContext?.infernoPipeline != nil,
            pollenPipelineAvailable: metalContext?.pollenPipeline != nil,
            onePassInfernoPipelineAvailable:
                metalContext?.onePassInfernoPipeline != nil,
            packedVideoPipelineAvailable:
                metalContext?.packedVideoPipeline != nil,
            textureCacheAvailable: metalContext?.textureCache != nil,
            rasterOrderGroupsSupported:
                metalContext?.device.areRasterOrderGroupsSupported ?? false
        )
    }

    var payload: [String: Any] {
        [
            "protocolVersion": Self.protocolVersion,
            "metalContextAvailable": metalContextAvailable,
            "genericCIGPUAvailable": genericCIGPUAvailable,
            "infernoPipelineAvailable": infernoPipelineAvailable,
            "pollenPipelineAvailable": pollenPipelineAvailable,
            "onePassInfernoPipelineAvailable":
                onePassInfernoPipelineAvailable,
            "packedVideoPipelineAvailable": packedVideoPipelineAvailable,
            "textureCacheAvailable": textureCacheAvailable,
            "rasterOrderGroupsSupported": rasterOrderGroupsSupported,
        ]
    }

    func fingerprint(
        rendererRevision: String,
        backendClass: String
    ) -> String {
        let bit: (Bool) -> String = { $0 ? "1" : "0" }
        let canonical = [
            "protocol=\(Self.protocolVersion)",
            "renderer=\(rendererRevision)",
            "backend=\(backendClass)",
            "metal=\(bit(metalContextAvailable))",
            "generic_ci_gpu=\(bit(genericCIGPUAvailable))",
            "inferno_pipeline=\(bit(infernoPipelineAvailable))",
            "pollen_pipeline=\(bit(pollenPipelineAvailable))",
            "one_pass_inferno_pipeline=\(bit(onePassInfernoPipelineAvailable))",
            "packed_video_pipeline=\(bit(packedVideoPipelineAvailable))",
            "texture_cache=\(bit(textureCacheAvailable))",
            "raster_order_groups=\(bit(rasterOrderGroupsSupported))",
        ].joined(separator: "|")
        return SHA256.hash(data: Data(canonical.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

@available(iOS 15.0, *)
struct SceneSurfaceDocumentPreflightEvaluation: Equatable {
    let capabilities: SceneSurfaceBackendCapabilities
    let supported: Bool
    let backendClass: String?
    let issueCodes: [String]
    let capabilityFingerprint: String

    var playbackResourceAllocationCount: Int { 0 }
}

/// The Metal context's pipelines are immutable. Compute its two certifiable
/// backend identities once; frame completion/failure checks remain live.
@available(iOS 15.0, *)
struct SceneSurfaceBackendFingerprints {
    let rendererRevision: String
    private let genericCI: String
    private let onePass: String

    init(
        rendererRevision: String,
        capabilities: SceneSurfaceBackendCapabilities
    ) {
        self.rendererRevision = rendererRevision
        genericCI = capabilities.fingerprint(
            rendererRevision: rendererRevision,
            backendClass: SceneSurfaceRenderPathMetrics.sceneSurfaceCIGPUPath
        )
        onePass = capabilities.fingerprint(
            rendererRevision: rendererRevision,
            backendClass: "one_pass_gpu"
        )
    }

    func fingerprint(for backendClass: String) -> String? {
        switch backendClass {
        case SceneSurfaceRenderPathMetrics.sceneSurfaceCIGPUPath:
            return genericCI
        case "one_pass_gpu":
            return onePass
        default:
            return nil
        }
    }
}

@available(iOS 15.0, *)
struct SceneSurfacePreflightBackendSelection: Equatable {
    let backendClass: String?
    let issueCodes: [String]

    var supported: Bool { backendClass != nil && issueCodes.isEmpty }
}

@available(iOS 15.0, *)
struct SceneSurfaceObservedBackendReceipt: Equatable {
    let rendererRevision: String
    let backendClass: String
    let capabilityFingerprint: String
    let gpuSubmitted: UInt64
    let gpuCompleted: UInt64
    let cpuReference: UInt64
    let fallback: UInt64
    let metalPipelineAvailable: Bool
    let gpuFailureLatched: Bool

    static func certified(
        baseline: SceneSurfaceRenderPathMetricsSnapshot,
        snapshot: SceneSurfaceRenderPathMetricsSnapshot,
        rendererRevision: String,
        capabilities: SceneSurfaceBackendCapabilities,
        subpassesSettledSuccessfully: Bool
    ) -> SceneSurfaceObservedBackendReceipt? {
        certified(
            baseline: baseline,
            snapshot: snapshot,
            fingerprints: SceneSurfaceBackendFingerprints(
                rendererRevision: rendererRevision,
                capabilities: capabilities
            ),
            subpassesSettledSuccessfully: subpassesSettledSuccessfully
        )
    }

    static func certified(
        baseline: SceneSurfaceRenderPathMetricsSnapshot,
        snapshot: SceneSurfaceRenderPathMetricsSnapshot,
        fingerprints: SceneSurfaceBackendFingerprints,
        subpassesSettledSuccessfully: Bool
    ) -> SceneSurfaceObservedBackendReceipt? {
        let delta: (UInt64, UInt64) -> UInt64? = { current, previous in
            current >= previous ? current - previous : nil
        }
        guard
            let gpuSubmitted = delta(
                snapshot.topLevelGPUSubmitted,
                baseline.topLevelGPUSubmitted
            ),
            let gpuCompleted = delta(
                snapshot.topLevelGPUCompleted,
                baseline.topLevelGPUCompleted
            ),
            let cpuReference = delta(
                snapshot.cpuReference,
                baseline.cpuReference
            ),
            let fallback = delta(snapshot.fallback, baseline.fallback),
            let gpuFailures = delta(
                snapshot.gpuFailureCount,
                baseline.gpuFailureCount
            )
        else {
            return nil
        }
        guard
            let fingerprint = fingerprints.fingerprint(
                for: snapshot.currentPath
            ),
            gpuSubmitted > 0,
            gpuCompleted == gpuSubmitted,
            cpuReference == 0,
            fallback == 0,
            gpuFailures == 0,
            snapshot.metalPipelineAvailable,
            subpassesSettledSuccessfully
        else {
            return nil
        }
        return SceneSurfaceObservedBackendReceipt(
            rendererRevision: fingerprints.rendererRevision,
            backendClass: snapshot.currentPath,
            capabilityFingerprint: fingerprint,
            gpuSubmitted: gpuSubmitted,
            gpuCompleted: gpuCompleted,
            cpuReference: cpuReference,
            fallback: fallback,
            metalPipelineAvailable: snapshot.metalPipelineAvailable,
            gpuFailureLatched: false
        )
    }

    var payload: [String: Any] {
        let boundedInt: (UInt64) -> Int = {
            Int(min($0, UInt64(Int.max)))
        }
        return [
            "rendererRevision": rendererRevision,
            "backendClass": backendClass,
            "capabilityFingerprint": capabilityFingerprint,
            "gpuSubmitted": boundedInt(gpuSubmitted),
            "gpuCompleted": boundedInt(gpuCompleted),
            "cpuReference": boundedInt(cpuReference),
            "fallback": boundedInt(fallback),
            "metalPipelineAvailable": metalPipelineAvailable,
            "gpuFailureLatched": gpuFailureLatched,
        ]
    }
}

@available(iOS 15.0, *)
enum SceneSurfacePreflightBackendSelector {
    static func select(
        graphSupportsOnePass: Bool,
        requiresInfernoPipeline: Bool,
        requiresPollenPipeline: Bool,
        capabilities: SceneSurfaceBackendCapabilities
    ) -> SceneSurfacePreflightBackendSelection {
        guard capabilities.genericCIGPUAvailable else {
            return SceneSurfacePreflightBackendSelection(
                backendClass: nil,
                issueCodes: ["renderer_unavailable"]
            )
        }
        let onePassAvailable = capabilities.onePassInfernoPipelineAvailable &&
            capabilities.packedVideoPipelineAvailable &&
            capabilities.textureCacheAvailable &&
            capabilities.rasterOrderGroupsSupported
        if graphSupportsOnePass && onePassAvailable {
            return SceneSurfacePreflightBackendSelection(
                backendClass: "one_pass_gpu",
                issueCodes: []
            )
        }
        if (requiresInfernoPipeline &&
                !capabilities.infernoPipelineAvailable) ||
            (requiresPollenPipeline &&
                !capabilities.pollenPipelineAvailable) {
            return SceneSurfacePreflightBackendSelection(
                backendClass: nil,
                issueCodes: ["pipeline_unavailable"]
            )
        }
        return SceneSurfacePreflightBackendSelection(
            backendClass: SceneSurfaceRenderPathMetrics.sceneSurfaceCIGPUPath,
            issueCodes: []
        )
    }
}

/// Tracks backing allocations, including old viewport buffers still owned by
/// a consumer. Weak references never extend a published frame's lifetime.
final class SceneSurfacePublishedBufferBudget {
    static let capacity = 6
    static let byteLimit = 32 * 1024 * 1024
    private final class Entry {
        weak var buffer: AnyObject?
        weak var pool: AnyObject?
        let width: Int
        let height: Int
        let bytes: Int
        init(_ buffer: CVPixelBuffer, pool: CVPixelBufferPool) {
            self.buffer = buffer
            self.pool = pool
            width = CVPixelBufferGetWidth(buffer)
            height = CVPixelBufferGetHeight(buffer)
            bytes = max(CVPixelBufferGetDataSize(buffer), CVPixelBufferGetBytesPerRow(buffer) * height)
        }
    }
    private var entries = [Entry]()

    func allocationLimit(width: Int, height: Int, pool: CVPixelBufferPool?) -> Int {
        entries.removeAll { $0.buffer == nil }
        // A -> B -> A can leave buffers from a different pool with identical
        // dimensions. They still consume capacity and cannot be reused here.
        let retired = entries.filter { pool == nil || $0.pool !== pool }
        let bytes = retired.reduce(0) { $0 + $1.bytes }
        // Conservative row alignment before allocation; track() checks the
        // actual allocation too. A refusal retains the last completed frame.
        let estimatedBytes = ((width * 4 + 255) / 256) * 256 * height
        guard estimatedBytes > 0, bytes < Self.byteLimit else { return 0 }
        return max(0, min(3, Self.capacity - retired.count, (Self.byteLimit - bytes) / estimatedBytes))
    }

    func track(_ buffer: CVPixelBuffer, pool: CVPixelBufferPool) -> Bool {
        entries.removeAll { $0.buffer == nil }
        if entries.contains(where: { $0.buffer === buffer }) { return true }
        let entry = Entry(buffer, pool: pool)
        guard entries.count < Self.capacity,
            entries.reduce(entry.bytes, { $0 + $1.bytes }) <= Self.byteLimit else { return false }
        entries.append(entry)
        return true
    }

    var residentCount: Int { entries.filter { $0.buffer != nil }.count }
}

struct SceneSurfacePictureInPictureSource: Equatable {
    let sessionID: String
    let consumerID: String
    let generation: String
    let revision: Int
}

/// Renders a complete, ordered scene graph into one IOSurface-backed Flutter
/// texture. Sessions are independent so the PageView can keep adjacent scenes
/// alive during an interactive transition.
@available(iOS 15.0, *)
final class SceneSurfaceRenderEngine: NSObject {
    struct BufferPoolKey: Hashable {
        let width: Int
        let height: Int
    }

    static func retainingBufferPoolForFailedResize<Value>(
        _ pools: [BufferPoolKey: Value],
        previousWidth: Int,
        previousHeight: Int
    ) -> [BufferPoolKey: Value] {
        pools.filter { key, _ in
            key.width == previousWidth && key.height == previousHeight
        }
    }

    private struct ProbeIdentity {
        let token: String
        let sceneId: String
        let sessionId: String
        let rendererRevision: String
    }

    private final class PerformanceProbe {
        let token: String
        let sceneId: String
        let sessionId: String
        let generation: UInt64
        let startedAt: CFTimeInterval
        let renderPathBaseline: SceneSurfaceRenderPathMetricsSnapshot?
        var frameDurationsMilliseconds = [Double]()
        var jankFrameCount = 0
        var targetFramesPerSecond = 0

        init(
            token: String,
            sceneId: String,
            sessionId: String,
            generation: UInt64,
            startedAt: CFTimeInterval,
            renderPathBaseline: SceneSurfaceRenderPathMetricsSnapshot?
        ) {
            self.token = token
            self.sceneId = sceneId
            self.sessionId = sessionId
            self.generation = generation
            self.startedAt = startedAt
            self.renderPathBaseline = renderPathBaseline
        }
    }

    private final class Session {
        let id: String
        let texture: SceneSurfaceFlutterTexture
        let textureId: Int64
        var document: SceneSurfaceDocumentRuntime
        var sceneId: String
        var width: Int
        var height: Int
        var playing: Bool
        var generation: UInt64 = 1
        let documentGeneration = UUID().uuidString
        var foregroundAttached = true
        var pipSource: SceneSurfacePictureInPictureSource?
        var pipPlaying = false
        var editOperationId: String?
        var editRequestedRevision = 0
        var editAppliedRevision = 0
        var editStatus = "unknown"
        var editReason: String?
        var editDocumentKey: Data?
        var editObservedBackend: SceneSurfaceObservedBackendReceipt?
        var publishedFrameCount: UInt64 = 0
        var gpuFrameTiming = SceneSurfaceGPUFrameTiming()
        var performanceProbe: PerformanceProbe?
        var reactiveFrame = SceneSurfaceReactiveFrame()
        var audioSessionId = Int.min
        var audioSequence = -1
        var signalSessionId: Int64 = -1
        var signalSequence: Int64 = -1
        var pendingSignalResult: FlutterResult?
        var pendingSignalToken: UInt64 = 0
        let signalDeadline: SceneSurfaceSignalDeadline
        let filterDeadline: SceneSurfaceSignalDeadline
        var pendingFilterResult: FlutterResult?
        var pendingFilterUpdate: SceneCatalogControlUpdate?
        var preparationId: UUID?
        var cancelPreparation: (() -> Void)?
        var flutterTextureRegistered = true
        var pools = [BufferPoolKey: CVPixelBufferPool]()
        let publishedBufferBudget = SceneSurfacePublishedBufferBudget()
        var lastRenderedAt: CFTimeInterval = 0
        var lastFrameCheckAt: CFTimeInterval = 0
        var scheduledCadenceClock = SceneSurfaceLayerCadenceClock()
        var compositionRetryState = SceneSurfaceCompositionRetryState()
        var audioRevision: UInt64 = 0
        var lastRenderedAudioRevision: UInt64 = 0
        var eventRenderScheduled = false
        var observedBackend: SceneSurfaceObservedBackendReceipt?

        init(
            id: String,
            texture: SceneSurfaceFlutterTexture,
            textureId: Int64,
            document: SceneSurfaceDocumentRuntime,
            width: Int,
            height: Int,
            playing: Bool,
            renderQueue: DispatchQueue
        ) {
            self.id = id
            self.texture = texture
            self.textureId = textureId
            self.document = document
            self.sceneId = document.sceneId
            self.width = width
            self.height = height
            self.playing = playing
            signalDeadline = SceneSurfaceSignalDeadline(queue: renderQueue)
            filterDeadline = SceneSurfaceSignalDeadline(queue: renderQueue)
        }
    }

    private let channelName = "com.chic.colorlights/scene_surface_renderer"
    private let textureRegistry: FlutterTextureRegistry
    private let renderEngine: MusicVibeRenderEngine
    private let renderQueue = DispatchQueue(
        label: "com.chic.colorlights.scene-surface.render",
        qos: .userInteractive
    )
    /// Structural parsing and asset inspection may perform bounded file I/O.
    /// It must never sit ahead of active frames, control calls, or detach.
    private let inspectionQueue = DispatchQueue(
        label: "com.chic.colorlights.scene-surface.inspection",
        qos: .utility
    )
    private let metalContext: SceneSurfaceMetalContext?
    private let backendFingerprints: SceneSurfaceBackendFingerprints
    private let ciContext: CIContext
    private let v2ImageRuntime: SceneRenderV2ImageSurfaceRuntime

    var pictureInPictureV2Runtime: SceneRenderV2ImageSurfaceRuntime {
        v2ImageRuntime
    }
    private let outputColorSpace = CGColorSpaceCreateDeviceRGB()
    private let metalAvailable: Bool
    private static let rendererRevision = "native_scene_surface_v18"
    private static let initialVideoFrameWait: CFTimeInterval = 2
    private static let initialVideoFramePollInterval: TimeInterval = 1.0 / 120.0
    private var sessions = [String: Session]()
    private var documentInspections = [String: (
        id: UUID, operation: SceneSurfaceInspectionOperation<[String: SceneSurfaceVideoAssetInspection]>
    )]()

    func retainPictureInPictureSource(
        sessionID: String, consumerID: String, identity: [String: Any]
    ) -> SceneSurfacePictureInPictureSource? {
        renderQueue.sync {
            guard let generation = identity["generation"] as? String,
                  let revision = identity["revision"] as? Int,
                  identity["semanticPlanHash"] as? String == "v1:\(generation):\(revision)",
                  let session = sessions[sessionID], session.foregroundAttached,
                  session.documentGeneration == generation,
                  session.editAppliedRevision == revision,
                  session.editStatus != "pending", session.preparationId == nil,
                  documentInspections[sessionID] == nil,
                  session.pendingFilterResult == nil, session.publishedFrameCount > 0,
                  session.pipSource == nil else { return nil }
            let source = SceneSurfacePictureInPictureSource(
                sessionID: sessionID, consumerID: consumerID,
                generation: generation, revision: revision
            )
            session.pipSource = source
            return source
        }
    }

    func copyPictureInPictureFrame(_ source: SceneSurfacePictureInPictureSource)
        -> (buffer: CVPixelBuffer, revision: UInt64)? {
        renderQueue.sync {
            guard let session = sessions[source.sessionID], session.pipSource == source,
                  session.documentGeneration == source.generation,
                  session.editAppliedRevision == source.revision,
                  let buffer = session.texture.copyPixelBuffer()?.takeRetainedValue() else { return nil }
            return (buffer, session.publishedFrameCount)
        }
    }

    func setPictureInPictureSourcePlaying(_ source: SceneSurfacePictureInPictureSource, playing: Bool) {
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[source.sessionID], session.pipSource == source else { return }
            session.pipPlaying = playing
            if self.isSessionPlaying(session) { session.document.play() }
            else { session.document.pause() }
            self.reconcileRenderTimer()
        }
    }

    func releasePictureInPictureSource(_ source: SceneSurfacePictureInPictureSource) {
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[source.sessionID], session.pipSource == source else { return }
            session.pipSource = nil
            session.pipPlaying = false
            if !session.foregroundAttached { self.destroySession(session) }
            else if !self.isSessionPlaying(session) { session.document.pause() }
            self.reconcileRenderTimer()
        }
    }

    func acknowledgePictureInPictureCleanup(_ completion: @escaping () -> Void) {
        renderQueue.async { DispatchQueue.main.async(execute: completion) }
    }

    private func isSessionPlaying(_ session: Session) -> Bool {
        (applicationActive && session.foregroundAttached && session.playing) ||
            (session.pipSource != nil && session.pipPlaying)
    }

    private func destroySession(_ session: Session) {
        guard sessions[session.id] === session else { return }
        sessions.removeValue(forKey: session.id)
        documentInspections[session.id]?.operation.cancel()
        session.cancelPreparation?()
        finishSignal(session, error: "signal_session_detached")
        finishFilterUpdate(session, error: "scene_controls_session_detached")
        session.document.tearDown()
        metalContext?.renderPathMetrics.removeScope(session.id)
        session.pools.removeAll()
        unregisterTexture(session)
    }
    private var renderTimer: DispatchSourceTimer?
    private var renderTimerFramesPerSecond: Int?
    private var applicationActive: Bool
    private let windowProvider: () -> UIWindow?
    private var notificationTokens = [NSObjectProtocol]()
    private let capabilityReceiptLock = NSLock()
    private var capabilityReceiptLogged = false
    // One-entry cache keeps repeated exact-document checks deduplicated and
    // bounded. These fields are confined to inspectionQueue.
    private var cachedPreflightSignature: String?
    private var cachedPreflightEvaluation: SceneSurfaceDocumentPreflightEvaluation?

    init(
        textureRegistry: FlutterTextureRegistry,
        renderEngine: MusicVibeRenderEngine,
        windowProvider: @escaping () -> UIWindow? = { nil }
    ) {
        SceneCreatorCatalog.loadBundledIfNeeded(
            assetPath: Bundle.main.path(forResource: FlutterDartProject.lookupKey(
                forAsset: "assets/creator_catalog.json", fromPackage: "visual_catalog"), ofType: nil)
        )
        self.textureRegistry = textureRegistry
        self.renderEngine = renderEngine
        self.windowProvider = windowProvider
        let metalContext = SceneSurfaceMetalContext.shared
        self.metalContext = metalContext
        backendFingerprints = SceneSurfaceBackendFingerprints(
            rendererRevision: Self.rendererRevision,
            capabilities: SceneSurfaceBackendCapabilities(
                metalContext: metalContext
            )
        )
        if let metalContext {
            metalAvailable = true
            ciContext = metalContext.ciContext
        } else {
            metalAvailable = false
            ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        let initialApplicationActive = (windowProvider()?.windowScene).map {
            $0.activationState == .foregroundActive
        } ?? (UIApplication.shared.applicationState == .active)
        applicationActive = initialApplicationActive
        v2ImageRuntime = SceneRenderV2ImageSurfaceRuntime(
            textureRegistry: textureRegistry,
            device: metalContext?.device,
            ciContext: ciContext,
            renderEngine: renderEngine,
            metalContext: metalContext,
            applicationActive: initialApplicationActive
        )
        super.init()
        observeApplicationLifecycle()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    var isSupported: Bool { metalAvailable }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(
                    FlutterError(
                        code: "scene_surface_unavailable",
                        message: "The native scene renderer was released.",
                        details: nil
                    )
                )
                return
            }
            switch call.method {
            case "creatorDiagnostics":
                result(SceneCreatorCatalog.diagnostics)
            case "videoAdmissionProfile":
                result(["profileId": SceneSurfaceVideoAdmission.current.profileID,
                        "maximumVideoLayers": SceneSurfaceVideoAdmission.current.limit,
                        "maximumResidentPlayers": SceneSurfaceVideoAdmission.maximumResidentPlayers,
                        "maximumEncodedPixelsPerVideo": 1920 * 2160,
                        "maximumSourceFPSForExpandedMix": 30,
                        "maximumEncodedPixelsPerSecond": SceneSurfaceVideoAdmission.maximumEncodedPixelsPerSecond,
                        "videoReservations": SceneSurfaceVideoReservations.shared.diagnostics])
            case "isSupported":
                self.logCapabilityReceiptIfNeeded()
                result(self.isSupported)
            case "preflightDocument":
                self.preflightDocument(
                    arguments: call.arguments,
                    result: result
                )
            case "preflightDocumentV2":
                self.preflightDocumentV2(
                    arguments: call.arguments,
                    result: result
                )
            case "attachV2":
                self.v2ImageRuntime.attach(
                    arguments: call.arguments,
                    result: { value in
                        if
                            let payload = value as? [String: Any],
                            let observed = payload["observedBackend"]
                                as? [String: Any]
                        {
                            NSLog(
                                "[SceneSurfaceV2Native] phase=attached backend=%@ renderer=%@ quality=%@",
                                observed["backendClass"] as? String ?? "unknown",
                                observed["rendererRevision"] as? String ?? "unknown",
                                observed["quality"] as? String ?? "unknown"
                            )
                        } else if let error = value as? FlutterError {
                            NSLog(
                                "[SceneSurfaceV2Native] phase=attach_failed code=%@",
                                error.code
                            )
                        }
                        result(value)
                    }
                )
            case "updateDocumentV2":
                self.v2ImageRuntime.updateDocument(
                    arguments: call.arguments,
                    result: result
                )
            case "transitionQualityV2":
                self.v2ImageRuntime.transition(
                    arguments: call.arguments,
                    rebuildingResources: false,
                    result: result
                )
            case "recoverMinimumFunctionalV2":
                self.v2ImageRuntime.transition(
                    arguments: call.arguments,
                    rebuildingResources: true,
                    result: result
                )
            case "updateViewportV2":
                self.v2ImageRuntime.updateViewport(
                    arguments: call.arguments,
                    result: result
                )
            case "setPlayingV2":
                self.v2ImageRuntime.setPlaying(
                    arguments: call.arguments,
                    result: result
                )
            case "updateSignalFrameV2":
                self.v2ImageRuntime.updateSignal(
                    arguments: call.arguments,
                    result: result
                )
            case "readRuntimeMetricsV2":
                self.v2ImageRuntime.metrics(
                    arguments: call.arguments,
                    result: result
                )
            case "detachV2":
                self.v2ImageRuntime.detach(
                    arguments: call.arguments,
                    result: result
                )
            case "attach":
                self.attach(arguments: call.arguments, result: result)
            case "updateDocument":
                self.updateDocument(arguments: call.arguments) { value in
                    if let error = value as? FlutterError {
                        NSLog("[SceneSurfaceUpdate] outcome=rejected code=%@", error.code)
                    }
                    result(value)
                }
            case "updateDocumentConfirmed":
                self.updateDocumentConfirmed(arguments: call.arguments, result: result)
            case "queryDocumentOperation":
                self.queryDocumentOperation(arguments: call.arguments, result: result)
            case "updateViewport":
                self.updateViewport(arguments: call.arguments, result: result)
            case "setPlaying":
                self.setPlaying(arguments: call.arguments, result: result)
            case "updateAudioFrame":
                self.updateAudioFrame(arguments: call.arguments, result: result)
            case "updateSignalFrame":
                self.updateSignalFrame(arguments: call.arguments, result: result)
            case "activeSurfaceForScene":
                self.activeSurfaceForScene(
                    arguments: call.arguments,
                    result: result
                )
            case "startPerformanceProbe":
                self.startPerformanceProbe(
                    arguments: call.arguments,
                    result: result
                )
            case "stopPerformanceProbe":
                self.stopPerformanceProbe(
                    arguments: call.arguments,
                    result: result
                )
            case "cancelPerformanceProbe":
                self.cancelPerformanceProbe(
                    arguments: call.arguments,
                    result: result
                )
            case "detach":
                self.detach(arguments: call.arguments, result: result)
            case "dispose":
                self.disposeAll(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func shutdown() {
        v2ImageRuntime.shutdown()
        disposeAll(result: nil)
    }

    private func logCapabilityReceiptIfNeeded() {
        capabilityReceiptLock.lock()
        guard !capabilityReceiptLogged else {
            capabilityReceiptLock.unlock()
            return
        }
        capabilityReceiptLogged = true
        capabilityReceiptLock.unlock()

        let context = metalContext
        NSLog(
            "%@",
            sceneSurfaceCapabilityReceiptLine(
                supported: isSupported,
                rendererRevision: Self.rendererRevision,
                metalContextAvailable: context != nil,
                infernoPipelineAvailable: context?.infernoPipeline != nil,
                pollenPipelineAvailable: context?.pollenPipeline != nil,
                onePassInfernoPipelineAvailable:
                    context?.onePassInfernoPipeline != nil,
                packedVideoPipelineAvailable:
                    context?.packedVideoPipeline != nil,
                textureCacheAvailable: context?.textureCache != nil,
                rasterOrderGroupsSupported:
                    context?.device.areRasterOrderGroupsSupported ?? false
            )
        )
    }

    private func preflightDocument(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            Set(arguments.keys) == Set(["sceneDocument"]),
            let definition = arguments["sceneDocument"] as? [String: Any]
        else {
            result(
                Self.preflightPayload(
                    evaluation: preflightEvaluation(
                        supported: false,
                        backendClass: nil,
                        issueCodes: ["graph_invalid"]
                    )
                )
            )
            return
        }
        inspectionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    result(
                        Self.preflightPayload(
                            evaluation: Self.preflightEvaluation(
                                capabilities: SceneSurfaceBackendCapabilities(
                                    metalContext: nil
                                ),
                                supported: false,
                                backendClass: nil,
                                issueCodes: ["renderer_unavailable"]
                            )
                        )
                    )
                }
                return
            }
            let signature = Self.preflightSignature(definition: definition)
            let evaluation: SceneSurfaceDocumentPreflightEvaluation
            if
                signature != nil,
                signature == self.cachedPreflightSignature,
                let cached = self.cachedPreflightEvaluation
            {
                evaluation = cached
            } else {
                evaluation = self.evaluatePreflight(definition: definition)
                self.cachedPreflightSignature = signature
                self.cachedPreflightEvaluation = signature == nil
                    ? nil
                    : evaluation
                if !evaluation.supported {
                    NSLog(
                        "[SceneSurfacePreflight] outcome=rejected issues=%@",
                        evaluation.issueCodes.joined(separator: ",")
                    )
                }
            }
            DispatchQueue.main.async {
                result(Self.preflightPayload(evaluation: evaluation))
            }
        }
    }

    private func preflightDocumentV2(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        if let supported = v2ImageRuntime.preflight(arguments: arguments) {
            NSLog(
                "[SceneSurfaceV2Native] phase=preflight supported=true capability=%@",
                supported["capabilityClass"] as? String ?? "unknown"
            )
            result(supported)
            return
        }
        inspectionQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let evaluation = SceneRenderV2ShadowCompiler.preflight(
                arguments: arguments,
                metalAvailable: self.metalAvailable
            )
            DispatchQueue.main.async {
                let payload = evaluation?.payload
                NSLog(
                    "[SceneSurfaceV2Native] phase=preflight supported=%@ issues=%@",
                    (payload?["supported"] as? Bool) == true ? "true" : "false",
                    (payload?["issueCodes"] as? [String])?.joined(separator: ",")
                        ?? "invalid_request"
                )
                result(payload)
            }
        }
    }

    private static func preflightSignature(
        definition: [String: Any]
    ) -> String? {
        guard
            JSONSerialization.isValidJSONObject(definition),
            let data = try? JSONSerialization.data(
                withJSONObject: definition,
                options: [.sortedKeys]
            )
        else {
            return nil
        }
        var digest = SHA256()
        digest.update(data: data)
        for layer in definition["layers"] as? [[String: Any]] ?? [] {
            guard let identity = SceneSurfaceLayerSourceIdentity.key(layer) else { return nil }
            digest.update(data: identity)
        }
        return digest.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    func evaluatePreflight(
        definition: [String: Any]
    ) -> SceneSurfaceDocumentPreflightEvaluation {
        let capabilities = SceneSurfaceBackendCapabilities(
            metalContext: metalContext
        )
        guard isSupported else {
            return Self.preflightEvaluation(
                capabilities: capabilities,
                supported: false,
                backendClass: nil,
                issueCodes: ["renderer_unavailable"]
            )
        }
        guard
            let document = SceneSurfaceDocumentRuntime(
                definition: definition,
                renderEngine: renderEngine,
                metalContext: metalContext,
                constructionMode: .preflight
            )
        else {
            return Self.preflightEvaluation(
                capabilities: capabilities,
                supported: false,
                backendClass: nil,
                issueCodes: Self.preflightIssueCodes(
                    definition: definition
                )
            )
        }
        defer { document.tearDown() }
        let selection = SceneSurfacePreflightBackendSelector.select(
            graphSupportsOnePass: document.supportsOnePassGraph,
            requiresInfernoPipeline: document.requiresInfernoPipeline,
            requiresPollenPipeline: document.requiresPollenPipeline,
            capabilities: capabilities
        )
        return Self.preflightEvaluation(
            capabilities: capabilities,
            supported: selection.supported,
            backendClass: selection.backendClass,
            issueCodes: selection.issueCodes
        )
    }

    func documentParserAcceptsForTesting(
        definition: [String: Any],
        constructionMode: SceneSurfaceDocumentConstructionMode
    ) -> Bool {
        guard let document = SceneSurfaceDocumentRuntime(
            definition: definition,
            renderEngine: renderEngine,
            metalContext: metalContext,
            constructionMode: constructionMode
        ) else {
            return false
        }
        document.tearDown()
        return true
    }

    var activeSessionCountForTesting: Int {
        renderQueue.sync { sessions.count }
    }

    /// Exercises actual source scheduling/identity and layer preparation without
    /// registering a Flutter surface or creating a timer/audio owner.
    func stableSourceRasterCountsForTesting(
        definition: [String: Any], hostTimes: [CFTimeInterval],
        signals: [SceneRenderSignalFrameV2]
    ) -> [Int]? {
        guard hostTimes.count == signals.count else { return nil }
        return renderQueue.sync {
            guard let document = SceneSurfaceDocumentRuntime(
                definition: definition, renderEngine: renderEngine,
                metalContext: metalContext
            ) else { return nil }
            defer { document.tearDown() }
            document.layers.forEach { $0.play() }
            let target = CGRect(x: 0, y: 0, width: 64, height: 96)
            var counts = [Int]()
            for (time, signal) in zip(hostTimes, signals) {
                let success = autoreleasepool {
                    document.layers.forEach { _ = $0.updateSignalFrame(signal) }
                    _ = document.prepareScheduledFrame(
                        hostTime: time, frame: SceneSurfaceReactiveFrame(), audioAdvanced: true
                    )
                    return compose(document: document, targetRect: target, hostTime: time,
                                   frame: SceneSurfaceReactiveFrame(), sourcesPrepared: true) != nil
                }
                guard success else { return nil }
                counts.append(document.layers.reduce(0) { $0 + $1.stableSourceRasterCountForTesting })
            }
            return counts
        }
    }

    var renderTimerActiveForTesting: Bool {
        renderQueue.sync { renderTimer != nil }
    }

    func enqueueInspectionWorkForTesting(
        _ work: @escaping () -> Void
    ) {
        inspectionQueue.async(execute: work)
    }

    func enqueueRenderWorkForTesting(
        _ work: @escaping () -> Void
    ) {
        renderQueue.async(execute: work)
    }

    private func preflightEvaluation(
        supported: Bool,
        backendClass: String?,
        issueCodes: [String]
    ) -> SceneSurfaceDocumentPreflightEvaluation {
        Self.preflightEvaluation(
            capabilities: SceneSurfaceBackendCapabilities(
                metalContext: metalContext
            ),
            supported: supported,
            backendClass: backendClass,
            issueCodes: issueCodes
        )
    }

    private static func preflightEvaluation(
        capabilities: SceneSurfaceBackendCapabilities,
        supported: Bool,
        backendClass: String?,
        issueCodes: [String]
    ) -> SceneSurfaceDocumentPreflightEvaluation {
        let fingerprintBackend = backendClass ?? "unsupported"
        return SceneSurfaceDocumentPreflightEvaluation(
            capabilities: capabilities,
            supported: supported,
            backendClass: backendClass,
            issueCodes: issueCodes,
            capabilityFingerprint: capabilities.fingerprint(
                rendererRevision: rendererRevision,
                backendClass: fingerprintBackend
            )
        )
    }

    private static func preflightPayload(
        evaluation: SceneSurfaceDocumentPreflightEvaluation
    ) -> [String: Any] {
        return [
            "availability": "available",
            "supported": evaluation.supported,
            "rendererRevision": rendererRevision,
            "backendClass": evaluation.backendClass ?? NSNull(),
            "capabilityFingerprint": evaluation.capabilityFingerprint,
            "issueCodes": evaluation.issueCodes,
            "capabilities": evaluation.capabilities.payload,
        ]
    }

    private static func preflightIssueCodes(
        definition: [String: Any]
    ) -> [String] {
        guard
            let schemaVersion = definition["schemaVersion"] as? NSNumber,
            schemaVersion.intValue == 1
        else {
            return ["schema_unsupported"]
        }
        guard
            let layers = definition["layers"] as? [[String: Any]],
            !layers.isEmpty,
            layers.count <= 32
        else {
            return ["graph_invalid"]
        }
        for layer in layers {
            guard let sourceKind = layer["sourceKind"] as? String else {
                return ["layer_invalid"]
            }
            switch sourceKind {
            case "image", "animatedImage", "video":
                return ["asset_unavailable"]
            case "procedural":
                return ["preset_unsupported"]
            case "realtimeRenderer":
                return ["layer_invalid"]
            default:
                return ["source_unsupported"]
            }
        }
        return ["graph_invalid"]
    }

    /// Validate the complete candidate without allocating decoders. Only the
    /// inspected AVAssets cross back; temporary preflight layers are retired here.
    private func inspectDocument(
        _ definition: [String: Any], sessionId: String, deadline: CFTimeInterval,
        completion: @escaping ([String: SceneSurfaceVideoAssetInspection]?, String?) -> Void
    ) {
        let identity = UUID()
        let operation = SceneSurfaceInspectionOperation<[String: SceneSurfaceVideoAssetInspection]>(
            queue: renderQueue
        ) { [weak self] videos, error in
            guard let self, self.documentInspections[sessionId]?.id == identity else { return }
            self.documentInspections.removeValue(forKey: sessionId)
            completion(videos, error)
        }
        documentInspections[sessionId] = (identity, operation)
        let engine = renderEngine, metal = metalContext
        operation.start(on: inspectionQueue, timeout: deadline - CACurrentMediaTime()) { context in
            guard let inspected = SceneSurfaceDocumentRuntime(
                definition: definition, renderEngine: engine,
                metalContext: metal, constructionMode: .preflight,
                inspectionContext: context
            ) else { return nil }
            defer { inspected.tearDown() }
            var videos = [String: SceneSurfaceVideoAssetInspection]()
            for layer in inspected.layers {
                if let inspection = layer.videoInspection { videos[inspection.path] = inspection }
            }
            return videos
        }
    }

    private func attach(arguments: Any?, result: @escaping FlutterResult) {
        // Scene-based iPad activation can precede the implicit Flutter engine
        // observer or omit the legacy application notification. Sample the
        // exact app window on the main queue before admitting decoder work.
        if let scene = windowProvider()?.windowScene {
            setApplicationActive(scene.activationState == .foregroundActive)
        }
        let attachStartedAt = CACurrentMediaTime()
        let attemptedArguments = arguments as? [String: Any]
        let attemptedSessionId = Self.nonEmpty(
            attemptedArguments?["sessionId"]
        )
        let logAttachReceipt: (String, String?) -> Void = { outcome, code in
            let elapsedMilliseconds = Int(
                max(0, CACurrentMediaTime() - attachStartedAt) * 1_000
            )
            NSLog(
                "%@",
                sceneSurfaceAttachReceiptLine(
                    sessionId: attemptedSessionId,
                    outcome: outcome,
                    code: code,
                    elapsedMilliseconds: elapsedMilliseconds
                )
            )
        }
        guard
            isSupported,
            let arguments = attemptedArguments,
            let sessionId = attemptedSessionId,
            let documentDefinition = Self.document(from: arguments)
        else {
            logAttachReceipt("failed", "attach_invalid")
            result(Self.error("attach_invalid", "Invalid scene configuration."))
            return
        }

        let viewport = Self.viewport(from: arguments)
        let dimensions = Self.foregroundDimensions(
            width: viewport.width * viewport.scale,
            height: viewport.height * viewport.scale
        )
        let playing = arguments["playing"] as? Bool ?? true
        let texture = SceneSurfaceFlutterTexture()
        let textureId = textureRegistry.register(texture)
        guard textureId >= 0 else {
            logAttachReceipt("failed", "texture_registration_failed")
            result(Self.error("texture_registration_failed", "Unable to register scene texture."))
            return
        }
        let registeredTextureRegistry = textureRegistry

        renderQueue.async { [weak self] in
            guard let self else {
                logAttachReceipt("failed", "attach_cancelled")
                DispatchQueue.main.async {
                    registeredTextureRegistry.unregisterTexture(textureId)
                    result(Self.error("attach_cancelled", "The native scene renderer was released."))
                }
                return
            }
            guard self.sessions[sessionId] == nil, self.documentInspections[sessionId] == nil else {
                logAttachReceipt("failed", "session_exists")
                DispatchQueue.main.async {
                    self.textureRegistry.unregisterTexture(textureId)
                    result(Self.error("session_exists", "The scene session is already attached."))
                }
                return
            }
            let deadline = CACurrentMediaTime() + Self.initialVideoFrameWait
            self.inspectDocument(documentDefinition, sessionId: sessionId, deadline: deadline) { videos, error in
                guard let videos, error == nil else {
                    let code = error ?? "scene_document_invalid"
                    logAttachReceipt("failed", code)
                    DispatchQueue.main.async {
                        self.textureRegistry.unregisterTexture(textureId)
                        result(Self.error(code, "The complete scene could not be prepared."))
                    }
                    return
                }
                guard
                    let document = SceneSurfaceDocumentRuntime(
                        definition: documentDefinition,
                        renderEngine: self.renderEngine,
                        metalContext: self.metalContext,
                        metricsScope: sessionId,
                        inspectedVideos: videos
                    )
                else {
                    self.metalContext?.renderPathMetrics.removeScope(sessionId)
                    logAttachReceipt("failed", "scene_document_invalid")
                    DispatchQueue.main.async {
                        self.textureRegistry.unregisterTexture(textureId)
                        result(Self.error("scene_document_invalid", "The complete scene graph is not supported natively."))
                    }
                    return
                }

                let session = Session(
                    id: sessionId,
                    texture: texture,
                    textureId: textureId,
                    document: document,
                    width: dimensions.width,
                    height: dimensions.height,
                    playing: playing,
                    renderQueue: self.renderQueue
                )
                self.sessions[sessionId] = session
                self.prepareInitialVideoFrames(session: session, document: document, deadline: deadline) { ready in
                    if !session.playing || !self.applicationActive { document.pause() }
                    let published = ready && self.sessions[sessionId] === session &&
                        self.renderAndPublish(session: session, document: document)
                    guard published else {
                        let details: [String: Any] = [
                            "applicationActive": self.applicationActive,
                            "sources": document.layers.compactMap(\.videoDiagnostics),
                        ]
                        NSLog("[SceneSurfacePrepareFailure] %@", String(describing: details))
                        if self.sessions[sessionId] === session { self.sessions.removeValue(forKey: sessionId) }
                        document.tearDown()
                        self.metalContext?.renderPathMetrics.removeScope(sessionId)
                        self.unregisterTexture(session)
                        let code = ready ? "initial_frame_failed" : "initial_video_frame_timeout"
                        logAttachReceipt("failed", code)
                        self.reconcileRenderTimer()
                        DispatchQueue.main.async { result(FlutterError(code: code,
                            message: "A complete initial scene frame could not be prepared.", details: details)) }
                        return
                    }
                    self.reconcileRenderTimer()
                    logAttachReceipt("attached", nil)
                    let backend: Any = session.observedBackend?.payload ?? NSNull()
                    DispatchQueue.main.async {
                        result(["textureId": textureId, "documentGeneration": session.documentGeneration,
                            "width": dimensions.width, "height": dimensions.height, "observedBackend": backend])
                    }
                }
            }
        }
    }

    private func editReceipt(_ session: Session, operationId: String, revision: Int) -> [String: Any] {
        let matches = session.editOperationId == operationId && session.editRequestedRevision == revision
        return [
            "operationId": operationId,
            "requestedRevision": revision,
            "appliedRevision": session.editAppliedRevision,
            "status": matches ? session.editStatus : "superseded",
            "reason": matches ? (session.editReason as Any? ?? NSNull()) : "operation_not_current",
            "observedBackend": matches && session.editStatus == "applied"
                ? (session.editObservedBackend?.payload as Any? ?? NSNull()) : NSNull(),
        ]
    }

    private func queryDocumentOperation(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let id = Self.nonEmpty(args["sessionId"]),
              let operation = Self.nonEmpty(args["operationId"]),
              let generation = Self.nonEmpty(args["documentGeneration"]),
              let revision = args["revision"] as? Int, revision > 0 else {
            result(Self.error("edit_identity_invalid", "Invalid document operation identity."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[id], session.documentGeneration == generation else {
                DispatchQueue.main.async { result(Self.error("session_not_found", "The edit session no longer exists.")) }
                return
            }
            let receipt = self.editReceipt(session, operationId: operation, revision: revision)
            DispatchQueue.main.async { result(receipt) }
        }
    }

    private func updateDocumentConfirmed(arguments: Any?, result: @escaping FlutterResult) {
        guard let args = arguments as? [String: Any],
              let id = Self.nonEmpty(args["sessionId"]),
              let operation = Self.nonEmpty(args["operationId"]),
              let generation = Self.nonEmpty(args["documentGeneration"]),
              let revision = args["revision"] as? Int, revision > 0,
              let rawDocument = args["sceneDocument"] as? [String: Any],
              let key = try? JSONSerialization.data(withJSONObject: rawDocument, options: [.sortedKeys]) else {
            result(Self.error("edit_identity_invalid", "Invalid confirmed document update."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[id], session.documentGeneration == generation else {
                DispatchQueue.main.async { result(Self.error("session_not_found", "The edit session no longer exists.")) }
                return
            }
            if session.editOperationId == operation {
                guard session.editRequestedRevision == revision, session.editDocumentKey == key else {
                    DispatchQueue.main.async { result(Self.error("edit_identity_reused", "An operation cannot identify two documents.")) }
                    return
                }
                let receipt = self.editReceipt(session, operationId: operation, revision: revision)
                DispatchQueue.main.async { result(receipt) }
                return
            }
            guard session.editStatus != "pending", revision > session.editRequestedRevision else {
                DispatchQueue.main.async { result(Self.error("edit_not_admitted", "Another edit is pending or this revision is stale.")) }
                return
            }
            session.editOperationId = operation
            session.editRequestedRevision = revision
            session.editStatus = "pending"
            session.editReason = nil
            session.editDocumentKey = key
            session.editObservedBackend = nil
            self.updateDocument(arguments: args) { [weak self, weak session] value in
                guard let self, let session else { return }
                self.renderQueue.async {
                    guard self.sessions[id] === session,
                          session.documentGeneration == generation,
                          session.editOperationId == operation else {
                        DispatchQueue.main.async { result(Self.error("edit_cancelled", "The edit session was released.")) }
                        return
                    }
                    if let envelope = value as? [String: Any], envelope["accepted"] as? Bool == true {
                        session.editAppliedRevision = revision
                        session.editStatus = "applied"
                        session.editObservedBackend = session.observedBackend
                    } else {
                        session.editStatus = "rejected"
                        session.editReason = (value as? FlutterError)?.code ?? "document_update_rejected"
                    }
                    let receipt = self.editReceipt(session, operationId: operation, revision: revision)
                    DispatchQueue.main.async { result(receipt) }
                }
            }
        }
    }

    private func updateDocument(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let documentDefinition = Self.document(from: arguments)
        else {
            result(Self.error("update_document_invalid", "Invalid scene document update."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async {
                    result(Self.error("session_not_found", "The scene session is not attached."))
                }
                return
            }
            guard session.pipSource == nil else {
                DispatchQueue.main.async { result(Self.error("scene_continuation_owned", "Release PiP before editing this revision.")) }
                return
            }
            guard session.pendingFilterResult == nil, session.preparationId == nil,
                  self.documentInspections[sessionId] == nil else {
                DispatchQueue.main.async {
                    result(Self.error("scene_controls_in_flight", "A visual edit is still presenting."))
                }
                return
            }
            self.invalidatePerformanceProbe(session)
            if let update = session.document.prepareCatalogControlUpdate(to: documentDefinition) {
                update.apply()
                session.pendingFilterUpdate = update
                session.pendingFilterResult = result
                session.filterDeadline.arm(after: 2) { [weak self, weak session] in
                    guard let self, let session else { return }
                    self.finishFilterUpdate(session, error: "scene_controls_presentation_timeout")
                    _ = self.renderAndPublish(session: session)
                    self.reconcileRenderTimer()
                }
                guard self.renderAndPublish(session: session) else {
                    self.finishFilterUpdate(session, error: "scene_controls_render_failed")
                    self.reconcileRenderTimer()
                    return
                }
                self.reconcileRenderTimer()
                return
            }
            let deadline = CACurrentMediaTime() + Self.initialVideoFrameWait
            self.inspectDocument(documentDefinition, sessionId: sessionId, deadline: deadline) { videos, error in
                guard let videos, error == nil, self.sessions[sessionId] === session else {
                    let code = error ?? "scene_update_cancelled"
                    DispatchQueue.main.async { result(Self.error(code, "The edit was not applied; the previous scene is unchanged.")) }
                    return
                }
                self.finishSignal(session, error: "signal_document_replaced")
                session.document.pause()
                let suspended = session.document.suspendReplacedVideosIfNeeded(for: documentDefinition)
                let rejectAndRestore: (String) -> Void = { code in
                    guard self.sessions[sessionId] === session else {
                        DispatchQueue.main.async { result(Self.error("scene_update_cancelled", "The edit session was closed.")) }
                        return
                    }
                    let finish: (Bool) -> Void = { restored in
                        let current = self.sessions[sessionId] === session
                        if !restored { session.playing = false }
                        if current, restored, session.playing, self.applicationActive {
                            session.document.play()
                        } else {
                            session.document.pause()
                        }
                        self.reconcileRenderTimer()
                        DispatchQueue.main.async {
                            result(Self.error(restored ? code : "scene_update_restore_failed",
                                restored ? "The edit was rejected; the previous scene was restored."
                                    : "Playback stopped because the previous video sources could not be restored. Retry the scene."))
                        }
                    }
                    guard !suspended.isEmpty else { finish(true); return }
                    guard session.document.restoreVideos(suspended) else { finish(false); return }
                    self.prepareInitialVideoFrames(session: session, document: session.document) { ready in
                        guard self.sessions[sessionId] === session else { finish(false); return }
                        finish(ready && self.renderAndPublish(session: session))
                    }
                }
                guard let replacement = SceneSurfaceDocumentRuntime(
                        definition: documentDefinition,
                        renderEngine: self.renderEngine,
                        metalContext: self.metalContext,
                        metricsScope: sessionId,
                        reusing: session.document,
                        inspectedVideos: videos
                    )
                else {
                    rejectAndRestore("scene_update_resources_unavailable")
                    return
                }
                // Keep the last complete native output while the candidate prepares.
                replacement.applyBorrowedPresentation()
                self.prepareInitialVideoFrames(session: session, document: replacement, deadline: deadline) { ready in
                    if !session.playing || !self.applicationActive { replacement.pause() }
                    let current = self.sessions[sessionId] === session
                    guard ready && current && self.renderAndPublish(session: session, document: replacement) else {
                        replacement.tearDown()
                        let code = ready ? "scene_update_failed" : "scene_update_video_frame_timeout"
                        rejectAndRestore(code)
                        return
                    }
                    let previous = session.document
                    replacement.commitBorrowedPresentation()
                    session.document = replacement
                    session.sceneId = replacement.sceneId
                    previous.tearDown()
                    self.reconcileRenderTimer()
                    let backend: Any = session.observedBackend?.payload ?? NSNull()
                    DispatchQueue.main.async { result(["accepted": true, "observedBackend": backend]) }
                }
            }
        }
    }

    private func updateViewport(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let width = (arguments["width"] as? NSNumber)?.doubleValue,
            let height = (arguments["height"] as? NSNumber)?.doubleValue,
            let scale = (arguments["devicePixelRatio"] as? NSNumber)?.doubleValue,
            width.isFinite,
            height.isFinite,
            scale.isFinite,
            width > 0,
            height > 0,
            scale > 0
        else {
            result(Self.error("viewport_invalid", "Invalid scene viewport."))
            return
        }
        let dimensions = Self.foregroundDimensions(
            width: width * scale,
            height: height * scale
        )
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async {
                    result(Self.error("session_not_found", "The scene session is not attached."))
                }
                return
            }
            if session.width != dimensions.width ||
                session.height != dimensions.height {
                self.invalidatePerformanceProbe(session)
            }
            let previousWidth = session.width
            let previousHeight = session.height
            session.width = dimensions.width
            session.height = dimensions.height
            guard self.renderAndPublish(session: session) else {
                session.width = previousWidth
                session.height = previousHeight
                session.pools = Self.retainingBufferPoolForFailedResize(
                    session.pools,
                    previousWidth: previousWidth,
                    previousHeight: previousHeight
                )
                DispatchQueue.main.async {
                    result(Self.error("viewport_render_failed", "The resized scene could not be rendered."))
                }
                return
            }
            session.pools = session.pools.filter { key, _ in
                key.width == dimensions.width && key.height == dimensions.height
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func setPlaying(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let playing = arguments["playing"] as? Bool
        else {
            result(Self.error("playback_invalid", "Invalid scene playback update."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async {
                    result(Self.error("session_not_found", "The scene session is not attached."))
                }
                return
            }
            if session.playing != playing {
                self.invalidatePerformanceProbe(session)
            }
            session.playing = playing
            if self.isSessionPlaying(session) {
                session.document.play()
            } else {
                self.finishSignal(session, error: "signal_playback_suspended")
                session.document.pause()
                session.document.resetEffects()
                session.reactiveFrame = SceneSurfaceReactiveFrame()
            }
            _ = self.renderAndPublish(session: session)
            self.reconcileRenderTimer()
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func updateAudioFrame(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let frameDefinition = arguments["frame"] as? [String: Any]
        else {
            result(Self.error("audio_frame_invalid", "Invalid visual-audio frame."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async {
                    result(Self.error("session_not_found", "The scene session is not attached."))
                }
                return
            }
            if !self.acceptAudioFrame(frameDefinition, session: session) {
                DispatchQueue.main.async { result(nil) }
                return
            }
            session.document.updateAudioFrame(frameDefinition)
            session.reactiveFrame = SceneSurfaceReactiveFrame(
                arguments: frameDefinition
            )
            session.audioRevision &+= 1
            self.reconcileRenderTimer()
            let frame = self.freshReactiveFrame(session)
            if session.playing,
               session.document.isAudioReactive,
               !session.document.needsContinuousRendering(frame: frame) {
                self.scheduleEventRender(session)
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func updateSignalFrame(arguments: Any?, result: @escaping FlutterResult) {
        guard let arguments = arguments as? [String: Any],
              let sessionId = Self.nonEmpty(arguments["sessionId"]),
              let bytes = (arguments["frameBytes"] as? FlutterStandardTypedData)?.data,
              let frame = SceneRenderSignalFrameV2Codec.decode(bytes)
        else {
            result(Self.error("signal_invalid", "Invalid complete visual signal."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async {
                    result(Self.error("session_not_found", "The scene session is not attached."))
                }
                return
            }
            guard session.pendingSignalResult == nil else {
                DispatchQueue.main.async {
                    result(Self.error("signal_in_flight", "The previous signal has not been presented."))
                }
                return
            }
            if session.signalSessionId != frame.sessionId {
                session.signalSessionId = frame.sessionId
                session.signalSequence = -1
            }
            guard frame.sequence > session.signalSequence else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            session.signalSequence = frame.sequence
            guard self.isSessionPlaying(session) else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let changed = session.document.updateSignalFrame(frame)
            self.reconcileRenderTimer()
            guard changed else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            session.audioRevision &+= 1
            session.pendingSignalToken &+= 1
            let token = session.pendingSignalToken
            session.pendingSignalResult = result
            // The bounded Dart dispatcher waits for publication before sending
            // another event. Cadence and event delivery share this same surface.
            if !session.document.needsContinuousRendering(frame: self.freshReactiveFrame(session)) {
                self.scheduleEventRender(session)
            }
            session.signalDeadline.arm(after: 2) { [weak self, weak session] in
                guard let self, let session,
                      self.sessions[session.id] === session,
                      session.pendingSignalToken == token,
                      session.pendingSignalResult != nil else { return }
                self.finishSignal(session, error: "signal_presentation_timeout")
            }
        }
    }

    private func finishFilterUpdate(_ session: Session, error code: String? = nil) {
        session.filterDeadline.cancel()
        guard let result = session.pendingFilterResult else { return }
        session.pendingFilterResult = nil
        let update = session.pendingFilterUpdate
        session.pendingFilterUpdate = nil
        if code != nil { update?.rollback() }
        let backend: Any = session.observedBackend?.payload ?? NSNull()
        DispatchQueue.main.async {
            if let code {
                result(Self.error(code, "The visual edit was not fully presented."))
            } else {
                result(["accepted": true, "observedBackend": backend])
            }
        }
    }

    private func finishSignal(_ session: Session, error code: String? = nil) {
        session.signalDeadline.cancel()
        guard let result = session.pendingSignalResult else { return }
        session.pendingSignalResult = nil
        DispatchQueue.main.async {
            if let code {
                result(Self.error(code, "The complete visual signal was not presented."))
            } else {
                result(nil)
            }
        }
    }

    private func activeSurfaceForScene(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            let sceneId = Self.exactSceneId(arguments["sceneId"])
        else {
            result(Self.error("scene_id_invalid", "Invalid exact scene identifier."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let matches = self.sessions.values.filter {
                $0.sceneId == sceneId
            }
            guard matches.count <= 1 else {
                DispatchQueue.main.async {
                    result(
                        Self.error(
                            "scene_surface_ambiguous",
                            "More than one native surface renders the exact scene ID."
                        )
                    )
                }
                return
            }
            guard let session = matches.first else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let boundedInt: (UInt64) -> Int = {
                Int(min($0, UInt64(Int.max)))
            }
            var payload: [String: Any] = [
                "sceneId": session.sceneId,
                "sessionId": session.id,
                "rendererRevision": Self.rendererRevision,
                "publishedFrameCount": boundedInt(session.publishedFrameCount),
                "sampleTimeSeconds": CACurrentMediaTime(),
                "generation": boundedInt(session.generation),
                "videoReservations": SceneSurfaceVideoReservations.shared.diagnostics,
                "videoSources": session.document.layers.compactMap { $0.videoDiagnostics },
                "creatorPrograms": session.document.layers.compactMap { $0.creatorMetrics },
                "residentOutputBuffers": session.publishedBufferBudget.residentCount,
                "preparing": session.preparationId != nil || self.documentInspections[session.id] != nil,
                "playing": session.playing,
            ]
            if let backendClass = session.observedBackend?.backendClass {
                payload["backendClass"] = backendClass
            }
            payload.merge(session.gpuFrameTiming.payload) { _, latest in latest }
            let snapshot = payload
            DispatchQueue.main.async {
                result(snapshot)
            }
        }
    }

    private func startPerformanceProbe(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let arguments = arguments as? [String: Any],
            let sceneId = Self.exactSceneId(arguments["sceneId"])
        else {
            result(Self.error("scene_id_invalid", "Invalid exact scene identifier."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let matches = self.sessions.values.filter {
                $0.sceneId == sceneId
            }
            guard matches.count <= 1 else {
                DispatchQueue.main.async {
                    result(
                        Self.error(
                            "scene_surface_ambiguous",
                            "More than one native surface renders the exact scene ID."
                        )
                    )
                }
                return
            }
            guard let session = matches.first else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            guard session.performanceProbe == nil else {
                DispatchQueue.main.async {
                    result(
                        Self.error(
                            "probe_already_active",
                            "This native scene surface already has an active probe."
                        )
                    )
                }
                return
            }
            let probe = PerformanceProbe(
                token: UUID().uuidString,
                sceneId: session.sceneId,
                sessionId: session.id,
                generation: session.generation,
                startedAt: CACurrentMediaTime(),
                renderPathBaseline:
                    self.metalContext?.renderPathMetrics.snapshot(
                        scope: session.id
                    )
            )
            session.performanceProbe = probe
            DispatchQueue.main.async {
                result([
                    "probeToken": probe.token,
                    "sceneId": probe.sceneId,
                    "sessionId": probe.sessionId,
                    "rendererRevision": Self.rendererRevision,
                ])
            }
        }
    }

    private func stopPerformanceProbe(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard
            let identity = Self.probeIdentity(arguments),
            identity.rendererRevision == Self.rendererRevision
        else {
            result(Self.error("probe_identity_invalid", "Invalid native probe identity."))
            return
        }
        renderQueue.async { [weak self] in
            guard
                let self,
                let session = self.sessions[identity.sessionId],
                session.sceneId == identity.sceneId,
                session.generation > 0,
                let probe = session.performanceProbe,
                probe.token == identity.token,
                probe.sceneId == identity.sceneId,
                probe.sessionId == identity.sessionId,
                probe.generation == session.generation
            else {
                DispatchQueue.main.async {
                    result(
                        Self.error(
                            "probe_invalidated",
                            "The native scene surface changed while it was measured."
                        )
                    )
                }
                return
            }
            session.performanceProbe = nil
            let finishedAt = CACurrentMediaTime()
            let durationMicros = Int(
                max((finishedAt - probe.startedAt) * 1_000_000, 0).rounded()
            )
            let sorted = probe.frameDurationsMilliseconds.sorted()
            let pathSnapshot = self.metalContext?.renderPathMetrics.snapshot(
                scope: session.id
            )
            let pathBaseline = probe.renderPathBaseline
            func delta(
                _ current: UInt64?,
                _ baseline: UInt64?
            ) -> Int {
                guard let current else { return 0 }
                let value = current >= (baseline ?? 0)
                    ? current - (baseline ?? 0)
                    : 0
                return Int(min(value, UInt64(Int.max)))
            }
            let sampleCount = sorted.count
            let average: Double
            let p95: Double
            let jankPercent: Double
            if sampleCount == 0 {
                average = 0
                p95 = 0
                jankPercent = 0
            } else {
                average = sorted.reduce(0, +) / Double(sampleCount)
                let p95Index = Int(
                    (Double(sampleCount - 1) * 0.95).rounded()
                )
                p95 = sorted[p95Index]
                jankPercent = Double(probe.jankFrameCount) /
                    Double(sampleCount) * 100
            }
            let currentPath = pathSnapshot?.currentPath ?? "unavailable"
            let capabilityFingerprint = SceneSurfaceBackendCapabilities(
                metalContext: self.metalContext
            ).fingerprint(
                rendererRevision: Self.rendererRevision,
                backendClass: currentPath
            )
            DispatchQueue.main.async {
                result([
                    "sceneId": probe.sceneId,
                    "sessionId": probe.sessionId,
                    "durationMicros": durationMicros,
                    "sampleCount": sampleCount,
                    "averageFrameMilliseconds": average,
                    "p95FrameMilliseconds": p95,
                    "jankFrameCount": probe.jankFrameCount,
                    "jankPercent": jankPercent,
                    "targetFramesPerSecond": sampleCount == 0
                        ? 0
                        : probe.targetFramesPerSecond,
                    "gpuSubmitted": delta(
                        pathSnapshot?.gpuSubmitted,
                        pathBaseline?.gpuSubmitted
                    ),
                    "gpuCompleted": delta(
                        pathSnapshot?.gpuCompleted,
                        pathBaseline?.gpuCompleted
                    ),
                    "cpuReference": delta(
                        pathSnapshot?.cpuReference,
                        pathBaseline?.cpuReference
                    ),
                    "fallback": delta(
                        pathSnapshot?.fallback,
                        pathBaseline?.fallback
                    ),
                    "currentPath": currentPath,
                    "metalPipelineAvailable":
                        pathSnapshot?.metalPipelineAvailable ?? false,
                    "gpuFailureLatched":
                        pathSnapshot?.gpuFailureLatched ?? false,
                    "capabilityFingerprint": capabilityFingerprint,
                    "rendererRevision": Self.rendererRevision,
                ])
            }
        }
    }

    private func cancelPerformanceProbe(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard let identity = Self.probeIdentity(arguments) else {
            result(Self.error("probe_identity_invalid", "Invalid native probe identity."))
            return
        }
        renderQueue.async { [weak self] in
            if
                let session = self?.sessions[identity.sessionId],
                session.sceneId == identity.sceneId,
                let probe = session.performanceProbe,
                probe.token == identity.token
            {
                session.performanceProbe = nil
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func invalidatePerformanceProbe(_ session: Session) {
        dispatchPrecondition(condition: .onQueue(renderQueue))
        session.performanceProbe = nil
        session.generation &+= 1
        session.gpuFrameTiming = SceneSurfaceGPUFrameTiming()
    }

    private func recordPerformanceProbe(
        session: Session,
        document: SceneSurfaceDocumentRuntime,
        frame: SceneSurfaceReactiveFrame,
        startedAt: CFTimeInterval,
        finishedAt: CFTimeInterval
    ) {
        guard
            let probe = session.performanceProbe,
            probe.sceneId == session.sceneId,
            probe.sessionId == session.id,
            probe.generation == session.generation
        else {
            return
        }
        let milliseconds = min(
            max((finishedAt - startedAt) * 1_000, 0),
            1_000
        )
        guard milliseconds.isFinite else { return }
        let framesPerSecond = document.preferredFramesPerSecond(frame: frame)
        let safeFramesPerSecond = min(max(framesPerSecond, 1), 60)
        probe.frameDurationsMilliseconds.append(milliseconds)
        probe.targetFramesPerSecond = max(
            probe.targetFramesPerSecond,
            safeFramesPerSecond
        )
        let frameBudgetMilliseconds = 1_000 / Double(safeFramesPerSecond)
        if milliseconds > frameBudgetMilliseconds * 1.1 {
            probe.jankFrameCount += 1
        }
    }

    private func detach(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"])
        else {
            result(Self.error("detach_invalid", "Invalid scene session identifier."))
            return
        }
        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            self.documentInspections[sessionId]?.operation.cancel()
            guard let session = self.sessions[sessionId] else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            session.foregroundAttached = false
            if session.pipSource == nil { self.destroySession(session) }
            else if !self.isSessionPlaying(session) { session.document.pause() }
            self.reconcileRenderTimer()
            DispatchQueue.main.async { result(nil) }
        }
    }

    private func disposeAll(result: FlutterResult?) {
        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result?(nil) }
                return
            }
            self.cancelRenderTimer()
            Array(self.documentInspections.values).forEach { $0.operation.cancel() }
            let attached = Array(self.sessions.values)
            self.sessions.removeAll()
            attached.forEach {
                $0.cancelPreparation?()
                self.finishSignal($0, error: "signal_session_disposed")
                self.finishFilterUpdate($0, error: "scene_controls_session_disposed")
                $0.document.tearDown()
                self.metalContext?.renderPathMetrics.removeScope($0.id)
                $0.pools.removeAll()
            }
            attached.forEach { self.unregisterTexture($0) }
            DispatchQueue.main.async { result?(nil) }
        }
    }

    private func acceptAudioFrame(
        _ frame: [String: Any],
        session: Session
    ) -> Bool {
        guard let sequence = (frame["sequence"] as? NSNumber)?.intValue else {
            return true
        }
        let audioSessionId =
            (frame["audioSessionId"] as? NSNumber)?.intValue ?? 0
        if audioSessionId != session.audioSessionId {
            session.audioSessionId = audioSessionId
            session.audioSequence = -1
        }
        guard sequence > session.audioSequence else { return false }
        session.audioSequence = sequence
        return true
    }

    private func scheduleEventRender(_ session: Session) {
        guard isSessionPlaying(session), !session.eventRenderScheduled else { return }
        session.eventRenderScheduled = true
        let elapsed = CACurrentMediaTime() - session.lastRenderedAt
        let framesPerSecond = session.document.preferredFramesPerSecond(
            frame: freshReactiveFrame(session)
        )
        let delay = max((1.0 / Double(framesPerSecond)) - elapsed, 0)
        renderQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak session] in
            guard
                let self,
                let session,
                self.sessions[session.id] === session,
                self.isSessionPlaying(session)
            else {
                session?.eventRenderScheduled = false
                return
            }
            session.eventRenderScheduled = false
            _ = self.renderAndPublish(session: session)
            self.reconcileRenderTimer()
        }
    }

    private func reconcileRenderTimer() {
        dispatchPrecondition(condition: .onQueue(renderQueue))
        var framesPerSecond = 0
        for session in sessions.values where session.preparationId == nil && (isSessionPlaying(session) || (applicationActive && session.pendingFilterResult != nil)) {
            let frame = freshReactiveFrame(session)
            if session.document.needsContinuousRendering(frame: frame) || session.pendingFilterResult != nil {
                framesPerSecond = max(
                    framesPerSecond,
                    session.pendingFilterResult != nil ? 60 : session.document.preferredFramesPerSecond(frame: frame)
                )
            }
        }
        guard framesPerSecond > 0 else {
            cancelRenderTimer()
            return
        }
        let cappedFramesPerSecond = min(max(framesPerSecond, 1), 60)
        if renderTimer != nil,
           renderTimerFramesPerSecond == cappedFramesPerSecond {
            return
        }
        cancelRenderTimer()
        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        timer.schedule(
            deadline: .now() + (1.0 / Double(cappedFramesPerSecond)),
            repeating: .nanoseconds(1_000_000_000 / cappedFramesPerSecond),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            for session in self.sessions.values where self.isSessionPlaying(session) || (self.applicationActive && session.pendingFilterResult != nil) {
                let frame = self.freshReactiveFrame(session)
                guard session.document.needsContinuousRendering(frame: frame) || session.pendingFilterResult != nil else {
                    continue
                }
                let requested = session.pendingFilterResult != nil ? 60 : session.document.preferredFramesPerSecond(
                    frame: frame
                )
                if session.scheduledCadenceClock.consumeIfDue(
                    at: now,
                    framesPerSecond: requested
                ) {
                    _ = self.renderAndPublish(
                        session: session,
                        scheduled: true
                    )
                }
            }
            self.reconcileRenderTimer()
        }
        renderTimer = timer
        renderTimerFramesPerSecond = cappedFramesPerSecond
        timer.resume()
    }

    private func cancelRenderTimer() {
        renderTimer?.setEventHandler {}
        renderTimer?.cancel()
        renderTimer = nil
        renderTimerFramesPerSecond = nil
    }

    private func unregisterTexture(_ session: Session) {
        guard session.flutterTextureRegistered else { return }
        session.flutterTextureRegistered = false
        DispatchQueue.main.async { self.textureRegistry.unregisterTexture(session.textureId) }
    }

    /// One shared deadline for all videos, yielding between checks so pause,
    /// cancellation and teardown are never blocked by decoder readiness.
    private func prepareInitialVideoFrames(
        session: Session,
        document: SceneSurfaceDocumentRuntime,
        deadline suppliedDeadline: CFTimeInterval? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        let identity = UUID()
        session.preparationId = identity
        let deadline = suppliedDeadline ?? (CACurrentMediaTime() + Self.initialVideoFrameWait)
        let finish: (Bool) -> Void = { [weak session] ready in
            guard let session, session.preparationId == identity else { return }
            session.preparationId = nil
            session.cancelPreparation = nil
            completion(ready)
        }
        session.cancelPreparation = { finish(false) }
        var started = false
        func poll() {
            guard session.preparationId == identity else { return }
            guard self.sessions[session.id] === session else { finish(false); return }
            guard CACurrentMediaTime() < deadline else { finish(false); return }
            // A texture may attach before didBecomeActive at cold launch. Wait
            // within the same deadline instead of rejecting a valid document.
            // Never start decoders while the application is inactive.
            if self.applicationActive {
                if !started { document.play(); started = true }
                if document.prepareInitialVideoFrames(hostTime: CACurrentMediaTime()) { finish(true); return }
            } else if started {
                document.pause()
                started = false
            }
            self.renderQueue.asyncAfter(deadline: .now() + Self.initialVideoFramePollInterval, execute: poll)
        }
        poll()
    }

    @discardableResult
    private func renderAndPublish(
        session: Session,
        document: SceneSurfaceDocumentRuntime? = nil,
        scheduled: Bool = false
    ) -> Bool {
        guard session.preparationId == nil else { return false }
        return autoreleasepool {
            let document = document ?? session.document
            let observedBackendBaseline = metalContext?.renderPathMetrics
                .snapshot(scope: session.id)
            let targetRect = CGRect(
                x: 0,
                y: 0,
                width: session.width,
                height: session.height
            )
            let renderStartedAt = CACurrentMediaTime()
            let hostTime = renderStartedAt
            let frame = freshReactiveFrame(session)
            var sourcesPrepared = false
            if scheduled {
                session.lastFrameCheckAt = hostTime
                let audioAdvanced =
                    session.audioRevision != session.lastRenderedAudioRevision
                let observedWork = document.prepareScheduledFrame(
                    hostTime: hostTime,
                    frame: frame,
                    audioAdvanced: audioAdvanced
                )
                guard session.compositionRetryState.shouldCompose(
                    observedWork: observedWork || session.pendingFilterResult != nil
                ) else {
                    return false
                }
                sourcesPrepared = true
            } else {
                document.prepareForcedFrame(hostTime: hostTime, frame: frame)
            }
            document.filterState.advance(at: hostTime)
            session.gpuFrameTiming.invalidateLatest()
            guard let buffer = makePixelBuffer(session: session) else {
                return false
            }
            var published = false
            defer {
                if !published {
                    document.layers.forEach { $0.invalidateStableSourceRaster() }
                }
            }
            let graphEligible = document.onePassLayers != nil
            let attemptedOnePass = graphEligible && metalContext != nil
            let fallbackBaseline = metalContext?.renderPathMetrics.snapshot(
                scope: session.id
            ).fallback ?? 0
            let onePassResult = renderSceneSurfaceOnePass(
                graph: document.onePassLayers,
                targetRect: targetRect,
                targetBuffer: buffer,
                hostTime: hostTime,
                musicActive: frame.shouldReact,
                flowDrive: frame.flowDrive,
                bodyDrive: frame.bodyDrive,
                sparkDrive: frame.sparkDrive,
                sourcesPrepared: sourcesPrepared,
                compositor: graphEligible ? metalContext?.onePassCompositor : nil,
                metricsScope: session.id
            )
            if onePassResult != .rendered {
                guard
                    let image = compose(
                        document: document,
                        targetRect: targetRect,
                        hostTime: hostTime,
                        frame: frame,
                        sourcesPrepared: sourcesPrepared || attemptedOnePass
                    )
                else {
                    return false
                }
                guard renderSceneSurfaceCIFinalFrame(
                    image: image,
                    to: buffer,
                    bounds: targetRect,
                    colorSpace: outputColorSpace,
                    context: ciContext,
                    metrics: metalContext?.renderPathMetrics,
                    metricsScope: session.id
                ) else {
                    return false
                }
                if attemptedOnePass {
                    metalContext?.renderPathMetrics.recordCIFallback(
                        path: onePassResult == .failed
                            ? "one_pass_failure_v12_ci"
                            : "one_pass_unsupported_v12_ci",
                        scope: session.id,
                        ifFallbackCountEquals: fallbackBaseline
                    )
                }
                var remainingGPURecoveries = document.layers.count
                while document.recoverFromGPUCommandFailure() {
                    guard
                        remainingGPURecoveries > 0,
                        let recoveredImage = compose(
                            document: document,
                            targetRect: targetRect,
                            hostTime: hostTime,
                            frame: frame,
                            sourcesPrepared: true
                        )
                    else {
                        return false
                    }
                    guard renderSceneSurfaceCIFinalFrame(
                        image: recoveredImage,
                        to: buffer,
                        bounds: targetRect,
                        colorSpace: outputColorSpace,
                        context: ciContext,
                        metrics: metalContext?.renderPathMetrics,
                        metricsScope: session.id
                    ) else {
                        return false
                    }
                    remainingGPURecoveries -= 1
                }
            }
            let completedSnapshot = metalContext?.renderPathMetrics.snapshot(
                scope: session.id
            )
            if
                let baseline = observedBackendBaseline,
                let snapshot = completedSnapshot
            {
                session.observedBackend = SceneSurfaceObservedBackendReceipt
                    .certified(
                        baseline: baseline,
                        snapshot: snapshot,
                        fingerprints: backendFingerprints,
                        subpassesSettledSuccessfully:
                            document.gpuSubpassesSettledSuccessfully
                    )
            } else {
                session.observedBackend = nil
            }
            if let baseline = observedBackendBaseline,
               let snapshot = completedSnapshot {
                session.gpuFrameTiming.record(
                    baseline: baseline,
                    snapshot: snapshot,
                    completedAt: CACurrentMediaTime()
                )
            }
            recordPerformanceProbe(
                session: session,
                document: document,
                frame: frame,
                startedAt: renderStartedAt,
                finishedAt: CACurrentMediaTime()
            )
            session.texture.publish(buffer)
            published = true
            document.layers.forEach { $0.didPublishNativeProgram(hostTime: hostTime) }
            if document === session.document {
                finishSignal(session)
                if !document.filterState.active { finishFilterUpdate(session) }
            }
            if session.publishedFrameCount < UInt64.max {
                session.publishedFrameCount += 1
            }
            session.lastRenderedAt = hostTime
            session.lastFrameCheckAt = hostTime
            session.lastRenderedAudioRevision = session.audioRevision
            session.compositionRetryState.didPublish()
            if !scheduled {
                document.markForcedFrameRendered(hostTime: hostTime)
                if document.needsContinuousRendering(frame: frame) {
                    session.scheduledCadenceClock.markEvaluated(
                        at: hostTime,
                        framesPerSecond:
                            document.preferredFramesPerSecond(frame: frame)
                    )
                }
            }
            let textureId = session.textureId
            DispatchQueue.main.async { [weak self] in
                self?.textureRegistry.textureFrameAvailable(textureId)
            }
            return true
        }
    }

    private func makePixelBuffer(session: Session) -> CVPixelBuffer? {
        let key = BufferPoolKey(width: session.width, height: session.height)
        // Free unused pools before considering capacity. Buffers still held by
        // Flutter/AVKit remain in the shared budget even after their pool dies.
        session.pools = session.pools.filter { $0.key == key }
        let limit = session.publishedBufferBudget.allocationLimit(width: session.width, height: session.height, pool: session.pools[key])
        guard limit > 0 else { return nil }
        let pool: CVPixelBufferPool
        if let existing = session.pools[key] {
            pool = existing
        } else {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: session.width,
                kCVPixelBufferHeightKey: session.height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ]
            var created: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                [kCVPixelBufferPoolMinimumBufferCountKey: 1] as CFDictionary,
                attributes as CFDictionary,
                &created
            )
            guard status == kCVReturnSuccess, let created else { return nil }
            session.pools[key] = created
            pool = created
        }
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                kCFAllocatorDefault,
                pool,
                [kCVPixelBufferPoolAllocationThresholdKey: limit] as CFDictionary,
                &buffer
            ) == kCVReturnSuccess
        else {
            return nil
        }
        guard let buffer, session.publishedBufferBudget.track(buffer, pool: pool) else { return nil }
        return buffer
    }

    private func compose(
        document: SceneSurfaceDocumentRuntime,
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame,
        sourcesPrepared: Bool = false
    ) -> CIImage? {
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        ).cropped(to: targetRect)

        var authoredSources = [CIImage]()
        func flushAuthoredSources() -> Bool {
            guard !authoredSources.isEmpty else { return true }
            guard let next = try? SceneCatalogBlendKernel.sourceOverSequence(
                authoredSources, background: composed, target: targetRect
            ) else { return false }
            composed = next
            authoredSources.removeAll(keepingCapacity: true)
            return true
        }

        for layer in document.layers {
            let rawSource: CIImage?
            if layer.sourceKind == "procedural" {
                rawSource = layer.currentProceduralImage(
                    forceRefresh: !sourcesPrepared,
                    width: Int(targetRect.width),
                    height: Int(targetRect.height)
                ) {
                    proceduralImage(
                        layer: layer,
                        targetRect: targetRect,
                        hostTime: hostTime,
                        frame: frame
                    )
                }
            } else {
                rawSource = layer.currentImage(
                    forcePoster: false,
                    hostTime: hostTime,
                    width: Int(targetRect.width),
                    height: Int(targetRect.height),
                    refreshSource: !sourcesPrepared
                )
            }
            guard
                let rawSource,
                let normalized = layer.normalizedImage(rawSource)
            else {
                return nil
            }
            guard let rendered = layer.preparedCompositionImage(
                normalized,
                targetRect: targetRect,
                build: {
                    var source = normalized
                    if let effect = layer.rgbGainEffect {
                        source = applyRGBGain(source, gain: effect.gain)
                    }
                    if let effect = layer.naturalReactiveLightEffect {
                        source = effect.apply(to: source)
                    }
                    var rendered = transform(
                        source,
                        layer: layer,
                        targetRect: targetRect,
                        frame: frame
                    )
                    rendered = applyLayerAudio(
                        rendered,
                        layer: layer,
                        targetRect: targetRect,
                        frame: frame
                    )
                    return applyOpacity(rendered, opacity: layer.opacity)
                }
            ) else { return nil }
            if layer.usesAuthoredSourceOver && layer.blendMode == "sourceOver" {
                authoredSources.append(rendered)
            } else {
                guard flushAuthoredSources() else { return nil }
                composed = blend(
                    rendered,
                    over: composed,
                    mode: layer.blendMode,
                    targetRect: targetRect
                )
            }
        }
        guard flushAuthoredSources() else { return nil }
        return document.filterState.value.render(composed, target: targetRect)
    }

    private func applyRGBGain(_ input: CIImage, gain: Double) -> CIImage {
        guard gain > 1.00001 else { return input }
        return input.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]
        )
    }

    private func transform(
        _ input: CIImage,
        layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        frame: SceneSurfaceReactiveFrame
    ) -> CIImage {
        let definition = layer.transform
        let width = targetRect.width * definition.width
        let height = targetRect.height * definition.height
        let layerRect = CGRect(
            x: targetRect.midX - width * 0.5 +
                targetRect.width * definition.offsetX,
            y: targetRect.midY - height * 0.5 -
                targetRect.height * definition.offsetY,
            width: width,
            height: height
        )
        var image = aspectFill(input, targetRect: layerRect)
        let binding = layer.audioBinding
        let pulse = min(
            max(
                1 + frame.reactivity *
                    (
                        frame.bassDrive * binding.pulseBass +
                            frame.impact * binding.pulseImpact
                    ),
                0.75
            ),
            1.5
        )
        let scale = definition.scale * CGFloat(pulse)
        let horizontalScale = definition.flipped ? -scale : scale
        let center = CGPoint(x: layerRect.midX, y: layerRect.midY)
        var affine = CGAffineTransform(
            translationX: center.x,
            y: center.y
        )
        affine = affine.rotated(by: -definition.rotation)
        affine = affine.scaledBy(x: horizontalScale, y: scale)
        affine = affine.translatedBy(x: -center.x, y: -center.y)
        return image.transformed(by: affine).cropped(to: targetRect)
    }

    private func applyLayerAudio(
        _ input: CIImage,
        layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        frame: SceneSurfaceReactiveFrame
    ) -> CIImage {
        let binding = layer.audioBinding
        guard binding.isReactive else { return input }
        let brightness = frame.level * binding.brightnessLevel * frame.reactivity
        let contrast = 1 + frame.impact * binding.contrastImpact * frame.reactivity
        let saturation = 1 + frame.bodyDrive * binding.saturationBody * frame.reactivity
        var image = input.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputBrightnessKey: min(brightness, 0.35),
                kCIInputContrastKey: min(contrast, 1.8),
                kCIInputSaturationKey: min(saturation, 2.2),
            ]
        ).cropped(to: targetRect)
        let bloom = frame.sparkDrive * binding.bloomSpark * frame.reactivity +
            frame.hitStrength * binding.flashStrength
        if bloom > 0.01 {
            image = image.applyingFilter(
                "CIBloom",
                parameters: [
                    kCIInputRadiusKey: 3 + min(bloom, 1.5) * 10,
                    kCIInputIntensityKey: min(0.08 + bloom * 0.6, 0.9),
                ]
            ).cropped(to: targetRect)
        }
        return image
    }

    private func applyOpacity(_ input: CIImage, opacity: CGFloat) -> CIImage {
        guard opacity < 0.999 else { return input }
        return input.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            ]
        )
    }

    private func blend(
        _ foreground: CIImage,
        over background: CIImage,
        mode: String,
        targetRect: CGRect
    ) -> CIImage {
        let filterName: String
        switch mode {
        case "screen": filterName = "CIScreenBlendMode"
        case "add": filterName = "CIAdditionCompositing"
        case "multiply": filterName = "CIMultiplyBlendMode"
        default: filterName = "CISourceOverCompositing"
        }
        return foreground.applyingFilter(
            filterName,
            parameters: [kCIInputBackgroundImageKey: background]
        ).cropped(to: targetRect)
    }

    private func aspectFill(_ image: CIImage, targetRect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else {
            return image.cropped(to: targetRect)
        }
        let scale = max(
            targetRect.width / extent.width,
            targetRect.height / extent.height
        )
        let scaled = image.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        return scaled.transformed(
            by: CGAffineTransform(
                translationX: targetRect.midX - scaled.extent.midX,
                y: targetRect.midY - scaled.extent.midY
            )
        ).cropped(to: targetRect)
    }

    private func proceduralImage(
        layer: PictureInPictureSceneLayerRuntime,
        targetRect: CGRect,
        hostTime: CFTimeInterval,
        frame: SceneSurfaceReactiveFrame
    ) -> CIImage? {
        let colors = layer.palette.isEmpty
            ? [
                CIColor(red: 0.10, green: 0.86, blue: 0.92),
                CIColor(red: 0.94, green: 0.16, blue: 0.58),
                CIColor(red: 0.42, green: 0.31, blue: 1.00),
            ]
            : layer.palette
        var composed = CIImage(
            color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        ).cropped(to: targetRect)

        switch layer.proceduralPreset {
        case "native_program_v1":
            return layer.nativeProgramImage(
                targetRect: targetRect,
                hostTime: hostTime
            )
        case "deep_void_v1":
            return CIImage(
                color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)
            ).cropped(to: targetRect)
        case SceneSurfaceStatefulStormRecipeV1.preset:
            return layer.statefulStormImage(
                targetRect: targetRect,
                hostTime: hostTime
            )
        case SceneSurfaceFirefliesRecipeV1.preset:
            return layer.firefliesImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.shouldReact,
                flowDrive: frame.flowDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceInfernoEmbersRecipeV1.preset:
            return layer.infernoEmbersImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.shouldReact,
                flowDrive: frame.flowDrive,
                bodyDrive: frame.bodyDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceRadialWarpRecipeV1.preset:
            return layer.radialWarpImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.shouldReact,
                flowDrive: frame.flowDrive,
                bassDrive: frame.bassDrive,
                sparkDrive: frame.sparkDrive
            )
        case SceneSurfaceWildflowerPollenRecipeV1.preset:
            return layer.wildflowerPollenImage(
                targetRect: targetRect,
                hostTime: hostTime,
                musicActive: frame.shouldReact,
                flowDrive: frame.flowDrive,
                sparkDrive: frame.sparkDrive
            )
        case "aurora":
            for index in 0..<3 {
                let phase = hostTime * (0.20 + Double(index) * 0.035) +
                    Double(index) * 2.1
                let wave = CGFloat((sin(phase) + 1) * 0.5)
                let color = colors[index % colors.count]
                guard let band = CIFilter(
                    name: "CILinearGradient",
                    parameters: [
                        "inputPoint0": CIVector(
                            x: -targetRect.width * 0.2,
                            y: targetRect.height * (0.18 + wave * 0.62)
                        ),
                        "inputPoint1": CIVector(
                            x: targetRect.width * 1.2,
                            y: targetRect.height * (0.72 - wave * 0.42)
                        ),
                        "inputColor0": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0
                        ),
                        "inputColor1": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0.24 + CGFloat(frame.flowDrive) * 0.13
                        ),
                    ]
                )?.outputImage?.cropped(to: targetRect) else { continue }
                composed = band.applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: composed]
                ).cropped(to: targetRect)
            }
        case "liquid_lava":
            for index in 0..<4 {
                let phase = hostTime * (0.15 + Double(index) * 0.018) +
                    Double(index) * 1.7
                let xWave = CGFloat((sin(phase * 0.73) + 1) * 0.5)
                let yWave = CGFloat((cos(phase) + 1) * 0.5)
                let radiusWave = CGFloat(sin(phase * 1.3))
                let radius = targetRect.width * (
                    0.28 + 0.06 * radiusWave +
                        CGFloat(frame.bassDrive) * 0.07
                )
                let color = colors[index % colors.count]
                guard let blob = CIFilter(
                    name: "CIRadialGradient",
                    parameters: [
                        "inputCenter": CIVector(
                            x: targetRect.width * (0.18 + 0.64 * xWave),
                            y: targetRect.height * (0.12 + 0.76 * yWave)
                        ),
                        "inputRadius0": radius * 0.12,
                        "inputRadius1": radius,
                        "inputColor0": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0.38 + CGFloat(frame.flowDrive) * 0.12
                        ),
                        "inputColor1": CIColor(
                            red: color.red,
                            green: color.green,
                            blue: color.blue,
                            alpha: 0
                        ),
                    ]
                )?.outputImage?.cropped(to: targetRect) else { continue }
                composed = blob.applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: composed]
                ).cropped(to: targetRect)
            }
        default:
            return nil
        }
        return composed
    }

    private func applyFilter(
        _ filter: PictureInPictureSceneFilterRuntime?,
        to input: CIImage,
        targetRect: CGRect
    ) -> CIImage {
        guard let filter, filter.intensity > 0 else { return input }
        let amount = filter.intensity
        var image = input.applyingFilter(
            "CIExposureAdjust",
            parameters: [kCIInputEVKey: filter.exposure * amount]
        ).cropped(to: targetRect)
        image = image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputContrastKey: 1 + (filter.contrast - 1) * amount,
                kCIInputSaturationKey: 1 + (filter.saturation - 1) * amount,
            ]
        ).cropped(to: targetRect)
        if filter.vibrance != 0 {
            image = image.applyingFilter(
                "CIVibrance",
                parameters: ["inputAmount": filter.vibrance * amount]
            ).cropped(to: targetRect)
        }
        if filter.temperature != 0 || filter.tint != 0 {
            image = image.applyingFilter(
                "CITemperatureAndTint",
                parameters: [
                    "inputNeutral": CIVector(x: 6500, y: 0),
                    "inputTargetNeutral": CIVector(
                        x: 6500 + filter.temperature * amount * 2200,
                        y: filter.tint * amount * 140
                    ),
                ]
            ).cropped(to: targetRect)
        }
        if filter.blackLift != 0 {
            let lift = filter.blackLift * amount
            image = image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputBiasVector": CIVector(
                        x: lift,
                        y: lift,
                        z: lift,
                        w: 0
                    ),
                ]
            ).cropped(to: targetRect)
        }
        if filter.vignette > 0 {
            image = image.applyingFilter(
                "CIVignette",
                parameters: [
                    kCIInputIntensityKey: filter.vignette * amount,
                    kCIInputRadiusKey: min(targetRect.width, targetRect.height) *
                        filter.vignetteSoftness,
                ]
            ).cropped(to: targetRect)
        }
        return image
    }

    private func freshReactiveFrame(_ session: Session) -> SceneSurfaceReactiveFrame {
        session.reactiveFrame.freshened(
            nowMicros: Int64(Date().timeIntervalSince1970 * 1_000_000)
        )
    }

    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default
        for (name, active) in [
            (UIScene.didActivateNotification, true),
            (UIScene.willDeactivateNotification, false),
            (UIScene.didEnterBackgroundNotification, false),
        ] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self, let scene = notification.object as? UIWindowScene,
                      scene === self.windowProvider()?.windowScene else { return }
                self.setApplicationActive(active)
            })
        }
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.windowProvider()?.windowScene == nil else { return }
                self.setApplicationActive(true)
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.windowProvider()?.windowScene == nil else { return }
                self.setApplicationActive(false)
            }
        )
    }

    private func setApplicationActive(_ active: Bool) {
        v2ImageRuntime.setApplicationActive(active)
        renderQueue.async { [weak self] in
            guard let self else { return }
            let lifecycleChanged = self.applicationActive != active
            if lifecycleChanged {
                self.sessions.values.forEach {
                    self.invalidatePerformanceProbe($0)
                }
            }
            self.applicationActive = active
            for session in self.sessions.values {
                if self.isSessionPlaying(session) {
                    session.document.play()
                    _ = self.renderAndPublish(session: session)
                } else {
                    self.finishSignal(session, error: "signal_application_suspended")
                    self.finishFilterUpdate(session, error: "scene_controls_application_suspended")
                    session.document.pause()
                }
            }
            self.reconcileRenderTimer()
        }
    }

    private static func document(
        from arguments: [String: Any]
    ) -> [String: Any]? {
        (arguments["document"] as? [String: Any]) ??
            (arguments["sceneDocument"] as? [String: Any])
    }

    private static func viewport(
        from arguments: [String: Any]
    ) -> (width: Double, height: Double, scale: Double) {
        let width = (arguments["width"] as? NSNumber)?.doubleValue ?? 390
        let height = (arguments["height"] as? NSNumber)?.doubleValue ?? 844
        let scale =
            (arguments["devicePixelRatio"] as? NSNumber)?.doubleValue ?? 3
        guard
            width.isFinite,
            height.isFinite,
            scale.isFinite,
            width > 0,
            height > 0,
            scale > 0
        else {
            return (390, 844, 3)
        }
        return (width, height, scale)
    }

    private static func foregroundDimensions(
        width: Double,
        height: Double
    ) -> (width: Int, height: Int) {
        let safeWidth = max(width, 2)
        let safeHeight = max(height, 2)
        let dimensionScale = min(1, 1_440 / max(safeWidth, safeHeight))
        let pixelScale = min(1, sqrt(1_166_400 / (safeWidth * safeHeight)))
        let scale = min(dimensionScale, pixelScale)
        return (
            max(Int((safeWidth * scale).rounded()) & ~1, 2),
            max(Int((safeHeight * scale).rounded()) & ~1, 2)
        )
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func exactSceneId(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func probeIdentity(_ value: Any?) -> ProbeIdentity? {
        guard
            let arguments = value as? [String: Any],
            let token = nonEmpty(arguments["probeToken"]),
            let sceneId = exactSceneId(arguments["sceneId"]),
            let sessionId = nonEmpty(arguments["sessionId"]),
            let rendererRevision = nonEmpty(arguments["rendererRevision"])
        else {
            return nil
        }
        return ProbeIdentity(
            token: token,
            sceneId: sceneId,
            sessionId: sessionId,
            rendererRevision: rendererRevision
        )
    }

    private static func error(_ code: String, _ message: String) -> FlutterError {
        FlutterError(code: code, message: message, details: nil)
    }
}
