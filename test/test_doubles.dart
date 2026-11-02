import 'dart:async';
import 'dart:convert';

import 'package:cmsh_flutter/src/cmsh_client.dart';
import 'package:cmsh_flutter/src/platform_channel.dart';
import 'package:cmsh_flutter/src/storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const clickA = '11111111-1111-4111-8111-111111111111';

class MemoryStorage implements CmshStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class FakePlatform implements CmshPlatform {
  FakePlatform({
    this.isIos = false,
    this.initial,
    this.referrer,
    this.clipboard,
    this.referrerError = false,
  });

  @override
  final bool isIos;
  final Uri? initial;
  final String? referrer;
  final bool referrerError;
  String? clipboard;
  int clipboardReads = 0;
  final StreamController<Uri> controller = StreamController.broadcast();

  @override
  String get userAgentOs => 'Linux; Android';

  @override
  Stream<Uri> get links => controller.stream;

  @override
  Future<Uri?> initialLink() async => initial;

  @override
  Future<String?> installReferrer() async {
    if (referrerError) {
      throw Exception('no play store');
    }
    return referrer;
  }

  @override
  Future<String?> clipboardText() async {
    clipboardReads += 1;
    return clipboard;
  }

  @override
  Future<void> clearClipboard() async => clipboard = '';
}

/// Records requests and answers from [respond].
class FakeServer {
  FakeServer([
    http.Response Function(String path, Map<String, dynamic>)? respond,
  ]) : respond = respond ?? _matched;

  http.Response Function(String path, Map<String, dynamic> body) respond;
  final List<(String, Map<String, dynamic>)> requests = [];

  static http.Response _matched(String path, Map<String, dynamic> body) {
    if (path != 'open' || body['source'] == 'organic') {
      return http.Response(jsonEncode({'matched': false}), 200);
    }
    return http.Response(
      jsonEncode({
        'matched': true,
        'clickId': body['clickId'] ?? body['openId'],
        'linkId': 'link-1',
        'path': '/product/1',
        'data': {'coupon': 'SAVE10'},
        'matchType': body['source'],
      }),
      200,
    );
  }

  http.Client get client => MockClient((request) async {
    final path = request.url.pathSegments.last;
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    requests.add((path, body));
    return respond(path, body);
  });

  Iterable<Map<String, dynamic>> calls(String path) =>
      requests.where((request) => request.$1 == path).map((r) => r.$2);
}

CmshClient buildClient({
  required FakePlatform platform,
  required FakeServer server,
  MemoryStorage? storage,
  Set<String> domains = const {},
  bool requireConsent = false,
  bool iosClipboardMatching = false,
}) => CmshClient(
  sdkKey: 'pk_live_test',
  apiUrl: 'https://cmsh.test',
  domains: domains,
  requireConsent: requireConsent,
  iosClipboardMatching: iosClipboardMatching,
  debug: false,
  platform: platform,
  storage: storage ?? MemoryStorage(),
  httpClient: server.client,
);
