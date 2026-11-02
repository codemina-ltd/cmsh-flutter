import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Everything that touches the OS, so the client can be tested without it.
abstract class CmshPlatform {
  bool get isIos;
  String get userAgentOs;
  Stream<Uri> get links;
  Future<Uri?> initialLink();
  Future<String?> installReferrer();
  Future<String?> clipboardText();
  Future<void> clearClipboard();
}

class DeviceCmshPlatform implements CmshPlatform {
  static const _channel = MethodChannel('cmsh_flutter');

  final AppLinks _appLinks = AppLinks();

  @override
  bool get isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  String get userAgentOs =>
      isIos ? 'iPhone; CPU iPhone OS like Mac OS X' : 'Linux; Android';

  @override
  Stream<Uri> get links => _appLinks.uriLinkStream;

  @override
  Future<Uri?> initialLink() => _appLinks.getInitialLink();

  @override
  Future<String?> installReferrer() async {
    if (isIos) {
      return null;
    }
    return _channel.invokeMethod<String>('getInstallReferrer');
  }

  @override
  Future<String?> clipboardText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  @override
  Future<void> clearClipboard() =>
      Clipboard.setData(const ClipboardData(text: ''));
}
