/// How a link reached the app.
enum CmshMatchType {
  /// A `cmsh.io` link redirected to a link on your own domain.
  clickParam('click_param'),

  /// A custom-domain link that the OS opened directly.
  direct('direct'),

  /// Android: the click survived a Play Store install.
  installReferrer('install_referrer'),

  /// iOS: the click survived an App Store install through the clipboard.
  clipboard('clipboard');

  const CmshMatchType(this.value);

  /// The name used by the API.
  final String value;

  static CmshMatchType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) {
        return type;
      }
    }
    return null;
  }
}

/// A CMSH link that opened the app, from [Cmsh.onLink].
class CmshLink {
  const CmshLink({
    required this.path,
    this.url,
    this.data = const {},
    this.clickId,
    this.linkId,
    this.matchType,
    this.isDeferred = false,
    this.isMatched = false,
  });

  /// The route to open, such as `/product/1`.
  final String path;

  /// The URL the OS delivered. Null for deferred links.
  final Uri? url;

  /// Custom data set on the short link. Empty when [isMatched] is false.
  final Map<String, dynamic> data;

  final String? clickId;
  final String? linkId;
  final CmshMatchType? matchType;

  /// True when the link arrived through an install, not a direct open.
  final bool isDeferred;

  /// False when the server could not be reached or didn't recognise the link.
  /// [path] still comes from the URL, so the app can route normally.
  final bool isMatched;

  @override
  String toString() =>
      'CmshLink(path: $path, matched: $isMatched, type: ${matchType?.value})';
}
