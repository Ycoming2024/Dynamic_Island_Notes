import 'note.dart';

abstract class NoteRepository {
  Future<List<Note>> list({DateTime? updatedAfter});
  Future<Note> create({required String title, required String content});
  Future<Note> update(Note note);
  Future<void> remove(String id);
}
