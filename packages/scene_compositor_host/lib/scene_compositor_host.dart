/// Installs the shared native compositor in the standalone studio on iOS.
///
/// Production applications with an existing scene owner must depend on the
/// `scene_compositor` library directly, without this host plugin.
library;

import 'package:flutter/services.dart';

/// Studio-only QA channel of the host plugin: launch arguments, a device
/// snapshot for the energy probe and the idle timer. Every call throws
/// [MissingPluginException] where the host plugin is not installed
/// (Android, tests); callers treat that as "no QA host".
class SceneCompositorHostQa {
  const SceneCompositorHostQa._();

  static const MethodChannel channel = MethodChannel(
    'com.chic.audiovisualCreator/qa',
  );

  /// `ProcessInfo.processInfo.arguments` of the running app.
  static Future<List<String>> launchArguments() async {
    final arguments = await channel.invokeListMethod<String>('launchArguments');
    return arguments ?? const [];
  }

  /// Thermal state (`nominal|fair|serious|critical`), low power mode,
  /// battery level and charging, display refresh rate, hardware model,
  /// system name/version, whether the device is physical and the process
  /// physical memory footprint in bytes.
  static Future<Map<String, Object?>?> deviceSnapshot() =>
      channel.invokeMapMethod<String, Object?>('deviceSnapshot');

  /// Keeps the screen awake while a probe runs.
  static Future<void> setIdleTimerDisabled(bool disabled) => channel
      .invokeMethod<void>('setIdleTimerDisabled', {'disabled': disabled});
}
