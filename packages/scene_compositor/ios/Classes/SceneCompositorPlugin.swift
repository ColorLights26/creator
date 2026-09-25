import Flutter
import UIKit

/// The creator has the same scene owner and render queue as the production app.
/// Production compiles the Runtime sources directly and keeps its existing
/// AppDelegate registration, so it never installs this second channel owner.
public final class SceneCompositorPlugin: NSObject, FlutterPlugin {
  private let renderEngine: MusicVibeRenderEngine
  private let sceneEngine: SceneSurfaceRenderEngine
  private let pip: PictureInPictureHandler

  private init(registrar: FlutterPluginRegistrar) {
    let renderer = MusicVibeRenderEngine(textureRegistry: registrar.textures())
    renderEngine = renderer
    sceneEngine = SceneSurfaceRenderEngine(
      textureRegistry: registrar.textures(),
      renderEngine: renderer,
      windowProvider: { [weak registrar] in registrar?.viewController?.view.window }
    )
    pip = PictureInPictureHandler(
      windowProvider: { [weak registrar] in registrar?.viewController?.view.window },
      renderEngine: renderer, v2ImageRuntime: sceneEngine.pictureInPictureV2Runtime,
      sceneSurfaceEngine: sceneEngine)
    super.init()
    sceneEngine.register(with: registrar.messenger())
    pip.register(with: registrar.messenger())
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let plugin = SceneCompositorPlugin(registrar: registrar)
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    sceneEngine.shutdown()
    renderEngine.shutdown()
  }
}
