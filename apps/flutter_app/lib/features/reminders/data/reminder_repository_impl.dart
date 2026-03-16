import 'dart:convert';

import '../../../core/storage/drift_db.dart' hide Reminder;
import '../domain/reminder.dart';
import '../domain/reminder_repository.dart';
import 'reminder_api.dart';

class ReminderRepositoryImpl implements ReminderRepository {
  ReminderRepositoryImpl({required this.api, required this.db});

  final ReminderApi api;
  final AppDatabase db;

  @override
  Future<List<Reminder>> list({DateTime? updatedAfter}) async {
    try {
      final remote = await api.fetchReminders(updatedAfter: updatedAfter);
      for (final reminder in remote) {
        await db.upsertReminderFromRemote({
          'id': reminder.id,
          'title': reminder.title,
          'body': reminder.body,
          'due_at': reminder.dueAt.toUtc().toIso8601String(),
          'repeat_rule': reminder.repeatRule,
          'status': reminder.status,
          'snooze_until': reminder.snoozeUntil?.toUtc().toIso8601String(),
          'version': reminder.version,
          'updated_at': reminder.updatedAt.toUtc().toIso8601String(),
        });
      }
      return remote;
    } catch (_) {
      final cached = await db.listLocalReminders(updatedAfter: updatedAfter);
      return cached
          .map(
            (e) => Reminder(
              id: e.id,
              title: e.title,
              body: e.body,
              dueAt: e.dueAt,
              repeatRule: e.repeatRule,
              status: e.status,
              snoozeUntil: e.snoozeUntil,
              version: e.version,
              updatedAt: e.updatedAt,
            ),
          )
          .toList();
    }
  }

  @override
  Future<Reminder> create(
      {required String title,
      required DateTime dueAt,
      String repeatRule = 'none'}) async {
    try {
      final created = await api.createReminder(
          title: title, dueAt: dueAt, repeatRule: repeatRule);
      await db.upsertReminderFromRemote({
        'id': created.id,
        'title': created.title,
        'body': created.body,
        'due_at': created.dueAt.toUtc().toIso8601String(),
        'repeat_rule': created.repeatRule,
        'status': created.status,
        'snooze_until': created.snoozeUntil?.toUtc().toIso8601String(),
        'version': created.version,
        'updated_at': created.updatedAt.toUtc().toIso8601String(),
      });
      return created;
    } catch (_) {
      final now = DateTime.now().toUtc();
      final local = Reminder(
        id: 'local-reminder-${now.microsecondsSinceEpoch}',
        title: title,
        body: null,
        dueAt: dueAt.toUtc(),
        repeatRule: repeatRule,
        status: 'pending',
        snoozeUntil: null,
        version: 1,
        updatedAt: now,
      );
      await db.upsertReminderFromRemote({
        'id': local.id,
        'title': local.title,
        'body': local.body,
        'due_at': local.dueAt.toIso8601String(),
        'repeat_rule': local.repeatRule,
        'status': local.status,
        'snooze_until': local.snoozeUntil?.toIso8601String(),
        'version': local.version,
        'updated_at': local.updatedAt.toIso8601String(),
      });
      await db.enqueuePendingChange(
        entityType: 'reminder',
        entityId: local.id,
        op: 'create',
        payload: jsonEncode({
          'title': local.title,
          'body': local.body,
          'due_at': local.dueAt.toIso8601String(),
          'repeat_rule': local.repeatRule,
        }),
        updatedAt: now,
      );
      return local;
    }
  }

  @override
  Future<void> snooze(String id, int minutes) async {
    try {
      await api.snooze(id, minutes);
    } catch (_) {
      final now = DateTime.now().toUtc();
      final snoozeUntil = now.add(Duration(minutes: minutes));
      await db.setReminderSnoozeLocal(
        id: id,
        snoozeUntil: snoozeUntil,
        updatedAt: now,
      );
      final reminder = await db.getLocalReminderById(id);
      if (reminder != null) {
        await db.enqueuePendingChange(
          entityType: 'reminder',
          entityId: id,
          op: 'update',
          payload: jsonEncode({
            'title': reminder.title,
            'body': reminder.body,
            'due_at': reminder.dueAt.toUtc().toIso8601String(),
            'repeat_rule': reminder.repeatRule,
            'status': reminder.status,
            'snooze_until': snoozeUntil.toIso8601String(),
          }),
          updatedAt: now,
        );
      }
    }
  }

  @override
  Future<void> done(String id) async {
    try {
      await api.done(id);
      await db.setReminderStatusLocal(id: id, status: 'done');
    } catch (_) {
      final now = DateTime.now().toUtc();
      await db.setReminderStatusLocal(
        id: id,
        status: 'done',
        updatedAt: now,
      );
      final reminder = await db.getLocalReminderById(id);
      if (reminder != null) {
        await db.enqueuePendingChange(
          entityType: 'reminder',
          entityId: id,
          op: 'update',
          payload: jsonEncode({
            'title': reminder.title,
            'body': reminder.body,
            'due_at': reminder.dueAt.toUtc().toIso8601String(),
            'repeat_rule': reminder.repeatRule,
            'status': 'done',
            'snooze_until': reminder.snoozeUntil?.toUtc().toIso8601String(),
          }),
          updatedAt: now,
        );
      }
    }
  }

  @override
  Future<void> remove(String id) async {
    try {
      await api.deleteReminder(id);
      await db.setReminderDeletedLocal(id: id);
    } catch (_) {
      final now = DateTime.now().toUtc();
      await db.setReminderDeletedLocal(id: id, updatedAt: now);
      await db.enqueuePendingChange(
        entityType: 'reminder',
        entityId: id,
        op: 'delete',
        payload: '{}',
        updatedAt: now,
      );
    }
  }
}
