import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene_compositor/creator_build_manifest.dart';

import '../tool/readiness.dart';

// SYNTHETIC manifests only. These tests cannot become physical evidence.
void main() {
  const verifier = 'studio/tool/readiness.dart';
  const validator =
      'packages/scene_compositor/lib/creator_device_card_evidence.dart';
  const runtime = 'studio/lib/probe/energy_probe_screen.dart';
  String hash(Object? value) =>
      sha256.convert(utf8.encode(canonicalJson(value))).toString();
  Map<String, Object?> manifest({
    String verifierHash = 'old',
    String runtimeHash = 'same',
    String sdk = 'same',
    bool extra = false,
  }) {
    final files = {
      verifier: verifierHash,
      validator: 'same',
      runtime: runtimeHash,
      if (extra) 'new-runtime.dart': 'new',
    };
    final engine = <String, Object?>{
      'sdkHash': sdk,
      'buildInputs': {'files': files, 'hash': hash(files)},
      'checks': 'same',
      'energyContract': 'same',
    };
    return {'schemaVersion': 1, 'hash': hash(engine), 'engine': engine};
  }

  test(
    'verifier upgrades retain the sealed measured binary and expose their new hashes',
    () {
      final measured = manifest();
      final upgraded = manifest(verifierHash: 'new');
      final resolved = resolveCreatorEvidenceManifest(upgraded, measured);
      expect(resolved['manifest'], same(measured));
      expect(resolved['bundledMatches'], true);
      final receipt = resolved['verification'] as Map;
      expect(receipt['changedVerifierInputs'], [verifier]);
      expect(receipt['sourceManifestHash'], upgraded['hash']);
      expect((receipt['verifierHashes'] as Map)[verifier], 'new');
    },
  );
  test(
    'runtime, SDK, source membership and contract changes cannot reuse evidence',
    () {
      final measured = manifest();
      for (final current in [
        manifest(runtimeHash: 'new'),
        manifest(sdk: 'new'),
        manifest(extra: true),
      ]) {
        final resolved = resolveCreatorEvidenceManifest(current, measured);
        expect(resolved['manifest'], same(current));
        expect(resolved['bundledMatches'], false);
      }
      final changed = manifest();
      (changed['engine'] as Map)['energyContract'] = 'new';
      changed['hash'] = hash(changed['engine']);
      expect(
        resolveCreatorEvidenceManifest(changed, measured)['bundledMatches'],
        false,
      );
    },
  );
  test('altered measured manifest and altered source digest fail closed', () {
    final current = manifest(verifierHash: 'new');
    final altered = manifest()..['hash'] = 'forged';
    expect(
      resolveCreatorEvidenceManifest(current, altered)['bundledMatches'],
      false,
    );
    final brokenInputs = manifest();
    ((brokenInputs['engine'] as Map)['buildInputs'] as Map)['hash'] = 'forged';
    brokenInputs['hash'] = hash(brokenInputs['engine']);
    expect(
      resolveCreatorEvidenceManifest(current, brokenInputs)['bundledMatches'],
      false,
    );
    expect(
      resolveCreatorEvidenceManifest(current, null)['bundledMatches'],
      false,
    );
  });
}
