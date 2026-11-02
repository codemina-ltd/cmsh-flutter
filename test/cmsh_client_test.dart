import 'dart:async';
import 'dart:convert';

import 'package:cmsh_flutter/cmsh_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final appLink = Uri.parse(
    'https://acme.com/product/1?ref=x&cmsh_click=$clickA',
  );

  Future<List<CmshLink>> collect(Stream<CmshLink> stream) async {
    final links = <CmshLink>[];
    final subscription = stream.listen(links.add);
    await pumpEventQueue();
    await subscription.cancel();
    return links;
  }

  /// A started client on a device that has launched before.
  Future<MemoryStorage> returningUser() async =>
      MemoryStorage()..values['launched'] = '1';

  group('links', () {
    test(
      'resolves a cold-start link and holds it for a late listener',
      () async {
        final server = FakeServer();
        final client = buildClient(
          platform: FakePlatform(initial: appLink),
          server: server,
          storage: await returningUser(),
        );

        await client.start();
        await client.startupComplete;
        final links = await collect(client.onLink);

        expect(links.single.path, '/product/1');
        expect(links.single.data, {'coupon': 'SAVE10'});
        expect(links.single.matchType, CmshMatchType.clickParam);
        expect(links.single.isMatched, isTrue);
        expect(server.calls('open').single['clickId'], clickA);
      },
    );

    test('resolves a warm-start link', () async {
      final platform = FakePlatform();
      final client = buildClient(
        platform: platform,
        server: FakeServer(),
        storage: await returningUser(),
      );
      await client.start();
      await client.startupComplete;

      final future = client.onLink.first;
      platform.controller.add(appLink);

      expect((await future).clickId, clickA);
    });

    test('counts a link delivered on both channels once', () async {
      final server = FakeServer();
      final platform = FakePlatform(initial: appLink);
      final client = buildClient(
        platform: platform,
        server: server,
        storage: await returningUser(),
      );

      await client.start();
      platform.controller.add(appLink);
      await client.startupComplete;
      await pumpEventQueue();

      expect(server.calls('open'), hasLength(1));
    });

    test('sends a listed custom domain as a direct open', () async {
      final server = FakeServer();
      final platform = FakePlatform(
        initial: Uri.parse('https://go.acme.com/sale'),
      );
      final client = buildClient(
        platform: platform,
        server: server,
        storage: await returningUser(),
        domains: {'go.acme.com'},
      );

      await client.start();
      await client.startupComplete;

      final open = server.calls('open').single;
      expect(open['source'], 'direct');
      expect(open['url'], 'https://go.acme.com/sale');
    });

    test('never sends an unrelated deep link to CMSH', () async {
      final server = FakeServer();
      final url = Uri.parse('https://acme.com/reset?token=secret');
      final client = buildClient(
        platform: FakePlatform(initial: url),
        server: server,
        storage: await returningUser(),
      );

      await client.start();
      await client.startupComplete;
      final links = await collect(client.onLink);

      expect(server.requests, isEmpty);
      expect(links.single.path, '/reset?token=secret');
      expect(links.single.isMatched, isFalse);
    });

    test('still routes from the URL when the network is down', () async {
      final server = FakeServer((_, _) => throw Exception('offline'));
      final client = buildClient(
        platform: FakePlatform(initial: appLink),
        server: server,
        storage: await returningUser(),
      );

      await client.start();
      await client.startupComplete;
      final links = await collect(client.onLink);

      expect(links.single.path, '/product/1?ref=x');
      expect(links.single.isMatched, isFalse);
      expect(client.queueLength, 1);
    });
  });

  group('first launch', () {
    test('matches the Android install referrer', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(referrer: 'cmsh_click=$clickA'),
        server: server,
      );

      await client.start();
      await client.startupComplete;
      final links = await collect(client.onLink);

      final open = server.calls('open').single;
      expect(open['source'], 'install_referrer');
      expect(open['isFirstLaunch'], isTrue);
      expect(links.single.isDeferred, isTrue);
      expect(links.single.path, '/product/1');
    });

    test('matches the iOS clipboard token and clears it', () async {
      final server = FakeServer();
      final platform = FakePlatform(isIos: true, clipboard: 'cmsh:$clickA');
      final client = buildClient(
        platform: platform,
        server: server,
        iosClipboardMatching: true,
      );

      await client.start();
      await client.startupComplete;

      expect(server.calls('open').single['source'], 'clipboard');
      expect(platform.clipboard, '');
    });

    test('leaves other clipboard contents alone', () async {
      final platform = FakePlatform(isIos: true, clipboard: 'my password');
      final server = FakeServer();
      final client = buildClient(
        platform: platform,
        server: server,
        iosClipboardMatching: true,
      );

      await client.start();
      await client.startupComplete;

      expect(platform.clipboard, 'my password');
      expect(server.calls('open').single['source'], 'organic');
    });

    test('never touches the clipboard unless the developer opted in', () async {
      final platform = FakePlatform(isIos: true, clipboard: 'cmsh:$clickA');
      final client = buildClient(platform: platform, server: FakeServer());

      await client.start();
      await client.startupComplete;

      expect(platform.clipboardReads, 0);
    });

    test('reports an organic install when a referrer lookup fails', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(referrerError: true),
        server: server,
      );

      await client.start();
      await client.startupComplete;

      expect(server.calls('open').single['source'], 'organic');
    });

    test('reports the install only once', () async {
      final storage = MemoryStorage();
      final server = FakeServer();
      final first = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: storage,
      );
      await first.start();
      await first.startupComplete;

      final second = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: storage,
      );
      await second.start();
      await second.startupComplete;

      expect(server.calls('open'), hasLength(1));
      expect(storage.values['device_id'], isNotNull);
      expect(second.deviceId, first.deviceId);
    });
  });

  group('identify and track', () {
    test('identifies with any custom fields', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: await returningUser(),
      );
      await client.start();

      await client.identify('user_1', {'name': 'Sara', 'plan': 'gold'});

      final body = server.calls('identify').single;
      expect(body['externalId'], 'user_1');
      expect(body['traits'], {'name': 'Sara', 'plan': 'gold'});
      expect(body['deviceId'], client.deviceId);
    });

    test('keeps order: identify lands before the events after it', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: await returningUser(),
      );
      await client.start();

      await client.track('before', null);
      await client.identify('user_1', null);
      await client.track('after', null);
      await client.flush();

      expect(server.requests.map((request) => request.$1), [
        'events',
        'identify',
        'events',
      ]);
    });

    test('batches queued events into one request', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: await returningUser(),
      );
      await client.start();
      await client.startupComplete;

      await client.track('a', null);
      await client.track('b', {'value': 1});
      await client.flush();

      final events = server.calls('events').single['events'] as List;
      expect(events, hasLength(2));
    });

    test('keeps events through a restart and resends the same ids', () async {
      final storage = await returningUser();
      final offline = FakeServer((_, _) => http.Response('', 503));
      final first = buildClient(
        platform: FakePlatform(),
        server: offline,
        storage: storage,
      );
      await first.start();
      await first.track('purchase', {'value': 25});
      await first.flush();
      expect(first.queueLength, 1);

      final online = FakeServer();
      final second = buildClient(
        platform: FakePlatform(),
        server: online,
        storage: storage,
      );
      await second.start();
      await second.flush();

      Map<String, dynamic> eventOf(Map<String, dynamic> body) =>
          (body['events'] as List).single as Map<String, dynamic>;
      expect(second.queueLength, 0);
      expect(
        eventOf(online.calls('events').first)['eventId'],
        eventOf(offline.calls('events').first)['eventId'],
      );
    });

    test('drops what the server will always refuse', () async {
      final server = FakeServer(
        (_, _) => http.Response(
          jsonEncode({'code': 'ATTRIBUTION_LIMIT_REACHED'}),
          403,
        ),
      );
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: await returningUser(),
      );
      await client.start();

      await client.track('purchase', null);
      await client.flush();

      expect(client.queueLength, 0);
    });

    test('retries a rate limit', () async {
      final server = FakeServer((_, _) => http.Response('', 429));
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: await returningUser(),
      );
      await client.start();

      await client.track('purchase', null);
      await client.flush();

      expect(client.queueLength, 1);
      await client.dispose();
    });

    test('reset gives the next person a new device id', () async {
      final client = buildClient(
        platform: FakePlatform(),
        server: FakeServer(),
        storage: await returningUser(),
      );
      await client.start();
      final before = client.deviceId;

      await client.reset();

      expect(client.deviceId, isNot(before));
    });
  });

  group('consent', () {
    test('sends nothing without consent, but the app still routes', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(initial: appLink),
        server: server,
        requireConsent: true,
      );

      await client.start();
      await client.startupComplete;
      await client.identify('user_1', {'name': 'Sara'});
      await client.track('purchase', null);
      await client.flush();
      final links = await collect(client.onLink);

      expect(server.requests, isEmpty);
      expect(client.queueLength, 0);
      expect(links.single.path, '/product/1?ref=x');
    });

    test('reports the install once consent arrives', () async {
      final server = FakeServer();
      final client = buildClient(
        platform: FakePlatform(),
        server: server,
        requireConsent: true,
      );
      await client.start();
      await client.startupComplete;
      expect(server.requests, isEmpty);

      await client.setConsent(true);

      expect(server.calls('open').single['isFirstLaunch'], isTrue);
    });

    test('remembers consent across launches', () async {
      final storage = await returningUser();
      final first = buildClient(
        platform: FakePlatform(),
        server: FakeServer(),
        storage: storage,
        requireConsent: true,
      );
      await first.start();
      await first.setConsent(true);

      final server = FakeServer();
      final second = buildClient(
        platform: FakePlatform(),
        server: server,
        storage: storage,
        requireConsent: true,
      );
      await second.start();
      await second.track('purchase', null);
      await second.flush();

      expect(server.calls('events'), hasLength(1));
    });

    test('revoking deletes anything still queued', () async {
      final client = buildClient(
        platform: FakePlatform(),
        server: FakeServer((_, _) => http.Response('', 503)),
        storage: await returningUser(),
        requireConsent: false,
      );
      await client.start();
      await client.track('purchase', null);
      await client.flush();

      await client.setConsent(false);

      expect(client.queueLength, 0);
    });
  });

  group('robustness', () {
    test('never throws to the host app', () async {
      final client = buildClient(
        platform: FakePlatform(initial: appLink, referrerError: true),
        server: FakeServer((_, _) => throw StateError('boom')),
      );

      await client.start();
      await client.startupComplete;
      await client.identify('user_1', {'name': 'Sara'});
      await client.track('purchase', null);
      await client.flush();
      await client.reset();
      await client.setConsent(true);
    });

    test('survives a corrupt stored queue', () async {
      final storage = await returningUser();
      storage.values['queue'] = 'not json';
      final client = buildClient(
        platform: FakePlatform(),
        server: FakeServer(),
        storage: storage,
      );

      await client.start();
      await client.track('purchase', null);

      expect(client.queueLength, 1);
    });

    test('keeps user details out of the stored request log', () async {
      final logs = <String>[];
      await runZoned(
        () async {
          final client = buildClient(
            platform: FakePlatform(),
            server: FakeServer((_, _) => http.Response('', 500)),
            storage: await returningUser(),
          );
          await client.start();
          await client.identify('user_1', {'email': 'sara@example.com'});
          await client.dispose();
        },
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => logs.add(line),
        ),
      );
      expect(logs.join(), isNot(contains('sara@example.com')));
    });
  });
}
