import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:scene_compositor/scene_compositor.dart';

enum AudioChartMode {
  spectrum('Espectro'),
  waveform('Onda');

  const AudioChartMode(this.label);
  final String label;
}

/// A real-time audio visualizer line chart displaying live frequency spectrum
/// or time-domain waveform curves with neon glow aesthetics.
class AudioSignalChart extends StatefulWidget {
  const AudioSignalChart({
    this.signalListenable,
    this.reactive = true,
    this.playing = true,
    this.muted = false,
    this.initialMode = AudioChartMode.waveform,
    super.key,
  });

  final ValueListenable<SceneRenderSignalFrameV2?>? signalListenable;
  final bool reactive;
  final bool playing;
  final bool muted;
  final AudioChartMode initialMode;

  @override
  State<AudioSignalChart> createState() => _AudioSignalChartState();
}

class _AudioSignalChartState extends State<AudioSignalChart>
    with SingleTickerProviderStateMixin {
  late AudioChartMode _mode = widget.initialMode;
  final List<double> _displayBands = List.filled(31, 0.0);
  final List<double> _waveformHistory = List<double>.filled(64, 0.0, growable: true);
  double _energy = 0.0;
  bool _isBeat = false;
  double _wavePhase = 0.0;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    widget.signalListenable?.addListener(_onSignalFrame);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant AudioSignalChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signalListenable != widget.signalListenable) {
      oldWidget.signalListenable?.removeListener(_onSignalFrame);
      widget.signalListenable?.addListener(_onSignalFrame);
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    widget.signalListenable?.removeListener(_onSignalFrame);
    super.dispose();
  }

  void _onSignalFrame() {
    final frame = widget.signalListenable?.value;
    if (!mounted || frame == null || !widget.reactive || !widget.playing || widget.muted) {
      return;
    }

    final spectrum = frame.smoothedSpectrum;
    for (var i = 0; i < _displayBands.length && i < spectrum.length; i++) {
      _displayBands[i] = spectrum[i].clamp(0.0, 1.0);
    }

    _energy = frame.dynamics.isNotEmpty ? frame.dynamics[0].clamp(0.0, 1.0) : 0.0;
    _isBeat = frame.beat.active || frame.impact.active;

    // Advance synthetic waveform point based on real signal dynamics & frequency
    final bass = frame.channels.isNotEmpty ? frame.channels[0] : _energy;
    final spark = frame.channels.length > 2 ? frame.channels[2] : 0.0;
    _wavePhase += 0.35 + bass * 0.4;
    final newSample = (math.sin(_wavePhase) * _energy * 0.85 +
            math.sin(_wavePhase * 2.7) * spark * 0.3)
        .clamp(-1.0, 1.0);

    _waveformHistory.removeAt(0);
    _waveformHistory.add(newSample);

    setState(() {});
  }

  void _onTick(Duration elapsed) {
    if (!widget.playing || !widget.reactive || widget.muted || widget.signalListenable?.value == null) {
      var changed = false;
      for (var i = 0; i < _displayBands.length; i++) {
        if (_displayBands[i] > 0.005) {
          _displayBands[i] *= 0.90;
          changed = true;
        } else {
          _displayBands[i] = 0.0;
        }
      }
      for (var i = 0; i < _waveformHistory.length; i++) {
        if (_waveformHistory[i].abs() > 0.005) {
          _waveformHistory[i] *= 0.88;
          changed = true;
        } else {
          _waveformHistory[i] = 0.0;
        }
      }
      if (_energy > 0.005) {
        _energy *= 0.90;
        changed = true;
      } else {
        _energy = 0.0;
      }
      if (changed && mounted) {
        setState(() {});
      }
    }
  }

  String? get _phaseBadge {
    final frame = widget.signalListenable?.value;
    if (frame == null ||
        !widget.playing ||
        !widget.reactive ||
        widget.muted ||
        !frame.musicActive ||
        frame.semantics.isEmpty) {
      return null;
    }
    // Must be integer tag with semantics[1] == 0.0 to avoid false positives on continuous features
    if (frame.semantics.length > 1 && frame.semantics[1] != 0.0) {
      return null;
    }
    final tag = frame.semantics[0];
    final intTag = tag.round();
    if ((tag - intTag).abs() > 0.001) {
      return null;
    }
    return switch (intTag) {
      0 => 'AMBIENT',
      1 => 'BUILD-UP',
      2 => 'DROP',
      3 => 'TRAP 808',
      4 => 'CLÍMAX',
      5 => 'BARRIDO',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.signalListenable?.value;
    final active = widget.playing && widget.reactive && !widget.muted && frame != null && frame.musicActive;

    return Container(
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1714),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: active
              ? const Color(0xFF28544B)
              : const Color(0xFF1E332E),
          width: 1.2,
        ),
        boxShadow: [
          if (active)
            BoxShadow(
              color: const Color(0xFF73F572).withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: 1,
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Live Canvas Chart (Spectrum or Waveform)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 28, 10, 20),
              child: CustomPaint(
                painter: _AudioLinePainter(
                  mode: _mode,
                  bands: _displayBands,
                  waveform: _waveformHistory,
                  energy: _energy,
                  active: active,
                ),
              ),
            ),
          ),

          // 2. Chart Header: Mode selector & live status indicators
          Positioned(
            top: 6,
            left: 10,
            right: 10,
            child: Row(
              children: [
                // Mode Toggle Segment: Espectro / Onda
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mode in AudioChartMode.values)
                        GestureDetector(
                          onTap: () => setState(() => _mode = mode),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _mode == mode
                                  ? const Color(0xFF73F572).withValues(alpha: 0.25)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              mode.label,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: _mode == mode
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: _mode == mode
                                    ? const Color(0xFF73F572)
                                    : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const Spacer(),

                // Live Beat Indicator (Pulsing neon pill)
                if (_isBeat && active) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF33D98).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFF33D98),
                        width: 1,
                      ),
                    ),
                    child: const Text(
                      'BEAT',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFF33D98),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                // Energy / RMS chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active
                              ? const Color(0xFF73F572)
                              : (widget.muted ? const Color(0xFFFF9F0A) : Colors.white30),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        active
                            ? 'RMS ${(_energy * 100).toInt()}%'
                            : (widget.muted ? 'SILENCIO' : 'PAUSA'),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : (widget.muted ? const Color(0xFFFF9F0A) : Colors.white38),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Bottom Frequency / Time axis labels with Live Phase Badge
          Positioned(
            bottom: 4,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _mode == AudioChartMode.spectrum ? '60 Hz' : '-2s',
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                ),
                if (active && _phaseBadge != null && _mode == AudioChartMode.spectrum)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38E1FF).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF38E1FF).withValues(alpha: 0.7),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      _phaseBadge!,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF38E1FF),
                        letterSpacing: 0.6,
                      ),
                    ),
                  )
                else
                  Text(
                    _mode == AudioChartMode.spectrum ? '1 kHz' : 'Señal',
                    style: const TextStyle(fontSize: 9, color: Colors.white38),
                  ),
                Text(
                  _mode == AudioChartMode.spectrum ? '16 kHz' : 'Ahora',
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioLinePainter extends CustomPainter {
  _AudioLinePainter({
    required this.mode,
    required this.bands,
    required this.waveform,
    required this.energy,
    required this.active,
  });

  final AudioChartMode mode;
  final List<double> bands;
  final List<double> waveform;
  final double energy;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Draw reference grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(0, size.height * 0.33),
      Offset(size.width, size.height * 0.33),
      gridPaint,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.66),
      Offset(size.width, size.height * 0.66),
      gridPaint,
    );

    if (mode == AudioChartMode.spectrum) {
      _paintSpectrum(canvas, size);
    } else {
      _paintWaveform(canvas, size);
    }
  }

  void _paintSpectrum(Canvas canvas, Size size) {
    final points = <Offset>[];
    final count = bands.length;
    final stepX = size.width / (count - 1);

    for (var i = 0; i < count; i++) {
      final x = i * stepX;
      // 0 energy is at bottom, 1.0 energy is at top
      final normalized = bands[i].clamp(0.0, 1.0);
      final y = size.height - (normalized * size.height * 0.90) - 2;
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // Smooth spline path
    final linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    // Gradient fill under the curve
    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF73F572).withValues(alpha: active ? 0.30 : 0.08),
        const Color(0xFF4FF3A2).withValues(alpha: active ? 0.12 : 0.03),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = fillGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );

    // Glowing Neon Stroke
    final neonGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: active
          ? const [Color(0xFF73F572), Color(0xFF4FF3A2), Color(0xFF38E1FF)]
          : const [Colors.white24, Colors.white24, Colors.white24],
    );

    final lineShader = neonGradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    // Glow pass
    if (active) {
      canvas.drawPath(
        linePath,
        Paint()
          ..shader = lineShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5.0
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }

    // Main sharp line
    canvas.drawPath(
      linePath,
      Paint()
        ..shader = lineShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Peak highlights
    if (active) {
      final peakPaint = Paint()..color = const Color(0xFFFFFFFF);
      for (var i = 0; i < points.length; i++) {
        if (bands[i] > 0.65) {
          canvas.drawCircle(points[i], 2.5, peakPaint);
        }
      }
    }
  }

  void _paintWaveform(Canvas canvas, Size size) {
    final points = <Offset>[];
    final count = waveform.length;
    final stepX = size.width / (count - 1);
    final centerY = size.height / 2;

    for (var i = 0; i < count; i++) {
      final x = i * stepX;
      final y = centerY - (waveform[i] * centerY * 0.85);
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    final linePath = Path()..moveTo(points[0].dx, points[0].dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cx = (p0.dx + p1.dx) / 2;
      linePath.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    final neonGradient = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: active
          ? const [Color(0xFF73F572), Color(0xFF38E1FF), Color(0xFFF33D98)]
          : const [Colors.white24, Colors.white24, Colors.white24],
    );

    final lineShader = neonGradient.createShader(
      Rect.fromLTWH(0, 0, size.width, size.height),
    );

    // Glow pass
    if (active) {
      canvas.drawPath(
        linePath,
        Paint()
          ..shader = lineShader
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );
    }

    // Main sharp waveform line
    canvas.drawPath(
      linePath,
      Paint()
        ..shader = lineShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AudioLinePainter oldDelegate) => true;
}
