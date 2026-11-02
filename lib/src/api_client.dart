import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the queue should do with a request.
enum ApiOutcome {
  /// Accepted. Remove it.
  success,

  /// Network failure, 429 or 5xx. Keep it and try again later.
  retry,

  /// Any other 4xx will fail forever. Remove it.
  drop,
}

class ApiResult {
  const ApiResult(this.outcome, {this.body, this.statusCode, this.message});

  final ApiOutcome outcome;
  final Map<String, dynamic>? body;
  final int? statusCode;
  final String? message;
}

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.sdkKey,
    required this.userAgent,
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String sdkKey;
  final String userAgent;
  final Duration timeout;
  final http.Client _client;

  Future<ApiResult> post(String path, Map<String, dynamic> body) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$baseUrl/v1/sdk/$path'),
            headers: {
              'Content-Type': 'application/json',
              'X-CMSH-Key': sdkKey,
              'User-Agent': userAgent,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return ApiResult(
          ApiOutcome.success,
          statusCode: status,
          body: _decode(response.body),
        );
      }
      return ApiResult(
        status == 429 || status >= 500 ? ApiOutcome.retry : ApiOutcome.drop,
        statusCode: status,
        // The body never echoes traits, but keep logs to the status alone.
        message: 'POST $path returned $status',
      );
    } on Exception catch (error) {
      return ApiResult(
        ApiOutcome.retry,
        message: 'POST $path failed: ${error.runtimeType}',
      );
    }
  }

  void close() => _client.close();

  Map<String, dynamic>? _decode(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map<String, dynamic> ? value : null;
    } on FormatException {
      return null;
    }
  }
}
