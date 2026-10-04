import 'dart:io';

import 'package:scene_compositor/authoring.dart';
import 'package:scene_compositor/native_compiler.dart';

/// Builds the generated reader and transition scene around a probe visual,
/// with ASan/UBSan, and checks how each kind of modifier moves. Needs clang++.
void main() {
  if (Process.runSync('which', ['clang++']).exitCode != 0) {
    stdout.writeln('scene_compositor: glide checks skipped (no clang++).');
    return;
  }
  final sdk = Directory.fromUri(
    Platform.script.resolve('../../scene_program_native/src/'),
  );
  final visual =
      validateCreatorCatalog([
        const CreatorVisualDefinition(
          id: 'glide_probe',
          name: 'Glide probe',
          nativeSource: _visual,
          modifiers: [
            CreatorModifier.slider('ancho', 'Ancho', min: 0, max: 1, value: .5),
            CreatorModifier.steps('lados', 'Lados', min: 2, max: 8, value: 4),
            CreatorModifier.toggle('marco', 'Marco'),
            CreatorModifier.choice(
              'tono',
              'Tono',
              options: ['Azul', 'Rojo', 'Oro'],
            ),
          ],
        ),
      ]).single;
  final temporary = Directory.systemTemp.createTempSync('creator-glide-');
  try {
    final source = File('${temporary.path}/glide_probe.cpp')
      ..writeAsStringSync('''
#include "creator_scene.hpp"
#include <cstdio>
namespace creator {
const std::vector<Program>& installedPrograms() { static const std::vector<Program> none; return none; }
}
namespace authored_glide_probe {
using namespace creator;
struct Seen { float ancho, lados, marco, w0, w1, w2, liveT, copyT, otherT; int ladosInt, tonoInt; bool marcoOn; };
Seen seen;
${creatorModifierReader(visual)}
${creatorGlideReader(visual)}
${visual.nativeSource}
${creatorGlideWrapper(visual)}
}
$_harness
''');
    final binary = '${temporary.path}/glide_probe';
    final build = Process.runSync('clang++', [
      '-std=c++17',
      '-g',
      '-O1',
      '-Wall',
      '-Wextra',
      '-Werror',
      '-fsanitize=address,undefined',
      '-fno-omit-frame-pointer',
      '-fno-sanitize-recover=all',
      '-I${sdk.path}',
      source.path,
      '${sdk.path}creator_scene.cpp',
      '-o',
      binary,
    ]);
    if (build.exitCode != 0) {
      stderr.writeln(build.stdout);
      stderr.writeln(build.stderr);
      throw StateError('The generated transition code does not compile.');
    }
    final run = Process.runSync(binary, const []);
    stdout.write(run.stdout);
    if (run.exitCode != 0) {
      stderr.writeln(run.stderr);
      throw StateError('Transition checks failed.');
    }
  } finally {
    temporary.deleteSync(recursive: true);
  }
  stdout.writeln('scene_compositor: glide checks passed.');
}

/// Records what the author would see, in update and in render.
const _visual = r'''
class Visual final : public Scene {
  static void record(const Frame& f) {
    auto m = modifiers(f);
    auto g = glide(f);
    Frame copy = f;            // a copy taken during the call
    Frame other = f;           // a frame with other values
    other.modifiers[0] = -1;
    seen = {g.ancho, g.lados, g.marco, g.tono.weight(0), g.tono.weight(1),
            g.tono.weight(2), g.tono.t, glide(copy).tono.t, glide(other).tono.t,
            m.lados, m.tono, m.marco};
  }
 public:
  void reset(uint32_t) override {}
  void update(const Frame& f) override { record(f); }
  void render(const Frame& f, Canvas&) const override { record(f); }
};
''';

const _harness = r'''
using namespace authored_glide_probe;
static int failures = 0;
static void check(bool ok, const char* what) {
  if (!ok) { std::printf("FAIL %s\n", what); failures++; }
}
static bool near(float a, float b, float e) { return std::fabs(a - b) <= e; }
struct Probe {
  CreatorGlideScene_ scene;
  Frame frame;
  std::vector<float> commands;
  std::vector<std::string> none;
  explicit Probe(float fps = 30) {
    frame.delta = 1.0 / fps;
    frame.modifiers = {.5f, 4, 0, 0};
    scene.reset(1);
  }
  void tick() { scene.update(frame); }
  void draw() { Canvas canvas(commands, none, none); scene.render(frame, canvas); }
};

int main() {
  {  // Creation snaps; a slider eases toward its target and lands on it.
    Probe p; p.tick();
    check(seen.ancho == .5f, "first update snaps to the requested value");
    p.frame.modifiers[0] = 1; p.tick();
    const float expected = .5f + .5f * (1 - std::exp(-1.f / 30 / .25f));
    check(near(seen.ancho, expected, 1e-4f), "one frame moves by the exponential step");
    for (int i = 1; i < 30; i++) p.tick();
    check(seen.ancho >= .5f + .5f * .95f && seen.ancho < 1, "95% of the way after 1 s");
    for (int i = 0; i < 90; i++) p.tick();
    check(seen.ancho == 1, "lands exactly on the target");
    p.draw();
    check(seen.ancho == 1, "render sees the same eased value");
  }
  {  // 30 and 60 FPS follow the same curve.
    Probe a(30), b(60);
    a.tick(); b.tick();
    a.frame.modifiers[0] = 1; b.frame.modifiers[0] = 1;
    for (int i = 0; i < 15; i++) a.tick();
    float at30 = seen.ancho;
    for (int i = 0; i < 30; i++) b.tick();
    check(near(at30, seen.ancho, 1e-3f), "30 and 60 FPS agree");
  }
  {  // Steps pass through every whole value; a toggle fades and flips midway.
    Probe p; p.tick();
    p.frame.modifiers[1] = 8; p.frame.modifiers[2] = 1;
    bool five = false, six = false, seven = false, flippedEarly = false;
    for (int i = 0; i < 90; i++) {
      p.tick();
      five |= seen.ladosInt == 5; six |= seen.ladosInt == 6; seven |= seen.ladosInt == 7;
      flippedEarly |= seen.marcoOn != (seen.marco > .5f);
      check(seen.marco >= 0 && seen.marco <= 1, "toggle fade stays within 0..1");
    }
    check(five && six && seven, "steps go through 5, 6 and 7");
    check(seen.ladosInt == 8 && seen.lados == 8, "steps land on 8");
    check(!flippedEarly && seen.marcoOn && seen.marco == 1, "toggle flips at half and lands on 1");
  }
  {  // A choice crossfades; weights add up to 1; turning back is continuous.
    Probe p; p.tick();
    check(seen.w0 == 1 && seen.tonoInt == 0, "choice starts on its option");
    p.frame.modifiers[3] = 2; p.tick();
    check(seen.tonoInt == 2, "modifiers(f) gives the new option at once");
    check(seen.w0 > .9f && seen.w2 < .1f, "the crossfade starts from the old option");
    float previous = seen.w0;
    for (int i = 0; i < 6; i++) {
      p.tick();
      check(near(seen.w0 + seen.w1 + seen.w2, 1, 1e-5f), "weights add up to 1");
      check(seen.w0 <= previous, "the old option fades out");
      previous = seen.w0;
    }
    check(seen.liveT < 1 && seen.copyT == seen.liveT,
          "a copy taken during the call follows the same crossfade");
    check(seen.otherT == 1, "a frame with other values reads steady");
    const float step = 1.f / 30 / .45f + 1e-4f;
    float w0 = seen.w0, w1 = seen.w1, w2 = seen.w2;
    p.frame.modifiers[3] = 1; p.tick();  // a third option mid-fade
    check(std::fabs(seen.w0 - w0) <= step && std::fabs(seen.w2 - w2) <= step &&
          std::fabs(seen.w1 - w1) <= 2 * step, "a third option mid-fade never jumps");
    check(near(seen.w0 + seen.w1 + seen.w2, 1, 1e-5f), "weights still add up to 1");
    const float before = seen.w1;
    p.frame.modifiers[3] = 0; p.tick();
    check(std::fabs(seen.w1 - before) <= step, "turning back mid-way does not jump");
    for (int i = 0; i < 30; i++) p.tick();
    check(seen.w0 == 1 && seen.w1 == 0 && seen.w2 == 0, "back on the first option");
  }
  {  // Paused (render without update), reduced motion and reset are instant.
    Probe p; p.tick(); p.draw();
    p.frame.modifiers[0] = 0; p.draw();
    check(seen.ancho == 0, "a paused render shows the new value at once");
    p.frame.modifiers[0] = 1; p.frame.reducedMotion = true; p.tick();
    check(seen.ancho == 1, "reduced motion applies at once");
    p.frame.reducedMotion = false; p.frame.modifiers[0] = 0; p.tick();
    p.scene.reset(2); p.tick();
    check(seen.ancho == 0, "reset applies at once");
  }
  {  // Two instances never share transitions.
    Probe a, b; a.tick(); b.tick();
    a.frame.modifiers[3] = 2; a.tick(); b.tick();
    check(seen.w0 == 1, "the other instance keeps its option");
    a.tick();
    check(seen.w0 < 1, "the first instance keeps crossfading");
  }
  if (failures) return 1;
  std::printf("PASS glide: snap, ease, 30/60 FPS, steps, toggle, choice, pause, reduced motion, reset, instances\n");
}
''';
