import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:visual_catalog/visual_catalog.dart';

import 'studio_view.dart';

export 'studio_view.dart' show VisualCurationStatus;

List<CreatorVisualDefinition> _defaultCatalog() => creatorVisuals;

SceneCompositorController _defaultController() =>
    SceneCompositorController(assets: creatorCatalogAssets);

Widget _defaultThumbnail(CreatorVisualDefinition visual, int index) =>
    CreatorThumbnail(
      visual: visual,
      visualIndex: index,
      assets: creatorCatalogAssets,
    );

class CreatorStudio extends StatefulWidget {
  const CreatorStudio({
    this.initialCuration,
    this.catalogBuilder = _defaultCatalog,
    this.controllerFactory = _defaultController,
    this.thumbnailBuilder = _defaultThumbnail,
    this.recordingsLoader = loadStudioRecordings,
    super.key,
  });

  final Map<String, VisualCurationStatus>? initialCuration;
  final List<CreatorVisualDefinition> Function() catalogBuilder;
  final SceneCompositorController Function() controllerFactory;
  final Widget Function(CreatorVisualDefinition visual, int index)
  thumbnailBuilder;
  final Future<List<StudioRecording>> Function() recordingsLoader;

  @override
  State<CreatorStudio> createState() => _CreatorStudioState();
}

class _CreatorStudioState extends State<CreatorStudio>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SceneCompositorController _controller;
  late final Ticker _ticker;
  Duration _replayElapsed = Duration.zero;
  Duration _tickerStartElapsed = Duration.zero;
  Future<void> _commands = Future<void>.value();
  List<CreatorVisualDefinition> _catalog = [];
  late final List<StudioRecording> _recordings;
  late SceneSignalReplay _replay;
  String? _selectedId;
  int _sourceIndex = 0;
  Size? _viewport;
  double _pixelRatio = 1;
  String? _error;
  bool _loading = true;
  bool _sourcesReady = false;
  bool _recordingsLoading = false;
  bool _ready = false;
  bool _playing = true;
  bool _reactive = true;
  bool _muted = false;
  bool _foreground = true;
  bool _sending = false;
  bool _replayPrimed = false;
  bool _disposed = false;
  int _revision = 0;
  final ValueNotifier<SceneRenderSignalFrameV2?> _latestSignal =
      ValueNotifier<SceneRenderSignalFrameV2?>(null);
  final Map<String, VisualCurationStatus> _curationStatus = {};

  void _toggleMuted() {
    setState(() => _muted = !_muted);
    if (_muted && _latestSignal.value != null) {
      final silent = _latestSignal.value!.toSilent();
      _enqueue(() async {
        await _controller.sendSignal(silent);
        _latestSignal.value = silent;
      });
    }
  }

  static List<String> get _curationPaths {
    final candidates = <String>[];

    void addProjectDir(String base) {
      if (base.isEmpty) return;
      candidates.add('$base/creator/creator_curation_review.json');
      candidates.add('$base/creator_curation_review.json');
    }

    final projectEnv = Platform.environment['PROJECT_ROOT'] ??
        Platform.environment['APPRUN_PROJECT_ROOT'] ??
        Platform.environment['CODEX_PROJECT_ROOT'];
    if (projectEnv != null && projectEnv.isNotEmpty) {
      addProjectDir(projectEnv);
    }

    for (final home in [
      Platform.environment['SIMULATOR_HOST_HOME'],
      Platform.environment['HOME'],
    ]) {
      if (home != null && home.isNotEmpty) {
        addProjectDir('$home/Projects/colorlights26');
        addProjectDir('$home/colorlights26');
        addProjectDir('$home/Developer/colorlights26');
        addProjectDir('$home/Documents/colorlights26');
        addProjectDir('$home/Desktop/colorlights26');
      }
    }

    try {
      var dir = Directory.current.absolute;
      for (int i = 0; i < 5; i++) {
        candidates.add('${dir.path}/creator_curation_review.json');
        candidates.add('${dir.path}/creator/creator_curation_review.json');
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    candidates.add('${Directory.systemTemp.path}/creator_curation_review.json');
    return candidates.toSet().toList();
  }

  static List<String> get _approvedDirPaths {
    final candidates = <String>[];

    void addApproved(String base) {
      if (base.isEmpty) return;
      candidates.add('$base/metadata/creator_catalog/approved');
    }

    final projectEnv = Platform.environment['PROJECT_ROOT'] ??
        Platform.environment['APPRUN_PROJECT_ROOT'] ??
        Platform.environment['CODEX_PROJECT_ROOT'];
    if (projectEnv != null && projectEnv.isNotEmpty) {
      addApproved(projectEnv);
    }

    for (final home in [
      Platform.environment['SIMULATOR_HOST_HOME'],
      Platform.environment['HOME'],
    ]) {
      if (home != null && home.isNotEmpty) {
        addApproved('$home/Projects/colorlights26');
        addApproved('$home/colorlights26');
        addApproved('$home/Developer/colorlights26');
        addApproved('$home/Documents/colorlights26');
        addApproved('$home/Desktop/colorlights26');
      }
    }

    try {
      var dir = Directory.current.absolute;
      for (int i = 0; i < 5; i++) {
        candidates.add('${dir.path}/metadata/creator_catalog/approved');
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    return candidates.toSet().toList();
  }

  void _setCurationStatus(String id, VisualCurationStatus status) {
    setState(() {
      _curationStatus[id] = status;
    });
    _saveCuration();
  }

  void _saveCuration() {
    try {
      final jsonMap = {
        for (final entry in _curationStatus.entries)
          entry.key: entry.value.name,
      };
      final data = jsonEncode(jsonMap);
      bool savedToProject = false;
      for (final path in _curationPaths) {
        try {
          final file = File(path);
          if (file.existsSync()) {
            file.writeAsStringSync(data);
            savedToProject = true;
          }
        } catch (_) {}
      }
      if (!savedToProject) {
        for (final path in _curationPaths) {
          try {
            final file = File(path);
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(data);
            break;
          } catch (_) {}
        }
      }
      for (final home in [
        Platform.environment['SIMULATOR_HOST_HOME'],
        Platform.environment['HOME'],
      ]) {
        if (home != null && home.isNotEmpty) {
          final assetCandidates = [
            '$home/Projects/colorlights26/creator/studio/assets/creator_curation_review.json',
            '$home/colorlights26/creator/studio/assets/creator_curation_review.json',
            '$home/Developer/colorlights26/creator/studio/assets/creator_curation_review.json',
            '$home/Documents/colorlights26/creator/studio/assets/creator_curation_review.json',
            '$home/Desktop/colorlights26/creator/studio/assets/creator_curation_review.json',
          ];
          for (final assetPath in assetCandidates) {
            try {
              final file = File(assetPath);
              if (file.parent.existsSync()) {
                file.writeAsStringSync(data);
              }
            } catch (_) {}
          }
        }
      }
      developer.log(
        'Saved visual curation review: $jsonMap',
        name: 'audiovisual_creator',
      );
    } catch (_) {
      // non-blocking
    }
  }

  void _loadCuration() {
    // 1. Auto-aprobar los visuales que ya están oficialmente en la app (metadata/creator_catalog/approved)
    for (final path in _approvedDirPaths) {
      final approvedDir = Directory(path);
      if (approvedDir.existsSync()) {
        try {
          for (final entity in approvedDir.listSync()) {
            if (entity is File && entity.path.endsWith('.json')) {
              final id = entity.uri.pathSegments.last.replaceAll('.json', '');
              _curationStatus[id] = VisualCurationStatus.approved;
            }
          }
          break;
        } catch (_) {}
      }
    }
    _curationStatus.putIfAbsent('giroscopio_cuantico', () => VisualCurationStatus.approved);
    _curationStatus.putIfAbsent('plasma_scene', () => VisualCurationStatus.approved);
    _curationStatus.putIfAbsent('synthwave_scene', () => VisualCurationStatus.approved);
    _curationStatus.putIfAbsent('vortice_cosmico', () => VisualCurationStatus.approved);

    // 2. Cargar decisiones de curación guardadas previamente por el usuario
    for (final path in _curationPaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final decoded = jsonDecode(file.readAsStringSync());
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final status = VisualCurationStatus.values.firstWhere(
                (s) => s.name == entry.value,
                orElse: () => VisualCurationStatus.pending,
              );
              _curationStatus[entry.key as String] = status;
            }
            break;
          }
        }
      } catch (_) {}
    }
  }

  CreatorVisualDefinition? get _selected {
    for (final visual in _catalog) {
      if (visual.id == _selectedId) return visual;
    }
    return null;
  }

  bool get _effectiveReaction => switch (_selected?.reactivity) {
    CreatorReactivity.music => true,
    CreatorReactivity.optional => _reactive,
    _ => false,
  };
  bool get _shouldPlay =>
      !_disposed &&
      _playing &&
      (_foreground || _controller.pictureInPictureActive) &&
      _ready &&
      !_loading &&
      _error == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _controller = widget.controllerFactory()..addListener(_controllerChanged);
    _ticker = createTicker((elapsed) {
      _replayElapsed = _tickerStartElapsed + elapsed;
      _pumpReplay();
    });
    _recordings = [
      StudioRecording(
        name: 'Demo sintética',
        description:
            'Showcase dinámico de 32 s: Ambient → Build-up acelerado → Drop EDM contundente → Trap 808 → Clímax espectral.',
        recording: createDynamicShowcaseSignalRecording(),
      ),
      StudioRecording(
        name: 'EDM & Club Drop (128 BPM)',
        description:
            'Bombo 4-on-the-floor, subgraves masivos, eventos de beat en cada golpe y cajas a contratiempo.',
        recording: createEdmClubDropSignalRecording(),
      ),
      StudioRecording(
        name: 'Trap 808 & Hi-Hats (140 BPM)',
        description:
            'Sub-bass 808 profundo y sostenido, rolls rápidos de hi-hats (32 notas) en agudos y clap seco.',
        recording: createTrap808SignalRecording(),
      ),
      StudioRecording(
        name: 'Ambient & Chillout (75 BPM)',
        description:
            'Pads armónicos fluidos y respiración etérea. Flujo orgánico sin percusión agresiva.',
        recording: createAmbientChilloutSignalRecording(),
      ),
      StudioRecording(
        name: 'Barrido Espectral (20Hz - 20kHz)',
        description:
            'Barrido analítico banda por banda para auditar la respuesta del shader a cada frecuencia.',
        recording: createSpectralSweepSignalRecording(),
      ),
      StudioRecording(
        name: 'Demo clásica (32s)',
        description:
            'Pista de referencia clásica de 32 s con partes suaves y acentos.',
        recording: createSyntheticSceneSignalRecording(),
      ),
    ];
    _replay = SceneSignalReplay(_recordings.first.recording);
    if (widget.initialCuration != null) {
      _curationStatus.addAll(widget.initialCuration!);
    }
    _loadCuration();
    if (_curationStatus.isEmpty) {
      unawaited(_loadBundledCurationFallback());
    }
    _readCatalog();
    unawaited(_loadRecordings());
  }

  Future<void> _loadBundledCurationFallback() async {
    try {
      final assetString =
          await rootBundle.loadString('assets/creator_curation_review.json');
      if (_disposed) return;
      final decoded = jsonDecode(assetString);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          final status = VisualCurationStatus.values.firstWhere(
            (s) => s.name == entry.value,
            orElse: () => VisualCurationStatus.pending,
          );
          _curationStatus[entry.key as String] = status;
        }
        if (mounted) {
          setState(() {
            _readCatalog();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadRecordings() async {
    if (_recordingsLoading) return;
    _recordingsLoading = true;
    try {
      final recordings = await widget.recordingsLoader();
      if (_disposed) return;
      _recordings.addAll(recordings);
      _sourcesReady = true;
      _prepareSelected();
    } on Object catch (error, stack) {
      _fail(error, stack);
    } finally {
      _recordingsLoading = false;
    }
  }

  void _readCatalog() {
    try {
      final catalog = validateCreatorCatalog(widget.catalogBuilder());
      _catalog = catalog;
      final isCurrentPending = _selectedId != null &&
          catalog.any((v) => v.id == _selectedId) &&
          (_curationStatus[_selectedId!] ?? VisualCurationStatus.pending) ==
              VisualCurationStatus.pending;

      if (!isCurrentPending) {
        // Seleccionar el primer visual pendiente de revisión
        final firstPending = catalog.cast<CreatorVisualDefinition?>().firstWhere(
              (v) =>
                  (_curationStatus[v?.id] ?? VisualCurationStatus.pending) ==
                  VisualCurationStatus.pending,
              orElse: () => null,
            );
        _selectedId = firstPending?.id;
      }
      _error = null;
    } on Object catch (error, stack) {
      _catalog = [];
      _selectedId = null;
      _fail(error, stack);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _reload();
  }

  void _reload() {
    if (_disposed) return;
    _stopReplay();
    _revision++;
    _loadCuration();
    _readCatalog();
    if (_sourcesReady) {
      _prepareSelected();
    } else {
      _loading = true;
      unawaited(_loadRecordings());
    }
    setState(() {});
  }

  void _controllerChanged() {
    if (_disposed) return;
    if (_controller.error case final String error) {
      final changed = _error != error;
      _error = error;
      _stopReplay();
      if (changed) _enqueue(() => _controller.setPlaying(false));
    }
    setState(() {});
  }

  void _viewportChanged(Size size, double pixelRatio) {
    if (_disposed ||
        !size.isFinite ||
        size.isEmpty ||
        size == _viewport && pixelRatio == _pixelRatio) {
      return;
    }
    _viewport = size;
    _pixelRatio = pixelRatio;
    if (!_ready || _loading) {
      _prepareSelected();
    } else {
      _enqueue(() => _controller.resize(size, pixelRatio));
    }
  }

  void _selectVisual(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    if (id != null) {
      _prepareSelected();
    } else {
      _stopReplay();
      setState(() {});
    }
  }

  void _selectSource(String id) {
    final index = int.tryParse(id);
    if (index == null || index == _sourceIndex) return;
    _sourceIndex = index;
    _prepareSelected();
  }

  void _prepareSelected() {
    final visual = _selected;
    final viewport = _viewport;
    if (_disposed || !_sourcesReady || viewport == null) return;
    _stopReplay();
    final revision = ++_revision;
    _ready = false;
    if (visual == null) {
      _loading = false;
      _enqueue(() => _controller.setPlaying(false));
      setState(() {});
      return;
    }
    _loading = true;
    _error = null;
    setState(() {});
    _enqueue(() async {
      if (!_isCurrent(revision)) return;
      await _controller.setPlaying(false);
      if (!_isCurrent(revision)) return;
      await _controller.setVisual(
        visual,
        size: viewport,
        pixelRatio: _pixelRatio,
      );
      if (!_isCurrent(revision)) return;
      await _controller.setReactive(_effectiveReaction);
      _replayElapsed = Duration.zero;
      _tickerStartElapsed = Duration.zero;
      _replayPrimed = false;
      _replay = SceneSignalReplay(_recordings[_sourceIndex].recording);
      _ready = true;
      _loading = false;
      await _controller.setPlaying(_shouldPlay);
      if (!_isCurrent(revision)) return;
      if (_shouldPlay) await _deliverReplay(Duration.zero, revision);
      if (!_isCurrent(revision)) return;
      _syncReplay();
      setState(() {});
    });
  }

  void _togglePlaying() {
    setState(() => _playing = !_playing);
    if (!_playing) _stopReplay();
    _enqueue(() async {
      await _controller.setPlaying(_shouldPlay);
      if (_shouldPlay && !_replayPrimed) {
        await _deliverReplay(Duration.zero, _revision);
      }
      _syncReplay();
    });
  }

  void _setReactive(bool reactive) {
    setState(() => _reactive = reactive);
    if (!_effectiveReaction) _stopReplay();
    _enqueue(() async {
      await _controller.setReactive(_effectiveReaction);
      _syncReplay();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stopReplay();
    _enqueue(() async {
      await _controller.setPlaying(_shouldPlay);
      if (_shouldPlay && !_replayPrimed) {
        await _deliverReplay(Duration.zero, _revision);
      }
      _syncReplay();
    });
  }

  void _syncReplay() {
    if (_disposed) return;
    if (_shouldPlay && _foreground && _effectiveReaction) {
      if (!_ticker.isActive) {
        _tickerStartElapsed = _replayElapsed;
        _ticker.start();
      }
    } else {
      _stopReplay();
    }
  }

  void _stopReplay() {
    if (_ticker.isActive) _ticker.stop();
    _latestSignal.value = null;
  }

  void _pumpReplay() {
    if (_disposed || _sending || !_shouldPlay || !_effectiveReaction) return;
    _sending = true;
    final elapsed = _replayElapsed;
    final revision = _revision;
    _enqueue(() async {
      try {
        if (_isCurrent(revision) && _shouldPlay) {
          await _deliverReplay(elapsed, revision);
        }
      } finally {
        _sending = false;
      }
    });
  }

  Future<void> _deliverReplay(Duration elapsed, int revision) async {
    if (!_effectiveReaction) {
      if (!_replayPrimed) {
        await _controller.reset(
          qaSessionSeed: _recordings[_sourceIndex].recording.qaSessionSeed,
        );
        if (_isCurrent(revision)) _replayPrimed = true;
      }
      return;
    }
    final batch = _replay.advance(elapsed);
    if (!_replayPrimed) {
      await _controller.reset(
        qaSessionSeed: _recordings[_sourceIndex].recording.qaSessionSeed,
      );
      if (!_isCurrent(revision)) return;
      _replayPrimed = true;
    }
    for (final sample in batch.samples) {
      if (!_isCurrent(revision)) return;
      var frame = batch.cycle == 0
          ? sample.frame
          : sample.frame.withSessionId(sample.frame.sessionId + batch.cycle);
      if (_muted) {
        frame = frame.toSilent();
      }
      await _controller.sendSignal(frame);
      _latestSignal.value = frame;
    }
  }

  bool _isCurrent(int revision) => !_disposed && revision == _revision;

  void _enqueue(Future<void> Function() operation) {
    _commands = _commands.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } on Object catch (error, stack) {
        _fail(error, stack);
        try {
          await _controller.setPlaying(false);
        } on Object catch (pauseError, pauseStack) {
          developer.log(
            'Could not pause the compositor after a failure',
            name: 'audiovisual_creator',
            error: pauseError,
            stackTrace: pauseStack,
          );
        }
      }
    });
  }

  void _fail(Object error, StackTrace stack) {
    developer.log(
      'Visual Studio operation failed',
      name: 'audiovisual_creator',
      error: error,
      stackTrace: stack,
    );
    if (_disposed) return;
    _stopReplay();
    _error = switch (error) {
      PlatformException(:final message, :final code) => message ?? code,
      FormatException(:final message) => message,
      _ => error.toString(),
    };
    _loading = false;
    setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_controllerChanged);
    _ticker.dispose();
    _latestSignal.dispose();
    unawaited(
      _commands
          .then((_) => _controller.close())
          .catchError((Object error) {
            developer.log(
              'Visual Studio compositor cleanup failed',
              name: 'audiovisual_creator',
              error: error,
            );
          })
          .whenComplete(_controller.dispose),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudioView(
      visuals: [
        for (var index = 0; index < _catalog.length; index++)
          StudioVisualItem(
            id: _catalog[index].id,
            name: _catalog[index].name,
            description: _catalog[index].description,
            details: [
              _catalog[index].publication == CreatorPublication.draft
                  ? 'Borrador'
                  : 'Publicado',
              _catalog[index].role == CreatorRole.overlay ? 'Overlay' : 'Fondo',
              _catalog[index].reactivity == CreatorReactivity.none
                  ? 'Independiente del audio'
                  : 'Reactivo',
            ].join(' · '),
            thumbnail: widget.thumbnailBuilder(_catalog[index], index),
          ),
      ],
      sources: [
        for (var index = 0; index < _recordings.length; index++)
          StudioSignalSource(
            id: '$index',
            name: _recordings[index].name,
            description: _recordings[index].description,
          ),
      ],
      selectedVisualId: _selectedId,
      selectedSourceId: '$_sourceIndex',
      textureId: _controller.textureId,
      preview: _controller.preview,
      playing: _playing,
      reactive: _effectiveReaction,
      reactionEnabled: _selected?.reactivity == CreatorReactivity.optional,
      muted: _muted,
      onToggleMuted: _toggleMuted,
      loading: _loading,
      error: _error,
      onSelectVisual: _selectVisual,
      onSelectSource: _selectSource,
      onTogglePlaying: _togglePlaying,
      onReactiveChanged: _setReactive,
      onReload: _reload,
      onViewportChanged: _viewportChanged,
      pictureInPictureActive: _controller.pictureInPictureActive,
      curationStatus: _curationStatus,
      onCurationChanged: _setCurationStatus,
      signalListenable: _latestSignal,
      onPictureInPicture:
          defaultTargetPlatform == TargetPlatform.iOS
              ? () => _enqueue(() async {
                if (_controller.pictureInPictureActive) {
                  await _controller.stopPictureInPicture();
                } else {
                  await _controller.startPictureInPicture();
                }
              })
              : null,
    );
  }
}

class StudioRecording {
  const StudioRecording({
    required this.name,
    required this.description,
    required this.recording,
  });

  final String name;
  final String description;
  final SceneSignalRecording recording;
}

Future<List<StudioRecording>> loadStudioRecordings() async {
  final text = await rootBundle.loadString('assets/recordings.json');
  final decoded = jsonDecode(text);
  if (decoded is! List) {
    throw const FormatException('El índice de grabaciones no es una lista.');
  }
  return [
    for (final entry in decoded)
      if (entry is Map<String, dynamic> &&
          entry['name'] is String &&
          entry['signalsBase64'] is String &&
          entry['timelineJson'] is String)
        StudioRecording(
          name: entry['name'] as String,
          description:
              'Reproducción de una captura importada. No reproduce audio.',
          recording: SceneSignalRecording.fromBundle(
            signals: base64Decode(entry['signalsBase64'] as String),
            timelineJson: entry['timelineJson'] as String,
          ),
        )
      else
        throw const FormatException('Una grabación tiene un formato inválido.'),
  ];
}
