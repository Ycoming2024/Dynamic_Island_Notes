import 'dart:convert';

import '../../../core/storage/drift_db.dart' hide Note;
import '../domain/note.dart';
import '../domain/note_repository.dart';
import 'note_api.dart';

class NoteRepositoryImpl implements NoteRepository {
  NoteRepositoryImpl({required this.api, required this.db});

  final NoteApi api;
  final AppDatabase db;

  @override
  Future<List<Note>> list({DateTime? updatedAfter}) async {
    try {
      final remote = await api.fetchNotes(updatedAfter: updatedAfter);
      for (final note in remote) {
        await db.upsertNoteFromRemote({
          'id': note.id,
          'title': note.title,
          'content': note.content,
          'is_pinned': note.isPinned,
          'version': note.version,
          'updated_at': note.updatedAt.toUtc().toIso8601String(),
        });
      }
      return remote;
    } catch (_) {
      final cached = await db.listLocalNotes(updatedAfter: updatedAfter);
      return cached
          .map(
            (e) => Note(
              id: e.id,
              title: e.title,
              content: e.content,
              isPinned: e.isPinned,
              version: e.version,
              updatedAt: e.updatedAt,
            ),
          )
          .toList();
    }
  }

  @override
  Future<Note> create({required String title, required String content}) async {
    try {
      final created = await api.createNote(title: title, content: content);
      await db.upsertNoteFromRemote({
        'id': created.id,
        'title': created.title,
        'content': created.content,
        'is_pinned': created.isPinned,
        'version': created.version,
        'updated_at': created.updatedAt.toUtc().toIso8601String(),
      });
      return created;
    } catch (_) {
      final now = DateTime.now().toUtc();
      final local = Note(
        id: 'local-note-${now.microsecondsSinceEpoch}',
        title: title,
        content: content,
        isPinned: false,
        version: 1,
        updatedAt: now,
      );
      await db.upsertNoteFromRemote({
        'id': local.id,
        'title': local.title,
        'content': local.content,
        'is_pinned': local.isPinned,
        'version': local.version,
        'updated_at': local.updatedAt.toIso8601String(),
      });
      await db.enqueuePendingChange(
        entityType: 'note',
        entityId: local.id,
        op: 'create',
        payload: jsonEncode({
          'title': local.title,
          'content': local.content,
          'is_pinned': local.isPinned,
        }),
        updatedAt: now,
      );
      return local;
    }
  }

  @override
  Future<Note> update(Note note) async {
    try {
      final updated = await api.updateNote(note);
      await db.upsertNoteFromRemote({
        'id': updated.id,
        'title': updated.title,
        'content': updated.content,
        'is_pinned': updated.isPinned,
        'version': updated.version,
        'updated_at': updated.updatedAt.toUtc().toIso8601String(),
      });
      return updated;
    } catch (_) {
      final now = DateTime.now().toUtc();
      final local = Note(
        id: note.id,
        title: note.title,
        content: note.content,
        isPinned: note.isPinned,
        version: note.version + 1,
        updatedAt: now,
      );
      await db.upsertNoteFromRemote({
        'id': local.id,
        'title': local.title,
        'content': local.content,
        'is_pinned': local.isPinned,
        'version': local.version,
        'updated_at': local.updatedAt.toIso8601String(),
      });
      await db.enqueuePendingChange(
        entityType: 'note',
        entityId: local.id,
        op: 'update',
        payload: jsonEncode({
          'title': local.title,
          'content': local.content,
          'is_pinned': local.isPinned,
        }),
        updatedAt: now,
      );
      return local;
    }
  }

  @override
  Future<void> remove(String id) async {
    try {
      await api.deleteNote(id);
      await db.setNoteDeletedLocal(id: id);
    } catch (_) {
      final now = DateTime.now().toUtc();
      await db.setNoteDeletedLocal(id: id, updatedAt: now);
      await db.enqueuePendingChange(
        entityType: 'note',
        entityId: id,
        op: 'delete',
        payload: '{}',
        updatedAt: now,
      );
    }
  }
}
