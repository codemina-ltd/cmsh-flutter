// Runs the package against a real API, so both sides agree on the contract.
//
//   CMSH_E2E_URL=http://localhost:3100 CMSH_E2E_KEY=pk_live_... \
//   CMSH_E2E_CLICK=<id> flutter test test/integration
//
// The click must come from visiting an app link. Skipped without these.
import 'dart:io';

import 'package:cmsh_flutter/cmsh_flutter.dart';
import 'package:cmsh_flutter/src/cmsh_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_doubles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  final env = Platform.environment;
  final url = env['CMSH_E2E_URL'];
  final key = env['CMSH_E2E_KEY'];
  final click = env['CMSH_E2E_CLICK'];

  test(
    'link, identify and events reach the server',
    () async {
      final client = CmshClient(
        sdkKey: key!,
        apiUrl: url!,
        domains: const {},
        requireConsent: false,
        iosClipboardMatching: false,
        debug: true,
        platform: FakePlatform(
          initial: Uri.parse('https://acme.example.com/p?cmsh_click=$click'),
        ),
        storage: MemoryStorage()..values['launched'] = '1',
      );

      await client.start();
      await client.startupComplete;
      final link = await client.onLink.first;

      expect(link.isMatched, isTrue);
      expect(link.matchType, CmshMatchType.clickParam);
      expect(link.clickId, click);

      await client.track('view_item', {'sku': 'a1'});
      await client.identify('flutter-user', {
        'name': 'Sara',
        'email': 'sara@example.com',
      });
      await client.track('purchase', {'value': 25});
      await client.flush();

      expect(client.queueLength, 0);
    },
    skip: url == null || key == null || click == null
        ? 'Set CMSH_E2E_URL, CMSH_E2E_KEY and CMSH_E2E_CLICK'
        : false,
  );
}
