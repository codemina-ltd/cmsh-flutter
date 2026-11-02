import 'cmsh_client.dart';
import 'cmsh_link.dart';
import 'platform_channel.dart';
import 'storage.dart';

/// Entry point of the package.
///
/// ```dart
/// await Cmsh.init(sdkKey: 'pk_live_xxx');
/// Cmsh.onLink.listen((link) => router.go(link.path));
/// ```
class Cmsh {
  const Cmsh._();

  static CmshClient? _client;

  /// Starts the SDK. Call it once, before `runApp`. It returns quickly and
  /// never throws. Network work carries on in the background.
  ///
  /// - [sdkKey]: the publishable key from the CMSH portal.
  /// - [domains]: your custom link domains. Only these hosts, and links with
  ///   a CMSH click on them, are ever sent to CMSH.
  /// - [requireConsent]: when true, nothing is sent until
  ///   `setConsent(true)`.
  /// - [iosClipboardMatching]: reads the clipboard on first launch to carry a
  ///   click through an App Store install. iOS shows a paste prompt to every
  ///   new user, so it's off by default.
  /// - [debug]: logs failures. Payloads and user details are never logged.
  static Future<void> init({
    required String sdkKey,
    Set<String> domains = const {},
    bool requireConsent = false,
    bool iosClipboardMatching = false,
    String apiUrl = 'https://cmsh.io',
    bool debug = false,
  }) async {
    if (_client != null) {
      return;
    }
    final client = CmshClient(
      sdkKey: sdkKey,
      apiUrl: apiUrl,
      domains: domains.map((domain) => domain.toLowerCase()).toSet(),
      requireConsent: requireConsent,
      iosClipboardMatching: iosClipboardMatching,
      debug: debug,
      platform: DeviceCmshPlatform(),
      storage: PreferencesStorage(),
    );
    _client = client;
    await client.start();
  }

  /// Links that opened the app, from a cold start, a warm start or a deferred
  /// install. A link that arrives before you subscribe is held for you.
  static Stream<CmshLink> get onLink => _require.onLink;

  /// Attaches user details to this device and the click that brought them.
  /// Call it after sign-in. [traits] can hold any fields you need, and you
  /// must have a lawful basis to collect them. Later calls merge.
  static Future<void> identify(String userId, {Map<String, dynamic>? traits}) =>
      _require.identify(userId, traits);

  /// Records an in-app event. Works offline, and sends once.
  static Future<void> track(String name, {Map<String, dynamic>? properties}) =>
      _require.track(name, properties);

  /// Sets consent. Revoking also deletes anything still queued on the device.
  static Future<void> setConsent(bool granted) => _require.setConsent(granted);

  /// Sends queued events now.
  static Future<void> flush() => _require.flush();

  /// Call on sign-out, so the next person isn't linked to this one.
  static Future<void> reset() => _require.reset();

  static CmshClient get _require {
    final client = _client;
    if (client == null) {
      throw StateError('Call Cmsh.init() first');
    }
    return client;
  }
}
