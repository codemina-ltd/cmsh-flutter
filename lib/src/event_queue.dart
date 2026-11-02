import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'api_client.dart';
import 'storage.dart';

const _storageKey = 'queue';

/// Oldest items go first once this is reached, so the queue can't grow forever.
const maxQueueLength = 1000;
const maxBatchSize = 100;

/// One pending API call. Survives restarts as JSON.
class QueueItem {
  const QueueItem(this.path, this.body);

  factory QueueItem.fromJson(Map<String, dynamic> json) =>
      QueueItem(json['path'] as String, json['body'] as Map<String, dynamic>);

  final String path;
  final Map<String, dynamic> body;

  Map<String, dynamic> toJson() => {'path': path, 'body': body};
}

/// Persistent, ordered delivery queue. Order matters: `identify` must land
/// before the events that follow it. Payloads carry client-generated ids, so
/// a retry after a lost response can't double count on the server.
class EventQueue {
  EventQueue({
    required this.api,
    required this.storage,
    required this.onLog,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 5),
  });

  final ApiClient api;
  final CmshStorage storage;
  final void Function(String message) onLog;
  final Duration baseDelay;
  final Duration maxDelay;

  final List<QueueItem> _items = [];
  Future<void>? _flush;
  int _failures = 0;
  Timer? _retry;

  int get length => _items.length;

  Future<void> load() async {
    final stored = await storage.read(_storageKey);
    if (stored == null) {
      return;
    }
    try {
      final list = jsonDecode(stored) as List<dynamic>;
      _items.addAll(
        list.map((item) => QueueItem.fromJson(item as Map<String, dynamic>)),
      );
    } on Object {
      // A corrupt queue must not stop the app. Only this data is lost.
      await storage.delete(_storageKey);
    }
  }

  Future<void> add(QueueItem item) async {
    _items.add(item);
    if (_items.length > maxQueueLength) {
      _items.removeRange(0, _items.length - maxQueueLength);
    }
    await _persist();
  }

  Future<void> clear() async {
    _items.clear();
    _retry?.cancel();
    await storage.delete(_storageKey);
  }

  /// Sends everything it can. Stops at the first retryable failure. Callers
  /// that arrive mid-flush wait for it, and the loop picks up their items.
  Future<void> flush() =>
      _flush ??= _deliver().whenComplete(() => _flush = null);

  Future<void> _deliver() async {
    while (_items.isNotEmpty) {
      final count = _batchLength();
      final result = await api.post(_items.first.path, _combinedBody(count));
      if (result.outcome == ApiOutcome.retry) {
        _scheduleRetry();
        onLog(result.message ?? 'Delivery failed');
        return;
      }
      if (result.outcome == ApiOutcome.drop) {
        onLog(result.message ?? 'Delivery refused');
      }
      _failures = 0;
      _items.removeRange(0, min(count, _items.length));
      await _persist();
    }
  }

  void dispose() => _retry?.cancel();

  /// Runs of events for one device go in a single request.
  int _batchLength() {
    final first = _items.first;
    if (first.path != 'events') {
      return 1;
    }
    var count = 1;
    var size = (first.body['events'] as List).length;
    while (count < _items.length) {
      final next = _items[count];
      final nextSize = next.path == 'events'
          ? (next.body['events'] as List).length
          : 0;
      if (next.path != 'events' ||
          next.body['deviceId'] != first.body['deviceId'] ||
          size + nextSize > maxBatchSize) {
        break;
      }
      size += nextSize;
      count += 1;
    }
    return count;
  }

  Map<String, dynamic> _combinedBody(int count) {
    final first = _items.first;
    if (first.path != 'events' || count == 1) {
      return first.body;
    }
    return {
      ...first.body,
      'events': [
        for (final item in _items.take(count)) ...(item.body['events'] as List),
      ],
    };
  }

  void _scheduleRetry() {
    _failures += 1;
    final seconds = baseDelay.inMilliseconds * pow(2, _failures - 1);
    final delay = Duration(
      milliseconds: min(seconds.toInt(), maxDelay.inMilliseconds),
    );
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(_safeFlush()));
  }

  Future<void> _safeFlush() async {
    try {
      await flush();
    } on Object catch (error) {
      onLog('Flush failed: ${error.runtimeType}');
    }
  }

  Future<void> _persist() => storage.write(
    _storageKey,
    jsonEncode(_items.map((item) => item.toJson()).toList()),
  );
}
