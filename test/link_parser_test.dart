import 'package:cmsh_flutter/src/link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_doubles.dart';

void main() {
  group('clickIdFromUrl', () {
    test('reads the click', () {
      expect(
        clickIdFromUrl(Uri.parse('https://acme.com/p?cmsh_click=$clickA')),
        clickA,
      );
    });

    test('ignores a value that is not a click id', () {
      expect(
        clickIdFromUrl(Uri.parse('https://acme.com/p?cmsh_click=nope')),
        isNull,
      );
    });
  });

  group('clickIdFromReferrer', () {
    test('reads the click among other parameters', () {
      expect(clickIdFromReferrer('utm_source=x&cmsh_click=$clickA'), clickA);
    });

    test('ignores organic referrers', () {
      expect(clickIdFromReferrer('utm_source=google-play'), isNull);
    });
  });

  group('clickIdFromClipboard', () {
    test('reads a token', () {
      expect(clickIdFromClipboard('cmsh:$clickA'), clickA);
    });

    test('ignores whatever else the user copied', () {
      expect(clickIdFromClipboard('my password'), isNull);
      expect(clickIdFromClipboard('see cmsh:$clickA now'), isNull);
    });
  });

  group('pathFromUrl', () {
    test('removes the click and keeps other parameters', () {
      expect(
        pathFromUrl(Uri.parse('https://acme.com/p/1?ref=x&cmsh_click=$clickA')),
        '/p/1?ref=x',
      );
    });

    test('keeps the first segment of a URI-scheme link', () {
      expect(pathFromUrl(Uri.parse('acme://sale/1')), '/sale/1');
    });

    test('falls back to the root', () {
      expect(pathFromUrl(Uri.parse('https://acme.com')), '/');
    });
  });
}
