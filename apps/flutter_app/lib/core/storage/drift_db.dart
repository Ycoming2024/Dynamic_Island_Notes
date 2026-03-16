import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'drift_db.g.dart';

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Reminders extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get body => text().nullable()();
  DateTimeColumn get dueAt => dateTime()();
  TextColumn get repeatRule => text().withDefault(const Constant('none'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get snoozeUntil => dateTime().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PendingChanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();
}

@DriftDatabase(tables: [Notes, Reminders, PendingChanges])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<List<PendingChange>> listPendingChanges({int limit = 200}) {
    return (select(pendingChanges)
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)])
          ..limit(limit))
        .get();
  }

  Future<void> removePendingChanges(List<int> ids) async {
    if (ids.isEmpty) return;
    await (delete(pendingChanges)..where((t) => t.id.isIn(ids))).go();
  }

  Future<int> countPendingChanges() async {
    final expr = pendingChanges.id.count();
    final row =
        await (selectOnly(pendingChanges)..addColumns([expr])).getSingle();
    return row.read(expr) ?? 0;
  }

  Future<void> enqueuePendingChange({
    required String entityType,
    required String entityId,
    required String op,
    required String payload,
    DateTime? updatedAt,
  }) async {
    await into(pendingChanges).insert(
      PendingChangesCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        op: op,
        payload: payload,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> upsertNoteFromRemote(Map<String, dynamic> payload) async {
    await into(notes).insertOnConflictUpdate(
      NotesCompanion.insert(
        id: payload['id'] as String,
        title: Value((payload['title'] as String?) ?? ''),
        content: Value((payload['content'] as String?) ?? ''),
        isPinned: Value((payload['isPinned'] as bool?) ??
            (payload['is_pinned'] as bool?) ??
            false),
        isDeleted: Value((payload['isDeleted'] as bool?) ??
            (payload['is_deleted'] as bool?) ??
            false),
        version: Value((payload['version'] as num?)?.toInt() ?? 1),
        updatedAt: DateTime.parse(
            (payload['updatedAt'] ?? payload['updated_at']) as String),
      ),
    );
  }

  Future<void> upsertReminderFromRemote(Map<String, dynamic> payload) async {
    final snoozeRaw = payload['snoozeUntil'] ?? payload['snooze_until'];
    await into(reminders).insertOnConflictUpdate(
      RemindersCompanion.insert(
        id: payload['id'] as String,
        noteId: Value(
            payload['noteId'] as String? ?? payload['note_id'] as String?),
        title: payload['title'] as String,
        body: Value(payload['body'] as String?),
        dueAt:
            DateTime.parse((payload['dueAt'] ?? payload['due_at']) as String),
        repeatRule: Value((payload['repeatRule'] ??
            payload['repeat_rule'] ??
            'none') as String),
        status: Value((payload['status'] ?? 'pending') as String),
        snoozeUntil: Value(
            snoozeRaw == null ? null : DateTime.parse(snoozeRaw as String)),
        isDeleted: Value((payload['isDeleted'] as bool?) ??
            (payload['is_deleted'] as bool?) ??
            false),
        version: Value((payload['version'] as num?)?.toInt() ?? 1),
        updatedAt: DateTime.parse(
            (payload['updatedAt'] ?? payload['updated_at']) as String),
      ),
    );
  }

  Future<List<Note>> listLocalNotes({DateTime? updatedAfter, int limit = 200}) {
    final query = select(notes)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(limit);
    if (updatedAfter != null) {
      query
          .where((t) => t.updatedAt.isBiggerOrEqualValue(updatedAfter.toUtc()));
    }
    return query.get();
  }

  Future<List<Reminder>> listLocalReminders(
      {DateTime? updatedAfter, int limit = 200}) {
    final query = select(reminders)
      ..where((t) => t.isDeleted.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.dueAt)])
      ..limit(limit);
    if (updatedAfter != null) {
      query
          .where((t) => t.updatedAt.isBiggerOrEqualValue(updatedAfter.toUtc()));
    }
    return query.get();
  }

  Future<Reminder?> getLocalReminderById(String id) {
    return (select(reminders)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> setReminderSnoozeLocal({
    required String id,
    required DateTime snoozeUntil,
    DateTime? updatedAt,
  }) async {
    await (update(reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        snoozeUntil: Value(snoozeUntil),
        updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setReminderStatusLocal({
    required String id,
    required String status,
    DateTime? updatedAt,
  }) async {
    await (update(reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        status: Value(status),
        updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setReminderDeletedLocal({
    required String id,
    DateTime? updatedAt,
  }) async {
    await (update(reminders)..where((t) => t.id.equals(id))).write(
      RemindersCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setNoteDeletedLocal({
    required String id,
    DateTime? updatedAt,
  }) async {
    await (update(notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(updatedAt ?? DateTime.now().toUtc()),
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'notes_bridge.db'));
    return NativeDatabase.createInBackground(file);
  });
}
