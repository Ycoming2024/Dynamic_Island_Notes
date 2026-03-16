class Reminder {
  final String id;
  final String title;
  final String? body;
  final DateTime dueAt;
  final String repeatRule;
  final String status;
  final DateTime? snoozeUntil;
  final int version;
  final DateTime updatedAt;

  const Reminder({
    required this.id,
    required this.title,
    this.body,
    required this.dueAt,
    required this.repeatRule,
    required this.status,
    this.snoozeUntil,
    required this.version,
    required this.updatedAt,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final snoozeRaw = json['snoozeUntil'] ?? json['snooze_until'];
    return Reminder(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      dueAt: DateTime.parse((json['dueAt'] ?? json['due_at']) as String),
      repeatRule: (json['repeatRule'] ?? json['repeat_rule'] ?? 'none') as String,
      status: (json['status'] ?? 'pending') as String,
      snoozeUntil: snoozeRaw == null ? null : DateTime.parse(snoozeRaw as String),
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
    );
  }
}
