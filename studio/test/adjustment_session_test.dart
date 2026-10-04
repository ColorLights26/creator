import 'dart:convert';
import 'dart:math' as math;

import 'package:audiovisual_creator/studio/adjustments/adjustment_session.dart';
import 'package:audiovisual_creator/studio/adjustments/palettes.dart';
import 'package:audiovisual_creator/studio/adjustments/personal_variations.dart';
import 'package:flutter/painting.dart';
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
    final session =
        AdjustmentSession(_visual)
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

  group('palette', () {
    const colorful = CreatorVisualDefinition(
      id: 'color',
      name: 'Color',
      nativeSource: 'Color c = f.colors[1];',
      colors: [0xff101010, 0xffff0000, 0xff00ff00, 0xff0000ff],
    );
    const overlay = CreatorVisualDefinition(
      id: 'overlay',
      name: 'Overlay',
      role: CreatorRole.overlay,
      nativeSource: 'Color c = f.colors[1];',
      colors: [0x00000000, 0xffff0000, 0xff00ff00, 0xff0000ff],
    );

    test('only visuals that read their colors can be recolored', () {
      expect(usesPalette(colorful), isTrue);
      expect(usesPalette(_visual), isFalse);
      expect(AdjustmentSession(_visual).recolorable, isFalse);
    });

    test('an overlay keeps its transparent first color', () {
      expect(paletteFor(overlay, studioPalettes.first.colors).first, 0);
      expect(harmonicPalette(overlay, math.Random(1)).first, 0);
    });

    test('Armónica turns the hue and keeps light and saturation', () {
      final turned = harmonicPalette(colorful, math.Random(3));
      for (var i = 0; i < 4; i++) {
        final a = HSLColor.fromColor(Color(colorful.colors[i]));
        final b = HSLColor.fromColor(Color(turned[i]));
        expect(b.lightness, closeTo(a.lightness, .01));
        expect(b.saturation, closeTo(a.saturation, .01));
      }
      expect(turned, isNot(colorful.colors));
    });

    test('palette is part of undo, Original and the AI copy', () {
      final session = AdjustmentSession(colorful)
        ..setPalette(studioPalettes.first.colors);
      expect(session.differsFromOriginal, isTrue);
      session.undo();
      expect(session.palette, isNull);
      session.setPalette(studioPalettes[1].colors);
      session.resetToOriginal();
      expect(session.palette, isNull);
      final copy = variationForAi(
        colorful,
        'Mía 1',
        session.original,
        palette: const [0xff000000, 0xffffffff, 0xff00ff00, 0xffff00ff],
      );
      expect(
        copy,
        'Y en el archivo _metadata, para que esta paleta sea la original, '
        'usa colors: [0xff000000, 0xffffffff, 0xff00ff00, 0xffff00ff],',
      );
      expect(
        variationForAi(colorful, 'Mía 1', session.original),
        contains('no hay nada que copiar'),
      );
    });

    test('Sorprender sometimes recolors, always validly', () {
      final palettes = <List<int>?>{};
      for (var seed = 0; seed < 60; seed++) {
        final session = AdjustmentSession(colorful, random: math.Random(seed))
          ..surprise();
        final palette = session.palette;
        palettes.add(palette);
        if (palette != null) {
          expect(
            () => validateCreatorPalette(colorful, palette),
            returnsNormally,
          );
        }
      }
      expect(palettes.length, greaterThan(3));
      expect(palettes, contains(null));
    });

    test('saved looks keep their palette', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PersonalVariations();
      const palette = [0xff000000, 0xffffffff, 0xff00ff00, 0xffff00ff];
      await store.save(colorful, [
        (
          name: 'Mía 1',
          values: (
            controls: colorful.controls,
            modifiers: colorful.modifierDefaults,
          ),
          palette: palette,
        ),
      ]);
      final loaded = await store.load(colorful);
      expect(loaded.single.palette, palette);
    });
  });

  group('review fixes', () {
    const colorful = CreatorVisualDefinition(
      id: 'color',
      name: 'Color',
      nativeSource: 'Color c = f.colors[1]; m.brazos;',
      modifiers: [
        CreatorModifier.steps('brazos', 'Brazos', min: 2, max: 8, value: 4),
        CreatorModifier.choice('modo', 'Modo', options: ["Rock'n'roll", 'Pop']),
      ],
      variations: [
        CreatorVariation('Tormenta', {'brazos': 8}),
      ],
    );

    test('a palette change leaves the chip, so Original can come back', () {
      final session = AdjustmentSession(colorful)
        ..setPalette(studioPalettes.first.colors);
      expect(session.chip, isNull);
      session.resetToOriginal();
      expect(session.palette, isNull);
      expect(session.chip, originalChipName);
    });

    test('a saved look with its own colors brings them back', () {
      final session = AdjustmentSession(colorful);
      session.setPalette(studioPalettes.first.colors);
      session.apply('Mía 1', session.original, setsPalette: true);
      expect(session.palette, isNull);
      session.setPalette(studioPalettes[1].colors);
      session.apply('Tormenta', session.original);
      expect(session.palette, studioPalettes[1].colors);
    });

    test('Original also releases a held compare', () {
      final session =
          AdjustmentSession(colorful)
            ..set('brazos', 6)
            ..comparing = true
            ..resetToOriginal();
      expect(session.comparing, isFalse);
    });

    test('saved names never collide with Original or the author', () {
      final saved = [
        (
          name: 'Mía 1',
          values: AdjustmentSession(colorful).original,
          palette: null,
        ),
      ];
      for (final taken in ['original', 'Tormenta', 'tormenta', 'Mía 1']) {
        expect(
          PersonalVariations.nameProblem(taken, colorful, saved),
          isNotNull,
          reason: taken,
        );
      }
      expect(
        PersonalVariations.nameProblem(
          'Mía 1',
          colorful,
          saved,
          except: 'Mía 1',
        ),
        isNull,
      );
      expect(
        PersonalVariations.nameProblem('a' * 21, colorful, saved),
        isNotNull,
      );
      expect(PersonalVariations.nameProblem('Fuego', colorful, saved), isNull);
    });

    test('the AI copy escapes option texts so it pastes back valid', () {
      final session =
          AdjustmentSession(colorful)
            ..set('modo', 0)
            ..set('brazos', 5);
      final copy = variationForAi(colorful, 'Mía 1', session.current);
      expect(copy, contains("'brazos': 5"));
      final visual = CreatorVisualDefinition(
        id: 'color',
        name: 'Color',
        nativeSource: colorful.nativeSource,
        modifiers: colorful.modifiers,
      );
      // modo stays at its initial option, so only brazos is listed.
      expect(copy, isNot(contains('modo')));
      final withOption = variationForAi(visual, 'Mía 1', (
        controls: visual.controls,
        modifiers: {...visual.modifierDefaults, 'modo': 1},
      ));
      expect(withOption, contains("'modo': 'Pop'"));
      final tricky = CreatorVisualDefinition(
        id: 'tricky',
        name: 'Tricky',
        nativeSource: 'm.modo',
        modifiers: const [
          CreatorModifier.choice(
            'modo',
            'Modo',
            options: ['Pop', "Rock'n'roll"],
          ),
        ],
      );
      expect(
        variationForAi(tricky, 'Mía 1', (
          controls: tricky.controls,
          modifiers: {'modo': 1},
        )),
        contains(r"'modo': 'Rock\'n\'roll'"),
      );
    });
  });

  group('saved looks', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trip by modifier id', () async {
      final store = PersonalVariations();
      final look = (
        controls: const CreatorControls(speed: 1.2),
        modifiers: {..._visual.modifierDefaults, 'brazos': 7.0},
      );
      await store.save(_visual, [(name: 'Mía 1', values: look, palette: null)]);
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
          (name: 'Mía 1', values: look, palette: null),
          (name: 'Mía 3', values: look, palette: null),
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
