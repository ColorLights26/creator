import 'dart:math' as math;
import 'dart:typed_data';

import 'package:visual_contract/visual_contract.dart';

import 'creator_visual_definition.dart';

/// Portable shader state matching SceneCreatorShaderState on iOS. No audio
/// capture, smoothing, normalization, wall clock, or independent timer.
class CreatorShaderFrame {
  CreatorShaderFrame({
    required this.visual,
    required this.visualIndex,
    required this.reactive,
    int? seed,
  }) : seed = seed ?? visual.seed {
    validateCreatorCatalog([visual]);
    if (visualIndex < 0 ||
        visualIndex >= 64 ||
        this.seed < 0 ||
        this.seed > 0xffffffff) {
      throw ArgumentError('Invalid installed visual index or uint32 seed.');
    }
    if ((visual.reactivity == CreatorReactivity.none && reactive) ||
        (visual.reactivity == CreatorReactivity.music && !reactive)) {
      throw ArgumentError('Reactivity does not match the installed visual.');
    }
  }

  static const uniformCount = 34;
  final CreatorVisualDefinition visual;
  final int visualIndex;
  bool reactive;
  final int seed;
  CreatorControls? _liveControls;
  CreatorControls get controls => _liveControls ?? visual.controls;
  void setControls(CreatorControls value) {
    value.validate();
    _liveControls = value;
  }

  final Float32List _uniforms = Float32List(uniformCount);
  final List<int> _eventSerials = List<int>.filled(4, -1);
  SceneRenderSignalFrameV2? _frame;
  int _eventSession = -1;
  double _pendingPulse = 0;
  double _elapsed = 0;
  double? _lastHostTime;
  bool _playing = true;

  bool get playing => _playing;
  double get elapsed => _elapsed;

  void consume(SceneRenderSignalFrameV2 next) {
    _frame = next;
    if (_eventSession != next.sessionId) {
      _eventSession = next.sessionId;
      _eventSerials.fillRange(0, _eventSerials.length, -1);
      _pendingPulse = 0;
    }
    if (!reactive || !next.available || !next.musicActive) {
      _pendingPulse = 0;
      return;
    }
    final events = [next.impact, next.accent, next.beat, next.flash];
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.active && event.serial > _eventSerials[i]) {
        _pendingPulse = math.max(_pendingPulse, event.strength);
        _eventSerials[i] = event.serial;
      }
    }
  }

  void setReactive(bool next) {
    if ((visual.reactivity == CreatorReactivity.none && next) ||
        (visual.reactivity == CreatorReactivity.music && !next))
      throw ArgumentError('Invalid reactivity');
    reactive = next;
    _pendingPulse = 0;
    _frame = null;
  }

  void setPlaying(bool next, {required double hostTime}) {
    _validateHostTime(hostTime);
    if (_playing == next) return;
    _playing = next;
    _lastHostTime = hostTime;
    if (!next) _pendingPulse = 0;
  }

  /// Returns a reused buffer. Callers upload it immediately, not retain it.
  Float32List uniforms({
    required double width,
    required double height,
    required double hostTime,
    required bool reducedMotion,
  }) {
    _validateHostTime(hostTime);
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError('Invalid render dimensions.');
    }
    final previous = _lastHostTime;
    if (_playing && previous != null) {
      _elapsed +=
          (hostTime - previous).clamp(0.0, .25) * (reducedMotion ? .1 : 1);
    }
    _lastHostTime = hostTime;
    final frame = _frame;
    final active =
        reactive &&
        _playing &&
        frame != null &&
        frame.available &&
        frame.musicActive;
    _uniforms[0] = width;
    _uniforms[1] = height;
    _uniforms[2] = _elapsed;
    // Two exactly representable halves preserve every uint32 seed bit on GLSL.
    _uniforms[3] = (seed & 0xffff).toDouble();
    _uniforms[4] = ((seed >> 16) & 0xffff).toDouble();
    _uniforms[5] = active ? frame.dynamics[1] : 0;
    for (var i = 0; i < 4; i++) {
      _uniforms[6 + i] = active ? frame.channels[i] : 0;
    }
    _uniforms[10] = active && !reducedMotion ? _pendingPulse : 0;
    _pendingPulse = 0;
    _uniforms[11] = active ? frame.rhythm[1] : 0;
    _uniforms[12] = active ? frame.rhythm[0] : 0;
    _uniforms[13] = controls.intensity;
    _uniforms[14] = controls.speed;
    _uniforms[15] = controls.detail;
    _uniforms[16] = controls.glow;
    for (var i = 0; i < 4; i++) {
      final color = visual.colors[i];
      final offset = 17 + i * 4;
      _uniforms[offset] = ((color >> 16) & 255) / 255;
      _uniforms[offset + 1] = ((color >> 8) & 255) / 255;
      _uniforms[offset + 2] = (color & 255) / 255;
      _uniforms[offset + 3] = ((color >> 24) & 255) / 255;
    }
    _uniforms[33] = visualIndex.toDouble();
    return _uniforms;
  }

  static void _validateHostTime(double hostTime) {
    if (!hostTime.isFinite || hostTime < 0) {
      throw ArgumentError('Host time must be finite and non-negative.');
    }
  }
}
