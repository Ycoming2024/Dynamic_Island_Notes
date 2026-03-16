import 'reminder.dart';

abstract class ReminderRepository {
  Future<List<Reminder>> list({DateTime? updatedAfter});
  Future<Reminder> create(
      {required String title, required DateTime dueAt, String repeatRule});
  Future<void> snooze(String id, int minutes);
  Future<void> done(String id);
  Future<void> remove(String id);
}
