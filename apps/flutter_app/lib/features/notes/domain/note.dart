class Note {
  final String id;
  final String title;
  final String content;
  final bool isPinned;
  final int version;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.isPinned,
    required this.version,
    required this.updatedAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      isPinned: (json['isPinned'] as bool?) ?? (json['is_pinned'] as bool?) ?? false,
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
    );
  }
}
