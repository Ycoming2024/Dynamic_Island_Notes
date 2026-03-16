import 'dart:convert';

class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.text,
    required this.done,
    this.progressCurrent,
    this.progressTotal,
    this.progressUnit,
  });

  final String id;
  final String text;
  final bool done;
  final int? progressCurrent;
  final int? progressTotal;
  final String? progressUnit;

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? done,
    int? progressCurrent,
    int? progressTotal,
    String? progressUnit,
    bool clearProgressCurrent = false,
    bool clearProgressTotal = false,
    bool clearProgressUnit = false,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      done: done ?? this.done,
      progressCurrent: clearProgressCurrent
          ? null
          : (progressCurrent ?? this.progressCurrent),
      progressTotal:
          clearProgressTotal ? null : (progressTotal ?? this.progressTotal),
      progressUnit:
          clearProgressUnit ? null : (progressUnit ?? this.progressUnit),
    );
  }
}

class NoteContentData {
  NoteContentData({
    required this.text,
    required this.checklist,
  });

  final String text;
  final List<ChecklistItem> checklist;
}

class NoteContentCodec {
  static const _format = 'nb_note_v1';

  static NoteContentData decode(String raw) {
    if (raw.trim().isEmpty) {
      return NoteContentData(text: '', checklist: const []);
    }

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['format'] != _format) {
        return NoteContentData(text: raw, checklist: const []);
      }

      final text = (map['text'] as String?) ?? '';
      final checklistRaw = (map['checklist'] as List?) ?? const [];
      final checklist = checklistRaw
          .whereType<Map>()
          .map(
            (e) {
              final current = _toIntOrNull(e['progressCurrent'] ?? e['current']);
              final total = _toIntOrNull(e['progressTotal'] ?? e['total']);
              return ChecklistItem(
              id: (e['id'] as String?) ??
                  'item-${DateTime.now().microsecondsSinceEpoch}',
              text: (e['text'] as String?) ?? '',
              done: (e['done'] as bool?) ?? false,
              progressCurrent: current,
              progressTotal: total,
              progressUnit: (e['progressUnit'] as String?) ?? (e['unit'] as String?),
            );
            },
          )
          .toList();
      return NoteContentData(text: text, checklist: checklist);
    } catch (_) {
      return NoteContentData(text: raw, checklist: const []);
    }
  }

  static String encode({
    required String text,
    required List<ChecklistItem> checklist,
  }) {
    final cleanItems = checklist
        .map((e) => e.copyWith(text: e.text.trim()))
        .where((e) => e.text.isNotEmpty)
        .map(
          (e) {
            final map = <String, Object>{
            'id': e.id,
            'text': e.text,
            'done': e.done,
            };
            if (e.progressCurrent != null) {
              map['progressCurrent'] = e.progressCurrent!;
            }
            if (e.progressTotal != null) {
              map['progressTotal'] = e.progressTotal!;
            }
            if (e.progressUnit != null && e.progressUnit!.trim().isNotEmpty) {
              map['progressUnit'] = e.progressUnit!;
            }
            return map;
          },
        )
        .toList();

    if (cleanItems.isEmpty) return text;

    return jsonEncode({
      'format': _format,
      'text': text,
      'checklist': cleanItems,
    });
  }

  static int? _toIntOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed;
    }
    return null;
  }
}
