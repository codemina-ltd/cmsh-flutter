import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'cmsh_link.dart';
import 'event_queue.dart';
import 'link_parser.dart';
import 'platform_channel.dart';
import 'storage.dart';

const sdkVersion = '0.1.0';

const _deviceIdKey = 'device_id';
const _launchedKey = 'launched';
const _consentKey = 'consent';

/// Queued events go out at this count, or on [flushInterval], or on pause.
const _flushAt = 20;

/// The implementation behind [Cmsh]. It must never crash or block the host
/// app: public methods catch everything, and failures are only logged.
class CmshClient with WidgetsBindingObserver {
  CmshClient({
    required this.sdkKey,
    required this.apiUrl,
    required this.domains,
    required this.requireConsent,
    required this.iosClipboardMatching,
    required this.debug,
    required this.platform,
    required this.storage,
    http.Client? httpClient,
    this.flushInterval = const Duration(seconds: 30),
  }) : api = ApiClient(
         baseUrl: apiUrl,
         sdkKey: sdkKey,
         userAgent:
             'Mozilla/5.0 (${platform.userAgentOs}) CmshFlutter/$sdkVersion',
         client: httpClient,
       );

  final String sdkKey;
  final String apiUrl;
  final Set<String> domains;
  final bool requireConsent;
  final bool iosClipboardMatching;
  final bool debug;
  final CmshPlatform platform;
  final CmshStorage storage;
  final ApiClient api;
  final Duration flushInterval;

  static const _uuid = Uuid();

  late final EventQueue _queue = EventQueue(
    api: api,
    storage: storage,
    onLog: _log,
  );

  final List<CmshLink> _pendingLinks = [];
  late final StreamController<CmshLink> _links =
      StreamController<CmshLink>.broadcast(onListen: _deliverPending);

  StreamSubscription<Uri>? _linkSubscription;
  Timer? _flushTimer;
  late String _deviceId;
  bool _hasConsent = true;
  bool _ready = false;
  bool _isFirstLaunch = false;
  bool _initialChecked = false;
  String? _lastUrl;
  DateTime? _lastUrlAt;
  Future<void>? _startup;

  /// Links that opened the app. The cold-start link is held until the first
  /// listener attaches, so a late subscription can't miss it.
  Stream<CmshLink> get onLink => _links.stream;

  @visibleForTesting
  int get queueLength => _queue.length;

  @visibleForTesting
  String get deviceId => _deviceId;

  /// Reads local state, then does the network work in the background.
  Future<void> start() async {
    await _guard('init', () async {
      await _queue.load();

      final storedDevice = await storage.read(_deviceIdKey);
      _deviceId = storedDevice ?? _uuid.v4();
      if (storedDevice == null) {
        await storage.write(_deviceIdKey, _deviceId);
      }

      _isFirstLaunch = await storage.read(_launchedKey) == null;
      if (_isFirstLaunch) {
        await storage.write(_launchedKey, '1');
      }

      _hasConsent =
          !requireConsent || await storage.read(_consentKey) == 'granted';
      _ready = true;

      _linkSubscription = platform.links.listen(
        (url) => unawaited(_guard('link', () => _handleUrl(url))),
        onError: (Object error) => _log('Link stream: ${error.runtimeType}'),
      );
      _flushTimer = Timer.periodic(flushInterval, (_) => _flushInBackground());
      WidgetsBinding.instance.addObserver(this);

      _startup = _guard('startup', _handleStartup);
    });
  }

  /// Completes when start-up network work is done. For tests.
  @visibleForTesting
  Future<void> get startupComplete => _startup ?? Future.value();

  Future<void> setConsent(bool granted) => _guard('setConsent', () async {
    await storage.write(_consentKey, granted ? 'granted' : 'denied');
    final wasGranted = _hasConsent;
    _hasConsent = granted;
    if (!granted) {
      await _queue.clear();
      return;
    }
    if (!wasGranted) {
      await _handleStartup();
    }
  });

  Future<void> identify(String userId, Map<String, dynamic>? traits) =>
      _guard('identify', () async {
        if (!_canSend) {
          return;
        }
        await _queue.add(
          QueueItem('identify', {
            ..._deviceFields(),
            'externalId': userId,
            'traits': ?traits,
          }),
        );
        await _queue.flush();
      });

  Future<void> track(String name, Map<String, dynamic>? properties) =>
      _guard('track', () async {
        if (!_canSend) {
          return;
        }
        await _queue.add(
          QueueItem('events', {
            ..._deviceFields(),
            'events': [
              {
                'eventId': _uuid.v4(),
                'name': name,
                'properties': ?properties,
                'occurredAt': DateTime.now().toUtc().toIso8601String(),
              },
            ],
          }),
        );
        if (_queue.length >= _flushAt) {
          await _queue.flush();
        }
      });

  Future<void> flush() => _guard('flush', _queue.flush);

  /// A new device id, so the next person on this phone starts clean.
  Future<void> reset() => _guard('reset', () async {
    await _queue.flush();
    _deviceId = _uuid.v4();
    await storage.write(_deviceIdKey, _deviceId);
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _flushInBackground();
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _linkSubscription?.cancel();
    _flushTimer?.cancel();
    _queue.dispose();
    await _links.close();
    api.close();
  }

  bool get _canSend => _ready && _hasConsent;

  Map<String, dynamic> _deviceFields() => {
    'deviceId': _deviceId,
    'platform': platform.isIos ? 'ios' : 'android',
  };

  Future<void> _handleStartup() async {
    final initial = _initialChecked ? null : await platform.initialLink();
    _initialChecked = true;

    // Without consent the app still routes, from the URL alone. Only the
    // report to CMSH waits. A click on that link is lost, as it should be.
    if (initial != null) {
      await _handleUrl(initial);
      _isFirstLaunch = _isFirstLaunch && !_hasConsent;
    }
    if (!_hasConsent) {
      return;
    }

    unawaited(_queue.flush());
    if (_isFirstLaunch) {
      await _handleDeferred();
      _isFirstLaunch = false;
    }
  }

  Future<void> _handleDeferred() async {
    final match = await _findDeferredClick();
    if (match == null) {
      await _open(source: 'organic');
      return;
    }

    final response = await _open(source: match.source, clickId: match.clickId);
    if (response?['matched'] == true) {
      _emit(_toLink(response!, isDeferred: true));
    }
  }

  Future<({String source, String clickId})?> _findDeferredClick() async {
    String? referrer;
    try {
      referrer = await platform.installReferrer();
    } on Object catch (error) {
      // Sideloaded builds and devices without Play land here.
      _log('Install referrer: ${error.runtimeType}');
    }
    final referrerClick = referrer == null
        ? null
        : clickIdFromReferrer(referrer);
    if (referrerClick != null) {
      return (source: 'install_referrer', clickId: referrerClick);
    }

    if (!platform.isIos || !iosClipboardMatching) {
      return null;
    }
    final text = await platform.clipboardText();
    final clipboardClick = text == null ? null : clickIdFromClipboard(text);
    if (clipboardClick == null) {
      return null;
    }
    await platform.clearClipboard();
    return (source: 'clipboard', clickId: clipboardClick);
  }

  Future<void> _handleUrl(Uri url) async {
    // app_links can deliver the cold-start link on both channels.
    final now = DateTime.now();
    final key = url.toString();
    if (key == _lastUrl &&
        _lastUrlAt != null &&
        now.difference(_lastUrlAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastUrl = key;
    _lastUrlAt = now;

    final fallback = CmshLink(path: pathFromUrl(url), url: url);
    final clickId = clickIdFromUrl(url);

    // Other deep links can hold reset tokens and the like, so only hosts the
    // developer listed are ever sent to CMSH.
    final isOwnedDomain = domains.contains(url.host.toLowerCase());
    if (!_hasConsent || (clickId == null && !isOwnedDomain)) {
      _emit(fallback);
      return;
    }

    final response = clickId != null
        ? await _open(source: 'click_param', clickId: clickId)
        : await _open(source: 'direct', url: url);

    _emit(
      response?['matched'] == true
          ? _toLink(response!, url: url, isDeferred: false)
          : fallback,
    );
  }

  /// Sends now, so the app can route on the answer. If that fails the open is
  /// queued with the same id, and the app routes from the URL meanwhile.
  Future<Map<String, dynamic>?> _open({
    required String source,
    String? clickId,
    Uri? url,
  }) async {
    final body = {
      ..._deviceFields(),
      'openId': _uuid.v4(),
      'source': source,
      'clickId': ?clickId,
      'url': ?url?.toString(),
      'isFirstLaunch': _isFirstLaunch,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
    };

    final result = await api.post('open', body);
    if (result.outcome == ApiOutcome.retry) {
      _log(result.message ?? 'Open failed');
      await _queue.add(QueueItem('open', body));
      return null;
    }
    if (result.outcome == ApiOutcome.drop) {
      _log(result.message ?? 'Open refused');
      return null;
    }
    return result.body;
  }

  CmshLink _toLink(
    Map<String, dynamic> response, {
    Uri? url,
    required bool isDeferred,
  }) => CmshLink(
    path: response['path'] as String? ?? (url == null ? '/' : pathFromUrl(url)),
    url: url,
    data: (response['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    clickId: response['clickId'] as String?,
    linkId: response['linkId'] as String?,
    matchType: CmshMatchType.fromValue(response['matchType'] as String?),
    isDeferred: isDeferred,
    isMatched: true,
  );

  void _emit(CmshLink link) {
    if (_links.isClosed) {
      return;
    }
    if (_links.hasListener) {
      _links.add(link);
    } else {
      _pendingLinks.add(link);
    }
  }

  void _deliverPending() {
    final pending = List.of(_pendingLinks);
    _pendingLinks.clear();
    // Later, so the listener that triggered this is attached first.
    scheduleMicrotask(() {
      pending.forEach(_links.add);
    });
  }

  void _flushInBackground() => unawaited(_guard('flush', _queue.flush));

  Future<void> _guard(String name, Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      _log('$name failed: ${error.runtimeType}');
    }
  }

  void _log(String message) {
    if (debug) {
      debugPrint('[cmsh_flutter] $message');
    }
  }
}
