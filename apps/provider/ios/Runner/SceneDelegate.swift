import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if URLContexts.contains(where: {
      IncomingRequestActionBridge.shared.handle(url: $0.url)
    }) {
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
