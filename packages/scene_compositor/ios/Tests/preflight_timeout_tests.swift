import Foundation
import QuartzCore

// Runs the production SceneSurfaceInspectionContext and
// SceneSurfaceInspectionVerdict, extracted by check_preflight_timeout.py, with
// a forced delay: the same deadline a busy device runs into (05-nov-2026).

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

// 1. A slow inspection (forced delay past its deadline) is a timeout, never
//    the scene's fault, and it is never remembered.
do {
    let context = SceneSurfaceInspectionContext(timeout: 0.05)
    Thread.sleep(forTimeInterval: 0.12)
    var blamedScene = false
    let issues = SceneSurfaceInspectionVerdict.preflightIssues(context: context) {
        blamedScene = true
        return ["asset_unavailable"]
    }
    check(issues == ["timed_out"], "a slow preflight answers timed_out, got \(issues)")
    check(!blamedScene, "a slow preflight must not ask which file is missing")
    check(
        SceneSurfaceInspectionVerdict.operationError(context: context)
            == "scene_inspection_timeout",
        "a slow attach inspection is a timeout, not an invalid document"
    )
    check(
        !SceneSurfaceInspectionVerdict.mayCache(supported: false),
        "a timed-out answer is never cached"
    )
    // Building the document for attach or update has its own 2 s clock: on
    // a busy device it runs out too, and that is no verdict either.
    check(
        SceneSurfaceInspectionVerdict.updateRejection(context: context) == "timed_out",
        "a slow update build keeps the scene and asks again"
    )
}

// 2. A media load that never answers (the busy AVAsset load) fails the wait at
//    the deadline, and that failure is still a timeout.
do {
    let context = SceneSurfaceInspectionContext(timeout: 0.05)
    var cancelledLoad = false
    let loaded = context.waitForLoad(start: { _ in }, cancel: { cancelledLoad = true })
    check(!loaded, "a load that never answers is not ready")
    check(cancelledLoad, "the stuck load is cancelled at the deadline")
    check(
        SceneSurfaceInspectionVerdict.preflightIssues(context: context) {
            ["asset_unavailable"]
        } == ["timed_out"],
        "a load stuck past the deadline answers timed_out"
    )
}

// 3. An inspection that finished in time may refuse the scene, but a «no» is
//    still inspected again next time; only an accepted scene is cached.
do {
    let context = SceneSurfaceInspectionContext(timeout: 2)
    let issues = SceneSurfaceInspectionVerdict.preflightIssues(context: context) {
        ["asset_unavailable"]
    }
    check(issues == ["asset_unavailable"], "a finished inspection keeps its own verdict")
    check(
        SceneSurfaceInspectionVerdict.operationError(context: context)
            == "scene_document_invalid",
        "a finished attach inspection may call the document invalid"
    )
    check(
        !SceneSurfaceInspectionVerdict.mayCache(supported: false),
        "a refusal is inspected again, never cached"
    )
    check(
        SceneSurfaceInspectionVerdict.mayCache(supported: true),
        "an accepted scene is cached"
    )
    check(
        SceneSurfaceInspectionVerdict.updateRejection(context: context)
            == "scene_update_resources_unavailable",
        "a finished update build that fails is a real refusal"
    )
}

if failures > 0 {
    print("preflight timeout tests: \(failures) failure(s)")
    exit(1)
}
print("preflight timeout tests: ok")
