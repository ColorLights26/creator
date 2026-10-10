import 'dart:convert';

import 'package:audiovisual_creator/readiness/readiness_assets.dart';
import 'package:audiovisual_creator/readiness/readiness_build_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/creator_build_manifest.dart';
import 'package:visual_catalog/visual_catalog.dart';

import '../tool/readiness.dart';

const _verifier = 'studio/tool/readiness.dart';
const _validator =
    'packages/scene_compositor/lib/creator_device_card_evidence.dart';
const _runtime = 'studio/lib/probe/energy_probe_screen.dart';
const _otherVerifier =
    'packages/scene_compositor/lib/creator_trace_samples.dart';

String _hash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

// Synthetic manifests exercise identity rules, never physical evidence.
Map<String, Object?> _manifest({
  String verifier = 'same',
  String validator = 'same',
  String runtime = 'same',
  String otherVerifier = 'same',
  String sdk = 'same',
  bool extra = false,
}) {
  final files = {
    _verifier: verifier,
    _validator: validator,
    _runtime: runtime,
    _otherVerifier: otherVerifier,
    if (extra) 'new-runtime.dart': 'new',
  };
  final engine = <String, Object?>{
    'sdkHash': sdk,
    'abi': 1,
    'runtime': 'same',
    'checks': 'same',
    'resources': 'same',
    'surfaces': 'same',
    'materialToolchainHash': 'same',
    'energyContract': 'same',
    'buildInputs': {'files': files, 'hash': _hash(files)},
  };
  return {'schemaVersion': 1, 'hash': _hash(engine), 'engine': engine};
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.values);
  final Map<String, String> values;
  @override
  Future<ByteData> load(String key) async {
    final text = values[key];
    if (text == null) throw FlutterError('Missing test asset $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(text)));
  }
}

void main() {
  test('only the two authorized consumers may retain the measured stamp', () {
    final measured = _manifest();
    for (final current in [
      _manifest(verifier: 'new'),
      _manifest(validator: 'new'),
      _manifest(verifier: 'new', validator: 'new'),
    ]) {
      expect(
        resolveCreatorReadinessBuildHash(current, measured),
        measured['hash'],
      );
      final canonical = resolveCreatorEvidenceManifest(current, measured);
      expect(canonical['bundledMatches'], isTrue);
      expect(
        resolveCreatorReadinessBuildHash(current, measured),
        (canonical['manifest'] as Map)['hash'],
      );
    }
  });

  test(
    'SDK, runtime, unauthorized verifier and file membership reject reuse',
    () {
      final measured = _manifest();
      for (final current in [
        _manifest(sdk: 'new'),
        _manifest(runtime: 'new'),
        _manifest(otherVerifier: 'new'),
        _manifest(extra: true),
      ]) {
        expect(
          resolveCreatorReadinessBuildHash(current, measured),
          current['hash'],
        );
        expect(
          resolveCreatorEvidenceManifest(current, measured)['bundledMatches'],
          isFalse,
        );
      }
      for (final field in [
        'runtime',
        'checks',
        'resources',
        'surfaces',
        'energyContract',
        'materialToolchainHash',
        'abi',
      ]) {
        final current = _manifest(verifier: 'new');
        (current['engine'] as Map)[field] = 'changed';
        current['hash'] = _hash(current['engine']);
        expect(
          resolveCreatorReadinessBuildHash(current, measured),
          current['hash'],
        );
        expect(
          resolveCreatorEvidenceManifest(current, measured)['bundledMatches'],
          isFalse,
        );
      }
    },
  );

  test('incoherent hashes and incompatible schemas cannot reuse a stamp', () {
    final current = _manifest(verifier: 'new');
    final badMeasured = _manifest()..['hash'] = 'forged';
    expect(
      resolveCreatorReadinessBuildHash(current, badMeasured),
      current['hash'],
    );
    final badInputs = _manifest();
    ((badInputs['engine'] as Map)['buildInputs'] as Map)['hash'] = 'forged';
    badInputs['hash'] = _hash(badInputs['engine']);
    expect(
      resolveCreatorReadinessBuildHash(current, badInputs),
      current['hash'],
    );
    final badCurrent = _manifest(verifier: 'new')..['hash'] = 'forged';
    expect(resolveCreatorReadinessBuildHash(badCurrent, _manifest()), 'forged');
    expect(
      resolveCreatorReadinessBuildHash(
        current,
        _manifest()..['schemaVersion'] = 2,
      ),
      current['hash'],
    );
    expect(resolveCreatorReadinessBuildHash(null, _manifest()), isNull);
  });

  test('same engine needs no additional measured asset', () async {
    final current = _manifest();
    expect(resolveCreatorReadinessBuildHash(current, null), current['hash']);
    expect(
      await loadCreatorBuildHash(
        bundle: _Bundle({creatorBuildManifestAsset: jsonEncode(current)}),
      ),
      current['hash'],
    );
  });

  test(
    'asset loader rederives compatibility and tolerates malformed optional proof',
    () async {
      final current = _manifest(verifier: 'new', validator: 'new');
      final measured = _manifest();
      expect(
        await loadCreatorBuildHash(
          bundle: _Bundle({
            creatorBuildManifestAsset: jsonEncode(current),
            measuredCreatorBuildManifestAsset: jsonEncode(measured),
          }),
        ),
        measured['hash'],
      );
      expect(
        await loadCreatorBuildHash(
          bundle: _Bundle({
            creatorBuildManifestAsset: jsonEncode(current),
            measuredCreatorBuildManifestAsset: 'bad JSON',
          }),
        ),
        current['hash'],
      );
      expect(
        await loadCreatorBuildHash(
          bundle: _Bundle({
            creatorBuildManifestAsset: 'bad JSON',
            measuredCreatorBuildManifestAsset: jsonEncode(measured),
          }),
        ),
        isNull,
      );
    },
  );
}
