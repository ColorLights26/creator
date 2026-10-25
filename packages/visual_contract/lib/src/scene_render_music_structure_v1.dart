import 'dart:typed_data';

/// Cue kinds of the resolved music structure, in wire order.
enum SceneRenderMusicCueTypeV1 {
  none,
  beat,
  accent,
  impact,
  transition,
  drop,
  release,
}

/// Fixed-layout companion of `SceneRenderSignalFrameV2` that carries the
/// scene's resolved MusicMap structure to renderers whose family policy reads
/// it (energy, tension, anticipation, beat and bar phase, confidence and the
/// typed cue). The V2 frame keeps its generic projection unchanged.
///
/// A block travels in the same message as the frame it belongs to and names
/// it by transport session and sequence. When the runtime did not admit a
/// trusted map for that frame the block is untrusted and every value is zero,
/// so no reader can act on structure the runtime did not resolve.
class SceneRenderMusicStructureV1 {
  SceneRenderMusicStructureV1({
    required this.sessionId,
    required this.sequence,
    required this.mappedTrusted,
    required this.energy,
    required this.tension,
    required this.anticipation,
    required this.beatPhase,
    required this.barPhase,
    required this.confidence,
    required this.motionScale,
    required this.cueSerial,
    required this.cueType,
    required this.cueStrength,
  }) {
    final problem = _problem();
    if (problem != null) throw ArgumentError(problem);
  }

  SceneRenderMusicStructureV1.untrusted({
    required int sessionId,
    required int sequence,
  }) : this(
         sessionId: sessionId,
         sequence: sequence,
         mappedTrusted: false,
         energy: 0,
         tension: 0,
         anticipation: 0,
         beatPhase: 0,
         barPhase: 0,
         confidence: 0,
         motionScale: 0,
         cueSerial: 0,
         cueType: SceneRenderMusicCueTypeV1.none,
         cueStrength: 0,
       );

  factory SceneRenderMusicStructureV1.fromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes != byteLength) {
      throw FormatException('Expected $byteLength music structure bytes.');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != magic ||
        data.getUint16(4, Endian.little) != version ||
        data.getUint32(8, Endian.little) != byteLength ||
        data.getUint32(12, Endian.little) != 0 ||
        data.getUint8(73) != 0 ||
        data.getUint16(74, Endian.little) != 0 ||
        data.getUint32(76, Endian.little) != 0) {
      throw const FormatException('Invalid music structure header.');
    }
    final flags = data.getUint16(6, Endian.little);
    final cueTypeIndex = data.getUint8(72);
    if ((flags & ~_knownFlags) != 0 ||
        cueTypeIndex >= SceneRenderMusicCueTypeV1.values.length) {
      throw const FormatException('Unknown music structure flags or cue.');
    }
    try {
      return SceneRenderMusicStructureV1(
        sessionId: data.getInt64(16, Endian.little),
        sequence: data.getInt64(24, Endian.little),
        mappedTrusted: (flags & _mappedTrustedFlag) != 0,
        energy: data.getFloat32(32, Endian.little),
        tension: data.getFloat32(36, Endian.little),
        anticipation: data.getFloat32(40, Endian.little),
        beatPhase: data.getFloat32(44, Endian.little),
        barPhase: data.getFloat32(48, Endian.little),
        confidence: data.getFloat32(52, Endian.little),
        motionScale: data.getFloat32(56, Endian.little),
        cueStrength: data.getFloat32(60, Endian.little),
        cueSerial: data.getInt64(64, Endian.little),
        cueType: SceneRenderMusicCueTypeV1.values[cueTypeIndex],
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid music structure: ${error.message}');
    }
  }

  static const int magic = 0x314D5253;
  static const int version = 1;
  static const int byteLength = 80;

  static const int _mappedTrustedFlag = 1 << 0;
  static const int _knownFlags = _mappedTrustedFlag;

  final int sessionId;
  final int sequence;
  final bool mappedTrusted;
  final double energy;
  final double tension;
  final double anticipation;
  final double beatPhase;
  final double barPhase;
  final double confidence;

  /// Safety motion envelope the runtime applied to this frame.
  final double motionScale;
  final int cueSerial;
  final SceneRenderMusicCueTypeV1 cueType;
  final double cueStrength;

  bool get cuePresent => cueType != SceneRenderMusicCueTypeV1.none;

  /// Whether this block belongs to [sessionId] and [sequence] of its frame.
  bool pairsWith({required int sessionId, required int sequence}) =>
      this.sessionId == sessionId && this.sequence == sequence;

  Uint8List toBytes() {
    final bytes = Uint8List(byteLength);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, magic, Endian.little);
    data.setUint16(4, version, Endian.little);
    data.setUint16(6, mappedTrusted ? _mappedTrustedFlag : 0, Endian.little);
    data.setUint32(8, byteLength, Endian.little);
    data.setInt64(16, sessionId, Endian.little);
    data.setInt64(24, sequence, Endian.little);
    data.setFloat32(32, energy, Endian.little);
    data.setFloat32(36, tension, Endian.little);
    data.setFloat32(40, anticipation, Endian.little);
    data.setFloat32(44, beatPhase, Endian.little);
    data.setFloat32(48, barPhase, Endian.little);
    data.setFloat32(52, confidence, Endian.little);
    data.setFloat32(56, motionScale, Endian.little);
    data.setFloat32(60, cueStrength, Endian.little);
    data.setInt64(64, cueSerial, Endian.little);
    data.setUint8(72, cueType.index);
    return bytes;
  }

  String? _problem() {
    if (sessionId < 0 || sequence < 0 || cueSerial < 0) {
      return 'Session, sequence and cue serial must be non-negative.';
    }
    final values = <double>[
      energy,
      tension,
      anticipation,
      beatPhase,
      barPhase,
      confidence,
      motionScale,
      cueStrength,
    ];
    if (values.any((value) => !value.isFinite || value < 0 || value > 1)) {
      return 'Structure values must be finite and within [0, 1].';
    }
    if (cuePresent != (cueSerial > 0) || (!cuePresent && cueStrength != 0)) {
      return 'A cue needs a type and a positive serial; no cue carries none.';
    }
    if (!mappedTrusted && (cuePresent || values.any((value) => value != 0))) {
      return 'An untrusted structure carries no values.';
    }
    return null;
  }
}
