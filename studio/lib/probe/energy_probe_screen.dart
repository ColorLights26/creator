/// Full-screen energy probe: one catalog visual alone, black behind it, fed
/// by the loud synthetic signal, with one `[ENERGY_PROBE]` line every 2 s.
///
/// Observational: it plays the visual exactly as the studio does and only
/// reads counters. The pure parts (spec, profile, loud signal, record) live
/// in their own files; this one owns the widget, timers and platform calls.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show stdout;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scene_compositor/scene_compositor.dart';
import 'package:scene_compositor_host/scene_compositor_host.dart';
import 'package:visual_catalog/visual_catalog.dart';

import 'energy_probe_identity.dart';
import 'energy_probe_loud_signal.dart';
import 'energy_probe_profile.dart';
import 'energy_probe_record.dart';
import 'energy_probe_spec.dart';

/// One record every 2 s, as the main app's probe.
const energyProbePollInterval = Duration(seconds: 2);
const _readTimeout = Duration(seconds: 2);

/// Writes one record the way the main app does: raw stdout plus the debug
/// log (the os_log copy). The host console shows both; the driver merges
/// them by `(epochMs, visual)`.
void writeEnergyProbeLine(Map<String, Object?> record) {
  final line = '$energyProbeLogPrefix ${jsonEncode(record)}';
  try {
    stdout.writeln(line);
  } on Object catch (_) {
    // No stdout (tests, detached process): the debug log copy remains.
  }
  debugPrint(line);
}

List<CreatorVisualDefinition> _defaultCatalog() => creatorVisuals;

SceneCompositorController _defaultController() =>
    SceneCompositorController(assets: creatorCatalogAssets);

Future<String?> _defaultBuildManifest() async {
  try {
    return await rootBundle.loadString(energyProbeBuildManifestAsset);
  } on Object {
    // The manifest is optional: a studio without it reports a null hash.
    return null;
  }
}

class EnergyProbeApp extends StatelessWidget {
  const EnergyProbeApp({
    required this.specText,
    this.catalogError,
    this.controllerFactory = _defaultController,
    super.key,
  });

  /// The text after `energy-probe=`.
  final String specText;

  /// Why the catalog did not open, when it did not.
  final String? catalogError;
  final SceneCompositorController Function() controllerFactory;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Energy Probe',
      debugShowCheckedModeBanner: false,
      color: Colors.black,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: EnergyProbeScreen(
        specText: specText,
        catalogError: catalogError,
        controllerFactory: controllerFactory,
      ),
    );
  }
}

class EnergyProbeScreen extends StatefulWidget {
  const EnergyProbeScreen({
    required this.specText,
    this.catalogError,
    this.controllerFactory = _defaultController,
    this.catalogBuilder = _defaultCatalog,
    this.deviceSnapshot = SceneCompositorHostQa.deviceSnapshot,
    this.buildManifestLoader = _defaultBuildManifest,
    this.writeLine = writeEnergyProbeLine,
    this.pollInterval = energyProbePollInterval,
    super.key,
  });

  final String specText;
  final String? catalogError;
  final SceneCompositorController Function() controllerFactory;
  final List<CreatorVisualDefinition> Function() catalogBuilder;
  final Future<Map<String, Object?>?> Function() deviceSnapshot;
  final Future<String?> Function() buildManifestLoader;
  final void Function(Map<String, Object?> record) writeLine;
  final Duration pollInterval;

  @override
  State<EnergyProbeScreen> createState() => _EnergyProbeScreenState();
}

class _EnergyProbeScreenState extends State<EnergyProbeScreen>
    with WidgetsBindingObserver {
  EnergyProbeSpec? _spec;
  CreatorVisualDefinition? _visual;
  EnergyProbeProfile? _profile;
  EnergyProbeLoudSignal? _signal;
  SceneCompositorController? _controller;
  EnergyProbeRecorder? _recorder;

  /// A spec or catalog problem: shown, reported once, nothing measured.
  String? _fatal;

  /// A compositor problem while measuring: shown and carried by every record.
  String? _error;
  Size? _viewport;
  double _pixelRatio = 1;
  bool _prepared = false;
  bool _ready = false;
  bool _foreground = true;
  bool _disposed = false;
  bool _polling = false;
  bool _sending = false;
  int _flutterFrames = 0;
  int _lastSignalPosition = -1;
  Timer? _poll;
  Timer? _signalTimer;
  final Stopwatch _clock = Stopwatch()..start();

  /// Runs only while the visual plays, so a pause doesn't skip the section.
  final Stopwatch _signalClock = Stopwatch();
  Future<void> _commands = Future<void>.value();
  late final TimingsCallback _timings = (timings) {
    _flutterFrames += timings.length;
  };

  bool get _reactive => _visual?.reactivity != CreatorReactivity.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    SchedulerBinding.instance.addTimingsCallback(_timings);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      ).catchError((Object error) => _logHost('system UI mode', error)),
    );
    _host('idle timer', () => SceneCompositorHostQa.setIdleTimerDisabled(true));
    unawaited(_start());
  }

  Future<void> _start() async {
    final EnergyProbeSpec spec;
    try {
      spec = parseEnergyProbeSpec(widget.specText);
      if (widget.catalogError case final String problem) {
        throw FormatException('No se pudo abrir el catálogo: $problem');
      }
    } on FormatException catch (error) {
      _fail(error.message);
      return;
    }
    _spec = spec;
    if (!spec.baseline) {
      final visual =
          widget
              .catalogBuilder()
              .where((candidate) => candidate.id == spec.visualId)
              .firstOrNull;
      if (visual == null) {
        _fail('No existe el visual «${spec.visualId}» en el catálogo.');
        return;
      }
      final EnergyProbeProfile profile;
      try {
        profile = resolveEnergyProbeProfile(visual, spec);
        if (visual.reactivity != CreatorReactivity.none) {
          _signal = EnergyProbeLoudSignal.fromRecording(
            createSyntheticSceneSignalRecording(),
          );
        }
      } on FormatException catch (error) {
        _fail(error.message);
        return;
      }
      final buildHash = energyProbeBuildHash(await _buildManifest());
      if (_disposed) return;
      _visual = visual;
      _profile = profile;
      _recorder = EnergyProbeRecorder(
        visual: spec.text,
        sceneId: visual.programId,
        creator: energyProbeCreatorIdentity(
          visual: visual,
          profile: profile,
          reactive: _reactive,
          seed: visual.seed,
          buildHash: buildHash,
        ),
        startWallMicros: _clock.elapsedMicroseconds,
      );
      _controller = widget.controllerFactory()..addListener(_controllerChanged);
    } else {
      _recorder = EnergyProbeRecorder(
        visual: spec.text,
        sceneId: null,
        startWallMicros: _clock.elapsedMicroseconds,
      );
    }
    // Lines flow from now on, before the surface exists: the driver's thermal
    // gate reads the first one and waits for `surface: true` itself.
    _poll = Timer.periodic(widget.pollInterval, (_) => unawaited(_tick()));
    _maybePrepare();
    if (mounted) setState(() {});
  }

  Future<String?> _buildManifest() async {
    try {
      return await widget.buildManifestLoader().timeout(_readTimeout);
    } on Object {
      return null;
    }
  }

  void _fail(String message) {
    if (_disposed) return;
    _fatal = message;
    widget.writeLine({'visual': widget.specText, 'error': message});
    if (mounted) setState(() {});
  }

  void _viewportChanged(Size size, double pixelRatio) {
    if (_disposed ||
        !size.isFinite ||
        size.isEmpty ||
        size == _viewport && pixelRatio == _pixelRatio) {
      return;
    }
    final resized = _viewport != null;
    _viewport = size;
    _pixelRatio = pixelRatio;
    final controller = _controller;
    if (controller != null && _prepared && resized) {
      _enqueue(() => controller.resize(size, pixelRatio));
    } else {
      _maybePrepare();
    }
  }

  /// Installs the visual once both the controller and the viewport exist.
  void _maybePrepare() {
    final controller = _controller;
    final visual = _visual;
    final profile = _profile;
    final viewport = _viewport;
    if (_prepared ||
        controller == null ||
        visual == null ||
        profile == null ||
        viewport == null) {
      return;
    }
    _prepared = true;
    final pixelRatio = _pixelRatio;
    final reactive = _reactive;
    _enqueue(() async {
      await controller.setPlaying(false);
      await controller.setVisual(
        visual,
        size: viewport,
        pixelRatio: pixelRatio,
      );
      // setVisual installs the initial values; send the profile's if they differ.
      if (!mapEquals(profile.controls.toMap(), visual.controls.toMap())) {
        await controller.setControls(profile.controls);
      }
      if (!mapEquals(profile.modifiers, visual.modifierDefaults)) {
        await controller.setModifiers(profile.modifiers);
      }
      await controller.setReactive(reactive);
      await controller.reset(qaSessionSeed: visual.seed);
      _ready = true;
      await controller.setPlaying(_shouldPlay);
      _syncSignal();
      if (mounted) setState(() {});
    });
  }

  bool get _shouldPlay => !_disposed && _ready && _foreground && _error == null;

  void _syncSignal() {
    if (_shouldPlay && _signal != null) {
      _startSignal();
    } else {
      _stopSignal();
    }
  }

  void _startSignal() {
    final signal = _signal;
    final visual = _visual;
    final controller = _controller;
    if (signal == null ||
        visual == null ||
        controller == null ||
        _signalTimer != null) {
      return;
    }
    final fps = visual.framesPerSecond;
    _signalClock.start();
    _signalTimer = Timer.periodic(
      Duration(microseconds: Duration.microsecondsPerSecond ~/ fps),
      (_) => _pumpSignal(controller, signal, fps),
    );
  }

  void _stopSignal() {
    _signalTimer?.cancel();
    _signalTimer = null;
    _signalClock.stop();
  }

  /// One signal frame per 1/30 s of played time, indexed like the harness;
  /// a late send is skipped rather than queued behind the compositor.
  void _pumpSignal(
    SceneCompositorController controller,
    EnergyProbeLoudSignal signal,
    int fps,
  ) {
    if (_sending || !_shouldPlay) return;
    final tick =
        _signalClock.elapsedMicroseconds *
        fps ~/
        Duration.microsecondsPerSecond;
    final due = signal.frameForTick(tick, fps);
    final position = due.cycle * signal.length + due.index;
    if (position == _lastSignalPosition) return;
    _lastSignalPosition = position;
    _sending = true;
    _enqueue(() async {
      try {
        await controller.sendSignal(due.frame);
      } finally {
        _sending = false;
      }
    });
  }

  Future<void> _tick() async {
    if (_polling || _disposed) return;
    final recorder = _recorder;
    if (recorder == null) return;
    _polling = true;
    try {
      final controller = _controller;
      final reads = await Future.wait<Map<Object?, Object?>?>([
        _optional(() async => controller?.readSurfaceStats()),
        _optional(widget.deviceSnapshot),
      ]);
      if (_disposed) return;
      final wall = _clock.elapsedMicroseconds;
      final cpu = CpuClock.instance?.processMicros;
      final frames = _flutterFrames;
      _flutterFrames = 0;
      final viewport = _viewport;
      final record = recorder.record(
        epochMilliseconds: DateTime.now().millisecondsSinceEpoch,
        wallMicros: wall,
        processCpuMicros: cpu,
        flutterFrames: frames,
        device: reads[1],
        surface: reads[0],
        viewport: {
          'logicalWidth': viewport?.width,
          'logicalHeight': viewport?.height,
          'devicePixelRatio': viewport == null ? null : _pixelRatio,
        },
        error: _error ?? controller?.error,
      );
      widget.writeLine(record);
    } on Object catch (error, stack) {
      developer.log(
        'Energy probe poll failed',
        name: 'audiovisual_creator',
        error: error,
        stackTrace: stack,
      );
    } finally {
      _polling = false;
    }
  }

  /// A failed or slow read leaves its fields null, never stops the probe.
  Future<Map<Object?, Object?>?> _optional(
    Future<Map<Object?, Object?>?> Function() read,
  ) async {
    try {
      return await read().timeout(_readTimeout);
    } on Object {
      return null;
    }
  }

  void _controllerChanged() {
    if (_disposed) return;
    final controller = _controller;
    if (controller?.error case final String error) {
      final changed = _error != error;
      _error = error;
      _stopSignal();
      if (changed) _enqueue(() => controller!.setPlaying(false));
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stopSignal();
    final controller = _controller;
    if (controller == null || !_ready) return;
    _enqueue(() async {
      await controller.setPlaying(_shouldPlay);
      _syncSignal();
    });
  }

  void _enqueue(Future<void> Function() operation) {
    _commands = _commands.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } on Object catch (error, stack) {
        _runtimeFailure(error, stack);
      }
    });
  }

  void _runtimeFailure(Object error, StackTrace stack) {
    developer.log(
      'Energy probe compositor operation failed',
      name: 'audiovisual_creator',
      error: error,
      stackTrace: stack,
    );
    if (_disposed) return;
    _stopSignal();
    _error = switch (error) {
      PlatformException(:final message, :final code) => message ?? code,
      FormatException(:final message) => message,
      _ => error.toString(),
    };
    if (mounted) setState(() {});
  }

  void _host(String what, Future<void> Function() call) {
    unawaited(call().catchError((Object error) => _logHost(what, error)));
  }

  void _logHost(String what, Object error) {
    developer.log(
      'Energy probe host call unavailable: $what',
      name: 'audiovisual_creator',
      error: error,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _poll?.cancel();
    _stopSignal();
    _host(
      'idle timer',
      () => SceneCompositorHostQa.setIdleTimerDisabled(false),
    );
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_controllerChanged);
      unawaited(
        _commands
            .then((_) => controller.close())
            .catchError((Object error) {
              developer.log(
                'Energy probe compositor cleanup failed',
                name: 'audiovisual_creator',
                error: error,
              );
            })
            .whenComplete(controller.dispose),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textureId = _controller?.textureId;
    final preview = _controller?.preview;
    final message = _fatal ?? _error;
    final spec = _spec;
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final pixelRatio = MediaQuery.devicePixelRatioOf(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _viewportChanged(size, pixelRatio);
          });
          return Stack(
            fit: StackFit.expand,
            children: [
              if (spec != null && !spec.baseline)
                if (preview case final Widget surface)
                  surface
                else if (textureId != null)
                  Texture(
                    key: ValueKey(textureId),
                    textureId: textureId,
                    filterQuality: FilterQuality.low,
                  ),
              if (message != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: SelectableText(
                      'Sonda de energía «${widget.specText}»\n\n$message',
                      key: const ValueKey('energy-probe-error'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
