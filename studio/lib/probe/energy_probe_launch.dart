/// Decides at startup whether this launch is an energy probe.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:scene_compositor_host/scene_compositor_host.dart';

import 'energy_probe_spec.dart';

/// The probe spec text of this launch, or null to open the normal studio.
/// Never throws: without the host plugin (Android, tests) or with a slow
/// channel, Studio opens as usual.
Future<String?> readEnergyProbeSpec({
  Future<List<String>> Function() arguments =
      SceneCompositorHostQa.launchArguments,
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    return energyProbeSpecFromArguments(await arguments().timeout(timeout));
  } on MissingPluginException {
    return null;
  } on Object catch (error, stack) {
    developer.log(
      'Launch arguments unavailable; opening the studio',
      name: 'audiovisual_creator',
      error: error,
      stackTrace: stack,
    );
    return null;
  }
}
