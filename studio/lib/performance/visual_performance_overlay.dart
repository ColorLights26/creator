import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'visual_performance.dart';

const _good = Color(0xFF73F572);
const _warn = Color(0xFFFFC857);
const _bad = Color(0xFFFF6B6B);
const _muted = Colors.white54;
const _figures = [FontFeature.tabularFigures()];

/// Live cost of the visual on screen, refreshed every second. Collapsed it
/// shows CPU and FPS; a tap opens the frame budget and what can't be
/// measured on this platform.
class VisualPerformanceOverlay extends StatefulWidget {
  const VisualPerformanceOverlay({
    required this.sample,
    this.debugBuild = kDebugMode,
    super.key,
  });

  final ValueListenable<VisualPerformanceSample?> sample;

  /// Debug builds run unoptimized Dart and Swift: every cost reads higher
  /// than in the real app, so the overlay says so.
  final bool debugBuild;

  @override
  State<VisualPerformanceOverlay> createState() =>
      _VisualPerformanceOverlayState();
}

class _VisualPerformanceOverlayState extends State<VisualPerformanceOverlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VisualPerformanceSample?>(
      valueListenable: widget.sample,
      builder:
          (context, sample, _) => Material(
            key: const ValueKey('performance-overlay'),
            color: Colors.black.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white12),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('performance-toggle'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colors.white,
                    fontFeatures: _figures,
                  ),
                  child: _expanded ? _details(sample) : _summary(sample),
                ),
              ),
            ),
          ),
    );
  }

  Widget _summary(VisualPerformanceSample? sample) {
    final fps = _fpsText(sample);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.speed_rounded, size: 14, color: _good),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'CPU ${_percent(sample?.processCpuPercent)}'),
                  const TextSpan(text: ' · ', style: TextStyle(color: _muted)),
                  TextSpan(text: fps.$1, style: TextStyle(color: fps.$2)),
                  if (widget.debugBuild)
                    const TextSpan(
                      text: ' · debug',
                      style: TextStyle(color: _warn),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(VisualPerformanceSample? sample) {
    final budget = sample?.frameBudgetMs;
    final fps = _fpsText(sample, unit: false);
    final rows = <Widget>[
      Row(
        children: [
          const Icon(Icons.speed_rounded, size: 14, color: _good),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              sample == null
                  ? 'RENDIMIENTO'
                  : 'RENDIMIENTO · ${sample.nativeSurface ? 'iPhone' : 'Android'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.white70,
              ),
            ),
          ),
          const Icon(Icons.expand_less_rounded, size: 16, color: _muted),
        ],
      ),
      const SizedBox(height: 4),
      _row('CPU app', _percent(sample?.processCpuPercent)),
      ..._comparison(sample),
      _row('FPS', fps.$1, color: fps.$2),
    ];
    if (sample != null && sample.nativeSurface) {
      rows
        ..add(
          _row(
            'Cuadro',
            _ofBudget(sample.frameAverageMs, budget),
            color: _budgetColor(sample.frameAverageMs, budget),
          ),
        )
        ..add(
          _row(
            'Picos',
            sample.frameP95Ms == null
                ? '—'
                : '${_ms(sample.frameP95Ms)} · tirones '
                    '${_percent(sample.jankPercent)}',
            color: _worst(
              _budgetColor(sample.frameP95Ms, budget),
              _jankColor(sample.jankPercent),
            ),
          ),
        )
        ..add(_row('GPU', 'incluida en Cuadro', color: _muted));
    } else if (sample != null) {
      rows
        ..add(
          _row(
            'CPU visual',
            _ofBudget(sample.visualCpuMsPerFrame, budget),
            color: _budgetColor(sample.visualCpuMsPerFrame, budget),
          ),
        )
        ..add(_row('GPU', 'no medible en Android', color: _muted));
    }
    if (sample?.simulationMsPerFrame case final double simulation) {
      rows.add(_row('C++', _ms(simulation)));
    }
    if (sample?.thermalState case final int thermal) {
      rows.add(
        _row(
          'Temperatura',
          switch (thermal) {
            0 => 'normal',
            1 => 'tibio',
            2 => 'caliente (baja velocidad)',
            _ => 'crítica',
          },
          color: switch (thermal) {
            0 => _good,
            1 => _warn,
            _ => _bad,
          },
        ),
      );
    }
    rows
      ..add(const SizedBox(height: 4))
      ..add(
        Text(
          sample == null
              ? 'Midiendo…'
              : 'CPU 100% = 1 núcleo (hay ${sample.cores}).'
                  '${budget == null ? '' : ' Cada cuadro tiene ${_ms(budget)}.'}',
          style: const TextStyle(fontSize: 10, color: _muted),
        ),
      );
    if (widget.debugBuild) {
      rows.add(
        const Text(
          'Modo debug: todo sale más alto que en la app real. '
          'Para medir, abre el Creator con --profile.',
          style: TextStyle(fontSize: 10, color: _warn),
        ),
      );
    }
    return SizedBox(
      width: 232,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  /// What playing the visual adds over the paused studio.
  List<Widget> _comparison(VisualPerformanceSample? sample) {
    if (sample == null) return const [];
    return switch (sample.activity) {
      VisualActivity.paused => [
        _row('En pausa', 'base del estudio', color: _muted),
      ],
      VisualActivity.busy => [_row('Visual', 'cargando…', color: _muted)],
      VisualActivity.playing => [
        if (sample.visualCpuPercent case final double visual)
          _row(
            'Del visual',
            '≈ +${visual.toStringAsFixed(0)}% '
                '(pausa ${_percent(sample.pausedCpuPercent)})',
          )
        else
          _row('Del visual', 'pausa 2 s para comparar', color: _muted),
      ],
    };
  }

  Widget _row(String label, String value, {Color? color}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 74,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70),
        ),
      ),
      Expanded(
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color ?? Colors.white,
          ),
        ),
      ),
    ],
  );

  /// The detail row already says FPS; the summary needs the [unit].
  (String, Color) _fpsText(
    VisualPerformanceSample? sample, {
    bool unit = true,
  }) {
    final suffix = unit ? ' FPS' : '';
    if (sample == null) return ('—$suffix', Colors.white);
    if (sample.activity == VisualActivity.paused) return ('en pausa', _muted);
    final fps = sample.framesPerSecond;
    final target = sample.targetFramesPerSecond;
    if (fps == null) return ('—$suffix', Colors.white);
    final text =
        target == null
            ? '${fps.round()}$suffix'
            : '${fps.round()}/$target$suffix';
    if (target == null || target <= 0) return (text, Colors.white);
    final ratio = fps / target;
    if (ratio >= 0.9) return (text, _good);
    // The iOS compositor skips frames when nothing changes: fewer frames
    // that all fit the budget are not a cost problem.
    final budget = sample.frameBudgetMs;
    final p95 = sample.frameP95Ms;
    if (sample.nativeSurface &&
        budget != null &&
        p95 != null &&
        p95 <= budget &&
        (sample.jankPercent ?? 0) == 0) {
      return (text, Colors.white);
    }
    return (text, ratio >= 0.75 ? _warn : _bad);
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(0)}%';

  /// Sub-millisecond costs (a light C++ step) keep two decimals so they
  /// don't read as zero.
  static String _number(double value) {
    if (value < 0.01) return '< 0.01';
    return value.toStringAsFixed(value < 1 ? 2 : 1);
  }

  static String _ms(double? value) =>
      value == null ? '—' : '${_number(value)} ms';

  static String _ofBudget(double? value, double? budget) {
    if (value == null) return '—';
    if (budget == null) return _ms(value);
    return '${_number(value)} de ${_ms(budget)}';
  }

  static Color? _budgetColor(double? value, double? budget) {
    if (value == null || budget == null) return null;
    final ratio = value / budget;
    if (ratio <= 0.6) return _good;
    return ratio <= 1 ? _warn : _bad;
  }

  static Color? _jankColor(double? percent) {
    if (percent == null) return null;
    if (percent <= 2) return _good;
    return percent <= 10 ? _warn : _bad;
  }

  static Color? _worst(Color? a, Color? b) {
    for (final color in const [_bad, _warn, _good]) {
      if (a == color || b == color) return color;
    }
    return null;
  }
}
