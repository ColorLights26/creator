import 'dart:io';

import 'package:scene_compositor/authoring.dart';
import 'package:scene_compositor/creator_lint.dart';
import 'package:scene_compositor/native_compiler.dart';

/// Runs the real authored probe (ASan/UBSan) over visuals made to pass or
/// fail the modifier sweep: a dead modifier warns (fails when strict), one
/// that breaks the budget at its maximum fails, and one that only changes
/// the response to music passes. Also the pass gate: 40 separate points()
/// calls are 40 full-screen passes and fail on both surfaces, 30 fail only
/// on the iPad (28; the iPhone takes 35) and the same points in one batch
/// are one pass. Needs clang++.
void main() {
  if (Process.runSync('which', ['clang++']).exitCode != 0) {
    stdout.writeln('scene_compositor: sweep checks skipped (no clang++).');
    return;
  }
  final package = File.fromUri(Platform.script).parent.parent;
  final sdk = Directory.fromUri(
    Platform.script.resolve('../../scene_program_native/'),
  );
  final signals = File.fromUri(
    Platform.script.resolve(
      '../../visual_contract/test/fixtures/synthetic/signals.bin',
    ),
  );
  final visuals = validateCreatorCatalog(_fixtures);
  for (final visual in visuals) {
    if (lintCreatorVisual(visual).isNotEmpty) {
      throw StateError('${visual.id} must pass the static check');
    }
  }
  final temporary = Directory.systemTemp.createTempSync('creator-sweep-');
  try {
    prepareCreatorNative(
      host: package,
      catalog: temporary,
      visuals: visuals,
      outputDirectory: temporary,
    );
    final binary = '${temporary.path}/authored_probe';
    final build = Process.runSync('clang++', [
      '-std=c++17',
      '-g',
      '-O1',
      '-fsanitize=address,undefined',
      '-fno-omit-frame-pointer',
      '-I${sdk.path}src',
      '-I${temporary.path}',
      '${sdk.path}src/creator_scene.cpp',
      '${sdk.path}src/creator_registry.cpp',
      '${sdk.path}test/authored_probe.cpp',
      '-o',
      binary,
    ]);
    if (build.exitCode != 0) {
      stderr.writeln(build.stderr);
      throw StateError('The authored probe does not compile.');
    }
    String run(List<String> args, int expectedExit) {
      final result = Process.runSync(binary, args);
      final output = '${result.stdout}${result.stderr}';
      if (result.exitCode != expectedExit) {
        stderr.writeln(output);
        throw StateError('Probe exit ${result.exitCode}, expected $expectedExit');
      }
      return output;
    }

    void expectLine(String output, String text) {
      if (!output.contains(text)) {
        stderr.writeln(output);
        throw StateError('Missing: $text');
      }
    }

    final relaxed = run([signals.path], 1);
    expectLine(relaxed, 'PASS modifiers creator_sano');
    expectLine(relaxed, 'PASS modifiers creator_musical');
    // Only visible on hits that fade away: still a real modifier.
    expectLine(relaxed, 'PASS modifiers creator_golpe');
    expectLine(relaxed, 'PASS modifiers creator_destello');
    if (relaxed.contains('golpe: el modificador') ||
        relaxed.contains('destello: el modificador')) {
      stderr.writeln(relaxed);
      throw StateError('A hit-only modifier was reported dead');
    }
    // A music modifier on a visual that never reacts does nothing in the app.
    expectLine(relaxed, 'WARN sordo: el modificador pulso no cambia nada');
    expectLine(relaxed, 'PASS modifiers creator_solo_variaciones');
    expectLine(relaxed, 'WARN muerto: el modificador nada no cambia nada');
    expectLine(relaxed, 'FAIL pesado: cantidad = ');
    expectLine(relaxed, 'Copia cada línea FAIL');
    final strict = run([signals.path, '--strict-modifiers'], 1);
    expectLine(strict, 'FAIL muerto: el modificador nada no cambia nada');
    // The pass gate: what each surface exceeded and the recipes.
    expectLine(
      relaxed,
      'FAIL puntos_sueltos: 40 pasadas por cuadro en el iPhone (máx 35) y '
      '145,9 MiB (máx 128); 40 pasadas por cuadro en el iPad (máx 28)',
    );
    expectLine(relaxed, 'points() 40');
    expectLine(relaxed, 'una pasada del tamaño de su rectángulo');
    expectLine(relaxed, 'un lote de puntos');
    expectLine(
      relaxed,
      'FAIL puntos_ipad: 30 pasadas por cuadro en el iPad (máx 28) y '
      '133,5 MiB (máx 128).',
    );
    expectLine(relaxed, 'El iPhone cumple: 30 de 35.');
    expectLine(
      relaxed,
      'PASS passes creator_puntos_lote: iPhone 1 (máx 35), iPad 1 (máx 28)',
    );
    final missing = run(const [], 1);
    expectLine(missing, 'faltan las señales de música');
  } finally {
    temporary.deleteSync(recursive: true);
  }
  stdout.writeln('scene_compositor: sweep checks passed.');
}

const _fixtures = [
  CreatorVisualDefinition(
    id: 'puntos_sueltos',
    name: 'Puntos sueltos',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    Paint p; p.color = f.colors[1];
    for (int i = 0; i < 40; i++) c.points({Vec2{10.f + i * 8, 100}}, 2, p);
  }
};
''',
  ),
  CreatorVisualDefinition(
    id: 'puntos_ipad',
    name: 'Puntos en iPad',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    Paint p; p.color = f.colors[1];
    for (int i = 0; i < 30; i++) c.points({Vec2{10.f + i * 8, 100}}, 2, p);
  }
};
''',
  ),
  CreatorVisualDefinition(
    id: 'puntos_lote',
    name: 'Puntos en lote',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
  std::vector<Vec2> points;
 public:
  void reset(uint32_t) override {
    points.clear();
    for (int i = 0; i < 40; i++) points.push_back({10.f + i * 8, 100});
  }
  void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    Paint p; p.color = f.colors[1];
    c.points(points, 2, p);
  }
};
''',
  ),
  CreatorVisualDefinition(
    id: 'golpe',
    name: 'Golpe',
    reactivity: CreatorReactivity.music,
    nativeSource: r'''
class Visual final : public Scene {
  float clock = 0, hit = -10;
 public:
  void reset(uint32_t) override { clock = 0; hit = -10; }
  void update(const Frame& f) override {
    clock += float(f.delta);
    if (!f.music.events[2].empty()) hit = clock;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 50, 50}, p);
    const float accent = std::max(0.f, 1 - (clock - hit) / .3f);
    if (m.anillos && accent > 0) c.circle({160, 280}, 40 + 60 * accent, p);
  }
};
''',
    modifiers: [CreatorModifier.toggle('anillos', 'Anillos')],
  ),
  CreatorVisualDefinition(
    id: 'destello',
    name: 'Destello',
    reactivity: CreatorReactivity.music,
    nativeSource: r'''
class Visual final : public Scene {
  float clock = 0, flash = -10;
 public:
  void reset(uint32_t) override { clock = 0; flash = -10; }
  void update(const Frame& f) override {
    clock += float(f.delta);
    if (!f.music.events[3].empty()) flash = clock;
  }
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 50, 50}, p);
    if (clock - flash < .2f)
      for (int i = 0; i < m.chispas; i++) c.rect({10.f * i, 300, 4, 4}, p);
  }
};
''',
    modifiers: [
      CreatorModifier.steps('chispas', 'Chispas', min: 1, max: 20, value: 5),
    ],
  ),
  CreatorVisualDefinition(
    id: 'sordo',
    name: 'Sordo',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 100 + 100 * f.music.bass * g.pulso.weight(0), 100}, p);
  }
};
''',
    modifiers: [
      CreatorModifier.choice('pulso', 'Pulso', options: ['Graves', 'Nada']),
    ],
  ),
  CreatorVisualDefinition(
    id: 'solo_variaciones',
    name: 'Solo variaciones',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 100 * f.detail, 100 * f.intensity}, p);
  }
};
''',
    variations: [
      CreatorVariation('Grande', {'detail': 2, 'intensity': 2}),
    ],
  ),
  CreatorVisualDefinition(
    id: 'sano',
    name: 'Sano',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f); auto g = glide(f);
    Paint p; p.color = f.colors[1];
    for (int i = 0; i < m.lados; i++) c.rect({10.f + i * 30, 100, 20, 20}, p);
    c.rect({0, 200, 300 * g.ancho, 40}, p);
    if (m.marco) c.rect({0, 300, 100, 20}, p);
    p.color.a = g.tono.weight(1); c.rect({0, 400, 100, 20}, p);
  }
};
''',
    modifiers: [
      CreatorModifier.steps('lados', 'Lados', min: 2, max: 6, value: 3),
      CreatorModifier.slider('ancho', 'Ancho', min: .2, max: 1, value: .5),
      CreatorModifier.toggle('marco', 'Marco'),
      CreatorModifier.choice('tono', 'Tono', options: ['Azul', 'Oro']),
    ],
    variations: [
      CreatorVariation('Lleno', {'lados': 6, 'ancho': 1, 'tono': 'Oro'}),
    ],
  ),
  CreatorVisualDefinition(
    id: 'muerto',
    name: 'Muerto',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 100 + m.nada * 0, 100}, p);
  }
};
''',
    modifiers: [
      CreatorModifier.slider('nada', 'Nada', min: 0, max: 1, value: .5),
    ],
  ),
  CreatorVisualDefinition(
    id: 'musical',
    name: 'Musical',
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto g = glide(f);
    float pulse = f.music.bass * g.pulso.weight(0) + f.music.spark * g.pulso.weight(1);
    Paint p; p.color = f.colors[1];
    c.rect({0, 0, 100 + 100 * pulse, 100}, p);
  }
};
''',
    modifiers: [
      CreatorModifier.choice('pulso', 'Pulso', options: ['Graves', 'Brillos']),
    ],
  ),
  CreatorVisualDefinition(
    id: 'pesado',
    name: 'Pesado',
    reactivity: CreatorReactivity.none,
    nativeSource: r'''
class Visual final : public Scene {
 public:
  void reset(uint32_t) override {} void update(const Frame&) override {}
  void render(const Frame& f, Canvas& c) const override {
    auto m = modifiers(f);
    std::vector<Vec2> points(m.cantidad > 9 ? 40000 : 100, Vec2{10, 10});
    Paint p; p.color = f.colors[1];
    c.points(points, 1, p);
  }
};
''',
    modifiers: [
      CreatorModifier.steps('cantidad', 'Cantidad', min: 1, max: 10, value: 3),
    ],
  ),
];
