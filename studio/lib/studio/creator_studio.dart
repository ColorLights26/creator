import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:visual_catalog/visual_catalog.dart';

import '../performance/visual_performance.dart';
import '../performance/visual_performance_overlay.dart';
import '../team_review/team_ranking.dart';
import '../team_review/team_ranking_screen.dart';
import '../team_review/team_rating_panel.dart';
import '../team_review/team_review_controller.dart';
import '../team_review/team_voting_summary.dart';
import '../team_review/team_vote_filter.dart';
import '../team_review/visual_revision.dart';
import 'adjustments/adjustment_session.dart';
import 'adjustments/adjustments_button.dart';
import 'adjustments/adjustments_sheet.dart';
import 'adjustments/personal_variations.dart';
import 'studio_view.dart';

export 'studio_view.dart'
    show
        CheckerboardPainter,
        StudioBackgroundMode,
        StudioFilterOption,
        StudioRoleFilter,
        StudioSignalSource,
        StudioVisualItem;

List<CreatorVisualDefinition> _defaultCatalog() => creatorVisuals;

SceneCompositorController _defaultController() =>
    SceneCompositorController(assets: creatorCatalogAssets);

Widget _defaultThumbnail(CreatorVisualDefinition visual, int index) =>
    CreatorThumbnail(
      visual: visual,
      visualIndex: index,
      assets: creatorCatalogAssets,
    );

// Large enough to fill a phone screen behind an overlay without blur.
Widget _defaultBackdrop(CreatorVisualDefinition visual, int index) =>
    CreatorThumbnail(
      visual: visual,
      visualIndex: index,
      assets: creatorCatalogAssets,
      size: 1024,
    );

class CreatorStudio extends StatefulWidget {
  const CreatorStudio({
    this.catalogBuilder = _defaultCatalog,
    this.controllerFactory = _defaultController,
    this.thumbnailBuilder = _defaultThumbnail,
    this.backdropBuilder = _defaultBackdrop,
    this.recordingsLoader = loadStudioRecordings,
    this.teamReview,
    this.personalVariations,
    super.key,
  });

  /// Where saved looks ("Mía 1") live; on-device preferences by default.
  final PersonalVariations? personalVariations;

  /// Shared 1-10 team voting. Null hides it (tests, offline kits).
  final TeamReviewController? teamReview;
  final List<CreatorVisualDefinition> Function() catalogBuilder;
  final SceneCompositorController Function() controllerFactory;
  final Widget Function(CreatorVisualDefinition visual, int index)
  thumbnailBuilder;

  /// Full-screen still of a catalog background used as an overlay backdrop.
  final Widget Function(CreatorVisualDefinition visual, int index)
  backdropBuilder;
  final Future<List<StudioRecording>> Function() recordingsLoader;

  @override
  State<CreatorStudio> createState() => _CreatorStudioState();
}

class _CreatorStudioState extends State<CreatorStudio>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SceneCompositorController _controller;
  late final VisualPerformanceMonitor _performance;
  late final Ticker _ticker;
  Duration _replayElapsed = Duration.zero;
  Duration _tickerStartElapsed = Duration.zero;
  Future<void> _commands = Future<void>.value();
  List<CreatorVisualDefinition> _catalog = [];
  Map<String, String> _revisions = {};
  TeamVoteFilter _voteFilter = TeamVoteFilter.all;
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

  // Ajustes: what the team explores per visual during this Studio session.
  // Nothing is saved to disk except looks someone saves on purpose.
  final Map<String, ({String key, AdjustmentSession session})> _sessions = {};
  late final PersonalVariations _personal =
      widget.personalVariations ?? PersonalVariations();
  final math.Random _seeds = math.Random();

  /// What the compositor shows for the selected visual, and its seed (null
  /// for the recording's).
  AdjustmentValues? _sent;
  List<int>? _sentPalette;
  int? _appliedSeed;
  bool _adjusting = false;
  bool _adjustmentsDirty = false;

  /// Basics animate in Dart when a look replaces them at once; the engine
  /// already morphs modifiers.
  Timer? _basicsTween;
  CreatorControls? _tweenControls;

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

  VisualActivity get _activity {
    if (_shouldPlay) return VisualActivity.playing;
    // Only a loaded visual the user paused shows the studio's own cost.
    final paused =
        _foreground && !_playing && _ready && !_loading && _error == null;
    return paused ? VisualActivity.paused : VisualActivity.busy;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _controller = widget.controllerFactory()..addListener(_controllerChanged);
    _performance = VisualPerformanceMonitor(
      source: ControllerPerformanceSource(_controller),
      activity: () => _activity,
      targetFramesPerSecond: () => _selected?.framesPerSecond,
    );
    if (_foreground) _performance.start();
    _ticker = createTicker((elapsed) {
      _replayElapsed = _tickerStartElapsed + elapsed;
      _pumpReplay();
    });
    // Every musical demo has contrast (calm, build-up, drop, silence) so a
    // reactive visual can be judged; the sweep is a frequency test.
    _recordings = [
      StudioRecording(
        name: 'Demo sintética',
        shortName: 'Demo',
        description:
            'Recorrido de 32 s: calma → build-up → silencio → drop (lo más fuerte) → trap → clímax y fundido.',
        recording: createDynamicShowcaseSignalRecording(),
      ),
      StudioRecording(
        name: 'EDM & Club Drop (128 BPM)',
        shortName: 'EDM',
        description:
            'Intro, build-up, 1 s de silencio, drop con bombo en cada pulso, breakdown y segundo drop.',
        recording: createEdmClubDropSignalRecording(),
      ),
      StudioRecording(
        name: 'Trap 808 & Hi-Hats (140 BPM)',
        shortName: 'Trap',
        description:
            'Versos tranquilos y drops de 808 con rolls de hi-hats, un hueco de silencio y un segundo drop.',
        recording: createTrap808SignalRecording(),
      ),
      StudioRecording(
        name: 'Ambient & Chillout (72 BPM)',
        shortName: 'Ambient',
        description:
            'Respiraciones irregulares, un pulso suave al medio, un valle casi en silencio y un crescendo final.',
        recording: createAmbientChilloutSignalRecording(),
      ),
      StudioRecording(
        name: 'Cortes y silencios (124 BPM)',
        shortName: 'Cortes',
        description:
            'Música a tope que se corta y vuelve de golpe: huecos cortos, un silencio largo y tartamudeos.',
        recording: createCutsSignalRecording(),
      ),
      StudioRecording(
        name: 'Demo clásica (32s)',
        shortName: 'Clásica',
        description:
            'Pista de referencia: arranca en silencio, crece, se corta y vuelve.',
        recording: createSyntheticSceneSignalRecording(),
      ),
      StudioRecording(
        name: 'Barrido Espectral (20Hz - 20kHz)',
        shortName: 'Barrido de frecuencias',
        description:
            'Barrido analítico banda por banda para auditar la respuesta del shader a cada frecuencia.',
        recording: createSpectralSweepSignalRecording(),
        technical: true,
      ),
    ];
    _replay = SceneSignalReplay(_recordings.first.recording);
    _readCatalog();
    unawaited(_loadRecordings());
    if (widget.teamReview case final TeamReviewController review) {
      review.addListener(_teamReviewChanged);
      unawaited(review.start());
    }
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
      _revisions = {
        for (final visual in catalog) visual.id: visualRevision(visual),
      };
      // Recargar conserva el visual que se está viendo.
      final keepCurrent =
          _selectedId != null && catalog.any((v) => v.id == _selectedId);

      if (!keepCurrent) {
        _selectedId = catalog.isEmpty ? null : catalog.first.id;
      }
      _error = null;
    } on Object catch (error, stack) {
      _catalog = [];
      _revisions = {};
      _selectedId = null;
      _fail(error, stack);
    }
  }

  // Live votes can move visuals between vote filters.
  void _teamReviewChanged() {
    if (!_disposed) setState(() {});
  }

  bool _matchesVoteFilter(CreatorVisualDefinition visual, TeamVoteFilter filter) {
    final review = widget.teamReview;
    final revision = _revisions[visual.id];
    if (review == null || revision == null) return true;
    return filter.matches(
      review,
      TeamRankingEntry(id: visual.id, name: visual.name, revision: revision),
    );
  }

  void _setVoteFilter(String id) {
    final filter = TeamVoteFilter.values.byName(id);
    if (filter == _voteFilter) return;
    setState(() => _voteFilter = filter);
    final current = _selected;
    if (current != null && _matchesVoteFilter(current, filter)) return;
    final first = _catalog
        .where((visual) => _matchesVoteFilter(visual, filter))
        .firstOrNull;
    _selectVisual(first?.id);
  }

  Widget? _ratingPanel() {
    final review = widget.teamReview;
    final visual = _selected;
    final revision = visual == null ? null : _revisions[visual.id];
    if (review == null || visual == null || revision == null) return null;
    // The same structure with or without the notice, so the panel keeps a
    // score being chosen when the notice comes and goes.
    final panel = KeyedSubtree(
      key: const ValueKey('team-rating-slot'),
      child: _teamRatingPanel(review, visual, revision),
    );
    // The vote is for the original: say so while a variation is on screen.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_session?.differsFromOriginal == true)
        Padding(
          key: const ValueKey('adjustments-viewing-variation'),
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Estás viendo una variación',
                  style: TextStyle(color: Colors.amber, fontSize: 13),
                ),
              ),
              TextButton(
                key: const ValueKey('adjustments-view-original'),
                onPressed: _showOriginal,
                child: const Text('Ver original'),
              ),
            ],
          ),
        ),
        panel,
      ],
    );
  }

  Widget _teamRatingPanel(
    TeamReviewController review,
    CreatorVisualDefinition visual,
    String revision,
  ) {
    return TeamRatingPanel(
      controller: review,
      visualId: visual.id,
      visualName: visual.name,
      revision: revision,
      // A visual the team already discarded doesn't need more votes.
      queue: [
        for (final item in _catalog)
          if (!review.isTeamDiscarded(item.id, _revisions[item.id]!))
            (id: item.id, revision: _revisions[item.id]!),
      ],
      onSelectVisual: _selectVisual,
      onOpenRanking: () => unawaited(_openRanking(review)),
      onFinished: () => unawaited(_openSummary(review)),
    );
  }

  List<TeamRankingEntry> get _rankingEntries => [
    for (final visual in _catalog)
      TeamRankingEntry(
        id: visual.id,
        name: visual.name,
        revision: _revisions[visual.id]!,
      ),
  ];

  Future<void> _openRanking(TeamReviewController review) async {
    final chosen = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => TeamRankingScreen(
          controller: review,
          entries: _rankingEntries,
          onOpenVisual: (id) => Navigator.of(context).pop(id),
        ),
      ),
    );
    if (chosen != null && !_disposed) _selectVisual(chosen);
  }

  /// The end of a round: nothing left in the filter, or everything voted.
  Future<void> _openSummary(TeamReviewController review) async {
    final choice = await Navigator.of(context).push<TeamSummaryChoice>(
      MaterialPageRoute(
        builder: (context) => TeamVotingSummaryScreen(
          controller: review,
          entries: _rankingEntries,
        ),
      ),
    );
    if (choice == null || _disposed) return;
    switch (choice.action) {
      case TeamSummaryAction.ranking:
        await _openRanking(review);
      case TeamSummaryAction.allVisuals:
        _setVoteFilter(TeamVoteFilter.all.name);
      case TeamSummaryAction.nextToVote:
        // Switching to "Por votar" lands on the first visual left to vote.
        _setVoteFilter(TeamVoteFilter.toVote.name);
      case TeamSummaryAction.openVisual:
        _selectVisual(choice.visualId);
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
      // Sin visual seleccionado (revisión completada) el compositor no debe
      // seguir dibujando detrás de la pantalla final.
      _stopReplay();
      _revision++;
      _ready = false;
      _enqueue(() => _controller.setPlaying(false));
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
    _performance.restart();
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
    _sent = null;
    _sentPalette = null;
    _stopBasicsTween();
    // A compare held while leaving a visual never stays stuck on it.
    for (final entry in _sessions.values) {
      entry.session.comparing = false;
    }
    final session = _sessionFor(visual);
    _appliedSeed = session.seed;
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
      // setVisual restores the initial values; keep what the team chose.
      final shown = session.shown;
      if (!mapEquals(shown.controls.toMap(), visual.controls.toMap())) {
        await _controller.setControls(shown.controls);
      }
      if (!mapEquals(shown.modifiers, session.original.modifiers)) {
        await _controller.setModifiers(shown.modifiers);
      }
      final palette = session.shownPalette;
      if (palette != null) await _controller.setPalette(palette);
      if (!_isCurrent(revision)) return;
      _sent = shown;
      _sentPalette = palette;
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

  /// The seed the visual starts from: the recording's, unless the team asked
  /// for another arrangement in Ajustes.
  int get _seed =>
      _session?.seed ?? _recordings[_sourceIndex].recording.qaSessionSeed;

  AdjustmentSession? get _session {
    final visual = _selected;
    return visual == null ? null : _sessionFor(visual);
  }

  /// One session per visual for the whole Studio session. A reload that
  /// changes the visual's modifiers or variations starts a fresh one.
  AdjustmentSession _sessionFor(CreatorVisualDefinition visual) {
    final key = [
      _revisions[visual.id],
      jsonEncode(visual.toMetadata()['variations']),
      for (final modifier in visual.modifiers) jsonEncode(modifier.toMap()),
    ].join('|');
    final existing = _sessions[visual.id];
    if (existing != null && existing.key == key) return existing.session;
    existing?.session.dispose();
    final session = AdjustmentSession(visual)
      ..addListener(() => _sessionChanged(visual.id));
    _sessions[visual.id] = (key: key, session: session);
    return session;
  }

  void _sessionChanged(String visualId) {
    if (_disposed || visualId != _selectedId) return;
    final session = _sessions[visualId]!.session;
    if (session.seed != _appliedSeed) {
      _appliedSeed = session.seed;
      _restartWithSeed();
    }
    final sent = _sent;
    if (session.jumped && sent != null) {
      _tweenBasics(_tweenControls ?? sent.controls, session.shown.controls);
    } else {
      _stopBasicsTween();
    }
    _scheduleAdjustments();
    setState(() {});
  }

  void _tweenBasics(CreatorControls from, CreatorControls to) {
    _stopBasicsTween();
    if (mapEquals(from.toMap(), to.toMap())) return;
    const duration = 250, frame = 16;
    var elapsed = 0;
    _tweenControls = from;
    _basicsTween = Timer.periodic(const Duration(milliseconds: frame), (timer) {
      elapsed += frame;
      final t = Curves.easeOutCubic.transform(
        (elapsed / duration).clamp(0.0, 1.0),
      );
      double lerp(double a, double b) => a + (b - a) * t;
      _tweenControls =
          elapsed >= duration
              ? null
              : CreatorControls(
                intensity: lerp(from.intensity, to.intensity),
                speed: lerp(from.speed, to.speed),
                detail: lerp(from.detail, to.detail),
                glow: lerp(from.glow, to.glow),
              );
      if (elapsed >= duration) timer.cancel();
      _scheduleAdjustments();
    });
  }

  void _stopBasicsTween() {
    _basicsTween?.cancel();
    _basicsTween = null;
    _tweenControls = null;
  }

  /// Sends what Ajustes shows. A drag produces many values: only the latest
  /// is sent, with at most one update waiting behind the compositor queue,
  /// and never to a visual other than the one it was meant for.
  void _scheduleAdjustments() {
    _adjustmentsDirty = true;
    if (_adjusting) return;
    _adjusting = true;
    final revision = _revision;
    final visualId = _selectedId;
    _enqueue(() async {
      try {
        while (_adjustmentsDirty &&
            _isCurrent(revision) &&
            _selectedId == visualId) {
          _adjustmentsDirty = false;
          final session = _sessions[visualId]?.session;
          final sent = _sent;
          if (session == null || sent == null) break;
          final shown = session.shown;
          final next = (
            controls: _tweenControls ?? shown.controls,
            modifiers: shown.modifiers,
          );
          if (!mapEquals(next.controls.toMap(), sent.controls.toMap())) {
            await _controller.setControls(next.controls);
          }
          if (!mapEquals(next.modifiers, sent.modifiers)) {
            await _controller.setModifiers(next.modifiers);
          }
          final palette = session.shownPalette;
          if (!listEquals(palette, _sentPalette)) {
            await _controller.setPalette(palette);
          }
          if (_isCurrent(revision) && _selectedId == visualId) {
            _sent = next;
            _sentPalette = palette;
          }
        }
      } finally {
        _adjusting = false;
      }
    });
  }

  /// Another arrangement of the same visual: restarts it with a new seed,
  /// keeping the chosen values.
  void _anotherSeed() => _session?.seed = _seeds.nextInt(0x7fffffff);

  void _restartWithSeed() {
    final revision = _revision;
    final seed = _seed;
    _enqueue(() async {
      if (!_isCurrent(revision)) return;
      await _controller.reset(qaSessionSeed: seed);
      if (_isCurrent(revision)) _replayPrimed = true;
    });
  }

  /// Back to exactly what the team votes: initial values, recording's seed.
  void _showOriginal() => _session?.resetToOriginal();

  /// Holding the visual compares it with the original. Kept while a compare
  /// is held, so its release always arrives.
  ValueChanged<bool>? get _compareHandler {
    final session = _session;
    if (session == null ||
        !(session.differsFromOriginal || session.comparing)) {
      return null;
    }
    return (comparing) => session.comparing = comparing;
  }

  String? get _look {
    final session = _session;
    if (session == null || !session.differsFromOriginal) return null;
    return switch (session.chip) {
      null || originalChipName => 'cambiados',
      final String name => name,
    };
  }

  Widget? _adjustmentsButton() {
    final visual = _selected;
    final session = _session;
    if (visual == null || session == null || _error != null) return null;
    return VisualAdjustmentsButton(
      modifierCount: visual.modifiers.length,
      look: _look,
      onPressed:
          () => unawaited(
            showAdjustmentsSheet(
              context: context,
              session: session,
              store: _personal,
              onAnotherSeed: _anotherSeed,
            ),
          ),
    );
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
    widget.teamReview?.setActive(_foreground);
    if (_foreground) {
      _performance.start();
    } else {
      _performance.stop();
    }
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
        await _controller.reset(qaSessionSeed: _seed);
        if (_isCurrent(revision)) _replayPrimed = true;
      }
      return;
    }
    final batch = _replay.advance(elapsed);
    if (!_replayPrimed) {
      await _controller.reset(qaSessionSeed: _seed);
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
    widget.teamReview?.removeListener(_teamReviewChanged);
    _performance.dispose();
    _stopBasicsTween();
    for (final entry in _sessions.values) {
      entry.session.dispose();
    }
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
    // The visual on screen stays listed even if a vote just moved it out of
    // the filter, so voting never yanks it away; "Siguiente" moves on.
    final shown = [
      for (var index = 0; index < _catalog.length; index++)
        if (_catalog[index].id == _selectedId ||
            _matchesVoteFilter(_catalog[index], _voteFilter))
          index,
    ];
    return StudioView(
      voteFilters: widget.teamReview == null
          ? const []
          : [
              for (final filter in TeamVoteFilter.values)
                StudioFilterOption(
                  id: filter.name,
                  label: filter.label,
                  count: _catalog
                      .where((visual) => _matchesVoteFilter(visual, filter))
                      .length,
                ),
            ],
      selectedVoteFilter: _voteFilter.name,
      onVoteFilterChanged: _setVoteFilter,
      onListEnd: switch (widget.teamReview) {
        final TeamReviewController review => () =>
            unawaited(_openSummary(review)),
        null => null,
      },
      visuals: [
        for (final index in shown)
          StudioVisualItem(
            id: _catalog[index].id,
            name: _catalog[index].name,
            description: _catalog[index].description,
            role: _catalog[index].role,
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
            shortName: _recordings[index].shortName,
            technical: _recordings[index].technical,
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
      ratingPanel: _ratingPanel(),
      performanceOverlay: VisualPerformanceOverlay(sample: _performance.sample),
      adjustments: _adjustmentsButton(),
      compareLabel: _session?.comparing == true ? originalChipName : null,
      onCompare: _compareHandler,
      backdropVisuals: [
        for (var index = 0; index < _catalog.length; index++)
          if (_catalog[index].role == CreatorRole.background)
            (
              id: _catalog[index].id,
              name: _catalog[index].name,
              thumbnail: widget.thumbnailBuilder(_catalog[index], index),
            ),
      ],
      backdropBuilder: (id) {
        final index = _catalog.indexWhere((visual) => visual.id == id);
        return index < 0 ? null : widget.backdropBuilder(_catalog[index], index);
      },
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
    this.shortName,
    this.technical = false,
  });

  final String name;

  /// A test signal, not music: offered in the signal detail, not as a track.
  final bool technical;

  /// Label for the one-tap track buttons; falls back to [name].
  final String? shortName;
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
