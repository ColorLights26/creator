import 'dart:io';
import 'dart:typed_data';

import 'package:visual_contract/visual_contract.dart';

// SDK-only executable checks; run
// `dart run test/scene_render_music_structure_v1_test.dart`.
void main() {
  _layout();
  _untrusted();
  _construction();
  _decoding();
  stdout.writeln('visual_contract: music structure V1 checks passed.');
}

SceneRenderMusicStructureV1 _block({
  int cueSerial = 9,
  SceneRenderMusicCueTypeV1 cueType = SceneRenderMusicCueTypeV1.impact,
  double cueStrength = 0.75,
  double energy = 0.5,
}) => SceneRenderMusicStructureV1(
  sessionId: 0x123456789,
  sequence: 4097,
  mappedTrusted: true,
  energy: energy,
  tension: 0.25,
  anticipation: 0.125,
  beatPhase: 0.0625,
  barPhase: 0.375,
  confidence: 1,
  motionScale: 0.875,
  cueSerial: cueSerial,
  cueType: cueType,
  cueStrength: cueStrength,
);

void _layout() {
  final bytes = _block().toBytes();
  final data = ByteData.sublistView(bytes);
  _expect(bytes.lengthInBytes == 80, 'fixed 80-byte block');
  _expect(data.getUint32(0, Endian.little) == 0x314D5253, 'magic');
  _expect(data.getUint16(4, Endian.little) == 1, 'version');
  _expect(data.getUint16(6, Endian.little) == 1, 'trusted flag');
  _expect(data.getUint32(8, Endian.little) == 80, 'declared length');
  _expect(data.getInt64(16, Endian.little) == 0x123456789, 'session');
  _expect(data.getInt64(24, Endian.little) == 4097, 'sequence');
  final floats = [0.5, 0.25, 0.125, 0.0625, 0.375, 1.0, 0.875, 0.75];
  for (var index = 0; index < floats.length; index += 1) {
    _expect(
      data.getFloat32(32 + index * 4, Endian.little) == floats[index],
      'float offset ${32 + index * 4}',
    );
  }
  _expect(data.getInt64(64, Endian.little) == 9, 'cue serial');
  _expect(
    data.getUint8(72) == SceneRenderMusicCueTypeV1.impact.index,
    'cue type',
  );
  for (final offset in [12, 13, 14, 15, 73, 74, 75, 76, 77, 78, 79]) {
    _expect(bytes[offset] == 0, 'reserved byte $offset');
  }
  final decoded = SceneRenderMusicStructureV1.fromBytes(bytes);
  _expect(_sameBytes(decoded.toBytes(), bytes), 'byte round trip');
  _expect(
    decoded.pairsWith(sessionId: 0x123456789, sequence: 4097) &&
        !decoded.pairsWith(sessionId: 0x123456789, sequence: 4098) &&
        !decoded.pairsWith(sessionId: 1, sequence: 4097),
    'pairs only with its own frame',
  );
  for (final type in SceneRenderMusicCueTypeV1.values.skip(1)) {
    final block = _block(cueType: type);
    _expect(
      SceneRenderMusicStructureV1.fromBytes(block.toBytes()).cueType == type,
      'cue type ${type.name}',
    );
  }
}

void _untrusted() {
  final block = SceneRenderMusicStructureV1.untrusted(
    sessionId: 3,
    sequence: 8,
  );
  final bytes = block.toBytes();
  _expect(!block.mappedTrusted && !block.cuePresent, 'untrusted has no cue');
  _expect(
    bytes.sublist(32).every((value) => value == 0),
    'untrusted carries no values',
  );
  _expect(
    !SceneRenderMusicStructureV1.fromBytes(bytes).mappedTrusted,
    'untrusted round trip',
  );
}

void _construction() {
  _throwsArgument(() => _block(energy: double.nan), 'NaN value');
  _throwsArgument(() => _block(energy: 1.01), 'value above 1');
  _throwsArgument(() => _block(energy: -0.01), 'value below 0');
  _throwsArgument(() => _block(cueSerial: 0), 'cue without serial');
  _throwsArgument(
    () => _block(cueType: SceneRenderMusicCueTypeV1.none),
    'serial without cue',
  );
  _throwsArgument(
    () => _block(
      cueSerial: 0,
      cueType: SceneRenderMusicCueTypeV1.none,
      cueStrength: 0.2,
    ),
    'strength without cue',
  );
  _throwsArgument(
    () => SceneRenderMusicStructureV1(
      sessionId: 1,
      sequence: 1,
      mappedTrusted: false,
      energy: 0.1,
      tension: 0,
      anticipation: 0,
      beatPhase: 0,
      barPhase: 0,
      confidence: 0,
      motionScale: 0,
      cueSerial: 0,
      cueType: SceneRenderMusicCueTypeV1.none,
      cueStrength: 0,
    ),
    'untrusted with values',
  );
  _throwsArgument(
    () => SceneRenderMusicStructureV1.untrusted(sessionId: -1, sequence: 0),
    'negative session',
  );
}

void _decoding() {
  final valid = _block().toBytes();
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(Uint8List(79)),
    'short block',
  );
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(Uint8List(81)),
    'long block',
  );
  for (final offset in [0, 4, 8, 12, 73, 74, 76]) {
    final corrupted = Uint8List.fromList(valid);
    corrupted[offset] ^= 0x40;
    _throwsFormat(
      () => SceneRenderMusicStructureV1.fromBytes(corrupted),
      'invalid header or reserved byte $offset',
    );
  }
  final unknownFlag = Uint8List.fromList(valid);
  ByteData.sublistView(unknownFlag).setUint16(6, 3, Endian.little);
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(unknownFlag),
    'unknown flag',
  );
  final unknownCue = Uint8List.fromList(valid);
  unknownCue[72] = SceneRenderMusicCueTypeV1.values.length;
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(unknownCue),
    'unknown cue type',
  );
  final outOfRange = Uint8List.fromList(valid);
  ByteData.sublistView(outOfRange).setFloat32(32, 2, Endian.little);
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(outOfRange),
    'value out of range',
  );
  final cueWithoutSerial = Uint8List.fromList(valid);
  ByteData.sublistView(cueWithoutSerial).setInt64(64, 0, Endian.little);
  _throwsFormat(
    () => SceneRenderMusicStructureV1.fromBytes(cueWithoutSerial),
    'cue without serial',
  );
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void _expect(bool condition, String label) {
  if (!condition) throw StateError('Failed: $label');
}

void _throwsFormat(void Function() action, String label) {
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Expected FormatException: $label');
}

void _throwsArgument(void Function() action, String label) {
  try {
    action();
  } on ArgumentError {
    return;
  }
  throw StateError('Expected ArgumentError: $label');
}
