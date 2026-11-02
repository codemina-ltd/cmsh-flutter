import Flutter
import UIKit

/// iOS has no native work: links come from `app_links` and the clipboard from
/// Flutter. The plugin exists to ship the privacy manifest.
public class CmshFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {}
}
