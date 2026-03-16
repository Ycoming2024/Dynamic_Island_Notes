import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/reminder.dart';

class ReminderApi {
  ReminderApi(this.client);

  final DioClient client;

  Future<List<Reminder>> fetchReminders({DateTime? updatedAfter}) async {
    final response = await client.dio.get('/reminders', queryParameters: {
      if (updatedAfter != null)
        'updated_after': updatedAfter.toUtc().toIso8601String(),
      'limit': 200,
    });

    final raw = response.data;
    final data = raw is List ? raw : (raw['items'] as List? ?? <dynamic>[]);
    return data
        .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Reminder> createReminder({
    required String title,
    required DateTime dueAt,
    String repeatRule = 'none',
  }) async {
    final response = await client.dio.post('/reminders', data: {
      'title': title,
      'due_at': dueAt.toUtc().toIso8601String(),
      'repeat_rule': repeatRule,
    });
    return Reminder.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<void> snooze(String id, int minutes) async {
    await client.dio.post('/reminders/$id/snooze', data: {'minutes': minutes});
  }

  Future<void> done(String id) async {
    await client.dio.post('/reminders/$id/done');
  }

  Future<void> deleteReminder(String id) async {
    await client.dio.delete('/reminders/$id');
  }
}
