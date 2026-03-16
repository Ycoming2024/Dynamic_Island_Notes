import 'dart:convert';

import '../../../core/network/dio_client.dart';

class PullResult {
  PullResult({required this.changes, required this.nextSince});

  final List<Map<String, dynamic>> changes;
  final DateTime nextSince;
}

class SyncApi {
  SyncApi(this.client);

  final DioClient client;

  Future<void> pushChanges(List<Map<String, dynamic>> changes) async {
    await client.dio.post('/sync/push', data: {'changes': changes});
  }

  Future<PullResult> pullChanges(DateTime since) async {
    final response = await client.dio.get('/sync/pull', queryParameters: {
      'since': since.toUtc().toIso8601String(),
      'limit': 500,
    });

    final items = (response.data['changes'] as List?) ?? <dynamic>[];
    final parsed = items.map((e) {
      final map = Map<String, dynamic>.from(e);
      if (map['payload'] is String) {
        try {
          map['payload'] = jsonDecode(map['payload'] as String);
        } catch (_) {}
      }
      return map;
    }).toList();

    final nextRaw = response.data['next_since'] as String?;
    final nextSince = DateTime.tryParse(nextRaw ?? '') ?? since.toUtc();
    return PullResult(changes: parsed, nextSince: nextSince.toUtc());
  }

  Future<void> ack(DateTime since) async {
    await client.dio
        .post('/sync/ack', data: {'since': since.toUtc().toIso8601String()});
  }
}
