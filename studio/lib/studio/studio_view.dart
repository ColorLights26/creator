import 'dart:developer' as developer;
import 'dart:io';
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
  final ValueChanged<String> onSelectVisual;
  final ValueChanged<String> onSelectSource;
  final VoidCallback onTogglePlaying;
  final ValueChanged<bool> onReactiveChanged;
  final VoidCallback onReload;
  final void Function(Size size, double pixelRatio) onViewportChanged;
  final Map<String, VisualCurationStatus> curationStatus;
  final void Function(String id, VisualCurationStatus status)? onCurationChanged;
  final ValueListenable<SceneRenderSignalFrameV2?>? signalListenable;

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  int _fps = 144;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  bool _showControls = true;

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
    final pending = _pendingVisuals;
    if (pending.isEmpty) {
      final index = _currentIndex;
      final prevIndex = index <= 0 ? widget.visuals.length - 1 : index - 1;
      widget.onSelectVisual(widget.visuals[prevIndex].id);
      return;
    }

    final currentId = widget.selectedVisualId;
    final pendingIndex = pending.indexWhere((v) => v.id == currentId);
    if (pendingIndex >= 0) {
      final prevIndex =
          pendingIndex <= 0 ? pending.length - 1 : pendingIndex - 1;
      widget.onSelectVisual(pending[prevIndex].id);
    } else {
      final currentIndex = _currentIndex;
      final prevPending = pending.lastWhere(
        (v) => widget.visuals.indexOf(v) < currentIndex,
        orElse: () => pending.last,
      );
      widget.onSelectVisual(prevPending.id);
    }
  }

  void _goToNextVisual() {
    if (widget.visuals.isEmpty) return;
    final pending = _pendingVisuals;
    if (pending.isEmpty) {
      final index = _currentIndex;
      final nextIndex = (index + 1) % widget.visuals.length;
      widget.onSelectVisual(widget.visuals[nextIndex].id);
      return;
    }

    final currentId = widget.selectedVisualId;
    final pendingIndex = pending.indexWhere((v) => v.id == currentId);
    if (pendingIndex >= 0) {
      final nextIndex = (pendingIndex + 1) % pending.length;
      widget.onSelectVisual(pending[nextIndex].id);
    } else {
      final currentIndex = _currentIndex;
      final nextPending = pending.firstWhere(
        (v) => widget.visuals.indexOf(v) > currentIndex,
        orElse: () => pending.first,
      );
      widget.onSelectVisual(nextPending.id);
    }
  }

  void _advanceAfterCuration(String curatedId) {
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
    final isSelectedPending = selected != null &&
        (widget.curationStatus[selected.id] ?? VisualCurationStatus.pending) ==
            VisualCurationStatus.pending;
    final pendingIndex =
        isSelectedPending ? pending.indexWhere((v) => v.id == selected.id) : -1;

    final String indexString;
    final Color counterColor;
    if (pending.isEmpty) {
      indexString = '$total/$total';
      counterColor = const Color(0xFF73F572);
    } else if (isSelectedPending) {
      indexString =
          '${(pendingIndex + 1).toString().padLeft(2, '0')} / ${pending.length.toString().padLeft(2, '0')}';
      counterColor = const Color(0xFF73F572);
    } else {
      final currentStatus = widget.curationStatus[selected?.id];
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
      body: Stack(
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
                          wide ? Alignment.bottomRight : Alignment.bottomCenter,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 380 : 520,
                          maxHeight: constraints.maxHeight * (wide ? 1.0 : 0.66),
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
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                              child: _buildFloatingControls(context, selected),
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
                    if (val != null) widget.onSelectVisual(val);
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
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
          ),
        ],

        const SizedBox(height: 12),

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
          color: colors.surfaceContainerLowest,
          child: Stack(
            fit: StackFit.expand,
            children: [
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
    showModalBottomSheet(
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
                                      widget.onSelectVisual(visual.id);
                                      Navigator.of(context).pop();
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
                                        // Descartar
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
                                              VisualCurationStatus.rejected,
                                            );
                                            setSheetState(() {});
                                            setState(() {});
                                          },
                                        ),
                                        // Aprobar
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
                                              VisualCurationStatus.approved,
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
