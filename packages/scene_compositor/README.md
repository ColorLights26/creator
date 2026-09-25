> Para: mantener el compositor. Para crear un visual con una IA, empieza por la [guía de creación](../../README.md).

# Scene compositor SDK

This package hosts the existing iOS SceneSurface compositor and the reusable
Android Flutter shader surface for the standalone creator. iOS uses the same
production native source. Android follows the application's Flutter renderer
route with a `FragmentProgram` and a Canvas surface. The SDK contains no sensors,
Firebase, purchases, or another audio pipeline.

`authoring.dart` is a pure Dart definition/build API. A visual declares its
identity, four colors, bounded controls, 30 FPS budget, and reactivity policy:
`none`, `music`, or `optional`. Creator automatically pairs each visual source
file with its separate metadata file and lists the resulting definitions.
Shader source is bundled during the
build and compiled when preparing its native GPU pipeline; source is never
sent through the scene channel or downloaded as scene data. Adding or changing
a shader requires rebuilding. The portable shader body feeds both platforms.

On iOS, the scene document uses the production V1 owner and its `native_program_v1`
source with a compatible catalog node descriptor. It does not enable the
separate V2 rollout. Production publication remains a separate integration step;
appearance in the creator does not expose an unreviewed visual to app users.

Reactive visuals accept the unchanged 520-byte `SceneRenderSignalFrameV2`
contract from `visual_contract`. The creator's included demonstration is
**synthetic**, clearly labeled, and is not evidence of live sensor behavior.
No actual sensor recordings are shipped. Existing `signals.bin` +
`timeline.json` captures can be replayed without normalizing their data or
rewriting event serials. The original `qaSessionSeed` is supplied as an exact
uint32; values greater than `4294967295` are rejected instead of truncated.
Playback reset must recreate the native program before replaying original
session IDs and serials at a loop or backward seek.

On Android, `CreatorShaderFrame` shares the same signal mapping, event serial
deduplication, elapsed-time limits, and Reduce Motion behavior. Two 16-bit
uniforms preserve every uint32 seed bit. `AndroidCreatorSession` loads the
bundled fragment program once and retains the active shader. Its preview owns
one ticker capped at 30 FPS and stops when playback or TickerMode pauses it.
It draws to an offscreen image whose longest edge is at most 1024 physical
pixels, then scales that image into the viewport. One in-flight render plus one
displayed image bounds target ownership, with obsolete completions discarded.
This adds an offscreen pass; it is not a claim of free or thermally certified
rendering. There is no pixel-array generation or `toByteData` readback.

The renderer owns drawing, cadence, and resources. Thirty FPS and bounded
controls limit baseline cost, but cannot certify arbitrary generated shader
work. A new effect still needs sustained physical-device testing before claiming
temperature, battery, or performance suitability.

Run the pure authoring regression checks after resolving dependencies:

```sh
dart run test/creator_visual_definition_test.dart
flutter test --no-pub test/creator_shader_frame_test.dart
```

These tests cover native document shape, source isolation, bounded IDs and
controls, exact capture seed, and reactive versus nonreactive signal bindings.
