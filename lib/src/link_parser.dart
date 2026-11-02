/// Query parameter carrying the click on a redirected link.
const clickParam = 'cmsh_click';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _clipboardToken = RegExp(
  r'^cmsh:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
);

bool _isClickId(String? value) => value != null && _uuid.hasMatch(value);

/// The click in a delivered URL, if there is one.
String? clickIdFromUrl(Uri url) {
  final value = url.queryParameters[clickParam];
  return _isClickId(value) ? value : null;
}

/// The click in the Play Store referrer, such as `cmsh_click=<id>&utm=x`.
String? clickIdFromReferrer(String referrer) {
  try {
    final value = Uri.splitQueryString(referrer)[clickParam];
    return _isClickId(value) ? value : null;
  } on FormatException {
    return null;
  }
}

/// The click in a clipboard token. Anything else on the clipboard is ignored.
String? clickIdFromClipboard(String text) =>
    _clipboardToken.firstMatch(text.trim())?.group(1);

/// The in-app route for a URL, without the click parameter.
String pathFromUrl(Uri url) {
  final query = Map.of(url.queryParameters)..remove(clickParam);
  // A URI-scheme link keeps its first segment in the host: acme://sale/1.
  final isWeb = url.scheme == 'https' || url.scheme == 'http';
  final prefix = !isWeb && url.host.isNotEmpty ? '/${url.host}' : '';
  final path = '$prefix${url.path}';
  final route = path.isEmpty ? '/' : path;
  return query.isEmpty ? route : '$route?${Uri(queryParameters: query).query}';
}
