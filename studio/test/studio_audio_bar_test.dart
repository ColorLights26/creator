import 'package:audiovisual_creator/studio/studio_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tracks and silence are one tap away above the vote', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selected = <String>[];
    var mutedToggles = 0;
    Widget studio({required bool muted}) => MaterialApp(
      home: StudioView(
        visuals: const [
          StudioVisualItem(id: 'a', name: 'Visual A', thumbnail: SizedBox()),
        ],
        sources: const [
          StudioSignalSource(id: '0', name: 'Demo sintética', description: ''),
          StudioSignalSource(
            id: '1',
            name: 'EDM & Club Drop (128 BPM)',
            description: '',
          ),
        ],
        selectedVisualId: 'a',
        selectedSourceId: '0',
        textureId: null,
        preview: const SizedBox(),
        playing: true,
        reactive: true,
        reactionEnabled: true,
        loading: false,
        error: null,
        muted: muted,
        onToggleMuted: () => mutedToggles++,
        onSelectVisual: (_) {},
        onSelectSource: selected.add,
        onTogglePlaying: () {},
        onReactiveChanged: (_) {},
        onReload: () {},
        onViewportChanged: (_, _) {},
      ),
    );

    await tester.pumpWidget(studio(muted: false));
    expect(find.text('PRUÉBALO CON'), findsOneWidget);
    expect(find.text('EDM & Club Drop'), findsOneWidget, reason: 'short name');

    await tester.ensureVisible(find.byKey(const ValueKey('audio-chip-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audio-chip-1')));
    expect(selected, ['1']);
    await tester.ensureVisible(
      find.byKey(const ValueKey('audio-chip-silence')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audio-chip-silence')));
    expect(mutedToggles, 1);

    // While in silence, picking a track brings the music back.
    await tester.pumpWidget(studio(muted: true));
    await tester.ensureVisible(find.byKey(const ValueKey('audio-chip-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('audio-chip-0')));
    expect(mutedToggles, 2);
    expect(selected, ['1'], reason: 'already the selected track');
  });
}
