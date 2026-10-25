import CoreGraphics
import Foundation

/// Deterministic clock and scheduler: every deadline is a work item the test
/// fires by hand, so "completed exactly once" is checked without timers.
final class Scheduler {
    var now: TimeInterval = 10
    var scheduled: [(id: Int, delay: TimeInterval, work: () -> Void)] = []
    var cancelled: [Int] = []
    private var nextId = 0

    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        nextId += 1
        let id = nextId
        scheduled.append((id, delay, work))
        return { [weak self] in self?.cancelled.append(id) }
    }

    func fireAll() {
        let pending = scheduled
        scheduled.removeAll()
        for item in pending where !cancelled.contains(item.id) {
            now += item.delay
            item.work()
        }
    }
}

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

/// macOS stand-in for the UIKit base class of the extracted host view; the
/// production class only overrides `layoutSubviews`.
class UIView {
    var frame: CGRect
    var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
    init(frame: CGRect) { self.frame = frame }
    func layoutSubviews() {}
}

func makeBarrier(_ scheduler: Scheduler) -> PictureInPictureRestoreBarrier {
    PictureInPictureRestoreBarrier(
        deadline: 0.8,
        now: { scheduler.now },
        schedule: { delay, work in scheduler.schedule(delay, work) }
    )
}

@main
struct PictureInPictureRestoreBarrierTests {
    static func main() {
        acknowledgementCompletesOnceAndTrue()
        deadlineCompletesOnceAndLateAcknowledgementIsStale()
        newRestoreSupersedesAHeldOne()
        leavingPictureInPictureFinishesWhateverIsHeld()
        continuityRule()
        ReturnPresentationTests.run()
        PlaybackIntentGateTests.run()
        GeometryTests.run()
        SourceLayerLayoutTests.run()
        if failures > 0 {
            print("\(failures) failure(s)")
            exit(1)
        }
        print("PiP restore barrier tests passed")
    }

    static func acknowledgementCompletesOnceAndTrue() {
        let scheduler = Scheduler()
        let barrier = makeBarrier(scheduler)
        var completions: [Bool] = []
        let token = barrier.begin { completions.append($0) }
        check(barrier.pendingToken == token, "token is pending after begin")
        check(completions.isEmpty, "begin holds the completion")
        scheduler.now += 0.12
        check(barrier.acknowledge(token: "other") == .stale, "foreign token is stale")
        check(completions.isEmpty, "foreign token does not complete")
        let outcome = barrier.acknowledge(token: token)
        check(outcome == .completed(reason: "acknowledged", elapsedMilliseconds: 120),
              "acknowledgement completes with elapsed time, got \(outcome)")
        check(completions == [true], "completion answered once with true")
        check(barrier.pendingToken == nil, "nothing pending after acknowledgement")
        check(barrier.acknowledge(token: token) == .stale, "second acknowledgement is stale")
        scheduler.fireAll()
        check(completions == [true], "cancelled deadline never completes again")
        check(barrier.finish(reason: "stopped") == .stale, "finish without pending is stale")
    }

    static func deadlineCompletesOnceAndLateAcknowledgementIsStale() {
        let scheduler = Scheduler()
        let barrier = makeBarrier(scheduler)
        var completions: [Bool] = []
        let token = barrier.begin { completions.append($0) }
        check(scheduler.scheduled.count == 1 && scheduler.scheduled[0].delay == 0.8,
              "one deadline is scheduled at 0.8 s")
        scheduler.fireAll()
        check(completions == [true], "deadline completes once with true")
        check(barrier.pendingToken == nil, "deadline clears the pending token")
        check(barrier.acknowledge(token: token) == .stale, "late acknowledgement is stale")
        check(completions == [true], "late acknowledgement never completes again")
    }

    static func newRestoreSupersedesAHeldOne() {
        let scheduler = Scheduler()
        let barrier = makeBarrier(scheduler)
        var first: [Bool] = []
        var second: [Bool] = []
        let tokenA = barrier.begin { first.append($0) }
        let tokenB = barrier.begin { second.append($0) }
        check(tokenA != tokenB, "tokens are distinct")
        check(first == [true], "superseded completion is answered once")
        check(second.isEmpty, "new completion is still held")
        check(barrier.acknowledge(token: tokenA) == .stale, "old token is stale")
        check(second.isEmpty, "old token cannot complete the new restore")
        _ = barrier.acknowledge(token: tokenB)
        check(second == [true], "new token completes the new restore")
        scheduler.fireAll()
        check(first == [true] && second == [true], "no deadline completes anything twice")
    }

    static func leavingPictureInPictureFinishesWhateverIsHeld() {
        let scheduler = Scheduler()
        let barrier = makeBarrier(scheduler)
        var completions: [Bool] = []
        _ = barrier.begin { completions.append($0) }
        scheduler.now += 0.3
        let outcome = barrier.finish(reason: "stopped")
        check(outcome == .completed(reason: "stopped", elapsedMilliseconds: 300),
              "finish reports its reason and elapsed time, got \(outcome)")
        check(completions == [true], "leaving PiP answers the held completion once")
        scheduler.fireAll()
        check(completions == [true], "deadline after finish is inert")
    }

    static func continuityRule() {
        for kind in ["sceneV1Shared", "sceneV2Shared", "realtimeRenderer"] {
            check(pictureInPictureKeepsPresentationThroughStop(
                sourceKind: kind, foregroundReturn: true, playbackActive: true,
                emergencyRecoveryActive: false), "\(kind) continues on a playing return")
            check(!pictureInPictureKeepsPresentationThroughStop(
                sourceKind: kind, foregroundReturn: false, playbackActive: true,
                emergencyRecoveryActive: false), "\(kind) pauses on a stop that is not a return")
            check(!pictureInPictureKeepsPresentationThroughStop(
                sourceKind: kind, foregroundReturn: true, playbackActive: false,
                emergencyRecoveryActive: false), "\(kind) keeps a paused intent frozen")
            check(!pictureInPictureKeepsPresentationThroughStop(
                sourceKind: kind, foregroundReturn: true, playbackActive: true,
                emergencyRecoveryActive: true), "\(kind) keeps emergency recovery frozen")
        }
        for kind in ["video", "poster", "sceneComposition", "procedural"] {
            check(!pictureInPictureKeepsPresentationThroughStop(
                sourceKind: kind, foregroundReturn: true, playbackActive: true,
                emergencyRecoveryActive: false), "\(kind) owns decoders and pauses as before")
        }
    }
}

/// The one decision model the handler applies in `beginStopping`, `willStop`,
/// the foreground/restore/did-become-active returns and `didStop`.
enum ReturnPresentationTests {
    typealias Model = PictureInPictureReturnPresentation

    static func context(
        _ phase: Model.Phase,
        presenting: Bool,
        sourceKind: String = "sceneV1Shared",
        playbackActive: Bool = true,
        emergencyRecoveryActive: Bool = false
    ) -> Model.Context {
        Model.Context(
            phase: phase,
            sourceKind: sourceKind,
            playbackActive: playbackActive,
            emergencyRecoveryActive: emergencyRecoveryActive,
            presenting: presenting
        )
    }

    static func run() {
        returnBeforeStopKeepsPresenting()
        stopBeforeReturnResumesOnce()
        didBecomeActiveFallbackResumesAPausedStop()
        pausedIntentNeverResumes()
        emergencyRecoveryStaysFrozen()
        decoderOwningSourcesPauseAsBefore()
        backgroundClearsTheReturnUnlessStopping()
        watchdogFinishIsFinalAndIdempotent()
    }

    /// Order A: foreground notification or restore request, then willStop,
    /// then didStop. Nothing pauses until the return is over.
    static func returnBeforeStopKeepsPresenting() {
        let model = Model()
        check(model.returnRequested(context(.active, presenting: true)) == .unchanged,
              "a return while active changes nothing yet")
        check(model.continuityRequested, "the return is remembered")
        check(model.stopping(context(.stopping, presenting: true)) == .unchanged,
              "willStop after a return keeps the timer and sources")
        check(model.returnRequested(context(.stopping, presenting: true)) == .unchanged,
              "a repeated return (restore after foreground) is idempotent")
        check(model.returnFinished() == .pause, "didStop pauses the shared presentation")
        check(!model.continuityRequested, "didStop clears the return")
    }

    /// Order B: willStop arrives first (AVKit decided before the app knew),
    /// then the restore or foreground notification.
    static func stopBeforeReturnResumesOnce() {
        let model = Model()
        check(model.stopping(context(.stopping, presenting: true)) == .pause,
              "willStop without a known return pauses as before")
        check(model.returnRequested(context(.stopping, presenting: false)) == .resume,
              "the late return resumes the paused presentation")
        check(model.returnRequested(context(.stopping, presenting: true)) == .unchanged,
              "a second return does not restart a running timer")
        check(model.stopping(context(.stopping, presenting: true)) == .unchanged,
              "beginStopping after the return keeps presenting")
        check(model.returnFinished() == .pause, "didStop pauses once the return is over")
    }

    /// Direct activation: no restore callback at all, only did-become-active.
    static func didBecomeActiveFallbackResumesAPausedStop() {
        let model = Model()
        check(model.stopping(context(.stopping, presenting: true)) == .pause,
              "stop began without any return")
        check(model.returnRequested(context(.stopping, presenting: false)) == .resume,
              "did-become-active resumes the stopping presentation")
        check(model.returnFinished() == .pause, "the fallback stop still ends with a pause")
    }

    static func pausedIntentNeverResumes() {
        let model = Model()
        check(model.returnRequested(context(.active, presenting: false, playbackActive: false)) == .unchanged,
              "a paused scene is not resumed by a return")
        check(model.stopping(context(.stopping, presenting: true, playbackActive: false)) == .pause,
              "a paused scene pauses its presentation on stop")
        check(model.returnRequested(context(.stopping, presenting: false, playbackActive: false)) == .unchanged,
              "a paused scene stays paused through the return")
    }

    static func emergencyRecoveryStaysFrozen() {
        let model = Model()
        check(model.stopping(context(.stopping, presenting: true, emergencyRecoveryActive: true)) == .pause,
              "emergency recovery pauses on stop")
        check(model.returnRequested(context(.stopping, presenting: false, emergencyRecoveryActive: true)) == .unchanged,
              "emergency recovery is not revived by a return")
    }

    static func decoderOwningSourcesPauseAsBefore() {
        for kind in ["video", "poster", "sceneComposition", "procedural"] {
            let model = Model()
            check(model.returnRequested(context(.stopping, presenting: false, sourceKind: kind)) == .unchanged,
                  "\(kind) is not resumed by a return")
            check(model.stopping(context(.stopping, presenting: true, sourceKind: kind)) == .pause,
                  "\(kind) pauses on stop")
        }
    }

    static func backgroundClearsTheReturnUnlessStopping() {
        let model = Model()
        _ = model.returnRequested(context(.active, presenting: true))
        model.backgrounded(phase: .active)
        check(!model.continuityRequested, "going back to the background forgets the return")
        check(model.stopping(context(.stopping, presenting: true)) == .pause,
              "a later stop without a return pauses")
        _ = model.returnRequested(context(.stopping, presenting: false))
        model.backgrounded(phase: .stopping)
        check(model.continuityRequested, "a background notification during the stop keeps the return")
    }

    /// The watchdog gave up before didStop: returnFinished pauses once; a late
    /// didStop pauses again harmlessly and nothing stale survives.
    static func watchdogFinishIsFinalAndIdempotent() {
        let model = Model()
        _ = model.returnRequested(context(.active, presenting: true))
        check(model.stopping(context(.stopping, presenting: true)) == .unchanged, "return keeps presenting")
        check(model.returnFinished() == .pause, "watchdog pauses")
        check(model.returnFinished() == .pause, "late didStop pauses again")
        check(!model.continuityRequested, "no return survives the watchdog")
        check(model.stopping(context(.stopping, presenting: false)) == .pause,
              "a later stop without a new return does not resume")
        check(model.returnRequested(context(.idle, presenting: false)) == .unchanged,
              "a return while idle changes nothing")
    }
}

/// The source layer takes the output's aspect inside its host, so AVKit
/// derives the same window shape as the buffers it receives.
enum GeometryTests {
    static func run() {
        iPadPortraitOutputFillsItsHost()
        nineBySixteenOutputIsLetterboxedInAnIPadHost()
        portraitOutputInALandscapeHostIsPillarboxed()
        nonZeroHostOriginIsPreserved()
        invalidInputsReturnTheHost()
        receiptConsistency()
    }

    static func iPadPortraitOutputFillsItsHost() {
        let frame = pictureInPictureSourceLayerFrame(
            outputWidth: 400, outputHeight: 574, host: CGRect(x: 0, y: 0, width: 834, height: 1194))
        check(frame.width == 832 && frame.height == 1194, "fits the height, got \(frame)")
        check(frame.minX == 1 && frame.minY == 0, "centered horizontally, got \(frame)")
        check(abs(frame.width / frame.height - 400.0 / 574.0) < 0.002, "layer keeps the output aspect")
    }

    static func nineBySixteenOutputIsLetterboxedInAnIPadHost() {
        let frame = pictureInPictureSourceLayerFrame(
            outputWidth: 360, outputHeight: 640, host: CGRect(x: 0, y: 0, width: 834, height: 1194))
        check(frame.width == 672 && frame.height == 1194, "9:16 fits the height, got \(frame)")
        check(frame.minX == 81, "centered with a band each side, got \(frame)")
        check(frame.midX == 417, "horizontal center matches the host")
    }

    static func portraitOutputInALandscapeHostIsPillarboxed() {
        let frame = pictureInPictureSourceLayerFrame(
            outputWidth: 360, outputHeight: 640, host: CGRect(x: 0, y: 0, width: 1194, height: 834))
        check(frame.height == 834 && frame.width == 469, "fits the height, got \(frame)")
        check(abs(frame.midX - 597) <= 1, "centered horizontally, got \(frame)")
        let wide = pictureInPictureSourceLayerFrame(
            outputWidth: 572, outputHeight: 400, host: CGRect(x: 0, y: 0, width: 1194, height: 834))
        check(wide.height == 834 && abs(wide.width - 1193) <= 1 && abs(wide.midX - 597) <= 1,
              "a landscape output fills a landscape host, got \(wide)")
    }

    static func nonZeroHostOriginIsPreserved() {
        let host = CGRect(x: 20, y: 40, width: 400, height: 574)
        let frame = pictureInPictureSourceLayerFrame(outputWidth: 400, outputHeight: 574, host: host)
        check(frame == host, "an exact fit keeps the host origin, got \(frame)")
        let inset = pictureInPictureSourceLayerFrame(
            outputWidth: 360, outputHeight: 640, host: CGRect(x: 10, y: 30, width: 834, height: 1194))
        check(inset.minX == 91 && inset.minY == 30, "offset host keeps its origin, got \(inset)")
    }

    static func invalidInputsReturnTheHost() {
        let host = CGRect(x: 0, y: 0, width: 834, height: 1194)
        check(pictureInPictureSourceLayerFrame(outputWidth: 0, outputHeight: 640, host: host) == host,
              "zero output width returns the host")
        check(pictureInPictureSourceLayerFrame(outputWidth: 360, outputHeight: 640, host: .zero) == .zero,
              "an empty host returns itself")
    }

    static func receiptConsistency() {
        var receipt = PictureInPictureGeometryReceipt(
            step: "prepared", sessionId: "scene:1", source: CGSize(width: 1668, height: 2388),
            outputWidth: 400, outputHeight: 574,
            layer: CGRect(x: 1, y: 0, width: 832, height: 1194),
            host: CGRect(x: 0, y: 0, width: 834, height: 1194),
            renderWidth: 0, renderHeight: 0)
        check(receipt.consistent, "output and layer share one aspect before AVKit reports")
        receipt.renderWidth = 200
        receipt.renderHeight = 287
        check(receipt.consistent, "an AVKit render size with the same aspect stays consistent")
        receipt.renderWidth = 103
        receipt.renderHeight = 223
        check(!receipt.consistent, "the old 9:16 window aspect is reported as inconsistent")
        check(receipt.description.contains("step=prepared") && receipt.description.contains("consistent=false"),
              "description names the step and the verdict, got \(receipt.description)")
        let stale = PictureInPictureGeometryReceipt(
            step: "will_start", sessionId: "scene:1", source: .zero,
            outputWidth: 360, outputHeight: 640,
            layer: CGRect(x: 0, y: 0, width: 834, height: 1194),
            host: CGRect(x: 0, y: 0, width: 834, height: 1194),
            renderWidth: 0, renderHeight: 0)
        check(!stale.consistent, "a layer stretched to the host does not match a 9:16 output")
        let empty = PictureInPictureGeometryReceipt(
            step: "prepared", sessionId: "scene:1", source: .zero,
            outputWidth: 360, outputHeight: 640, layer: .zero, host: .zero,
            renderWidth: 0, renderHeight: 0)
        check(!empty.consistent, "an unlaid layer is not consistent")
    }
}

/// AVKit's `setPlaying` callback: only the user's control in an active window
/// may change playback. The same decision governs pause and play.
enum PlaybackIntentGateTests {
    typealias Gate = PictureInPicturePlaybackIntentGate

    static func decide(
        active: Bool = true,
        foregroundStop: Bool = false,
        startStop: Bool = false,
        returning: Bool = false
    ) -> Gate.Decision {
        Gate.decide(
            lifecycleActive: active,
            foregroundStopRequested: foregroundStop,
            stopRequestedDuringStart: startStop,
            returnRequested: returning
        )
    }

    static func run() {
        check(decide() == .apply, "a pause or play in the active window is the user's control")
        check(decide(active: false) == .ignore, "a teardown false while starting or stopping is ignored")
        check(decide(foregroundStop: true) == .ignore, "a false after the foreground stop request is ignored")
        check(decide(startStop: true) == .ignore, "a callback while a stop waits for the start is ignored")
        check(decide(returning: true) == .ignore,
              "a false after the restore request, before willStop, keeps the Play intent")
        check(decide(active: false, returning: true) == .ignore, "stopping with a return pending is ignored")
    }
}

/// A host layout pass re-fits the attached layer to the current host bounds
/// and moves nothing else; the host view forwards every pass.
enum SourceLayerLayoutTests {
    static let portrait = CGRect(x: 0, y: 0, width: 834, height: 1194)
    static let landscape = CGRect(x: 0, y: 0, width: 1194, height: 834)

    static func update(_ host: CGRect, current: CGRect) -> CGRect? {
        pictureInPictureSourceLayerUpdate(outputWidth: 400, outputHeight: 574, host: host, current: current)
    }

    static func run() {
        unchangedHostMovesNothing()
        rotationRefitsTheLayer()
        splitResizeKeepsTheOutputAspectInTheNarrowerHost()
        nonZeroOriginIsRespected()
        hostViewForwardsEveryLayoutPass()
    }

    static func unchangedHostMovesNothing() {
        let current = pictureInPictureSourceLayerFrame(outputWidth: 400, outputHeight: 574, host: portrait)
        check(update(portrait, current: current) == nil, "a frame that already fits is left alone (no receipt)")
    }

    /// Rotation after prepare, before an automatic start: the layer attached
    /// in portrait must be re-fitted to the landscape host.
    static func rotationRefitsTheLayer() {
        let current = pictureInPictureSourceLayerFrame(outputWidth: 400, outputHeight: 574, host: portrait)
        guard let frame = update(landscape, current: current) else {
            check(false, "a rotated host re-fits the layer")
            return
        }
        check(frame.height == 834 && abs(frame.width - 581) <= 1, "fits the landscape height, got \(frame)")
        check(abs(frame.midX - 597) <= 1 && frame.minY == 0, "centered in the landscape host, got \(frame)")
        check(abs(frame.width / frame.height - 400.0 / 574.0) < 0.002, "keeps the output aspect")
        check(landscape.contains(frame), "stays inside the host")
    }

    /// Split View narrows the host without changing the output (Dart only
    /// prepares again when the output geometry itself changes).
    static func splitResizeKeepsTheOutputAspectInTheNarrowerHost() {
        let split = CGRect(x: 0, y: 0, width: 639, height: 1194)
        let current = pictureInPictureSourceLayerFrame(outputWidth: 400, outputHeight: 574, host: portrait)
        guard let frame = update(split, current: current) else {
            check(false, "a narrower host re-fits the layer")
            return
        }
        check(frame.width == 639 && frame.height == 917, "fits the split width, got \(frame)")
        check(split.contains(frame) && frame.minX == 0, "stays inside the split host, got \(frame)")
        check(abs(frame.width / frame.height - 400.0 / 574.0) < 0.002, "keeps the output aspect")
    }

    static func nonZeroOriginIsRespected() {
        let host = CGRect(x: 0, y: 59, width: 1194, height: 775)
        guard let frame = update(host, current: .zero) else {
            check(false, "an unlaid layer is fitted")
            return
        }
        check(frame.minY == 59 && frame.height == 775 && frame.width == 540, "fits the inset host, got \(frame)")
        check(host.contains(frame), "stays inside the inset host")
    }

    /// The extracted production host view: every `layoutSubviews` reaches the
    /// hook with the view's current bounds, and no hook is safe.
    static func hostViewForwardsEveryLayoutPass() {
        let view = PictureInPictureSourceHostView(frame: portrait)
        view.layoutSubviews()
        var passes = 0
        var seen = [CGRect]()
        view.onLayout = {
            passes += 1
            seen.append(view.bounds)
        }
        view.layoutSubviews()
        view.frame = landscape
        view.layoutSubviews()
        check(passes == 2, "each layout pass reaches the hook once, got \(passes)")
        check(seen.first == portrait && seen.last == landscape,
              "the hook sees the bounds of that pass, got \(seen)")
    }
}
