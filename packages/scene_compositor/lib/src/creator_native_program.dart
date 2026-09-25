import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:visual_contract/visual_contract.dart';
import 'creator_visual_definition.dart';

typedef _Handle = Pointer<Void>;

/// Thin C ABI binding. The owner supplies all scheduling and signal delivery.
/// Each object exclusively owns one native instance; there are no shared scenes.
class CreatorNativeProgram {
  CreatorNativeProgram(this.visual, {int? seed, String? libraryPath})
    : _api = _NativeApi(libraryPath) {
    if (!visual.isNative ||
        visual.nativeBuild['abi'] != 1 ||
        visual.nativeBuild['hash'] is! String ||
        _api.version() != 1) {
      throw StateError(
        '${visual.id}: programa nativo sin preparar. Usa Stop → Run.',
      );
    }
    final name = _api.string(visual.programId);
    final hash = _api.string(visual.nativeBuild['hash'] as String);
    try {
      _handle = _api.create(name.cast(), hash.cast(), seed ?? visual.seed);
      if (_handle == nullptr) throw StateError(_api.errorText(nullptr));
    } finally {
      _api.free(name.cast());
      _api.free(hash.cast());
    }
    _options = _api.allocate(20 * 4).cast<Float>();
    _signal = _api.allocate(520).cast<Uint8>();
    if (_options == nullptr || _signal == nullptr) {
      dispose();
      throw StateError('No se pudo reservar el estado del visual.');
    }
    final values = _options.asTypedList(20);
    values.setAll(0, visual.controls.toMap().values);
    for (var i = 0; i < 4; i++) {
      final c = visual.colors[i];
      values.setAll(4 + i * 4, [
        ((c >> 16) & 255) / 255,
        ((c >> 8) & 255) / 255,
        (c & 255) / 255,
        ((c >> 24) & 255) / 255,
      ]);
    }
  }

  final CreatorVisualDefinition visual;
  final _NativeApi _api;
  _Handle _handle = nullptr;
  Pointer<Float> _options = nullptr;
  Pointer<Uint8> _signal = nullptr;

  void _check(int value) {
    if (value != 1)
      throw StateError('${visual.id}: ${_api.errorText(_handle)}');
  }

  void _open() {
    if (_handle == nullptr) throw StateError('Native scene is closed.');
  }

  void configure({
    required bool reactive,
    required bool playing,
    required double hostTime,
  }) {
    _open();
    if ((visual.reactivity == CreatorReactivity.none && reactive) ||
        (visual.reactivity == CreatorReactivity.music && !reactive))
      throw ArgumentError('Reactivity does not match ${visual.id}.');
    _check(
      _api.configure(
        _handle,
        _options,
        20,
        reactive ? 1 : 0,
        playing ? 1 : 0,
        hostTime,
      ),
    );
  }

  void consume(SceneRenderSignalFrameV2 frame) {
    _open();
    _signal.asTypedList(520).setAll(0, frame.toBytes());
    _check(_api.consume(_handle, _signal, 520));
  }

  void setControls(CreatorControls controls) {
    _open();
    controls.validate();
    _options.asTypedList(20).setAll(0, controls.toMap().values);
  }

  void update({
    required double width,
    required double height,
    required double hostTime,
    required bool reducedMotion,
  }) {
    _open();
    _check(
      _api.update(_handle, width, height, hostTime, reducedMotion ? 1 : 0),
    );
  }

  /// This view expires on the next draw/reset/dispose. Record it synchronously.
  Float32List draw() {
    _open();
    _check(_api.draw(_handle));
    final count = _api.length(_handle);
    if (count > 262144)
      throw StateError('Native command buffer exceeds its ABI budget.');
    return count == 0
        ? Float32List(0)
        : _api.commands(_handle).asTypedList(count);
  }

  void reset({int? seed}) {
    _open();
    _check(_api.reset(_handle, seed ?? visual.seed));
  }

  double get updateMicros {
    _open();
    return _api.updateMicros(_handle);
  }

  void dispose() {
    if (_handle != nullptr) _api.destroy(_handle);
    if (_options != nullptr) _api.free(_options.cast());
    if (_signal != nullptr) _api.free(_signal.cast());
    _handle = nullptr;
    _options = nullptr;
    _signal = nullptr;
  }
}

class _NativeApi {
  _NativeApi(String? path)
    : library =
          path != null
              ? DynamicLibrary.open(path)
              : Platform.isAndroid
              ? DynamicLibrary.open('libscene_program_native.so')
              : DynamicLibrary.process();
  final DynamicLibrary library;
  late final version = library
      .lookupFunction<Uint32 Function(), int Function()>('cp_abi_version');
  late final allocate = library.lookupFunction<
    Pointer<Void> Function(Size),
    Pointer<Void> Function(int)
  >('cp_allocate');
  late final free = library.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)
  >('cp_free');
  late final create = library.lookupFunction<
    _Handle Function(Pointer<Int8>, Pointer<Int8>, Uint32),
    _Handle Function(Pointer<Int8>, Pointer<Int8>, int)
  >('cp_create');
  late final destroy = library
      .lookupFunction<Void Function(_Handle), void Function(_Handle)>(
        'cp_destroy',
      );
  late final error = library.lookupFunction<
    Pointer<Uint8> Function(_Handle),
    Pointer<Uint8> Function(_Handle)
  >('cp_error');
  late final configure = library.lookupFunction<
    Int32 Function(_Handle, Pointer<Float>, Uint32, Int32, Int32, Double),
    int Function(_Handle, Pointer<Float>, int, int, int, double)
  >('cp_configure');
  late final consume = library.lookupFunction<
    Int32 Function(_Handle, Pointer<Uint8>, Uint32),
    int Function(_Handle, Pointer<Uint8>, int)
  >('cp_consume');
  late final update = library.lookupFunction<
    Int32 Function(_Handle, Double, Double, Double, Int32),
    int Function(_Handle, double, double, double, int)
  >('cp_update');
  late final draw = library
      .lookupFunction<Int32 Function(_Handle), int Function(_Handle)>(
        'cp_draw',
      );
  late final reset = library.lookupFunction<
    Int32 Function(_Handle, Uint32),
    int Function(_Handle, int)
  >('cp_reset');
  late final commands = library.lookupFunction<
    Pointer<Float> Function(_Handle),
    Pointer<Float> Function(_Handle)
  >('cp_commands');
  late final length = library
      .lookupFunction<Uint32 Function(_Handle), int Function(_Handle)>(
        'cp_command_length',
      );
  late final updateMicros = library
      .lookupFunction<Double Function(_Handle), double Function(_Handle)>(
        'cp_update_micros',
      );
  Pointer<Uint8> string(String text) {
    final bytes = utf8.encode(text);
    final p = allocate(bytes.length + 1).cast<Uint8>();
    if (p == nullptr) throw StateError('Native allocation failed.');
    p.asTypedList(bytes.length + 1).setAll(0, bytes);
    return p;
  }

  String errorText(_Handle h) {
    final p = error(h);
    if (p == nullptr) return 'Native scene failure';
    final bytes = <int>[];
    for (var i = 0; i < 8192 && p[i] != 0; i++) bytes.add(p[i]);
    return utf8.decode(bytes, allowMalformed: true);
  }
}
