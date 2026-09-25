import CoreVideo
import Flutter
import Metal
import UIKit
import simd

@available(iOS 15.0, *)
final class MusicVibeFlutterTexture: NSObject, FlutterTexture {
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
final class MusicVibeRenderEngine: NSObject {
    private struct RenderOptions {
        var waveEnabled = true
        var pulseEnabled = true
        var randomFlashes = true
        var syncColorsWithMusic = true
        var waveSpeed = 5.0
        var brightness = 1.0
        var maxWaves = 10
        var runtimeTargetFramesPerSecond = 60
        var runtimeDetailScale = 1.0
        var runtimeMotionScale = 1.0
        var runtimeReduceMotion = false

        mutating func apply(_ values: [String: Any]) {
            if let value = values["waveEnabled"] as? Bool {
                waveEnabled = value
            }
            if let value = values["pulseEnabled"] as? Bool {
                pulseEnabled = value
            }
            if let value = values["randomFlashes"] as? Bool {
                randomFlashes = value
            }
            if let value = values["syncColorsWithMusic"] as? Bool {
                syncColorsWithMusic = value
            }
            if let value = (values["waveSpeed"] as? NSNumber)?.doubleValue {
                waveSpeed = min(max(value, 0.1), 10)
            }
            if let value = (values["brightness"] as? NSNumber)?.doubleValue {
                brightness = min(max(value, 0.1), 2)
            }
            if let value = (values["maxWaves"] as? NSNumber)?.intValue {
                maxWaves = min(max(value, 1), 40)
            }
            if let value = (values["runtimeTargetFps"] as? NSNumber)?.intValue {
                runtimeTargetFramesPerSecond = min(max(value, 1), 60)
            }
            if let value = (values["runtimeDetailScale"] as? NSNumber)?.doubleValue {
                runtimeDetailScale = min(max(value, 0.1), 1)
            }
            if let value = (values["runtimeMotionScale"] as? NSNumber)?.doubleValue {
                runtimeMotionScale = min(max(value, 0), 1)
            }
            if let value = values["runtimeReduceMotion"] as? Bool {
                runtimeReduceMotion = value
            }
        }

        var waveLifetime: CFTimeInterval {
            let normalized = (waveSpeed - 0.1) / 9.9
            return 2.2 - (1.2 * normalized)
        }
    }

    private struct Wave {
        let center: SIMD2<Float>
        let baseRadius: Float
        let color: SIMD3<Float>
        let pulse: Bool
        var createdAt: CFTimeInterval
    }

    private struct Flash {
        let color: SIMD3<Float>
        let strength: Float
        var createdAt: CFTimeInterval
    }

    private struct RenderGlobals {
        var resolution: SIMD2<Float>
        var brightness: Float
        var waveCount: UInt32
        var flashCount: UInt32
        var playing: UInt32
        var padding: SIMD2<Float> = .zero
    }

    private struct BufferPoolKey: Hashable {
        let width: Int
        let height: Int
    }

    private struct SplitMix64 {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
            value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
            return value ^ (value >> 31)
        }

        mutating func unit() -> Double {
            Double(next() >> 11) / 9_007_199_254_740_992.0
        }
    }

    private final class Session {
        let id: String
        let programId: String
        var random: SplitMix64
        var options = RenderOptions()
        var playing = true
        var logicalSize = CGSize(width: 390, height: 844)
        var foregroundWidth = 360
        var foregroundHeight = 640
        var texture: MusicVibeFlutterTexture?
        var textureId: Int64?
        var pictureInPictureReferences = 0
        var waves = [Wave]()
        var flashes = [Flash]()
        var pools = [BufferPoolKey: CVPixelBufferPool]()
        var audioSessionId = Int.min
        var audioSequence = -1
        var impactSerial = -1
        var flashSerial = -1
        var level = 0.0
        var pausedAt: CFTimeInterval?

        init(id: String, programId: String, seed: UInt64) {
            self.id = id
            self.programId = programId
            random = SplitMix64(seed: seed)
        }
    }

    private let channelName = "com.chic.dev/realtime_visual_renderer"
    private let textureRegistry: FlutterTextureRegistry
    private let renderQueue = DispatchQueue(
        label: "com.chic.dev.realtime-visual.render",
        qos: .userInteractive
    )
    private let queueKey = DispatchSpecificKey<Void>()
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private var waveScratch = Array(
        repeating: SIMD4<Float>(repeating: 0),
        count: 80
    )
    private var flashScratch = Array(
        repeating: SIMD4<Float>(repeating: 0),
        count: 40
    )
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private var sessions = [String: Session]()
    private var foregroundTimer: DispatchSourceTimer?
    private var foregroundTimerFramesPerSecond: Int?
    private var applicationActive: Bool
    private var notificationTokens = [NSObjectProtocol]()

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        let metalDevice = MTLCreateSystemDefaultDevice()
        device = metalDevice
        commandQueue = metalDevice?.makeCommandQueue()
        pipelineState = metalDevice.flatMap(Self.makePipeline)
        applicationActive = UIApplication.shared.applicationState == .active
        super.init()
        renderQueue.setSpecific(key: queueKey, value: ())
        if let metalDevice {
            CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil,
                metalDevice,
                nil,
                &textureCache
            )
        }
        observeApplicationLifecycle()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        // Creating a weak reference to self from deinit is invalid for NSObject.
        // Retire queue-owned work now; the main-thread callback retains only the registry.
        let textureIds = syncOnRenderQueue { retireAllSessions() }
        let registry = textureRegistry
        DispatchQueue.main.async {
            textureIds.forEach(registry.unregisterTexture)
        }
    }

    var isSupported: Bool {
        device != nil && commandQueue != nil && pipelineState != nil && textureCache != nil
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else {
                result(false)
                return
            }
            switch call.method {
            case "isSupported":
                result(self.isSupported)
            case "attach":
                self.attach(arguments: call.arguments, result: result)
            case "updateViewport":
                self.updateViewport(arguments: call.arguments, result: result)
            case "updateOptions":
                self.updateOptions(arguments: call.arguments, result: result)
            case "updateAudioFrame":
                self.updateAudioFrame(arguments: call.arguments, result: result)
            case "setPlaying":
                self.setPlaying(arguments: call.arguments, result: result)
            case "sendInteraction":
                self.sendInteraction(arguments: call.arguments, result: result)
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
        disposeAll()
    }

    func retainForPictureInPicture(
        sessionId: String,
        programId: String,
        seed: UInt64
    ) -> Bool {
        syncOnRenderQueue {
            guard isSupported, programId == "blinding_colors" else { return false }
            let session: Session
            if let existing = sessions[sessionId] {
                guard existing.programId == programId else { return false }
                session = existing
            } else {
                session = Session(id: sessionId, programId: programId, seed: seed)
                sessions[sessionId] = session
            }
            session.pictureInPictureReferences += 1
            return true
        }
    }

    func releasePictureInPicture(sessionId: String) {
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else { return }
            session.pictureInPictureReferences = max(
                session.pictureInPictureReferences - 1,
                0
            )
            self.removeSessionIfUnused(session)
        }
    }

    /// The scene owner supplies data-only authored controls; there is no hidden
    /// Flutter visual or extra foreground renderer session to apply them.
    static func sceneVisualOptions(_ controls: [String: Any]) -> [String: Any]? {
        let flags = ["Ondas": "waveEnabled", "Pulsos": "pulseEnabled",
                     "Destellos Aleatorios": "randomFlashes",
                     "Sincronizar Colores con Música": "syncColorsWithMusic"]
        let numbers: [String: (String, ClosedRange<Double>)] = [
            "Velocidad de Onda": ("waveSpeed", 0.1...10),
            "Brillo": ("brightness", 0.1...2),
            "Número Máximo de Ondas": ("maxWaves", 1...40),
        ]
        guard Set(controls.keys).isSubset(of: Set(flags.keys).union(numbers.keys)) else { return nil }
        var result = [String: Any]()
        for (key, target) in flags {
            guard let raw = controls[key] else { continue }
            guard let value = raw as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            result[target] = value.boolValue
        }
        for (key, pair) in numbers {
            guard let raw = controls[key] else { continue }
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite, pair.1.contains(value.doubleValue) else { return nil }
            result[pair.0] = pair.0 == "maxWaves" ? Double(value.intValue) : value.doubleValue
        }
        return result
    }

    func setRetainedProgramOptions(sessionId: String, options: [String: Any]) {
        syncOnRenderQueue {
            guard let session = sessions[sessionId] else { return }
            session.options.apply(options)
            if !session.options.waveEnabled { session.waves.removeAll() }
            if !session.options.randomFlashes { session.flashes.removeAll() }
            trim(session)
        }
    }

    func prepareRetainedProgramOptions(sessionId: String, options: [String: Any]) -> SceneCatalogControlUpdate? {
        syncOnRenderQueue {
            guard let session = sessions[sessionId] else { return nil }
            let previousOptions = session.options
            let previousWaves = session.waves
            let previousFlashes = session.flashes
            return SceneCatalogControlUpdate(apply: { [weak self] in
                self?.setRetainedProgramOptions(sessionId: sessionId, options: options)
            }, rollback: { [weak self] in
                self?.syncOnRenderQueue {
                    guard let current = self?.sessions[sessionId], current === session else { return }
                    current.options = previousOptions
                    current.waves = previousWaves
                    current.flashes = previousFlashes
                }
            })
        }
    }

    func renderPictureInPictureFrame(
        sessionId: String,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        syncOnRenderQueue {
            guard let session = sessions[sessionId] else { return nil }
            return render(session: session, width: width, height: height)
        }
    }

    func pictureInPictureNeedsContinuousFrames(sessionId: String) -> Bool {
        syncOnRenderQueue {
            guard let session = sessions[sessionId], session.playing else {
                return false
            }
            // Keep one final render after an effect expires. The render pass
            // prunes expired items and publishes the clean resting frame;
            // the following reconciliation can then stop the timer.
            return !session.waves.isEmpty || !session.flashes.isEmpty
        }
    }

    func pictureInPictureFramesPerSecond(sessionId: String) -> Int {
        syncOnRenderQueue {
            guard let session = sessions[sessionId] else { return 30 }
            return min(max(session.options.runtimeTargetFramesPerSecond, 1), 60)
        }
    }

    func updateAudioFrame(sessionId: String, arguments: [String: Any]) {
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else { return }
            if self.applyAudioFrame(arguments, to: session) {
                _ = self.renderForeground(session)
                self.reconcileForegroundTimer()
            }
        }
    }

    /// Renders a locally installed declarative node without registering a
    /// second Flutter texture. Signal ingestion and rendering share the same
    /// queue, so a V2 frame can never observe a partially applied event.
    func renderRetainedProgramFrame(
        sessionId: String,
        width: Int,
        height: Int,
        audioFrame: [String: Any]?
    ) -> CVPixelBuffer? {
        syncOnRenderQueue {
            guard let session = sessions[sessionId] else { return nil }
            if let audioFrame {
                _ = applyAudioFrame(audioFrame, to: session)
            }
            return render(session: session, width: width, height: height)
        }
    }

    /// Keeps the effect timeline phase stable while the scene is paused.
    func setRetainedProgramPlaying(sessionId: String, playing: Bool) {
        syncOnRenderQueue {
            guard let session = sessions[sessionId], session.playing != playing else {
                return
            }
            let now = CACurrentMediaTime()
            if playing, let pausedAt = session.pausedAt {
                let pauseDuration = max(0, now - pausedAt)
                for index in session.waves.indices {
                    session.waves[index].createdAt += pauseDuration
                }
                for index in session.flashes.indices {
                    session.flashes[index].createdAt += pauseDuration
                }
                session.pausedAt = nil
            } else if !playing {
                session.pausedAt = now
            }
            session.playing = playing
        }
    }

    private func attach(arguments: Any?, result: @escaping FlutterResult) {
        guard
            isSupported,
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let programId = Self.nonEmpty(arguments["programId"]),
            programId == "blinding_colors"
        else {
            result(nil)
            return
        }

        let texture = MusicVibeFlutterTexture()
        let textureId = textureRegistry.register(texture)
        guard textureId > 0 else {
            result(nil)
            return
        }
        let seed = (arguments["seed"] as? NSNumber)?.uint64Value ?? 1
        let options = arguments["options"] as? [String: Any] ?? [:]
        let textureRegistry = textureRegistry

        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async {
                    textureRegistry.unregisterTexture(textureId)
                    result(nil)
                }
                return
            }
            let session: Session
            if let existing = self.sessions[sessionId] {
                if let existingTextureId = existing.textureId {
                    DispatchQueue.main.async {
                        self.textureRegistry.unregisterTexture(textureId)
                        result(["textureId": existingTextureId])
                    }
                    return
                }
                session = existing
            } else {
                session = Session(id: sessionId, programId: programId, seed: seed)
                self.sessions[sessionId] = session
            }
            session.options.apply(options)
            session.texture = texture
            session.textureId = textureId
            let rendered = self.renderForeground(session)
            self.reconcileForegroundTimer()
            DispatchQueue.main.async {
                if rendered {
                    result(["textureId": textureId])
                } else {
                    self.textureRegistry.unregisterTexture(textureId)
                    self.renderQueue.async {
                        session.texture = nil
                        session.textureId = nil
                        self.removeSessionIfUnused(session)
                    }
                    result(nil)
                }
            }
        }
    }

    private func updateViewport(arguments: Any?, result: @escaping FlutterResult) {
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
            result(nil)
            return
        }
        mutate(sessionId: sessionId, result: result) { [weak self] session in
            guard let self else { return }
            session.logicalSize = CGSize(width: width, height: height)
            let dimensions = Self.foregroundDimensions(
                width: width * scale,
                height: height * scale
            )
            if session.foregroundWidth != dimensions.width ||
                session.foregroundHeight != dimensions.height {
                session.foregroundWidth = dimensions.width
                session.foregroundHeight = dimensions.height
            }
            _ = self.renderForeground(session)
        }
    }

    private func updateOptions(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let options = arguments["options"] as? [String: Any]
        else {
            result(nil)
            return
        }
        mutate(sessionId: sessionId, result: result) { [weak self] session in
            guard let self else { return }
            session.options.apply(options)
            if !session.options.waveEnabled { session.waves.removeAll() }
            if !session.options.randomFlashes { session.flashes.removeAll() }
            self.trim(session)
            _ = self.renderForeground(session)
            self.reconcileForegroundTimer()
        }
    }

    private func updateAudioFrame(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let frame = arguments["frame"] as? [String: Any]
        else {
            result(nil)
            return
        }
        mutate(sessionId: sessionId, result: result) { [weak self] session in
            guard let self else { return }
            if self.applyAudioFrame(frame, to: session) {
                _ = self.renderForeground(session)
                self.reconcileForegroundTimer()
            }
        }
    }

    private func setPlaying(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let playing = arguments["playing"] as? Bool
        else {
            result(nil)
            return
        }
        mutate(sessionId: sessionId, result: result) { [weak self] session in
            session.playing = playing
            _ = self?.renderForeground(session)
            self?.reconcileForegroundTimer()
        }
    }

    private func sendInteraction(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"]),
            let interaction = arguments["interaction"] as? [String: Any],
            interaction["type"] as? String == "tap",
            let x = (interaction["x"] as? NSNumber)?.doubleValue,
            let y = (interaction["y"] as? NSNumber)?.doubleValue
        else {
            result(nil)
            return
        }
        mutate(sessionId: sessionId, result: result) { [weak self] session in
            guard let self, session.playing, session.options.waveEnabled else { return }
            self.addWave(
                to: session,
                center: Self.canonicalPoint(
                    x: Self.unit(x),
                    y: Self.unit(y),
                    outputSize: session.logicalSize
                ),
                strength: session.level,
                allowQuiet: true
            )
            _ = self.renderForeground(session)
            self.reconcileForegroundTimer()
        }
    }

    private func detach(arguments: Any?, result: @escaping FlutterResult) {
        guard
            let arguments = arguments as? [String: Any],
            let sessionId = Self.nonEmpty(arguments["sessionId"])
        else {
            result(nil)
            return
        }
        renderQueue.async { [weak self] in
            guard let self, let session = self.sessions[sessionId] else {
                DispatchQueue.main.async { result(nil) }
                return
            }
            let textureId = session.textureId
            session.texture = nil
            session.textureId = nil
            self.removeSessionIfUnused(session)
            self.reconcileForegroundTimer()
            DispatchQueue.main.async {
                if let textureId {
                    self.textureRegistry.unregisterTexture(textureId)
                }
                result(nil)
            }
        }
    }

    private func mutate(
        sessionId: String,
        result: @escaping FlutterResult,
        _ mutation: @escaping (Session) -> Void
    ) {
        renderQueue.async { [weak self] in
            if let session = self?.sessions[sessionId] {
                mutation(session)
            }
            DispatchQueue.main.async { result(nil) }
        }
    }

    @discardableResult
    private func applyAudioFrame(_ frame: [String: Any], to session: Session) -> Bool {
        let audioSessionId = (frame["audioSessionId"] as? NSNumber)?.intValue ?? 0
        let sequence = (frame["sequence"] as? NSNumber)?.intValue ?? 0
        if audioSessionId == session.audioSessionId && sequence <= session.audioSequence {
            return false
        }
        if audioSessionId != session.audioSessionId {
            session.audioSessionId = audioSessionId
            session.audioSequence = -1
            session.impactSerial = -1
            session.flashSerial = -1
        }
        session.audioSequence = sequence
        let shouldReact = frame["shouldReact"] as? Bool ?? false
        let level = shouldReact ? Self.unit(frame["level"]) : 0
        session.level = level
        guard shouldReact, session.playing else { return false }

        var animationAdded = false

        let impactSerial = (frame["impactSerial"] as? NSNumber)?.intValue ?? 0
        let impactActive = frame["impactActive"] as? Bool ?? false
        if impactActive && impactSerial != session.impactSerial {
            session.impactSerial = impactSerial
            animationAdded = addWave(
                to: session,
                center: nil,
                strength: max(level, Self.unit(frame["impactStrength"])),
                allowQuiet: false
            ) || animationAdded
        }

        let flashSerial = (frame["flashSerial"] as? NSNumber)?.intValue ?? 0
        let flashActive = frame["flashActive"] as? Bool ?? false
        if flashActive && flashSerial != session.flashSerial {
            session.flashSerial = flashSerial
            animationAdded = addFlash(
                to: session,
                strength: max(Self.unit(frame["flashStrength"]), 0.25)
            ) || animationAdded
        }
        return animationAdded
    }

    @discardableResult
    private func addWave(
        to session: Session,
        center: SIMD2<Float>?,
        strength: Double,
        allowQuiet: Bool
    ) -> Bool {
        guard
            session.options.waveEnabled,
            allowQuiet || strength > 0.1
        else { return false }
        let resolvedCenter = center ?? SIMD2(
            Float(session.random.unit()),
            Float(session.random.unit())
        )
        let pulse = session.options.pulseEnabled && session.random.unit() > 0.8
        let minimumDimension = max(
            min(session.logicalSize.width, session.logicalSize.height),
            1
        )
        let radius = Float((50 + (Self.unit(strength) * 200)) / minimumDimension)
        let color = session.options.syncColorsWithMusic
            ? Self.color(for: strength)
            : Self.palette[Int(session.random.next() % UInt64(Self.palette.count))]
        session.waves.append(
            Wave(
                center: resolvedCenter,
                baseRadius: radius,
                color: color,
                pulse: pulse,
                createdAt: CACurrentMediaTime()
            )
        )
        trim(session)
        return true
    }

    @discardableResult
    private func addFlash(to session: Session, strength: Double) -> Bool {
        guard session.options.randomFlashes else { return false }
        let color = Self.palette[
            Int(session.random.next() % UInt64(Self.palette.count))
        ]
        session.flashes.append(
            Flash(
                color: color,
                strength: Float(Self.unit(strength)),
                createdAt: CACurrentMediaTime()
            )
        )
        trim(session)
        return true
    }

    private func trim(_ session: Session) {
        let limit = session.options.maxWaves
        if session.waves.count > limit {
            session.waves.removeFirst(session.waves.count - limit)
        }
        if session.flashes.count > limit {
            session.flashes.removeFirst(session.flashes.count - limit)
        }
    }

    @discardableResult
    private func renderForeground(_ session: Session) -> Bool {
        guard
            let texture = session.texture,
            let textureId = session.textureId,
            let buffer = render(
                session: session,
                width: session.foregroundWidth,
                height: session.foregroundHeight
            )
        else { return false }
        texture.publish(buffer)
        DispatchQueue.main.async { [weak self] in
            self?.textureRegistry.textureFrameAvailable(textureId)
        }
        return true
    }

    private func render(
        session: Session,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        dispatchPrecondition(condition: .onQueue(renderQueue))
        guard
            let device,
            let commandQueue,
            let pipelineState,
            let textureCache,
            let buffer = makePixelBuffer(session: session, width: width, height: height)
        else { return nil }

        var metalTexture: CVMetalTexture?
        let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            buffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &metalTexture
        )
        guard
            textureStatus == kCVReturnSuccess,
            let metalTexture,
            let target = CVMetalTextureGetTexture(metalTexture),
            target.device === device,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return nil }

        let now = CACurrentMediaTime()
        let waveLifetime = session.options.waveLifetime
        pruneExpiredEffects(session, now: now)

        for (index, wave) in session.waves.prefix(40).enumerated() {
            let progress = Float(min(max((now - wave.createdAt) / waveLifetime, 0), 1))
            let opacity = Float(
                min(max((1 - Double(progress)) * session.options.brightness, 0), 1)
            )
            let baseExpansion: Float = wave.pulse ? 0.45 : 0.22
            let expansion = baseExpansion * Float(session.options.runtimeMotionScale)
            waveScratch[index * 2] = SIMD4(
                wave.center.x,
                wave.center.y,
                wave.baseRadius * (1 + (progress * expansion)),
                opacity
            )
            waveScratch[(index * 2) + 1] = SIMD4(
                wave.color.x,
                wave.color.y,
                wave.color.z,
                0
            )
        }

        for (index, flash) in session.flashes.prefix(40).enumerated() {
            let progress = Float(min(max((now - flash.createdAt) / 0.3, 0), 1))
            let opacity = Float(
                min(
                    max(
                        (1 - Double(progress)) *
                            session.options.brightness *
                            Double(flash.strength),
                        0
                    ),
                    1
                )
            )
            flashScratch[index] = SIMD4(
                flash.color.x,
                flash.color.y,
                flash.color.z,
                opacity
            )
        }

        var globals = RenderGlobals(
            resolution: SIMD2(Float(width), Float(height)),
            brightness: Float(session.options.brightness),
            waveCount: UInt32(min(session.waves.count, 40)),
            flashCount: UInt32(min(session.flashes.count, 40)),
            playing: session.playing ? 1 : 0
        )
        let pass = renderPassDescriptor
        pass.colorAttachments[0].texture = target
        defer { pass.colorAttachments[0].texture = nil }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &globals,
            length: MemoryLayout<RenderGlobals>.stride,
            index: 0
        )
        waveScratch.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                encoder.setFragmentBytes(address, length: bytes.count, index: 1)
            }
        }
        flashScratch.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress {
                encoder.setFragmentBytes(address, length: bytes.count, index: 2)
            }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return commandBuffer.status == .completed ? buffer : nil
    }

    private func pruneExpiredEffects(
        _ session: Session,
        now: CFTimeInterval
    ) {
        let waveLifetime = session.options.waveLifetime
        session.waves.removeAll { now - $0.createdAt >= waveLifetime }
        session.flashes.removeAll { now - $0.createdAt >= 0.3 }
    }

    private func makePixelBuffer(
        session: Session,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        let key = BufferPoolKey(width: width, height: height)
        let pool: CVPixelBufferPool
        if let existing = session.pools[key] {
            pool = existing
        } else {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferMetalCompatibilityKey: true,
            ]
            var created: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary,
                attributes as CFDictionary,
                &created
            )
            guard status == kCVReturnSuccess, let created else { return nil }
            session.pools[key] = created
            pool = created
        }
        var buffer: CVPixelBuffer?
        guard
            CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pool,
                &buffer
            ) == kCVReturnSuccess
        else { return nil }
        return buffer
    }

    private func reconcileForegroundTimer() {
        dispatchPrecondition(condition: .onQueue(renderQueue))
        var hasActiveSession = false
        var requestedFramesPerSecond = 60
        for session in sessions.values where
            session.textureId != nil &&
            session.playing &&
            (!session.waves.isEmpty || !session.flashes.isEmpty)
        {
            hasActiveSession = true
            requestedFramesPerSecond = min(
                requestedFramesPerSecond,
                session.options.runtimeTargetFramesPerSecond
            )
        }
        if !applicationActive || !hasActiveSession {
            foregroundTimer?.setEventHandler {}
            foregroundTimer?.cancel()
            foregroundTimer = nil
            foregroundTimerFramesPerSecond = nil
            return
        }
        let thermalState = ProcessInfo.processInfo.thermalState
        let constrained = ProcessInfo.processInfo.isLowPowerModeEnabled ||
            thermalState == .serious || thermalState == .critical
        let framesPerSecond = min(
            requestedFramesPerSecond,
            constrained ? 30 : 60
        )
        if foregroundTimer != nil,
           foregroundTimerFramesPerSecond == framesPerSecond {
            return
        }
        foregroundTimer?.setEventHandler {}
        foregroundTimer?.cancel()
        foregroundTimer = nil
        foregroundTimerFramesPerSecond = nil
        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        timer.schedule(
            deadline: .now(),
            repeating: .nanoseconds(1_000_000_000 / framesPerSecond),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.applicationActive else { return }
            for session in self.sessions.values where
                session.textureId != nil &&
                session.playing &&
                (!session.waves.isEmpty || !session.flashes.isEmpty)
            {
                _ = self.renderForeground(session)
            }
            self.reconcileForegroundTimer()
        }
        foregroundTimer = timer
        foregroundTimerFramesPerSecond = framesPerSecond
        timer.resume()
    }

    private func observeApplicationLifecycle() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setApplicationActive(true)
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setApplicationActive(false)
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restartForegroundTimer()
            }
        )
        notificationTokens.append(
            center.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restartForegroundTimer()
            }
        )
    }

    private func setApplicationActive(_ active: Bool) {
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.applicationActive = active
            if active {
                for session in self.sessions.values where session.textureId != nil {
                    _ = self.renderForeground(session)
                }
            }
            self.reconcileForegroundTimer()
        }
    }

    private func restartForegroundTimer() {
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.foregroundTimer?.setEventHandler {}
            self.foregroundTimer?.cancel()
            self.foregroundTimer = nil
            self.foregroundTimerFramesPerSecond = nil
            self.reconcileForegroundTimer()
        }
    }

    private func removeSessionIfUnused(_ session: Session) {
        guard
            session.textureId == nil,
            session.pictureInPictureReferences == 0
        else { return }
        sessions.removeValue(forKey: session.id)
    }

    private func disposeAll(result: FlutterResult? = nil) {
        renderQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { result?(nil) }
                return
            }
            let textureIds = self.retireAllSessions()
            DispatchQueue.main.async {
                textureIds.forEach(self.textureRegistry.unregisterTexture)
                result?(nil)
            }
        }
    }

    private func retireAllSessions() -> [Int64] {
        foregroundTimer?.setEventHandler {}
        foregroundTimer?.cancel()
        foregroundTimer = nil
        foregroundTimerFramesPerSecond = nil
        let textureIds = sessions.values.compactMap(\.textureId)
        sessions.removeAll()
        return textureIds
    }

    private func syncOnRenderQueue<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return operation()
        }
        return renderQueue.sync(execute: operation)
    }

    private static func foregroundDimensions(
        width: Double,
        height: Double
    ) -> (width: Int, height: Int) {
        let safeWidth = max(width, 2)
        let safeHeight = max(height, 2)
        let dimensionScale = min(1, 1_440 / max(safeWidth, safeHeight))
        let pixelScale = min(
            1,
            sqrt(1_166_400 / (safeWidth * safeHeight))
        )
        let scale = min(dimensionScale, pixelScale)
        return (
            max(Int((safeWidth * scale).rounded()) & ~1, 2),
            max(Int((safeHeight * scale).rounded()) & ~1, 2)
        )
    }

    private static func canonicalPoint(
        x: Double,
        y: Double,
        outputSize: CGSize
    ) -> SIMD2<Float> {
        let outputAspect = Double(
            max(outputSize.width / max(outputSize.height, 1), 0.001)
        )
        var canonicalX = x
        var canonicalY = y
        if outputAspect > canonicalAspect {
            canonicalY = ((y - 0.5) * (canonicalAspect / outputAspect)) + 0.5
        } else {
            canonicalX = ((x - 0.5) * (outputAspect / canonicalAspect)) + 0.5
        }
        return SIMD2(Float(canonicalX), Float(canonicalY))
    }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard
            let library = try? device.makeLibrary(source: metalSource, options: nil),
            let vertex = library.makeFunction(name: "musicVibeVertex"),
            let fragment = library.makeFunction(name: "musicVibeFragment")
        else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func unit(_ value: Any?) -> Double {
        clampUnit((value as? NSNumber)?.doubleValue ?? 0)
    }

    private static func unit(_ value: Double) -> Double {
        clampUnit(value)
    }

    private static func clampUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func color(for strength: Double) -> SIMD3<Float> {
        let index = Int(
            (unit(strength) * Double(palette.count - 1)).rounded()
        )
        return palette[index]
    }

    private static let palette: [SIMD3<Float>] = [
        SIMD3(0.957, 0.263, 0.212),
        SIMD3(1.000, 0.596, 0.000),
        SIMD3(1.000, 0.922, 0.231),
        SIMD3(0.298, 0.686, 0.314),
        SIMD3(0.129, 0.588, 0.953),
        SIMD3(0.247, 0.318, 0.710),
        SIMD3(0.612, 0.153, 0.690),
    ]

    private static let canonicalAspect = 9.0 / 16.0

    private static let metalSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOutput {
        float4 position [[position]];
    };

    struct RenderGlobals {
        float2 resolution;
        float brightness;
        uint waveCount;
        uint flashCount;
        uint playing;
        float2 padding;
    };

    vertex VertexOutput musicVibeVertex(uint vertexId [[vertex_id]]) {
        const float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        VertexOutput output;
        output.position = float4(positions[vertexId], 0.0, 1.0);
        return output;
    }

    fragment float4 musicVibeFragment(
        VertexOutput input [[stage_in]],
        constant RenderGlobals &globals [[buffer(0)]],
        constant float4 *waves [[buffer(1)]],
        constant float4 *flashes [[buffer(2)]]) {
        constexpr float canonicalAspect = 9.0 / 16.0;
        float2 uv = input.position.xy / globals.resolution;
        float outputAspect = globals.resolution.x / max(globals.resolution.y, 1.0);
        float2 canonicalUV = uv;
        if (outputAspect > canonicalAspect) {
            canonicalUV.y = (uv.y - 0.5) * (canonicalAspect / outputAspect) + 0.5;
        } else {
            canonicalUV.x = (uv.x - 0.5) * (outputAspect / canonicalAspect) + 0.5;
        }

        if (globals.playing == 0) {
            float vertical = exp(-pow((canonicalUV.y - 0.5) * 2.45, 2.0));
            float2 centered = float2(
                canonicalUV.x - 0.5,
                (canonicalUV.y - 0.5) / canonicalAspect
            );
            float vignette = 1.0 - smoothstep(0.25, 0.78, length(centered));
            float3 paused = float3(0.37, 0.0, 0.385) * vertical * vignette;
            return float4(paused, 1.0);
        }

        float3 color = float3(0.0);
        for (uint index = 0; index < min(globals.waveCount, 40u); index++) {
            float4 geometry = waves[index * 2];
            float3 waveColor = waves[(index * 2) + 1].rgb;
            float2 delta = float2(
                canonicalUV.x - geometry.x,
                (canonicalUV.y - geometry.y) / canonicalAspect
            );
            float distanceFromCenter = length(delta);
            float normalizedDistance = distanceFromCenter / max(geometry.z, 0.0001);
            float alpha;
            if (normalizedDistance <= 0.45) {
                alpha = mix(1.0, 0.5, normalizedDistance / 0.45);
            } else {
                alpha = 0.5 * (1.0 - smoothstep(0.45, 1.0, normalizedDistance));
            }
            alpha = clamp(alpha * geometry.w, 0.0, 1.0);
            color = mix(color, waveColor, alpha);
        }

        for (uint index = 0; index < min(globals.flashCount, 40u); index++) {
            color += flashes[index].rgb * flashes[index].a;
        }
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }
    """
}
