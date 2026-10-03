import 'dart:ffi';
import 'dart:io';

typedef _ClockGetTimeNative = Int32 Function(Int32, Pointer<Int64>);
typedef _ClockGetTime = int Function(int, Pointer<Int64>);
typedef _MallocNative = Pointer<Void> Function(IntPtr);
typedef _Malloc = Pointer<Void> Function(int);

/// CPU time consumed by this process and by the calling thread, read from
/// libc `clock_gettime`. Meant for diagnostics overlays: one syscall per
/// read and no allocation after creation.
///
/// Process time counts every thread (UI, raster, audio, native renderers);
/// thread time counts only the caller, so wrapping synchronous work with it
/// measures that work's CPU and ignores time the thread was preempted.
final class CpuClock {
  CpuClock._(this._clockGettime, this._buffer, this._processId, this._threadId);

  /// The shared clock, or null where it can't be read reliably (32-bit
  /// devices, other platforms or a failed lookup) — callers show "—" then.
  static final CpuClock? instance = _create();

  final _ClockGetTime _clockGettime;
  final Pointer<Int64> _buffer;
  final int _processId;
  final int _threadId;

  static CpuClock? _create() {
    // timespec is two 64-bit fields only on 64-bit iOS and Android.
    if (sizeOf<IntPtr>() != 8) return null;
    // clockid_t values differ: Darwin uses 12/16, Linux/Android 2/3.
    final (process, thread) = switch (Platform.operatingSystem) {
      'ios' || 'macos' => (12, 16),
      'android' || 'linux' => (2, 3),
      _ => (-1, -1),
    };
    if (process < 0) return null;
    try {
      final libc =
          Platform.isAndroid
              ? DynamicLibrary.open('libc.so')
              : DynamicLibrary.process();
      final clockGettime = libc
          .lookupFunction<_ClockGetTimeNative, _ClockGetTime>('clock_gettime');
      final malloc = libc.lookupFunction<_MallocNative, _Malloc>('malloc');
      // Lives as long as the app: one 16-byte timespec for every read.
      final buffer = malloc(16).cast<Int64>();
      if (buffer == nullptr) return null;
      final clock = CpuClock._(clockGettime, buffer, process, thread);
      if (clock._read(process) == null || clock._read(thread) == null) {
        return null;
      }
      return clock;
    } on Object {
      return null;
    }
  }

  /// CPU time of the whole process, in microseconds, or null on failure.
  int? get processMicros => _read(_processId);

  /// CPU time of the calling thread, in microseconds, or null on failure.
  int? get threadMicros => _read(_threadId);

  int? _read(int clockId) {
    if (_clockGettime(clockId, _buffer) != 0) return null;
    return _buffer[0] * Duration.microsecondsPerSecond + _buffer[1] ~/ 1000;
  }
}
