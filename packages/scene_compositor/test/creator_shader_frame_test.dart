import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

void main() {
  test(
    'portable uniforms preserve exact uint32 seed, color and contract positions',
    () {
      final state = _state(seed: 0xffffffff);
      state.consume(_frame());
      final values = _uniforms(state);
      expect(values.length, 34);
      expect(values.sublist(0, 5), [390, 844, 0, 65535, 65535]);
      expect(values[5], closeTo(.2, 1e-6));
      expect(
        values.sublist(6, 10),
        orderedEquals(Float32List.fromList([.3, .4, .5, .6])),
      );
      expect(values[10], closeTo(.9, 1e-6));
      expect(values[11], .25);
      expect(values[12], 128);
      expect(
        values.sublist(13, 17),
        orderedEquals(Float32List.fromList([.4, .7, .8, .9])),
      );
      expect(
        values.sublist(17, 21),
        orderedEquals(
          Float32List.fromList([
            0x11 / 255,
            0x22 / 255,
            0x33 / 255,
            0x80 / 255,
          ]),
        ),
      );
      expect(values[33], 7);
      final split = _uniforms(_state(seed: 0x1234abcd));
      expect(split[3], 0xabcd);
      expect(split[4], 0x1234);
      expect(() => _state(seed: 0x100000000), throwsArgumentError);
    },
  );

  test(
    'new events coalesce before presentation and deduplicate per source session',
    () {
      final state = _state();
      state.consume(_frame(serial: 20, strength: .8));
      state.consume(_frame(serial: 21, strength: .4));
      expect(_uniforms(state)[10], closeTo(.8, 1e-6));
      state.consume(_frame(serial: 21, strength: 1));
      expect(_uniforms(state)[10], 0);
      state.consume(_frame(serial: 19, strength: 1));
      expect(_uniforms(state)[10], 0);
      state.consume(_frame(session: 2, serial: 1, strength: .7));
      expect(_uniforms(state)[10], closeTo(.7, 1e-6));
      expect(_uniforms(state)[10], 0);
    },
  );

  test(
    'nonreactive, unavailable, and nonmusical frames deliver neutral music inputs',
    () {
      for (final state in [_state(reactive: false), _state(reactive: true)]) {
        state.consume(_frame(music: false));
        expect(_uniforms(state).sublist(5, 13), everyElement(0));
        state.consume(_frame(available: false));
        expect(_uniforms(state).sublist(5, 13), everyElement(0));
      }
      final nonreactive = _state(reactive: false)..consume(_frame());
      expect(_uniforms(nonreactive).sublist(5, 13), everyElement(0));
    },
  );

  test('host clock, pause and Reduce Motion match native state semantics', () {
    final state = _state();
    _uniforms(state, time: 10);
    expect(_uniforms(state, time: 10.1)[2], closeTo(.1, 1e-6));
    expect(_uniforms(state, time: 100)[2], closeTo(.35, 1e-6));
    state.consume(_frame());
    state.setPlaying(false, hostTime: 100);
    expect(_uniforms(state, time: 101).sublist(5, 13), everyElement(0));
    expect(state.elapsed, closeTo(.35, 1e-6));
    state.setPlaying(true, hostTime: 101);
    state.consume(_frame(serial: 10));
    final reduced = _uniforms(state, time: 101.1, reduced: true);
    expect(reduced[2], closeTo(.36, 1e-6));
    expect(reduced[10], 0);
    expect(_uniforms(state, time: 101.2)[10], 0);
  });

  test(
    'raster budget caps actual target edge while preserving aspect ratio',
    () {
      final highDpi = AndroidCreatorSession.rasterSize(const Size(390, 844), 3);
      expect(highDpi.longestSide, 1024);
      expect(highDpi.aspectRatio, closeTo(390 / 844, 1 / 1024));
      expect(
        AndroidCreatorSession.rasterSize(const Size(200, 100), 2),
        const Size(400, 200),
      );
      expect(
        AndroidCreatorSession.rasterSize(const Size(8192, 1), 8),
        const Size(1024, 1),
      );
      expect(
        () => AndroidCreatorSession.rasterSize(Size.zero, 3),
        throwsArgumentError,
      );
    },
  );
}

CreatorShaderFrame _state({int seed = 42, bool reactive = true}) =>
    CreatorShaderFrame(
      visual: const CreatorVisualDefinition(
        id: 'test_visual',
        name: 'Test visual',
        shaderSource:
            'vec4 paintVisual(vec2 uv, CreatorFrame f) { return f.color0; }',
        controls: CreatorControls(
          intensity: .4,
          speed: .7,
          detail: .8,
          glow: .9,
        ),
        colors: [0x80112233, 0xff000000, 0xffffffff, 0x00ffffff],
      ),
      visualIndex: 7,
      reactive: reactive,
      seed: seed,
    );

List<double> _uniforms(
  CreatorShaderFrame state, {
  double time = 0,
  bool reduced = false,
}) => List.of(
  state.uniforms(
    width: 390,
    height: 844,
    hostTime: time,
    reducedMotion: reduced,
  ),
);

SceneRenderSignalFrameV2 _frame({
  int session = 1,
  int serial = 3,
  double strength = .9,
  bool music = true,
  bool available = true,
}) => SceneRenderSignalFrameV2(
  sessionId: session,
  sequence: serial,
  audioTimestampMicros: 100000,
  available: available,
  fresh: true,
  musicActive: music,
  dynamics: [.1, .2, .3, .4, .5, 18],
  channels: [.3, .4, .5, .6],
  spectrumSummary: List.filled(7, 0),
  instantSpectrum: List.filled(31, 0),
  smoothedSpectrum: List.filled(31, 0),
  semantics: List.filled(6, 0),
  rhythm: [128, .25, .9, .8],
  onsets: List.filled(4, 0),
  tonalAvailable: false,
  tonal: List.filled(3, 0),
  impact: SceneRenderSignalEventV2(
    serial: serial,
    active: true,
    timestampMicros: 100000,
    strength: strength,
    band: SceneRenderSignalEventBandV2.low,
  ),
  accent: _inactive,
  beat: _inactive,
  flash: _inactive,
);

const _inactive = SceneRenderSignalEventV2(
  serial: 0,
  active: false,
  timestampMicros: 0,
  strength: 0,
  band: SceneRenderSignalEventBandV2.none,
);
