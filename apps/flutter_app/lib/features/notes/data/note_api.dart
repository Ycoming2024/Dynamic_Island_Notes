import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';
import '../domain/note.dart';

class NoteApi {
  NoteApi(this.client);

  final DioClient client;

  Future<List<Note>> fetchNotes({DateTime? updatedAfter}) async {
    final response = await client.dio.get('/notes', queryParameters: {
      if (updatedAfter != null)
        'updated_after': updatedAfter.toUtc().toIso8601String(),
      'limit': 200,
    });

    final raw = response.data;
    final data = raw is List ? raw : (raw['items'] as List? ?? <dynamic>[]);
    return data
        .map((e) => Note.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Note> createNote(
      {required String title, required String content}) async {
    final response = await client.dio
        .post('/notes', data: {'title': title, 'content': content});
    return Note.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<Note> updateNote(Note note) async {
    final response = await client.dio.put('/notes/${note.id}', data: {
      'title': note.title,
      'content': note.content,
      'is_pinned': note.isPinned,
    });
    return Note.fromJson(Map<String, dynamic>.from(response.data));
  }

  Future<void> deleteNote(String id) async {
    await client.dio.delete('/notes/$id');
  }
}
