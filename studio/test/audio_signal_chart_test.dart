import 'package:audiovisual_creator/studio/audio_signal_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';

SceneRenderSignalFrameV2 _createTestFrame({
  bool musicActive = true,
  double energy = 0.75,
  bool beat = false,
}) {
  return SceneRenderSignalFrameV2(
    sessionId: 1,
    sequence: 1,
    audioTimestampMicros: 1000000,
    available: true,
    fresh: true,
    musicActive: musicActive,
    dynamics: [energy, energy, energy, 0.5, energy, 18],
    channels: [0.8, 0.5, 0.4, 0.6],
    spectrumSummary: [energy, 0.8, 0.5, 0.6, 0.4, 0.3, 0.2],
    instantSpectrum: List.filled(31, energy),
    smoothedSpectrum: List.generate(31, (i) => (energy * (1.0 - i / 31)).clamp(0.0, 1.0)),
    semantics: List.filled(6, 0.5),
    rhythm: List.filled(4, 0.5),
    onsets: List.filled(4, 0.5),
    tonalAvailable: false,
    tonal: List.filled(3, 0.0),
    impact: const SceneRenderSignalEventV2(
      serial: 1,
      active: false,
      timestampMicros: 0,
      strength: 0,
      band: SceneRenderSignalEventBandV2.none,
    ),
    accent: const SceneRenderSignalEventV2(
      serial: 1,
      active: false,
      timestampMicros: 0,
      strength: 0,
      band: SceneRenderSignalEventBandV2.none,
    ),
    beat: SceneRenderSignalEventV2(
      serial: 1,
      active: beat,
      timestampMicros: 1000000,
      strength: beat ? 0.9 : 0.0,
      band: SceneRenderSignalEventBandV2.broadband,
    ),
    flash: const SceneRenderSignalEventV2(
      serial: 1,
      active: false,
      timestampMicros: 0,
      strength: 0,
      band: SceneRenderSignalEventBandV2.none,
    ),
  );
}

void main() {
  testWidgets('AudioSignalChart renders idle state when inactive', (tester) async {
    final notifier = ValueNotifier<SceneRenderSignalFrameV2?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 104,
              child: AudioSignalChart(
                signalListenable: notifier,
                reactive: true,
                playing: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('PAUSA'), findsOneWidget);
    expect(find.text('Espectro'), findsOneWidget);
    expect(find.text('Onda'), findsOneWidget);
    expect(find.text('BEAT'), findsNothing);
  });

  testWidgets('AudioSignalChart updates dynamically on incoming signal frames', (tester) async {
    final notifier = ValueNotifier<SceneRenderSignalFrameV2?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 104,
              child: AudioSignalChart(
                signalListenable: notifier,
                reactive: true,
                playing: true,
              ),
            ),
          ),
        ),
      ),
    );

    notifier.value = _createTestFrame(energy: 0.82, beat: true);
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('RMS 82%'), findsOneWidget);
    expect(find.text('BEAT'), findsOneWidget);

    // Switch to Waveform Mode
    await tester.tap(find.text('Onda'));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Señal'), findsOneWidget);
    expect(find.text('Ahora'), findsOneWidget);
  });

  testWidgets('AudioSignalChart displays SILENCIO when muted', (tester) async {
    final notifier = ValueNotifier<SceneRenderSignalFrameV2?>(
      _createTestFrame(energy: 0.82, beat: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 104,
              child: AudioSignalChart(
                signalListenable: notifier,
                reactive: true,
                playing: true,
                muted: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('SILENCIO'), findsOneWidget);
    expect(find.text('BEAT'), findsNothing);
  });
}
