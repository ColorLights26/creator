import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/frame_rate.dart';

void main() {
  late Directory catalog;
  late Directory visuals;
  late StringBuffer out;
  late StringBuffer err;

  String metadata(String id, {String? fpsLine}) =>
      "import 'package:scene_compositor/authoring.dart';\n"
      '\n'
      'const metadata = CreatorVisualMetadata(\n'
      "  id: '$id',\n"
      "  name: '$id',\n"
      '  role: CreatorRole.background,\n'
      '  reactivity: CreatorReactivity.optional,\n'
      '  colors: [0xff000000, 0xff111111, 0xff222222, 0xff333333],\n'
      '  // El autor explica su decisión.\n'
      '${fpsLine == null ? '' : '  $fpsLine\n'}'
      ');\n';

  File file(String id) => File('${visuals.path}/${id}_metadata.dart');
  String read(String id) => file(id).readAsStringSync();
  File record() => File('${catalog.path}/energy/frame_rate_record.json');

  int run(List<String> args) {
    out.clear();
    err.clear();
    return runFrameRate(
      [...args, '--catalog', catalog.path],
      out: out,
      err: err,
    );
  }

  void writeCsv(String text) =>
      File('${catalog.path}/energy.csv').writeAsStringSync(text);

  const header =
      'id,fps,cpu_ms_p50,gpu_ms_iphone_est,R3_passes_violation_iphone,'
      'R3_passes_violation_ipad,R5_should_be_30fps,rounds\n';

  setUp(() {
    catalog = Directory.systemTemp.createTempSync('frame-rate-');
    visuals = Directory('${catalog.path}/lib/visuals')
      ..createSync(recursive: true);
    out = StringBuffer();
    err = StringBuffer();
    file(
      'alpha',
    ).writeAsStringSync(metadata('alpha', fpsLine: 'framesPerSecond: 60,'));
    file('beta').writeAsStringSync(metadata('beta'));
    file(
      'gamma',
    ).writeAsStringSync(metadata('gamma', fpsLine: 'framesPerSecond: 60,'));
    file(
      'delta',
    ).writeAsStringSync(metadata('delta', fpsLine: 'framesPerSecond: 30,'));
    writeCsv(
      '${header}alpha,60,2.5,4.64,0,0,1,"g1.0:gpu=0.2/cpu=3,g2.0:gpu=0.163/cpu=2.5"\n'
      'gamma,60,1.2,5.44,1,1,1,"g1.0:gpu=0.2/cpu=1,g2.0:gpu=0.19/cpu=1.2"\n'
      'delta,30,0.3,1.0,0,0,0,"g1.0:gpu=0.1/cpu=0.3,g2.0:gpu=0.1/cpu=0.3"\n',
    );
  });
  tearDown(() => catalog.deleteSync(recursive: true));

  int recordCsv() => run([
    'record',
    '--from-csv',
    '${catalog.path}/energy.csv',
    '--base-commit',
    '549d910',
    '--date',
    '2026-10-06',
  ]);

  test('record keeps R5 visuals that respect the pass rule', () {
    expect(recordCsv(), 0, reason: '$err');
    final json =
        jsonDecode(record().readAsStringSync()) as Map<String, Object?>;
    expect(json['policy'], frameRatePolicy);
    expect(json['visuals'], {
      'alpha': {
        'authored': 60,
        'applied': 30,
        'reason': frameRateReason,
        'gpuIphoneEstMs': 4.64,
        'cpuMs': 2.5,
        'K': 28.47,
        'round': 'g2',
        'baseCommit': '549d910',
        'date': '2026-10-06',
      },
    });
    expect('$out', contains('Excluidos por pases (R3): gamma'));
    final first = record().readAsStringSync();
    expect(recordCsv(), 0);
    expect(record().readAsStringSync(), first);
    // Después de aplicar, la misma medición sigue dando el mismo registro.
    expect(run(['apply', '--all']), 0);
    expect(recordCsv(), 0, reason: '$err');
    expect(record().readAsStringSync(), first);
  });

  // aggregate.py sólo pone R5 en filas a 60 fps: medido ya a 30, R5 vale 0.
  int recordAfterApply(String alphaRow) {
    expect(recordCsv(), 0, reason: '$err');
    expect(run(['apply', '--all']), 0, reason: '$err');
    writeCsv(
      '$header$alphaRow\n'
      'delta,30,0.3,1.0,0,0,0,"g3.0:gpu=0.1/cpu=0.3"\n',
    );
    return run([
      'record',
      '--from-csv',
      '${catalog.path}/energy.csv',
      '--base-commit',
      '8284fae',
      '--date',
      '2026-10-07',
    ]);
  }

  test('record after apply keeps entries that still need 30 fps', () {
    expect(
      recordAfterApply('alpha,30,2.4,4.3,0,0,0,"g3.0:gpu=0.151/cpu=2.4"'),
      0,
      reason: '$err',
    );
    final json =
        jsonDecode(record().readAsStringSync()) as Map<String, Object?>;
    expect(json['visuals'], {
      'alpha': {
        'authored': 60,
        'applied': 30,
        'reason': frameRateReason,
        'gpuIphoneEstMs': 4.3,
        'cpuMs': 2.4,
        'K': 28.47,
        'round': 'g3',
        'baseCommit': '8284fae',
        'date': '2026-10-07',
      },
    });
    expect('$out', contains('(0 nuevos, 1 actualizados, 0 quitados)'));
    expect(read('alpha'), contains('framesPerSecond: 30, $frameRateMarker'));
    expect(run(['check']), 0, reason: '$out');
  });

  test('record after apply reports a visual that now fits 60 fps', () {
    expect(recordCsv(), 0);
    final before = record().readAsStringSync();
    expect(
      recordAfterApply('alpha,30,1.5,3.2,0,0,0,"g3.0:gpu=0.112/cpu=1.5"'),
      0,
      reason: '$err',
    );
    // El registro y el metadata no cambian: revertir lo decide una persona.
    expect(record().readAsStringSync(), before);
    expect(read('alpha'), contains('framesPerSecond: 30, $frameRateMarker'));
    expect('$out', contains('Ya caben en 60 fps y siguen aplicados'));
    expect(
      '$out',
      contains('dart run tool/frame_rate.dart revert --ids alpha'),
    );
    expect(run(['check']), 0, reason: '$out');
  });

  test('record after apply refuses an applied visual over the 30 budget', () {
    expect(recordCsv(), 0);
    final before = record().readAsStringSync();
    expect(
      recordAfterApply('alpha,30,2.4,8.6,0,0,0,"g3.0:gpu=0.302/cpu=2.4"'),
      1,
    );
    expect('$err', contains('alpha: ya no cumple la regla y está aplicado'));
    expect(record().readAsStringSync(), before);
  });

  test('apply and revert touch one line and are idempotent', () {
    final original = {
      for (final id in ['alpha', 'beta', 'gamma', 'delta']) id: read(id),
    };
    expect(recordCsv(), 0);

    expect(run(['apply', '--all']), 0, reason: '$err');
    final applied = read('alpha');
    expect(
      applied,
      original['alpha']!.replaceFirst(
        '  framesPerSecond: 60,\n',
        '  framesPerSecond: 30, $frameRateMarker\n',
      ),
    );
    // El comentario explica el 30 sin depender del comentario del autor y
    // cabe en 80 columnas, así dart format no parte la línea.
    final line = applied
        .split('\n')
        .singleWhere((text) => text.contains('framesPerSecond'));
    expect(
      line,
      '  framesPerSecond: 30, '
      '// energía: 60 no cabe; ver energy/frame_rate_record.json',
    );
    expect(line.length, lessThanOrEqualTo(80));
    for (final id in ['beta', 'gamma', 'delta']) {
      expect(read(id), original[id]);
    }
    expect(run(['apply', '--all']), 0);
    expect(read('alpha'), applied);
    expect('$out', contains('0 metadata cambiados'));
    expect(run(['check']), 0, reason: '$out');

    expect(run(['revert', '--all']), 0);
    expect(read('alpha'), original['alpha']);
    expect(run(['revert', '--ids', 'alpha']), 0);
    expect(read('alpha'), original['alpha']);
    expect(run(['check']), 0, reason: '$out');

    expect(run(['apply', '--ids', 'alpha']), 0);
    expect(read('alpha'), applied);
    expect(run(['status']), 0);
    expect('$out', contains('1 aplicados'));
  });

  test('inserts framesPerSecond after reactivity when the target is 60', () {
    final original = read('beta');
    record()
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'policy': frameRatePolicy,
          'visuals': {
            'beta': {'authored': 60, 'applied': 30},
          },
        }),
      );
    // Sin línea vale 30, que ya es el aplicado: no hay nada que escribir.
    expect(run(['apply', '--ids', 'beta']), 0, reason: '$err');
    expect(read('beta'), original);
    expect(run(['check']), 0, reason: '$out');

    expect(run(['revert', '--ids', 'beta']), 0, reason: '$err');
    final reverted = original.replaceFirst(
      '  reactivity: CreatorReactivity.optional,\n',
      '  reactivity: CreatorReactivity.optional,\n'
          '  framesPerSecond: 60,\n',
    );
    expect(read('beta'), reverted);
    expect(run(['revert', '--ids', 'beta']), 0);
    expect(read('beta'), reverted);

    expect(run(['apply', '--ids', 'beta']), 0);
    expect(read('beta'), contains('  framesPerSecond: 30, $frameRateMarker\n'));
    expect(run(['revert', '--ids', 'beta']), 0);
    expect(read('beta'), reverted);
  });

  test('check fails on drift', () {
    expect(recordCsv(), 0);
    expect(run(['apply', '--all']), 0);
    final applied = read('alpha');

    file(
      'alpha',
    ).writeAsStringSync(applied.replaceFirst(' $frameRateMarker', ''));
    expect(run(['check']), 1);
    expect('$out', contains('alpha: vale 30 sin la marca de energía'));

    file('alpha').writeAsStringSync(
      applied.replaceFirst('framesPerSecond: 30,', 'framesPerSecond: 60,'),
    );
    expect(run(['check']), 1);
    expect('$out', contains('alpha: tiene la marca con el valor del autor'));

    file('alpha').writeAsStringSync(applied);
    file('delta').writeAsStringSync(
      read('delta').replaceFirst(
        'framesPerSecond: 30,',
        'framesPerSecond: 30, $frameRateMarker',
      ),
    );
    expect(run(['check']), 1);
    expect('$out', contains('delta: tiene la marca de energía pero no está'));

    file(
      'delta',
    ).writeAsStringSync(metadata('delta', fpsLine: 'framesPerSecond: 30,'));
    file('alpha').deleteSync();
    expect(run(['check']), 1);
    expect('$out', contains('Falta lib/visuals/alpha_metadata.dart'));
  });

  test('rejects unknown ids and ambiguous metadata without writing', () {
    expect(recordCsv(), 0);
    expect(run(['apply', '--ids', 'alpha,nope']), 2);
    expect('$err', contains('nope'));
    expect(run(['apply']), 2);

    final ambiguous =
        '${read('alpha')}// framesPerSecond: 30 sería más barato\n';
    file('alpha').writeAsStringSync(ambiguous);
    expect(run(['apply', '--all']), 1);
    expect('$err', contains('framesPerSecond aparece 2 veces'));
    expect(read('alpha'), ambiguous);

    // El único valor aplicado por energía es 30: la marca no admite otro.
    final original = read('beta');
    record().writeAsStringSync(
      jsonEncode({
        'policy': frameRatePolicy,
        'visuals': {
          'beta': {'authored': 30, 'applied': 60},
        },
      }),
    );
    expect(run(['apply', '--ids', 'beta']), 1);
    expect('$err', contains('beta.applied debe ser 30 o igual a authored'));
    expect(read('beta'), original);
  });

  test('record refuses a measurement that no longer matches the metadata', () {
    file(
      'alpha',
    ).writeAsStringSync(metadata('alpha', fpsLine: 'framesPerSecond: 30,'));
    expect(recordCsv(), 1);
    expect('$err', contains('se midió a 60 fps pero el metadata vale 30'));
    expect(record().existsSync(), isFalse);
  });
}
