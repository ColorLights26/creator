import 'package:audiovisual_creator/studio/studio_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a slide decision advances to the following visual of the slide',
    (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const ids = ['a', 'b', 'c'];
      // Mutated synchronously, like the studio does before advancing.
      final status = {for (final id in ids) id: VisualCurationStatus.rejected};
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => StudioView(
              visuals: [
                for (final id in ids)
                  StudioVisualItem(
                    id: id,
                    name: 'Visual $id',
                    thumbnail: const SizedBox(),
                  ),
              ],
              sources: const [
                StudioSignalSource(id: '0', name: 'Demo', description: ''),
              ],
              selectedVisualId: selected,
              selectedSourceId: '0',
              textureId: null,
              preview: const SizedBox(),
              playing: true,
              reactive: true,
              reactionEnabled: true,
              loading: false,
              error: null,
              onSelectVisual: (id) => setState(() => selected = id),
              onSelectSource: (_) {},
              onTogglePlaying: () {},
              onReactiveChanged: (_) {},
              onReload: () {},
              onViewportChanged: (_, _) {},
              curationStatus: status,
              onCurationChanged: (id, value) =>
                  setState(() => status[id] = value),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('SEGUNDA OPORTUNIDAD (3 DESCARTADOS)'));
      await tester.pump();
      expect(selected, 'a');

      await tester.ensureVisible(find.text('SIGUIENTE VISUAL'));
      await tester.tap(find.text('SIGUIENTE VISUAL'));
      await tester.pump();
      expect(selected, 'b');

      // Approving b removes it from the rejected slide; the next one is c,
      // not the first remaining visual.
      await tester.ensureVisible(find.text('Aprobar'));
      await tester.tap(find.text('Aprobar'));
      await tester.pump();
      expect(status['b'], VisualCurationStatus.approved);
      expect(selected, 'c');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
