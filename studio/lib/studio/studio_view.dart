import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';

import 'audio_signal_chart.dart';

enum VisualCurationStatus {
  pending,
  approved,
  rejected,
}

enum StudioBackgroundMode {
  dark,
  checkerboard,
  light,
}

class StudioVisualItem {
  const StudioVisualItem({
    required this.id,
    required this.name,
    required this.thumbnail,
    this.description = '',
    this.details = '',
  });
  final String id;
  final String name;
  final Widget thumbnail;
  final String description;
  final String details;
}

class StudioSignalSource {
  const StudioSignalSource({
    required this.id,
    required this.name,
    required this.description,
  });
  final String id;
  final String name;
  final String description;
}

class StudioView extends StatefulWidget {
  const StudioView({
    required this.visuals,
    required this.sources,
    required this.selectedVisualId,
    required this.selectedSourceId,
    required this.textureId,
    required this.preview,
    required this.playing,
    required this.reactive,
    required this.reactionEnabled,
    required this.loading,
    required this.error,
    required this.onSelectVisual,
    required this.onSelectSource,
    required this.onTogglePlaying,
    required this.onReactiveChanged,
    required this.onReload,
    required this.onViewportChanged,
    this.signalListenable,
    this.onPictureInPicture,
    this.pictureInPictureActive = false,
    this.curationStatus = const {},
    this.onCurationChanged,
    this.muted = false,
    this.onToggleMuted,
    this.ratingPanel,
    super.key,
  });

  final VoidCallback? onPictureInPicture;
  final bool pictureInPictureActive;
  final List<StudioVisualItem> visuals;
  final List<StudioSignalSource> sources;
  final String? selectedVisualId;
  final String selectedSourceId;
  final int? textureId;
  final Widget? preview;
  final bool playing;
  final bool reactive;
  final bool reactionEnabled;
  final bool loading;
  final String? error;
  final bool muted;
  final VoidCallback? onToggleMuted;
  final ValueChanged<String?> onSelectVisual;
  final ValueChanged<String> onSelectSource;
  final VoidCallback onTogglePlaying;
  final ValueChanged<bool> onReactiveChanged;
  final VoidCallback onReload;
  final void Function(Size size, double pixelRatio) onViewportChanged;
  final Map<String, VisualCurationStatus> curationStatus;
  final void Function(String id, VisualCurationStatus status)? onCurationChanged;
  final ValueListenable<SceneRenderSignalFrameV2?>? signalListenable;

  /// Team 1-10 voting for the selected visual, when the studio has it.
  final Widget? ratingPanel;

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  int _fps = 144;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  bool _showControls = true;
  StudioBackgroundMode _bgMode = StudioBackgroundMode.dark;

  void _cycleBackgroundMode() {
    setState(() {
      _bgMode = switch (_bgMode) {
        StudioBackgroundMode.dark => StudioBackgroundMode.checkerboard,
        StudioBackgroundMode.checkerboard => StudioBackgroundMode.light,
        StudioBackgroundMode.light => StudioBackgroundMode.dark,
      };
    });
  }

  IconData get _bgModeIcon => switch (_bgMode) {
    StudioBackgroundMode.dark => Icons.grid_4x4_rounded,
    StudioBackgroundMode.checkerboard => Icons.texture_rounded,
    StudioBackgroundMode.light => Icons.light_mode_rounded,
  };

  String get _bgModeLabel => switch (_bgMode) {
    StudioBackgroundMode.dark => 'Fondo oscuro',
    StudioBackgroundMode.checkerboard => 'Cuadrícula alpha',
    StudioBackgroundMode.light => 'Fondo claro',
  };

  String get _bgModeTooltip => switch (_bgMode) {
    StudioBackgroundMode.dark => 'Fondo: Oscuro (toca para cuadrícula alpha)',
    StudioBackgroundMode.checkerboard =>
        'Fondo: Cuadrícula alpha (toca para fondo claro)',
    StudioBackgroundMode.light => 'Fondo: Claro (toca para fondo oscuro)',
  };

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (!mounted) return;
      _frameCount++;
      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsTime).inMilliseconds;
      if (elapsed >= 1000) {
        final calculated = (_frameCount * 1000 / elapsed).round();
        setState(() {
          _fps = calculated.clamp(30, 240);
          _frameCount = 0;
          _lastFpsTime = now;
        });
      }
    });
  }

  int get _currentIndex {
    if (widget.visuals.isEmpty || widget.selectedVisualId == null) return -1;
    return widget.visuals.indexWhere((v) => v.id == widget.selectedVisualId);
  }

  List<StudioVisualItem> get _pendingVisuals {
    return widget.visuals.where((v) {
      final status =
          widget.curationStatus[v.id] ?? VisualCurationStatus.pending;
      return status == VisualCurationStatus.pending;
    }).toList();
  }

  void _goToPreviousVisual() {
    if (widget.visuals.isEmpty) return;
    final view = _viewVisuals;
    if (view.isEmpty) {
      widget.onSelectVisual(null);
      return;
    }

    final currentId = widget.selectedVisualId;
    final viewIndex = view.indexWhere((v) => v.id == currentId);
    if (viewIndex > 0) {
      widget.onSelectVisual(view[viewIndex - 1].id);
    } else if (viewIndex == 0) {
      widget.onSelectVisual(view.last.id);
    } else {
      widget.onSelectVisual(view.first.id);
    }
  }

  void _goToNextVisual() {
    if (widget.visuals.isEmpty) return;
    final view = _viewVisuals;
    if (view.isEmpty) {
      widget.onSelectVisual(null);
      return;
    }

    final currentId = widget.selectedVisualId;
    final viewIndex = view.indexWhere((v) => v.id == currentId);
    if (viewIndex >= 0) {
      final nextIndex = (viewIndex + 1) % view.length;
      widget.onSelectVisual(view[nextIndex].id);
    } else {
      widget.onSelectVisual(view.first.id);
    }
  }

  void _advanceAfterCuration(String curatedId) {
    // En modo vista se avanza dentro del slide actual.
    if (_viewFilter != null) {
      final remaining = _viewVisuals.where((v) => v.id != curatedId).toList();
      if (remaining.isNotEmpty) {
        final curatedIndex = _viewVisuals.indexWhere(
          (v) => v.id == curatedId,
        );
        final next = remaining.firstWhere(
          (v) => _viewVisuals.indexOf(v) > curatedIndex,
          orElse: () => remaining.first,
        );
        widget.onSelectVisual(next.id);
      } else {
        // Slide terminado: salir del modo y volver a la cola normal.
        setState(() => _viewFilter = null);
        final pending = _pendingVisuals.where((v) => v.id != curatedId);
        if (pending.isNotEmpty) {
          widget.onSelectVisual(pending.first.id);
        } else {
          widget.onSelectVisual(null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '🎉 ¡Completado! Has evaluado todos los visuales del catálogo.',
              ),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }

    final remainingPending = widget.visuals.where((v) {
      if (v.id == curatedId) return false;
      final status =
          widget.curationStatus[v.id] ?? VisualCurationStatus.pending;
      return status == VisualCurationStatus.pending;
    }).toList();

    if (remainingPending.isNotEmpty) {
      final curatedIndex = widget.visuals.indexWhere((v) => v.id == curatedId);
      final next = remainingPending.firstWhere(
        (v) => widget.visuals.indexOf(v) > curatedIndex,
        orElse: () => remainingPending.first,
      );
      widget.onSelectVisual(next.id);
    } else {
      widget.onSelectVisual(null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '🎉 ¡Completado! Has evaluado todos los visuales del catálogo.',
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected =
        widget.visuals.where((v) => v.id == widget.selectedVisualId).firstOrNull;

    final index = _currentIndex;
    final total = widget.visuals.length;
    final pending = _pendingVisuals;
    final view = _viewVisuals;
    final isSelectedPending = selected != null &&
        (widget.curationStatus[selected.id] ?? VisualCurationStatus.pending) ==
            VisualCurationStatus.pending;
    final pendingIndex =
        isSelectedPending ? pending.indexWhere((v) => v.id == selected.id) : -1;

    final String indexString;
    final Color counterColor;
    if (_viewFilter != null && selected != null) {
      final viewIndex = view.indexWhere((v) => v.id == selected.id);
      final prefix = _viewFilter == VisualCurationStatus.rejected ? '↺ ' : '👀 ';
      if (viewIndex >= 0) {
        indexString =
            '$prefix${(viewIndex + 1).toString().padLeft(2, '0')} / ${view.length.toString().padLeft(2, '0')}';
      } else {
        indexString =
            '$prefix${(index >= 0 ? index + 1 : 1).toString().padLeft(2, '0')}/$total';
      }
      counterColor = _viewFilter == VisualCurationStatus.rejected
          ? const Color(0xFFFFB74D)
          : const Color(0xFF73F572);
    } else if (selected == null || pending.isEmpty) {
      indexString = '✓ Completado';
      counterColor = const Color(0xFF73F572);
    } else if (isSelectedPending) {
      indexString =
          '${(pendingIndex + 1).toString().padLeft(2, '0')} / ${pending.length.toString().padLeft(2, '0')}';
      counterColor = const Color(0xFF73F572);
    } else {
      final currentStatus = widget.curationStatus[selected.id];
      final statusPrefix =
          currentStatus == VisualCurationStatus.approved ? '✓ ' : '✕ ';
      indexString =
          '$statusPrefix${(index >= 0 ? index + 1 : 1).toString().padLeft(2, '0')}/$total';
      counterColor = currentStatus == VisualCurationStatus.approved
          ? const Color(0xFF73F572)
          : const Color(0xFFFF8B80);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: InkWell(
          onTap: () => _showCurationSheet(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              indexString,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: counterColor,
                fontFeatures: const [FontFeature.tabularFigures()],
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
          ),
        ),
        actions: [
          Center(
            child: Text(
              '$_fps FPS',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: Colors.white70,
                fontFeatures: [FontFeature.tabularFigures()],
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 10),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (widget.onPictureInPicture != null)
            IconButton(
              tooltip: widget.pictureInPictureActive
                  ? 'Volver de PiP'
                  : 'Probar PiP',
              onPressed: widget.loading ? null : widget.onPictureInPicture,
              icon: const Icon(
                Icons.picture_in_picture_alt,
                color: Colors.white,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          IconButton(
            tooltip: _bgModeTooltip,
            onPressed: _cycleBackgroundMode,
            icon: Icon(
              _bgModeIcon,
              color: _bgMode == StudioBackgroundMode.dark
                  ? Colors.white70
                  : const Color(0xFF73F572),
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          IconButton(
            tooltip: _showControls ? 'Ocultar interfaz' : 'Mostrar interfaz',
            onPressed: () => setState(() => _showControls = !_showControls),
            icon: Icon(
              _showControls
                  ? Icons.fullscreen_rounded
                  : Icons.fullscreen_exit_rounded,
              color: const Color(0xFF73F572),
              size: 22,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          IconButton(
            tooltip: 'Recargar visuales',
            onPressed: widget.loading ? null : widget.onReload,
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: selected == null
          ? (widget.error != null
              ? _preview(context)
              : _buildAllDoneView(context))
          : (widget.error != null
              ? _buildErrorView(context, selected)
              : Stack(
              fit: StackFit.expand,
              children: [
                // 1. Unobstructed Visual Canvas (100% full screen)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showControls = !_showControls),
                    onHorizontalDragEnd: (details) {
                      if (details.primaryVelocity case final double velocity) {
                        if (velocity < -250) {
                          _goToNextVisual();
                        } else if (velocity > 250) {
                          _goToPreviousVisual();
                        }
                      }
                    },
                    child: _preview(context),
                  ),
                ),

                // 2. Floating Bottom Hero & Controls Overlay
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: SafeArea(
                      minimum: const EdgeInsets.fromLTRB(16, 72, 16, 16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          return Align(
                            alignment:
                                wide
                                    ? Alignment.bottomRight
                                    : Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: wide ? 380 : 520,
                                maxHeight:
                                    constraints.maxHeight * (wide ? 1.0 : 0.66),
                              ),
                              child: Material(
                                key: const ValueKey('studio-controls-overlay'),
                                color: Colors.transparent,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.35),
                                        Colors.black.withValues(alpha: 0.85),
                                      ],
                                      stops: const [0.0, 0.25, 1.0],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      12,
                                      16,
                                      16,
                                    ),
                                    child: _buildFloatingControls(
                                      context,
                                      selected,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            )),
    );
  }

  Widget _buildErrorView(BuildContext context, StudioVisualItem selected) {
    final problem = widget.error ?? 'Error desconocido';
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity case final double velocity) {
          if (velocity < -250) {
            _goToNextVisual();
          } else if (velocity > 250) {
            _goToPreviousVisual();
          }
        }
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFF162521).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFFF453A).withValues(alpha: 0.4),
                  width: 1.5,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.error.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: colors.error,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    selected.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (selected.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      selected.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        problem,
                        textAlign: TextAlign.left,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.white70,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF453A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      widget.onCurationChanged?.call(
                        selected.id,
                        VisualCurationStatus.rejected,
                      );
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('✕ "${selected.name}" descartado.'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      _advanceAfterCuration(selected.id);
                    },
                    icon: const Icon(Icons.close_rounded, size: 20),
                    label: const Text(
                      'DESCARTAR ESTE VISUAL',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _goToPreviousVisual,
                        icon: const Icon(Icons.arrow_back_rounded, size: 16),
                        label: const Text('Anterior'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _goToNextVisual,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Siguiente'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _showCurationSheet(context),
                        icon: const Icon(Icons.format_list_bulleted_rounded, size: 16),
                        label: const Text('Lista'),
                      ),
                      IconButton(
                        tooltip: 'Recargar visual',
                        onPressed: widget.loading ? null : widget.onReload,
                        icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Modo de vista slide: null = cola normal de pendientes,
  /// rejected = segunda oportunidad (recorre descartados),
  /// approved = revisión de aprobados. No cambia estados al entrar;
  /// SALIR vuelve a la cola sin tocar lo no redecidido.
  VisualCurationStatus? _viewFilter;

  List<StudioVisualItem> get _viewVisuals {
    final filter = _viewFilter;
    if (filter != null) {
      return widget.visuals
          .where((v) => widget.curationStatus[v.id] == filter)
          .toList();
    }
    return _pendingVisuals;
  }

  void _enterViewMode(VisualCurationStatus filter) {
    final list = widget.visuals
        .where((v) => widget.curationStatus[v.id] == filter)
        .toList();
    if (list.isEmpty) return;
    setState(() => _viewFilter = filter);
    widget.onSelectVisual(list.first.id);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          filter == VisualCurationStatus.rejected
              ? '🔄 Segunda oportunidad: recorre ${list.length} descartados.'
              : '👀 Revisando ${list.length} aprobados.',
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _exitViewMode() {
    setState(() => _viewFilter = null);
    final pending = _pendingVisuals;
    widget.onSelectVisual(pending.isNotEmpty ? pending.first.id : null);
  }

  /// Selección manual (dropdown o lista): sale del modo vista.
  void _selectVisualManual(String? id) {
    if (_viewFilter != null) setState(() => _viewFilter = null);
    widget.onSelectVisual(id);
  }

  Widget _buildAllDoneView(BuildContext context) {
    final approvedCount = widget.visuals
        .where(
          (v) =>
              widget.curationStatus[v.id] == VisualCurationStatus.approved,
        )
        .length;
    final rejectedCount = widget.visuals
        .where(
          (v) =>
              widget.curationStatus[v.id] == VisualCurationStatus.rejected,
        )
        .length;
    final total = widget.visuals.length;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: const Color(0xFF162521).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF73F572).withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF73F572).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Color(0xFF73F572),
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '¡Revisión Completada!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Has evaluado todos los visuales del catálogo.\nLos aprobados y descartados no aparecen en la cola principal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatBadge(
                    'Aprobados',
                    '$approvedCount',
                    const Color(0xFF73F572),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBadge(
                    'Descartados',
                    '$rejectedCount',
                    const Color(0xFFFF453A),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBadge('Total', '$total', Colors.white70),
                ],
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => _showCurationSheet(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF73F572),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                label: const Text(
                  'VER Y EDITAR LISTA COMPLETA',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
              ),
              if (rejectedCount > 0) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _enterViewMode(VisualCurationStatus.rejected),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFB74D),
                    side: const BorderSide(
                      color: Color(0xFFFFB74D),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 20),
                  label: Text(
                    'SEGUNDA OPORTUNIDAD ($rejectedCount DESCARTADOS)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              if (approvedCount > 0) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      _enterViewMode(VisualCurationStatus.approved),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF73F572),
                    side: const BorderSide(
                      color: Color(0xFF73F572),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.visibility_rounded, size: 20),
                  label: Text(
                    'REVISAR APROBADOS ($approvedCount)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingControls(
    BuildContext context,
    StudioVisualItem? selected,
  ) {
    final currentStatus = selected != null
        ? (widget.curationStatus[selected.id] ?? VisualCurationStatus.pending)
        : VisualCurationStatus.pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Banner de modo vista slide con SALIR fijo
        if (_viewFilter != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFB74D).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFFB74D).withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 16,
                  color: Color(0xFFFFB74D),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _viewFilter == VisualCurationStatus.rejected
                        ? 'Segunda oportunidad: slide de descartados'
                        : 'Viendo slide de aprobados',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFB74D),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _exitViewMode,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                    backgroundColor: const Color(0xFFFFB74D),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'SALIR',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // Title Selector (Dropdown with bold hero title)
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('visual-selector'),
            value: widget.selectedVisualId,
            isExpanded: true,
            dropdownColor: const Color(0xFF162521),
            borderRadius: BorderRadius.circular(16),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF73F572),
                size: 20,
              ),
            ),
            selectedItemBuilder: (context) => [
              for (final visual in widget.visuals)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    visual.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 16,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            items: [
              for (final visual in widget.visuals)
                DropdownMenuItem(
                  value: visual.id,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: visual.thumbnail,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          visual.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (widget.curationStatus[visual.id] ==
                          VisualCurationStatus.approved)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF73F572),
                          size: 16,
                        )
                      else if (widget.curationStatus[visual.id] ==
                          VisualCurationStatus.rejected)
                        const Icon(
                          Icons.cancel_rounded,
                          color: Color(0xFFFF453A),
                          size: 16,
                        ),
                    ],
                  ),
                ),
            ],
            onChanged: widget.loading
                ? null
                : (val) {
                    if (val != null) _selectVisualManual(val);
                  },
          ),
        ),

        // Subtitle / Description (e.g. Interferencia de ondas en color puro)
        if (selected != null && selected.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            selected.description,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.3,
              shadows: const [
                Shadow(color: Colors.black, blurRadius: 10),
              ],
            ),
          ),
        ],

        // Spec / Tech details pill chip (e.g. C++17 · Impeller Metal/Vulkan · Reactivo al audio)
        if (selected != null && selected.details.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF73F572).withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                  color: const Color(0xFF162521).withValues(alpha: 0.65),
                ),
                child: Text(
                  selected.details,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: Color(0xFF73F572),
                  ),
                ),
              ),
              InkWell(
                key: const ValueKey('toggle-background-mode-button'),
                onTap: _cycleBackgroundMode,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _bgMode == StudioBackgroundMode.dark
                          ? Colors.white24
                          : const Color(0xFF73F572).withValues(alpha: 0.6),
                      width: 1.0,
                    ),
                    color: _bgMode == StudioBackgroundMode.dark
                        ? Colors.black45
                        : const Color(0xFF162521).withValues(alpha: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _bgModeIcon,
                        size: 14,
                        color: _bgMode == StudioBackgroundMode.dark
                            ? Colors.white70
                            : const Color(0xFF73F572),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _bgModeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _bgMode == StudioBackgroundMode.dark
                              ? Colors.white70
                              : const Color(0xFF73F572),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),

        if (widget.ratingPanel case final Widget panel) ...[
          panel,
          const SizedBox(height: 12),
        ],

        // Curation Status Badge
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: switch (currentStatus) {
                VisualCurationStatus.approved =>
                  const Color(0xFF73F572).withValues(alpha: 0.2),
                VisualCurationStatus.rejected =>
                  const Color(0xFFFF453A).withValues(alpha: 0.2),
                VisualCurationStatus.pending =>
                  Colors.white.withValues(alpha: 0.08),
              },
              border: Border.all(
                color: switch (currentStatus) {
                  VisualCurationStatus.approved => const Color(0xFF73F572),
                  VisualCurationStatus.rejected => const Color(0xFFFF453A),
                  VisualCurationStatus.pending => Colors.white30,
                },
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  switch (currentStatus) {
                    VisualCurationStatus.approved =>
                      Icons.check_circle_rounded,
                    VisualCurationStatus.rejected => Icons.cancel_rounded,
                    VisualCurationStatus.pending =>
                      Icons.radio_button_unchecked_rounded,
                  },
                  size: 14,
                  color: switch (currentStatus) {
                    VisualCurationStatus.approved => const Color(0xFF73F572),
                    VisualCurationStatus.rejected => const Color(0xFFFF453A),
                    VisualCurationStatus.pending => Colors.white60,
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  switch (currentStatus) {
                    VisualCurationStatus.approved =>
                      'APROBADO (PARA AGREGAR A LA APP)',
                    VisualCurationStatus.rejected =>
                      'DESCARTADO (PARA ELIMINAR)',
                    VisualCurationStatus.pending =>
                      'PENDIENTE DE REVISIÓN',
                  },
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: switch (currentStatus) {
                      VisualCurationStatus.approved => const Color(0xFF73F572),
                      VisualCurationStatus.rejected => const Color(0xFFFF453A),
                      VisualCurationStatus.pending => Colors.white70,
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Curation Action Buttons: Descartar, Aprobar, Lista
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: selected == null
                    ? null
                    : () {
                        widget.onCurationChanged?.call(
                          selected.id,
                          VisualCurationStatus.rejected,
                        );
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✕ "${selected.name}" descartado.',
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        _advanceAfterCuration(selected.id);
                      },
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Descartar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF453A),
                  side: BorderSide(
                    color: currentStatus == VisualCurationStatus.rejected
                        ? const Color(0xFFFF453A)
                        : const Color(0xFFFF453A).withValues(alpha: 0.5),
                  ),
                  backgroundColor:
                      currentStatus == VisualCurationStatus.rejected
                          ? const Color(0xFFFF453A).withValues(alpha: 0.2)
                          : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: selected == null
                    ? null
                    : () {
                        widget.onCurationChanged?.call(
                          selected.id,
                          VisualCurationStatus.approved,
                        );
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '✓ "${selected.name}" aprobado para la app.',
                            ),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        _advanceAfterCuration(selected.id);
                      },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Aprobar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF73F572),
                  side: BorderSide(
                    color: currentStatus == VisualCurationStatus.approved
                        ? const Color(0xFF73F572)
                        : const Color(0xFF73F572).withValues(alpha: 0.5),
                  ),
                  backgroundColor:
                      currentStatus == VisualCurationStatus.approved
                          ? const Color(0xFF73F572).withValues(alpha: 0.2)
                          : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Ver lista de curaduría',
              onPressed: () => _showCurationSheet(context),
              icon: const Icon(
                Icons.format_list_bulleted_rounded,
                color: Colors.white70,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white12,
                padding: const EdgeInsets.all(10),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Navigation Action Bar: < , Play/Pause, SIGUIENTE VISUAL
        Row(
          children: [
            // Circular Previous Button <
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.loading || widget.visuals.isEmpty
                    ? null
                    : _goToPreviousVisual,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF162521).withValues(alpha: 0.85),
                    border: Border.all(
                      color: const Color(0xFF28544B),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chevron_left_rounded,
                      color: Color(0xFF4FF3A2),
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Play/Pause FilledButton
            FilledButton(
              key: const ValueKey('play-button'),
              onPressed:
                  widget.loading ||
                          (widget.preview == null && widget.textureId == null) ||
                          widget.error != null
                      ? null
                      : widget.onTogglePlaying,
              style: FilledButton.styleFrom(
                backgroundColor:
                    const Color(0xFF162521).withValues(alpha: 0.85),
                foregroundColor: const Color(0xFF4FF3A2),
                side: const BorderSide(color: Color(0xFF28544B), width: 1.5),
                shape: const CircleBorder(),
                fixedSize: const Size(48, 48),
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                widget.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 24,
              ),
            ),

            const SizedBox(width: 8),

            // Gradient Next Button: SIGUIENTE VISUAL
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF76F76E), Color(0xFFF33D98)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF76F76E).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.loading || widget.visuals.isEmpty
                        ? null
                        : _goToNextVisual,
                    borderRadius: BorderRadius.circular(24),
                    child: const Center(
                      child: Text(
                        'SIGUIENTE VISUAL',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Technical Audio / Signal Settings Section (scrollable below navigation)
        _buildTechnicalPanel(context),
      ],
    );
  }

  Widget _buildTechnicalPanel(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.sources
        .firstWhere((item) => item.id == widget.selectedSourceId);

    return Material(
      color: const Color(0xFF162521).withValues(alpha: 0.75),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF28544B)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SEÑAL DE AUDIO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF73F572),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                // Botón interactivo de Silenciado (simula música sonando / en silencio en vivo)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('mute-button'),
                    onTap: widget.playing && widget.reactive
                        ? widget.onToggleMuted
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.muted
                            ? const Color(0xFFFF9F0A).withValues(alpha: 0.22)
                            : (widget.reactive && widget.playing
                                ? const Color(0xFF73F572).withValues(alpha: 0.15)
                                : Colors.white10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.muted
                              ? const Color(0xFFFF9F0A)
                              : (widget.reactive && widget.playing
                                  ? const Color(0xFF73F572).withValues(alpha: 0.6)
                                  : Colors.white24),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.muted
                                ? Icons.volume_off_rounded
                                : (widget.reactive && widget.playing
                                    ? Icons.volume_up_rounded
                                    : Icons.pause_circle_outline_rounded),
                            size: 13,
                            color: widget.muted
                                ? const Color(0xFFFF9F0A)
                                : (widget.reactive && widget.playing
                                    ? const Color(0xFF73F572)
                                    : Colors.white38),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.muted
                                ? 'SILENCIADO (TOCAR)'
                                : (widget.reactive && widget.playing
                                    ? 'SILENCIAR'
                                    : 'PAUSA'),
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: widget.muted
                                  ? const Color(0xFFFF9F0A)
                                  : (widget.reactive && widget.playing
                                      ? const Color(0xFF73F572)
                                      : Colors.white38),
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AudioSignalChart(
              signalListenable: widget.signalListenable,
              reactive: widget.reactive,
              playing: widget.playing,
              muted: widget.muted,
            ),
            const SizedBox(height: 12),
            _selector(
              context,
              key: const ValueKey('source-selector'),
              label: 'Señal de prueba',
              value: widget.selectedSourceId,
              items: [
                for (final item in widget.sources)
                  DropdownMenuItem(value: item.id, child: Text(item.name)),
              ],
              onChanged: widget.loading ? null : widget.onSelectSource,
            ),
            const SizedBox(height: 8),
            Text(
              source.description,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            SwitchListTile.adaptive(
              key: const ValueKey('reaction-switch'),
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Reaccionar a la señal musical',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              value: widget.reactive,
              onChanged: widget.loading || !widget.reactionEnabled
                  ? null
                  : widget.onReactiveChanged,
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final nativeTextureId = widget.textureId;
    final problem = widget.error;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onViewportChanged(size, pixelRatio);
        });
        return ColoredBox(
          key: const ValueKey('visual-surface'),
          color: _bgMode == StudioBackgroundMode.light
              ? const Color(0xFFF2F2F7)
              : colors.surfaceContainerLowest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_bgMode == StudioBackgroundMode.checkerboard)
                const Positioned.fill(
                  child: CustomPaint(
                    painter: CheckerboardPainter(),
                  ),
                ),
              if (widget.preview case final Widget surface)
                surface
              else if (nativeTextureId != null)
                Texture(
                  key: ValueKey(nativeTextureId),
                  textureId: nativeTextureId,
                  filterQuality: FilterQuality.low,
                ),
              if (widget.preview == null &&
                  nativeTextureId == null &&
                  problem == null &&
                  !widget.loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.visuals.isEmpty
                          ? 'La lista de visuales está vacía.'
                          : 'Prepara un visual para empezar.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              if (problem != null)
                ColoredBox(
                  color: colors.surfaceContainerLowest.withValues(alpha: 0.95),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: colors.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No se pudo mostrar el visual',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            problem,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.loading)
                Center(
                  child: Semantics(
                    label: 'Preparando visual',
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _selector(
    BuildContext context, {
    required Key key,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String>? onChanged,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF162521).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF28544B), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: key,
            isExpanded: true,
            value: value,
            hint: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            dropdownColor: const Color(0xFF162521),
            borderRadius: BorderRadius.circular(16),
            items: items,
            onChanged: onChanged == null
                ? null
                : (val) {
                    if (val != null) onChanged(val);
                  },
          ),
        ),
      ),
    );
  }

  void _showCurationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1715),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        int activeFilterIndex = 0; // 0: Todos, 1: Pendientes, 2: Aprobados, 3: Descartados
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final approved = widget.visuals.where(
              (v) =>
                  widget.curationStatus[v.id] == VisualCurationStatus.approved,
            );
            final rejected = widget.visuals.where(
              (v) =>
                  widget.curationStatus[v.id] == VisualCurationStatus.rejected,
            );
            final pending = widget.visuals.where(
              (v) =>
                  (widget.curationStatus[v.id] ??
                      VisualCurationStatus.pending) ==
                  VisualCurationStatus.pending,
            );

            final displayedVisuals = widget.visuals.where((v) {
              final status =
                  widget.curationStatus[v.id] ?? VisualCurationStatus.pending;
              return switch (activeFilterIndex) {
                1 => status == VisualCurationStatus.pending,
                2 => status == VisualCurationStatus.approved,
                3 => status == VisualCurationStatus.rejected,
                _ => true,
              };
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header
                      Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Curaduría de Visuales',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Marca cuáles agregar o eliminar de Color Lights.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white70),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Summary chips (interactive filter tabs)
                      Row(
                        children: [
                          _buildCountBadge(
                            'Total',
                            '${widget.visuals.length}',
                            Colors.white24,
                            Colors.white,
                            isSelected: activeFilterIndex == 0,
                            onTap: () =>
                                setSheetState(() => activeFilterIndex = 0),
                          ),
                          const SizedBox(width: 8),
                          _buildCountBadge(
                            'Pendientes',
                            '${pending.length}',
                            Colors.white12,
                            Colors.white70,
                            isSelected: activeFilterIndex == 1,
                            onTap: () =>
                                setSheetState(() => activeFilterIndex = 1),
                          ),
                          const SizedBox(width: 8),
                          _buildCountBadge(
                            'Aprobados',
                            '${approved.length}',
                            const Color(0xFF73F572).withValues(alpha: 0.2),
                            const Color(0xFF73F572),
                            isSelected: activeFilterIndex == 2,
                            onTap: () =>
                                setSheetState(() => activeFilterIndex = 2),
                          ),
                          const SizedBox(width: 8),
                          _buildCountBadge(
                            'Descartados',
                            '${rejected.length}',
                            const Color(0xFFFF453A).withValues(alpha: 0.2),
                            const Color(0xFFFF453A),
                            isSelected: activeFilterIndex == 3,
                            onTap: () =>
                                setSheetState(() => activeFilterIndex = 3),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Bulk requeue: revisar descartados/aprobados sin
                      // tener que terminar la cola principal
                      if (rejected.isNotEmpty || approved.isNotEmpty) ...[
                        Row(
                          children: [
                            if (rejected.isNotEmpty)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _enterViewMode(
                                      VisualCurationStatus.rejected,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.history_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Ver slide (${rejected.length} descartados)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFFFB74D),
                                    side: const BorderSide(
                                      color: Color(0xFFFFB74D),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            if (rejected.isNotEmpty && approved.isNotEmpty)
                              const SizedBox(width: 8),
                            if (approved.isNotEmpty)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _enterViewMode(
                                      VisualCurationStatus.approved,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.visibility_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    'Ver slide (${approved.length} aprobados)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF73F572),
                                    side: const BorderSide(
                                      color: Color(0xFF73F572),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Visuals List
                      Expanded(
                        child: displayedVisuals.isEmpty
                            ? Center(
                                child: Text(
                                  switch (activeFilterIndex) {
                                    1 => 'No hay visuales pendientes.',
                                    2 => 'No hay visuales aprobados aún.',
                                    3 => 'No hay visuales descartados.',
                                    _ => 'No hay visuales en esta sección.',
                                  },
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: displayedVisuals.length,
                                separatorBuilder: (_, __) => const Divider(
                                    color: Colors.white10, height: 1),
                                itemBuilder: (context, index) {
                                  final visual = displayedVisuals[index];
                                  final catalogIndex =
                                      widget.visuals.indexOf(visual);
                                  final status =
                                      widget.curationStatus[visual.id] ??
                                          VisualCurationStatus.pending;
                                  final isCurrent =
                                      visual.id == widget.selectedVisualId;

                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 6,
                                    ),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      _selectVisualManual(visual.id);
                                    },
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 48,
                                        height: 48,
                                        color: Colors.black26,
                                        child: visual.thumbnail,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          '${(catalogIndex + 1).toString().padLeft(2, '0')}. ',
                                          style: const TextStyle(
                                            color: Color(0xFF73F572),
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            visual.name,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? const Color(0xFF73F572)
                                                  : Colors.white,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w900
                                                  : FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      visual.details,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Descartar (tocar de nuevo = volver a pendiente)
                                        IconButton(
                                          icon: Icon(
                                            status ==
                                                    VisualCurationStatus
                                                        .rejected
                                                ? Icons.cancel_rounded
                                                : Icons.cancel_outlined,
                                            color: status ==
                                                    VisualCurationStatus
                                                        .rejected
                                                ? const Color(0xFFFF453A)
                                                : Colors.white30,
                                            size: 22,
                                          ),
                                          onPressed: () {
                                            widget.onCurationChanged?.call(
                                              visual.id,
                                              status ==
                                                      VisualCurationStatus
                                                          .rejected
                                                  ? VisualCurationStatus.pending
                                                  : VisualCurationStatus
                                                      .rejected,
                                            );
                                            setSheetState(() {});
                                            setState(() {});
                                          },
                                        ),
                                        // Aprobar (tocar de nuevo = volver a pendiente)
                                        IconButton(
                                          icon: Icon(
                                            status ==
                                                    VisualCurationStatus
                                                        .approved
                                                ? Icons.check_circle_rounded
                                                : Icons
                                                    .check_circle_outline_rounded,
                                            color: status ==
                                                    VisualCurationStatus
                                                        .approved
                                                ? const Color(0xFF73F572)
                                                : Colors.white30,
                                            size: 22,
                                          ),
                                          onPressed: () {
                                            widget.onCurationChanged?.call(
                                              visual.id,
                                              status ==
                                                      VisualCurationStatus
                                                          .approved
                                                  ? VisualCurationStatus.pending
                                                  : VisualCurationStatus
                                                      .approved,
                                            );
                                            setSheetState(() {});
                                            setState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 12),

                      // Export Action Bar
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                final text = _generateCurationReport();
                                Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      '¡Lista de curaduría copiada al portapapeles!',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('Copiar lista para la app'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF73F572),
                                side: const BorderSide(
                                    color: Color(0xFF73F572)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCountBadge(
    String label,
    String count,
    Color bg,
    Color textColor, {
    bool isSelected = false,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? textColor.withValues(alpha: 0.25) : bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? textColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _generateCurationReport() {
    final approved = widget.visuals.where(
      (v) => widget.curationStatus[v.id] == VisualCurationStatus.approved,
    );
    final rejected = widget.visuals.where(
      (v) => widget.curationStatus[v.id] == VisualCurationStatus.rejected,
    );
    final pending = widget.visuals.where(
      (v) =>
          (widget.curationStatus[v.id] ?? VisualCurationStatus.pending) ==
          VisualCurationStatus.pending,
    );

    final buffer = StringBuffer();
    buffer.writeln('=== CURADURÍA DE VISUALES (Color Lights) ===');
    buffer.writeln();
    buffer.writeln('✅ PARA AGREGAR A LA APP (${approved.length}):');
    if (approved.isEmpty) {
      buffer.writeln('  (Ninguno)');
    } else {
      for (final v in approved) {
        buffer.writeln('  • ${v.name} (id: ${v.id}) - ${v.details}');
      }
    }
    buffer.writeln();
    buffer.writeln('❌ PARA ELIMINAR / DESCARTADOS (${rejected.length}):');
    if (rejected.isEmpty) {
      buffer.writeln('  (Ninguno)');
    } else {
      for (final v in rejected) {
        buffer.writeln('  • ${v.name} (id: ${v.id}) - ${v.details}');
      }
    }
    buffer.writeln();
    buffer.writeln('⏳ PENDIENTES DE REVISIÓN (${pending.length}):');
    if (pending.isEmpty) {
      buffer.writeln('  (Ninguno)');
    } else {
      for (final v in pending) {
        buffer.writeln('  • ${v.name} (id: ${v.id}) - ${v.details}');
      }
    }
    return buffer.toString();
  }
}

class CheckerboardPainter extends CustomPainter {
  const CheckerboardPainter({
    this.squareSize = 20.0,
    this.lightColor = const Color(0xFF383842),
    this.darkColor = const Color(0xFF1C1C22),
  });

  final double squareSize;
  final Color lightColor;
  final Color darkColor;

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = darkColor;
    final lightPaint = Paint()..color = lightColor;
    canvas.drawRect(Offset.zero & size, darkPaint);

    final xCount = (size.width / squareSize).ceil();
    final yCount = (size.height / squareSize).ceil();

    for (var y = 0; y < yCount; y++) {
      final isEvenRow = y % 2 == 0;
      for (var x = isEvenRow ? 0 : 1; x < xCount; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(
            x * squareSize,
            y * squareSize,
            squareSize,
            squareSize,
          ),
          lightPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckerboardPainter oldDelegate) =>
      oldDelegate.squareSize != squareSize ||
      oldDelegate.lightColor != lightColor ||
      oldDelegate.darkColor != darkColor;
}
