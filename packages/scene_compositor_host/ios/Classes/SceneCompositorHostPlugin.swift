import Flutter
import scene_compositor

/// Studio-only registration. The shared package itself is not a Flutter plugin,
/// so an application that already owns SceneSurface never installs another one.
public final class SceneCompositorHostPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    SceneCompositorPlugin.register(with: registrar)
  }
}
