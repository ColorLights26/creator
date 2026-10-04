import 'dart:convert';
import 'dart:math' as math;

import 'package:audiovisual_creator/studio/adjustments/adjustment_session.dart';
import 'package:audiovisual_creator/studio/adjustments/personal_variations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _visual = CreatorVisualDefinition(
  id: 'galaxia',
  name: 'Galaxia',
  nativeSource: 'f.intensity f.speed',
  modifiers: [
    CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
    CreatorModifier.slider('estela', 'Estela', min: 0, max: 1, value: .3),
    CreatorModifier.toggle('nucleo', 'Núcleo', value: true),
    CreatorModifier.choice(
      'pulso',
      'Pulso',
      options: ['Graves', 'Golpes', 'Brillos'],
    ),
  ],
);

void main() {
  test('only the basics the code reads are offered', () {
    expect(AdjustmentSession(_visual).usedBasics, {'intensity', 'speed'});
  });

  test('Variar always changes a modifier and stays near and in range', () {
    for (var seed = 0; seed < 200; seed++) {
      final session = AdjustmentSession(_visual, random: math.Random(seed));
      session.vary();
      final after = session.current;
      expect(
        after.modifiers,
        isNot(_visual.modifierDefaults),
        reason: 'seed $seed changed nothing',
      );
      for (final modifier in _visual.modifiers) {
        final value = after.modifiers[modifier.id]!;
        expect(modifier.accepts(value), isTrue);
        if (modifier.kind == CreatorModifierKind.slider) {
          expect((value - modifier.value).abs(), lessThanOrEqualTo(.2 + 1e-9));
        }
        if (modifier.kind == CreatorModifierKind.steps) {
          expect((value - modifier.value).abs(), lessThanOrEqualTo(2));
        }
      }
      for (final id in ['intensity', 'speed']) {
        final value = after.controls.toMap()[id]!;
        expect(value, inInclusiveRange(.5, 1.5));
      }
      // Basics the code never reads stay where they were.
      expect(after.controls.detail, _visual.controls.detail);
      expect(after.controls.glow, _visual.controls.glow);
    }
  });

  test('Sorprender covers each declared range and nothing beyond', () {
    final seen = <String, Set<double>>{};
    for (var seed = 0; seed < 300; seed++) {
      final session = AdjustmentSession(_visual, random: math.Random(seed))
        ..surprise();
      for (final modifier in _visual.modifiers) {
        final value = session.current.modifiers[modifier.id]!;
        expect(modifier.accepts(value), isTrue);
        seen.putIfAbsent(modifier.id, () => {}).add(value);
      }
      expect(session.current.controls.speed, inInclusiveRange(.6, 1.4));
    }
    expect(seen['brazos'], containsAll([2.0, 8.0]));
    expect(seen['pulso'], {0.0, 1.0, 2.0});
    expect(seen['nucleo'], {0.0, 1.0});
  });

  test('undo walks back through looks, gestures and dice', () {
    final session = AdjustmentSession(_visual, random: math.Random(1));
    expect(session.canUndo, isFalse);
    session.apply('Tormenta', (
      controls: _visual.controls,
      modifiers: {..._visual.modifierDefaults, 'brazos': 8},
    ));
    session
      ..beginEdit()
      ..set('estela', .5)
      ..set('estela', .9);
    session.vary();
    expect(session.chip, isNull);
    session.undo();
    expect(session.current.modifiers['estela'], .9);
    session.undo();
    expect(session.current.modifiers['estela'], .3);
    expect(session.chip, 'Tormenta');
    session.undo();
    expect(session.current.modifiers, _visual.modifierDefaults);
    expect(session.chip, originalChipName);
    expect(session.canUndo, isFalse);
  });

  test('history keeps the last 20 steps', () {
    final session = AdjustmentSession(_visual, random: math.Random(2));
    for (var i = 0; i < 30; i++) {
      session.vary();
    }
    var undos = 0;
    while (session.canUndo) {
      session.undo();
      undos++;
    }
    expect(undos, AdjustmentSession.historyLimit);
  });

  test('comparing shows the original and comes back', () {
    final session = AdjustmentSession(_visual, random: math.Random(3))
      ..surprise();
    final chosen = session.current;
    session.comparing = true;
    expect(session.shown, session.original);
    expect(session.jumped, isTrue);
    session.comparing = false;
    expect(sameAdjustmentValues(session.shown, chosen), isTrue);
  });

  test('the original is exact values and the recording seed', () {
    final session = AdjustmentSession(_visual)
      ..set('brazos', 6)
      ..seed = 99;
    expect(session.differsFromOriginal, isTrue);
    session.resetToOriginal();
    expect(session.seed, isNull);
    expect(session.differsFromOriginal, isFalse);
  });

  test('the AI copy lists only what changed, choices by their text', () {
    final text = variationForAi(_visual, 'Mía 1', (
      controls: const CreatorControls(speed: 1.25),
      modifiers: {
        ..._visual.modifierDefaults,
        'brazos': 6,
        'nucleo': 0,
        'pulso': 2,
      },
    ));
    expect(
      text,
      endsWith(
        "CreatorVariation('Mía 1', {'brazos': 6, 'nucleo': false, "
        "'pulso': 'Brillos', 'speed': 1.25}),",
      ),
    );
    expect(text, contains('const variations'));
    // What the AI pastes back is a valid variation.
    final pasted = _visual.withVariation(
      const CreatorVariation('Mía 1', {
        'brazos': 6,
        'nucleo': false,
        'pulso': 'Brillos',
        'speed': 1.25,
      }),
    );
    expect(() => validateCreatorCatalog([pasted]), returnsNormally);
  });

  test('slider text keeps the decimals its range needs, never outside it', () {
    expect(sliderText(.004, .02, .004), '0.004');
    expect(sliderText(0, 1, .123456), '0.123');
    expect(sliderText(0, 1, 1), '1');
    expect(sliderText(0, .125, .125), '0.125');
    expect(sliderText(0, 2, 1.4), '1.4');
  });

  group('saved looks', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trip by modifier id', () async {
      final store = PersonalVariations();
      final look = (
        controls: const CreatorControls(speed: 1.2),
        modifiers: {..._visual.modifierDefaults, 'brazos': 7.0},
      );
      await store.save(_visual, [(name: 'Mía 1', values: look)]);
      final loaded = await store.load(_visual);
      expect(loaded.single.name, 'Mía 1');
      expect(sameAdjustmentValues(loaded.single.values, look), isTrue);
    });

    test('survive edits: unknown ids and new ranges are dropped', () async {
      SharedPreferences.setMockInitialValues({
        'creator.variations.galaxia': jsonEncode([
          {
            'name': 'Vieja',
            'values': {'brazos': 12, 'giro': 2, 'estela': .8, 'speed': 9},
          },
          {
            'name': 'Muerta',
            'values': {'giro': 2},
          },
          {'name': 3},
        ]),
      });
      final loaded = await PersonalVariations().load(_visual);
      expect(loaded.map((v) => v.name), ['Vieja']);
      expect(loaded.single.values.modifiers['brazos'], 4);
      expect(loaded.single.values.modifiers['estela'], .8);
      expect(loaded.single.values.controls.speed, _visual.controls.speed);
    });

    test('next name skips the ones in use', () {
      final look = (
        controls: _visual.controls,
        modifiers: _visual.modifierDefaults,
      );
      expect(PersonalVariations.nextName(const []), 'Mía 1');
      expect(
        PersonalVariations.nextName([
          (name: 'Mía 1', values: look),
          (name: 'Mía 3', values: look),
        ]),
        'Mía 2',
      );
    });
  });
}

extension on CreatorVisualDefinition {
  CreatorVisualDefinition withVariation(CreatorVariation variation) =>
      CreatorVisualDefinition(
        id: id,
        name: name,
        nativeSource: nativeSource,
        modifiers: modifiers,
        variations: [variation],
      );
}
