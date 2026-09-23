import Flutter
import UIKit

/// Adopts the UIScene lifecycle.
///
/// iOS 27 terminates at launch — before the first Flutter frame, with no
/// catchable exception — any app linked against the iOS 27 SDK that still
/// uses the legacy UIApplicationDelegate lifecycle. Declaring this class in
/// `UIApplicationSceneManifest` is what opts the app in; `FlutterSceneDelegate`
/// carries the whole Flutter side, so there is nothing to add here.
class SceneDelegate: FlutterSceneDelegate {}
