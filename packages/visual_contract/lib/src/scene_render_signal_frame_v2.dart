import 'dart:typed_data';

enum SceneRenderSignalEventBandV2 { none, low, body, high, broadband }

class SceneRenderSignalEventV2 {
  const SceneRenderSignalEventV2({
    required this.serial,
    required this.active,
    required this.timestampMicros,
    required this.strength,
    required this.band,
  });

  final int serial;
  final bool active;
  final int timestampMicros;
  final double strength;
  final SceneRenderSignalEventBandV2 band;
}

/// Fixed-layout, bounded visual-audio payload consumed by native scene nodes.
///
/// The renderer never opens an audio source. This frame is serialized from the
/// production visual authority and contains no raw PCM or labels.
class SceneRenderSignalFrameV2 {
  SceneRenderSignalFrameV2({
    required this.sessionId,
    required this.sequence,
    required this.audioTimestampMicros,
    required this.available,
    required this.fresh,
    required this.musicActive,
    required List<double> dynamics,
    required List<double> channels,
    required List<double> spectrumSummary,
    required List<double> instantSpectrum,
    required List<double> smoothedSpectrum,
    required List<double> semantics,
    required List<double> rhythm,
    required List<double> onsets,
    required this.tonalAvailable,
    required List<double> tonal,
    required this.impact,
    required this.accent,
    required this.beat,
    required this.flash,
  }) : dynamics = _vector(dynamics, dynamicsFieldCount, 'dynamics'),
       channels = _vector(channels, channelsFieldCount, 'channels'),
       spectrumSummary = _vector(
         spectrumSummary,
         spectrumSummaryFieldCount,
         'spectrumSummary',
       ),
       instantSpectrum = _vector(
         instantSpectrum,
         spectrumBandCount,
         'instantSpectrum',
       ),
       smoothedSpectrum = _vector(
         smoothedSpectrum,
         spectrumBandCount,
         'smoothedSpectrum',
       ),
       semantics = _vector(semantics, semanticsFieldCount, 'semantics'),
       rhythm = _vector(rhythm, rhythmFieldCount, 'rhythm'),
       onsets = _vector(onsets, onsetsFieldCount, 'onsets'),
       tonal = _vector(tonal, tonalFieldCount, 'tonal') {
    if (sessionId < 0 || sequence < 0 || audioTimestampMicros < 0) {
      throw ArgumentError('Clock and sequence values must be non-negative.');
    }
    for (final event in <SceneRenderSignalEventV2>[
      impact,
      accent,
      beat,
      flash,
    ]) {
      if (event.serial < 0 ||
          event.timestampMicros < 0 ||
          !event.strength.isFinite) {
        throw ArgumentError('Event values must be finite and non-negative.');
      }
    }
  }

  factory SceneRenderSignalFrameV2.fromBytes(Uint8List bytes) {
    if (bytes.lengthInBytes != byteLength) {
      throw FormatException('Expected $byteLength signal bytes.');
    }
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != magic ||
        data.getUint16(4, Endian.little) != version ||
        data.getUint32(8, Endian.little) != byteLength ||
        data.getUint32(12, Endian.little) != 0) {
      throw const FormatException('Invalid signal frame header.');
    }
    final flags = data.getUint16(6, Endian.little);
    if ((flags & ~_knownFlags) != 0) {
      throw const FormatException('Unknown signal frame flags.');
    }
    var floatOffset = floatBlockOffset;
    List<double> readVector(int count) {
      final result = List<double>.generate(count, (_) {
        final value = data.getFloat32(floatOffset, Endian.little);
        floatOffset += 4;
        if (!value.isFinite) {
          throw const FormatException('Signal frame contains non-finite data.');
        }
        return value;
      }, growable: false);
      return result;
    }

    var eventOffset = eventBlockOffset;
    SceneRenderSignalEventV2 readEvent() {
      final serial = data.getInt64(eventOffset, Endian.little);
      final timestamp = data.getInt64(eventOffset + 8, Endian.little);
      final strength = data.getFloat32(eventOffset + 16, Endian.little);
      final bandIndex = data.getUint8(eventOffset + 20);
      final activeValue = data.getUint8(eventOffset + 21);
      final reserved = data.getUint16(eventOffset + 22, Endian.little);
      eventOffset += eventStride;
      if (serial < 0 ||
          timestamp < 0 ||
          !strength.isFinite ||
          bandIndex >= SceneRenderSignalEventBandV2.values.length ||
          activeValue > 1 ||
          reserved != 0) {
        throw const FormatException('Invalid signal event payload.');
      }
      return SceneRenderSignalEventV2(
        serial: serial,
        active: activeValue == 1,
        timestampMicros: timestamp,
        strength: strength,
        band: SceneRenderSignalEventBandV2.values[bandIndex],
      );
    }

    return SceneRenderSignalFrameV2(
      sessionId: data.getInt64(16, Endian.little),
      sequence: data.getInt64(24, Endian.little),
      audioTimestampMicros: data.getInt64(32, Endian.little),
      available: (flags & _availableFlag) != 0,
      fresh: (flags & _freshFlag) != 0,
      musicActive: (flags & _musicActiveFlag) != 0,
      dynamics: readVector(dynamicsFieldCount),
      channels: readVector(channelsFieldCount),
      spectrumSummary: readVector(spectrumSummaryFieldCount),
      instantSpectrum: readVector(spectrumBandCount),
      smoothedSpectrum: readVector(spectrumBandCount),
      semantics: readVector(semanticsFieldCount),
      rhythm: readVector(rhythmFieldCount),
      onsets: readVector(onsetsFieldCount),
      tonalAvailable: (flags & _tonalAvailableFlag) != 0,
      tonal: readVector(tonalFieldCount),
      impact: readEvent(),
      accent: readEvent(),
      beat: readEvent(),
      flash: readEvent(),
    );
  }

  static const int magic = 0x32565253;
  static const int version = 2;
  static const int spectrumBandCount = 31;
  static const int dynamicsFieldCount = 6;
  static const int channelsFieldCount = 4;
  static const int spectrumSummaryFieldCount = 7;
  static const int semanticsFieldCount = 6;
  static const int rhythmFieldCount = 4;
  static const int onsetsFieldCount = 4;
  static const int tonalFieldCount = 3;
  static const int floatFieldCount =
      dynamicsFieldCount +
      channelsFieldCount +
      spectrumSummaryFieldCount +
      spectrumBandCount * 2 +
      semanticsFieldCount +
      rhythmFieldCount +
      onsetsFieldCount +
      tonalFieldCount;
  static const int floatBlockOffset = 40;
  static const int eventStride = 24;
  static const int eventBlockOffset = floatBlockOffset + floatFieldCount * 4;
  static const int byteLength = eventBlockOffset + eventStride * 4;

  static const int _availableFlag = 1 << 0;
  static const int _freshFlag = 1 << 1;
  static const int _musicActiveFlag = 1 << 2;
  static const int _tonalAvailableFlag = 1 << 3;
  static const int _knownFlags =
      _availableFlag | _freshFlag | _musicActiveFlag | _tonalAvailableFlag;

  final int sessionId;
  final int sequence;
  final int audioTimestampMicros;
  final bool available;
  final bool fresh;
  final bool musicActive;
  final List<double> dynamics;
  final List<double> channels;
  final List<double> spectrumSummary;
  final List<double> instantSpectrum;
  final List<double> smoothedSpectrum;
  final List<double> semantics;
  final List<double> rhythm;
  final List<double> onsets;
  final bool tonalAvailable;
  final List<double> tonal;
  final SceneRenderSignalEventV2 impact;
  final SceneRenderSignalEventV2 accent;
  final SceneRenderSignalEventV2 beat;
  final SceneRenderSignalEventV2 flash;

  Uint8List toBytes() {
    final bytes = Uint8List(byteLength);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, magic, Endian.little);
    data.setUint16(4, version, Endian.little);
    var flags = 0;
    if (available) flags |= _availableFlag;
    if (fresh) flags |= _freshFlag;
    if (musicActive) flags |= _musicActiveFlag;
    if (tonalAvailable) flags |= _tonalAvailableFlag;
    data.setUint16(6, flags, Endian.little);
    data.setUint32(8, byteLength, Endian.little);
    data.setUint32(12, 0, Endian.little);
    data.setInt64(16, sessionId, Endian.little);
    data.setInt64(24, sequence, Endian.little);
    data.setInt64(32, audioTimestampMicros, Endian.little);

    var floatOffset = floatBlockOffset;
    for (final vector in <List<double>>[
      dynamics,
      channels,
      spectrumSummary,
      instantSpectrum,
      smoothedSpectrum,
      semantics,
      rhythm,
      onsets,
      tonal,
    ]) {
      for (final value in vector) {
        data.setFloat32(floatOffset, value, Endian.little);
        floatOffset += 4;
      }
    }
    var eventOffset = eventBlockOffset;
    for (final event in <SceneRenderSignalEventV2>[
      impact,
      accent,
      beat,
      flash,
    ]) {
      data.setInt64(eventOffset, event.serial, Endian.little);
      data.setInt64(eventOffset + 8, event.timestampMicros, Endian.little);
      data.setFloat32(eventOffset + 16, event.strength, Endian.little);
      data.setUint8(eventOffset + 20, event.band.index);
      data.setUint8(eventOffset + 21, event.active ? 1 : 0);
      data.setUint16(eventOffset + 22, 0, Endian.little);
      eventOffset += eventStride;
    }
    return bytes;
  }
}

List<double> _vector(List<double> values, int length, String name) {
  if (values.length != length || values.any((value) => !value.isFinite)) {
    throw ArgumentError.value(values, name, 'Expected $length finite values.');
  }
  return List<double>.unmodifiable(values);
}
