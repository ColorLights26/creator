import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scene_compositor/scene_compositor.dart';

import 'audio_signal_chart.dart';
import 'studio_backdrop.dart';

export 'studio_backdrop.dart'
    show
        CheckerboardPainter,
        StudioBackdrop,
        StudioBackdropVisual,
        StudioBackgroundMode;

enum StudioRoleFilter {
  all,
  overlays,
  backgrounds,
}

class StudioVisualItem {
  const StudioVisualItem({
    required this.id,
    required this.name,
    required this.thumbnail,
    this.role = CreatorRole.background,
    this.description = '',
    this.details = '',
  });
  final String id;
  final String name;
  final Widget thumbnail;
  final CreatorRole role;
  final String description;
  final String details;

  bool get isOverlay => role == CreatorRole.overlay;
  bool get isBackground => role == CreatorRole.background;
}

/// An extra filter offered in the top filter menu (for example, by vote).
class StudioFilterOption {
  const StudioFilterOption({
    required this.id,
    required this.label,
    required this.count,
  });
  final String id;
  final String label;
  final int count;
}

class StudioSignalSource {
  const StudioSignalSource({
    required this.id,
    required this.name,
    required this.description,
    this.shortName,
    this.technical = false,
  });
  final String id;
  final String name;
  final String description;
  final String? shortName;

  /// A test signal (e.g. a frequency sweep) rather than music.
  final bool technical;

  String get label => shortName ?? name.split(' (').first;
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
    this.muted = false,
    this.onToggleMuted,
    this.ratingPanel,
    this.performanceOverlay,
    this.backdropVisuals = const [],
    this.backdropBuilder,
    this.voteFilters = const [],
    this.selectedVoteFilter,
    this.onVoteFilterChanged,
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
  final ValueListenable<SceneRenderSignalFrameV2?>? signalListenable;

  /// Team 1-10 voting for the selected visual, when the studio has it.
  final Widget? ratingPanel;

  /// Live CPU/FPS of the visual, shown under the app bar with the controls.
  final Widget? performanceOverlay;

  /// Catalog backgrounds that can sit, frozen, behind an overlay.
  final List<StudioBackdropVisual> backdropVisuals;

  /// Full-screen still of a catalog background chosen as backdrop.
  final Widget? Function(String visualId)? backdropBuilder;

  /// Vote filters shown under the type filter; the first one means "all".
  /// [visuals] already arrive filtered by the selected one.
  final List<StudioFilterOption> voteFilters;
  final String? selectedVoteFilter;
  final ValueChanged<String>? onVoteFilterChanged;

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  /// Name search in the visual list; cleared every time the list opens.
  final TextEditingController _visualSearch = TextEditingController();
  bool _showControls = true;
  bool _audioDetail = false;
  // Alpha grid first: it shows at a glance what an overlay leaves transparent.
  StudioBackdrop _backdrop = StudioBackdrop.alpha;

  StudioBackgroundMode get _bgMode => _backdrop.base;
  StudioRoleFilter _roleFilter = StudioRoleFilter.all;

  @override
  void dispose() {
    _visualSearch.dispose();
    super.dispose();
  }

  void _pickBackdrop() => unawaited(
    showStudioBackdropPicker(
      context: context,
      current: _backdrop,
      visuals: widget.backdropVisuals,
      onSelected: (backdrop) => setState(() => _backdrop = backdrop),
    ),
  );

  IconData get _bgModeIcon =>
      _backdrop.visualId != null
          ? Icons.image_rounded
          : _backdrop.colors.isNotEmpty
          ? Icons.palette_rounded
          : switch (_bgMode) {
            StudioBackgroundMode.dark => Icons.grid_4x4_rounded,
            StudioBackgroundMode.checkerboard => Icons.texture_rounded,
            StudioBackgroundMode.light => Icons.light_mode_rounded,
          };

  String get _bgModeTooltip => 'Fondo: ${_backdrop.label} (toca para elegir)';

  /// The selected vote filter, unless it is the first ("all") one.
  StudioFilterOption? get _activeVoteFilter {
    if (widget.voteFilters.isEmpty) return null;
    final selected = widget.voteFilters
        .where((option) => option.id == widget.selectedVoteFilter)
        .firstOrNull;
    return selected == widget.voteFilters.first ? null : selected;
  }

  bool get _anyFilterActive =>
      _roleFilter != StudioRoleFilter.all || _activeVoteFilter != null;

  List<StudioVisualItem> get _filteredVisuals {
    return switch (_roleFilter) {
      StudioRoleFilter.all => widget.visuals,
      StudioRoleFilter.overlays =>
        widget.visuals.where((v) => v.isOverlay).toList(),
      StudioRoleFilter.backgrounds =>
        widget.visuals.where((v) => v.isBackground).toList(),
    };
  }

  void _setRoleFilter(StudioRoleFilter filter) {
    if (_roleFilter == filter) return;
    setState(() {
      _roleFilter = filter;
      final filtered = _filteredVisuals;
      if (filtered.isEmpty) {
        widget.onSelectVisual(null);
      } else if (!filtered.any((v) => v.id == widget.selectedVisualId)) {
        widget.onSelectVisual(filtered.first.id);
      }
    });
  }

  int get _currentIndex {
    final list = _filteredVisuals;
    if (list.isEmpty || widget.selectedVisualId == null) return -1;
    return list.indexWhere((v) => v.id == widget.selectedVisualId);
  }

  void _goToPreviousVisual() {
    if (widget.visuals.isEmpty) return;
    final view = _filteredVisuals;
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
    final view = _filteredVisuals;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected =
        widget.visuals.where((v) => v.id == widget.selectedVisualId).firstOrNull;

    final filtered = _filteredVisuals;
    final index = _currentIndex;
    final total = filtered.length;
    final indexString =
        '${(index >= 0 ? (index + 1).toString().padLeft(2, '0') : '--')} / '
        '${total.toString().padLeft(2, '0')}';
    const counterColor = Color(0xFF73F572);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        title: InkWell(
          onTap: () => _showVisualList(context),
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
          IconButton(
            key: const ValueKey('visual-search-button'),
            tooltip: 'Buscar visual por nombre',
            onPressed: () => _showVisualList(context, search: true),
            icon: const Icon(
              Icons.search_rounded,
              color: Colors.white70,
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          PopupMenuButton<Object>(
            key: const ValueKey('role-filter-button'),
            tooltip: switch (_roleFilter) {
              StudioRoleFilter.all => 'Filtrar tipo: Todos',
              StudioRoleFilter.overlays => 'Filtrar tipo: Solo Transparencias',
              StudioRoleFilter.backgrounds => 'Filtrar tipo: Solo Fondos',
            },
            initialValue: _roleFilter,
            onSelected: (value) {
              if (value is StudioRoleFilter) _setRoleFilter(value);
              if (value is String) widget.onVoteFilterChanged?.call(value);
            },
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  switch (_roleFilter) {
                    StudioRoleFilter.all => Icons.filter_alt_outlined,
                    StudioRoleFilter.overlays => Icons.layers_rounded,
                    StudioRoleFilter.backgrounds => Icons.wallpaper_rounded,
                  },
                  color: _roleFilter == StudioRoleFilter.all
                      ? Colors.white70
                      : const Color(0xFF73F572),
                  size: 19,
                ),
                if (_activeVoteFilter case final StudioFilterOption vote) ...[
                  const SizedBox(width: 4),
                  Text(
                    vote.label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF73F572),
                    ),
                  ),
                ],
                if (_roleFilter != StudioRoleFilter.all) ...[
                  const SizedBox(width: 4),
                  Text(
                    _roleFilter == StudioRoleFilter.overlays
                        ? 'Overlay'
                        : 'Fondo',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF73F572),
                    ),
                  ),
                ],
              ],
            ),
            style: IconButton.styleFrom(
              backgroundColor: !_anyFilterActive
                  ? Colors.black.withValues(alpha: 0.4)
                  : const Color(0xFF73F572).withValues(alpha: 0.2),
              side: !_anyFilterActive
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFF73F572), width: 1.0),
            ),
            color: const Color(0xFF1E1E24),
            itemBuilder: (context) {
              final overlaysCount =
                  widget.visuals.where((v) => v.isOverlay).length;
              final backgroundsCount =
                  widget.visuals.where((v) => v.isBackground).length;
              return [
                PopupMenuItem(
                  value: StudioRoleFilter.all,
                  child: Row(
                    children: [
                      Icon(
                        Icons.apps_rounded,
                        size: 18,
                        color: _roleFilter == StudioRoleFilter.all
                            ? const Color(0xFF73F572)
                            : Colors.white70,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Todos (${widget.visuals.length})',
                          style: TextStyle(
                            fontWeight: _roleFilter == StudioRoleFilter.all
                                ? FontWeight.w800
                                : FontWeight.normal,
                            color: _roleFilter == StudioRoleFilter.all
                                ? const Color(0xFF73F572)
                                : Colors.white,
                          ),
                        ),
                      ),
                      if (_roleFilter == StudioRoleFilter.all)
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Color(0xFF73F572),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: StudioRoleFilter.overlays,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.layers_rounded,
                        size: 18,
                        color: Color(0xFF73F572),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Solo Transparencias ($overlaysCount)',
                          style: TextStyle(
                            fontWeight: _roleFilter == StudioRoleFilter.overlays
                                ? FontWeight.w800
                                : FontWeight.normal,
                            color: _roleFilter == StudioRoleFilter.overlays
                                ? const Color(0xFF73F572)
                                : Colors.white,
                          ),
                        ),
                      ),
                      if (_roleFilter == StudioRoleFilter.overlays)
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Color(0xFF73F572),
                        ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: StudioRoleFilter.backgrounds,
                  child: Row(
                    children: [
                      Icon(
                        Icons.wallpaper_rounded,
                        size: 18,
                        color: _roleFilter == StudioRoleFilter.backgrounds
                            ? const Color(0xFF73F572)
                            : Colors.white70,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Solo Fondos ($backgroundsCount)',
                          style: TextStyle(
                            fontWeight:
                                _roleFilter == StudioRoleFilter.backgrounds
                                    ? FontWeight.w800
                                    : FontWeight.normal,
                            color: _roleFilter == StudioRoleFilter.backgrounds
                                ? const Color(0xFF73F572)
                                : Colors.white,
                          ),
                        ),
                      ),
                      if (_roleFilter == StudioRoleFilter.backgrounds)
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Color(0xFF73F572),
                        ),
                    ],
                  ),
                ),
                if (widget.voteFilters.isNotEmpty) ...[
                  const PopupMenuDivider(),
                  const PopupMenuItem<Object>(
                    enabled: false,
                    height: 28,
                    child: Text(
                      'VOTACIÓN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  for (final option in widget.voteFilters)
                    PopupMenuItem<Object>(
                      key: ValueKey('vote-filter-${option.id}'),
                      value: option.id,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${option.label} (${option.count})',
                              style: TextStyle(
                                fontWeight:
                                    option.id == widget.selectedVoteFilter
                                        ? FontWeight.w800
                                        : FontWeight.normal,
                                color: option.id == widget.selectedVoteFilter
                                    ? const Color(0xFF73F572)
                                    : Colors.white,
                              ),
                            ),
                          ),
                          if (option.id == widget.selectedVoteFilter)
                            const Icon(
                              Icons.check_rounded,
                              size: 18,
                              color: Color(0xFF73F572),
                            ),
                        ],
                      ),
                    ),
                ],
              ];
            },
          ),
          IconButton(
            key: const ValueKey('toggle-background-mode-button'),
            tooltip: _bgModeTooltip,
            onPressed: _pickBackdrop,
            icon: Icon(
              _bgModeIcon,
              color: _backdrop == StudioBackdrop.dark
                  ? Colors.white70
                  : const Color(0xFF73F572),
              size: 20,
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.4),
            ),
          ),
          if (widget.onPictureInPicture != null)
            IconButton(
              tooltip: widget.pictureInPictureActive
                  ? 'Volver de PiP'
                  : 'Probar PiP',
              onPressed: widget.loading ? null : widget.onPictureInPicture,
              icon: Icon(
                widget.pictureInPictureActive
                    ? Icons.picture_in_picture_alt_rounded
                    : Icons.picture_in_picture_rounded,
                color: widget.pictureInPictureActive
                    ? const Color(0xFF73F572)
                    : Colors.white,
                size: 20,
              ),
              style: IconButton.styleFrom(
                backgroundColor: widget.pictureInPictureActive
                    ? const Color(0xFF73F572).withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.4),
                side: widget.pictureInPictureActive
                    ? const BorderSide(color: Color(0xFF73F572), width: 1.2)
                    : BorderSide.none,
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
              : _buildEmptyView())
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

                // 3. Live cost of the visual, under the app bar.
                if (widget.performanceOverlay case final Widget overlay)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    // Clear the side system bar (Android buttons in landscape).
                    left: MediaQuery.paddingOf(context).left + 12,
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: overlay,
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
                        onPressed: () => _showVisualList(context),
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

  /// Selección manual desde el desplegable o la lista.
  void _selectVisualManual(String? id) => widget.onSelectVisual(id);

  Widget _buildEmptyView() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'No hay visuales en este filtro.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildFloatingControls(
    BuildContext context,
    StudioVisualItem? selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title Selector (Dropdown with bold hero title)
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('visual-selector'),
            value: _filteredVisuals.any((v) => v.id == widget.selectedVisualId)
                ? widget.selectedVisualId
                : null,
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
              for (final visual in _filteredVisuals)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Expanded(
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
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: visual.isOverlay
                              ? const Color(0xFF73F572).withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: visual.isOverlay
                                ? const Color(0xFF73F572).withValues(alpha: 0.6)
                                : Colors.white24,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          visual.isOverlay ? 'Overlay' : 'Fondo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: visual.isOverlay
                                ? const Color(0xFF73F572)
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            items: [
              for (final visual in _filteredVisuals)
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
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: visual.isOverlay
                              ? const Color(0xFF73F572).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: visual.isOverlay
                                ? const Color(0xFF73F572).withValues(alpha: 0.4)
                                : Colors.white12,
                            width: 0.6,
                          ),
                        ),
                        child: Text(
                          visual.isOverlay ? 'Overlay' : 'Fondo',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: visual.isOverlay
                                ? const Color(0xFF73F572)
                                : Colors.white60,
                          ),
                        ),
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
          // The background toggle lives in the app bar only.
          Align(
            alignment: AlignmentDirectional.centerStart,
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

        _buildAudioQuickBar(),
        const SizedBox(height: 10),

        if (widget.ratingPanel case final Widget panel) ...[
          panel,
          const SizedBox(height: 12),
        ],

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
      ],
    );
  }

  /// One tap to hear the visual with another track or in silence: judging a
  /// reactive visual needs both, so this sits right above the vote.
  Widget _buildAudioQuickBar() {
    final canMute = widget.reactive && widget.playing;
    Widget chip({
      required Key key,
      required String label,
      required IconData icon,
      required bool selected,
      VoidCallback? onTap,
    }) {
      final color = selected ? const Color(0xFF73F572) : Colors.white70;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: selected
              ? const Color(0xFF73F572).withValues(alpha: 0.2)
              : Colors.black.withValues(alpha: 0.35),
          shape: StadiumBorder(
            side: BorderSide(
              color: selected ? const Color(0xFF73F572) : Colors.white24,
            ),
          ),
          child: InkWell(
            key: key,
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: onTap == null && !selected
                      ? Colors.white24
                      : color),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: onTap == null && !selected ? Colors.white30 : color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Silence is its own fixed button: never scrolled or wrapped away.
        Row(
          children: [
            Expanded(
              child: Text(
                widget.reactionEnabled || widget.reactive
                    ? 'PRUÉBALO CON'
                    : 'ESTE VISUAL NO REACCIONA A LA MÚSICA',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white54,
                ),
              ),
            ),
            chip(
              key: const ValueKey('audio-chip-silence'),
              label: widget.muted ? 'En silencio' : 'Silencio',
              icon: widget.muted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              selected: widget.muted,
              onTap: canMute || widget.muted ? widget.onToggleMuted : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Every track visible at once: they wrap to a new line, no sliding.
        Wrap(
          key: const ValueKey('audio-quick-bar'),
          runSpacing: 6,
          children: [
            for (final source in widget.sources.where((s) => !s.technical))
              chip(
                key: ValueKey('audio-chip-${source.id}'),
                label: source.label,
                icon: Icons.music_note_rounded,
                selected:
                    !widget.muted && source.id == widget.selectedSourceId,
                onTap: widget.loading
                    ? null
                    : () {
                        // Choosing a track always means "with music".
                        if (widget.muted) widget.onToggleMuted?.call();
                        if (source.id != widget.selectedSourceId) {
                          widget.onSelectSource(source.id);
                        }
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        // The signal lives with the track picker: tap for the detail.
        GestureDetector(
          key: const ValueKey('audio-strip'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _audioDetail = !_audioDetail),
          child: AudioSignalChart(
            compact: true,
            expanded: _audioDetail,
            label: widget.sources
                .where((source) => source.id == widget.selectedSourceId)
                .firstOrNull
                ?.label,
            signalListenable: widget.signalListenable,
            reactive: widget.reactive,
            playing: widget.playing,
            muted: widget.muted,
          ),
        ),
        if (_audioDetail) ...[
          const SizedBox(height: 8),
          AudioSignalChart(
            signalListenable: widget.signalListenable,
            reactive: widget.reactive,
            playing: widget.playing,
            muted: widget.muted,
          ),
          if (widget.sources.any((s) => s.technical)) ...[
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text(
                    'PRUEBA TÉCNICA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Colors.white54,
                    ),
                  ),
                ),
                for (final source in widget.sources.where((s) => s.technical))
                  chip(
                    key: ValueKey('audio-chip-${source.id}'),
                    label: source.label,
                    icon: Icons.graphic_eq_rounded,
                    selected:
                        !widget.muted && source.id == widget.selectedSourceId,
                    onTap: widget.loading
                        ? null
                        : () {
                            if (widget.muted) widget.onToggleMuted?.call();
                            if (source.id != widget.selectedSourceId) {
                              widget.onSelectSource(source.id);
                            }
                          },
                  ),
              ],
            ),
          ],
          SwitchListTile.adaptive(
            key: const ValueKey('reaction-switch'),
            contentPadding: EdgeInsets.zero,
            dense: true,
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
      ],
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
              Positioned.fill(
                child: StudioBackdropFill(
                  backdrop: _backdrop,
                  visualBuilder: widget.backdropBuilder,
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

  void _showVisualList(BuildContext context, {bool search = false}) {
    _visualSearch.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F1715),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final roleBaseVisuals = _filteredVisuals;
            final query = _visualSearch.text;
            final displayedVisuals = [
              for (final visual in roleBaseVisuals)
                if (_matchesSearch(visual.name, query)) visual,
            ];

            final overlaysCount =
                widget.visuals.where((v) => v.isOverlay).length;
            final backgroundsCount =
                widget.visuals.where((v) => v.isBackground).length;

            return DraggableScrollableSheet(
              initialChildSize: search ? 0.92 : 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.92,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
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
                                  'Visuales',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Elige uno para verlo. Las notas del equipo están en el ranking.',
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

                      const SizedBox(height: 12),

                      TextField(
                        key: const ValueKey('visual-search-field'),
                        controller: _visualSearch,
                        autofocus: search,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setSheetState(() {}),
                        // Enter opens the first match.
                        onSubmitted: (_) {
                          if (displayedVisuals.isEmpty) return;
                          Navigator.of(context).pop();
                          _selectVisualManual(displayedVisuals.first.id);
                        },
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                        cursorColor: const Color(0xFF73F572),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Colors.white54,
                          ),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Borrar búsqueda',
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white54,
                                  ),
                                  onPressed: () {
                                    _visualSearch.clear();
                                    setSheetState(() {});
                                  },
                                ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Role filter row (Todos / Transparencias / Fondos)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              avatar: const Icon(Icons.apps_rounded, size: 14),
                              label: Text('Todos (${widget.visuals.length})'),
                              selected: _roleFilter == StudioRoleFilter.all,
                              onSelected: (_) {
                                _setRoleFilter(StudioRoleFilter.all);
                                setSheetState(() {});
                              },
                              selectedColor: const Color(0xFF73F572)
                                  .withValues(alpha: 0.25),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight: _roleFilter == StudioRoleFilter.all
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: _roleFilter == StudioRoleFilter.all
                                    ? const Color(0xFF73F572)
                                    : Colors.white70,
                              ),
                              side: BorderSide(
                                color: _roleFilter == StudioRoleFilter.all
                                    ? const Color(0xFF73F572)
                                    : Colors.transparent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              avatar: const Icon(
                                Icons.layers_rounded,
                                size: 14,
                                color: Color(0xFF73F572),
                              ),
                              label: Text(
                                'Solo Transparencias ($overlaysCount)',
                              ),
                              selected: _roleFilter == StudioRoleFilter.overlays,
                              onSelected: (_) {
                                _setRoleFilter(StudioRoleFilter.overlays);
                                setSheetState(() {});
                              },
                              selectedColor: const Color(0xFF73F572)
                                  .withValues(alpha: 0.25),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    _roleFilter == StudioRoleFilter.overlays
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                color: _roleFilter == StudioRoleFilter.overlays
                                    ? const Color(0xFF73F572)
                                    : Colors.white70,
                              ),
                              side: BorderSide(
                                color: _roleFilter == StudioRoleFilter.overlays
                                    ? const Color(0xFF73F572)
                                    : Colors.transparent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              avatar: const Icon(
                                Icons.wallpaper_rounded,
                                size: 14,
                                color: Colors.white70,
                              ),
                              label: Text('Solo Fondos ($backgroundsCount)'),
                              selected:
                                  _roleFilter == StudioRoleFilter.backgrounds,
                              onSelected: (_) {
                                _setRoleFilter(StudioRoleFilter.backgrounds);
                                setSheetState(() {});
                              },
                              selectedColor: const Color(0xFF73F572)
                                  .withValues(alpha: 0.25),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              labelStyle: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    _roleFilter == StudioRoleFilter.backgrounds
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                color:
                                    _roleFilter == StudioRoleFilter.backgrounds
                                        ? const Color(0xFF73F572)
                                        : Colors.white70,
                              ),
                              side: BorderSide(
                                color:
                                    _roleFilter == StudioRoleFilter.backgrounds
                                        ? const Color(0xFF73F572)
                                        : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Visuals List
                      Expanded(
                        child: displayedVisuals.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      query.trim().isEmpty
                                          ? 'No hay visuales en esta sección.'
                                          : 'Ningún visual coincide con '
                                              '«${query.trim()}».',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 14,
                                      ),
                                    ),
                                    // A filter may be hiding it.
                                    if (query.trim().isNotEmpty &&
                                        _anyFilterActive)
                                      TextButton(
                                        key: const ValueKey(
                                          'visual-search-all',
                                        ),
                                        onPressed: () {
                                          _setRoleFilter(StudioRoleFilter.all);
                                          if (widget.voteFilters.isNotEmpty) {
                                            widget.onVoteFilterChanged?.call(
                                              widget.voteFilters.first.id,
                                            );
                                          }
                                          // The studio rebuilds with every
                                          // visual first, then the list.
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                            if (context.mounted) {
                                              setSheetState(() {});
                                            }
                                          });
                                        },
                                        child: const Text(
                                          'Buscar en todos los visuales',
                                        ),
                                      ),
                                  ],
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
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: visual.isOverlay
                                                ? const Color(0xFF73F572)
                                                    .withValues(alpha: 0.15)
                                                : Colors.white
                                                    .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                              color: visual.isOverlay
                                                  ? const Color(0xFF73F572)
                                                      .withValues(alpha: 0.4)
                                                  : Colors.white12,
                                              width: 0.6,
                                            ),
                                          ),
                                          child: Text(
                                            visual.isOverlay
                                                ? 'Overlay'
                                                : 'Fondo',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: visual.isOverlay
                                                  ? const Color(0xFF73F572)
                                                  : Colors.white60,
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
                                  );
                                },
                              ),
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

}

/// Lowercase without accents, so "igneo" finds "Ígneo".
String _plainText(String text) {
  const accented = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const plain = 'aaaaaeeeeiiiiooooouuuunc';
  final buffer = StringBuffer();
  for (final char in text.toLowerCase().split('')) {
    final index = accented.indexOf(char);
    buffer.write(index < 0 ? char : plain[index]);
  }
  return buffer.toString();
}

/// Every word of [query] appears in [name], in any order.
bool _matchesSearch(String name, String query) {
  final plainName = _plainText(name);
  return _plainText(query)
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .every(plainName.contains);
}
