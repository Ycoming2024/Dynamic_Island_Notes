import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/di.dart';
import '../../../shared/widgets/pressable_scale.dart';
import '../../reminders/presentation/reminders_page.dart';
import '../data/note_content_codec.dart';
import '../domain/note.dart';

enum _NoteFilter { all, pinned, checklist }

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> _notes = const [];
  bool _loading = true;
  int _pendingCount = 0;
  String _query = '';
  _NoteFilter _filter = _NoteFilter.all;
  Timer? _autoSyncTimer;

  double _progressValue(ChecklistItem item) {
    final total = item.progressTotal;
    if (total == null || total <= 0) return item.done ? 1 : 0;
    final current = (item.progressCurrent ?? 0).clamp(0, total);
    return current / total;
  }

  String _unitSuffix(String? unit) {
    switch (unit) {
      case 'chapter':
        return 'ch';
      case 'page':
        return 'p';
      default:
        return '';
    }
  }

  void _upsertLocalNote(Note note) {
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx < 0) {
      _notes = [note, ..._notes];
      return;
    }
    final updated = [..._notes];
    updated[idx] = note;
    _notes = updated;
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _autoSyncTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _reload(silent: true),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final count = await AppDI.syncManager.pendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      try {
        await AppDI.syncManager.syncOnce();
      } catch (_) {}
      final notes = await AppDI.noteRepo.list();
      if (!mounted) return;
      setState(() => _notes = notes);
      await _refreshPendingCount();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backend is unreachable')),
      );
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _forceSync() async {
    try {
      await AppDI.syncManager.forceFullSync();
      await _reload(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full sync completed')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full sync failed')),
      );
    } finally {}
  }

  Future<void> _showNoteEditor({Note? note}) async {
    final result = await Navigator.of(context).push<_NoteEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _NoteEditorPage(note: note),
      ),
    );

    if (result == null) return;

    if (note == null) {
      final temp = Note(
        id: 'ui-note-${DateTime.now().microsecondsSinceEpoch}',
        title: result.title,
        content: result.content,
        isPinned: false,
        version: 1,
        updatedAt: DateTime.now().toUtc(),
      );
      setState(() {
        _notes = [temp, ..._notes];
      });
      Future<void>(() async {
        final created = await AppDI.noteRepo.create(
          title: result.title,
          content: result.content,
        );
        if (!mounted) return;
        setState(() {
          _notes = _notes.map((n) => n.id == temp.id ? created : n).toList();
        });
        if (created.id.startsWith('local-note-')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Saved offline, sync queued')),
          );
        }
        await _reload(silent: true);
      });
      return;
    } else {
      final localUpdated = Note(
        id: note.id,
        title: result.title,
        content: result.content,
        isPinned: note.isPinned,
        version: note.version + 1,
        updatedAt: DateTime.now().toUtc(),
      );
      setState(() => _upsertLocalNote(localUpdated));
      Future<void>(() async {
        await AppDI.noteRepo.update(localUpdated);
        if (!mounted) return;
        await _reload(silent: true);
      });
      return;
    }

    await _reload(silent: true);
  }

  Future<void> _openReminders() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RemindersPage()),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open reminders page')),
      );
    }
  }

  Future<void> _toggleChecklist(Note note, ChecklistItem item) async {
    final parsed = NoteContentCodec.decode(note.content);
    final updated = parsed.checklist
        .map((e) => e.id == item.id ? e.copyWith(done: !e.done) : e)
        .toList();
    final localUpdated = Note(
      id: note.id,
      title: note.title,
      content: NoteContentCodec.encode(text: parsed.text, checklist: updated),
      isPinned: note.isPinned,
      version: note.version + 1,
      updatedAt: DateTime.now().toUtc(),
    );

    setState(() {
      _notes = _notes.map((n) => n.id == note.id ? localUpdated : n).toList();
    });

    Future<void>(() async {
      try {
        await AppDI.noteRepo.update(localUpdated);
      } finally {
        if (mounted) {
          await _reload(silent: true);
        }
      }
    });
  }

  Future<void> _togglePinned(Note note) async {
    final localUpdated = Note(
      id: note.id,
      title: note.title,
      content: note.content,
      isPinned: !note.isPinned,
      version: note.version + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() => _upsertLocalNote(localUpdated));
    Future<void>(() async {
      await AppDI.noteRepo.update(localUpdated);
      if (!mounted) return;
      await _reload(silent: true);
    });
  }

  Future<void> _confirmDeleteNote(Note note) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text(
            '"${note.title.isEmpty ? '(Untitled)' : note.title}" will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );

    if (yes != true) return;
    setState(() {
      _notes = _notes.where((n) => n.id != note.id).toList();
    });
    await AppDI.noteRepo.remove(note.id);
    if (!mounted) return;
    await _reload(silent: true);
  }

  Widget _pendingChip() {
    final hasPending = _pendingCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: hasPending ? const Color(0xFFFFEEE6) : const Color(0xFFEAF8EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        hasPending ? 'Pending $_pendingCount' : 'Synced',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: hasPending ? const Color(0xFFB54708) : const Color(0xFF027A48),
        ),
      ),
    );
  }

  List<Note> get _visibleNotes {
    final query = _query.trim().toLowerCase();
    final filtered = _notes.where((note) {
      final parsed = NoteContentCodec.decode(note.content);
      final byFilter = switch (_filter) {
        _NoteFilter.all => true,
        _NoteFilter.pinned => note.isPinned,
        _NoteFilter.checklist => parsed.checklist.isNotEmpty,
      };
      if (!byFilter) return false;
      if (query.isEmpty) return true;

      final checklistText =
          parsed.checklist.map((e) => e.text.toLowerCase()).join(' ');
      return note.title.toLowerCase().contains(query) ||
          parsed.text.toLowerCase().contains(query) ||
          checklistText.contains(query);
    }).toList();

    filtered.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          _pendingChip(),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _reload(silent: true),
            icon: const Icon(CupertinoIcons.refresh_thick),
          ),
          IconButton(
            onPressed: _forceSync,
            icon: const Icon(CupertinoIcons.arrow_2_circlepath),
          ),
          IconButton(
            onPressed: _openReminders,
            icon: const Icon(CupertinoIcons.bell),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 1.5),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Search notes and checklist',
                    prefixIcon: Icon(CupertinoIcons.search),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<_NoteFilter>(
                  groupValue: _filter,
                  onValueChanged: (v) {
                    if (v == null) return;
                    setState(() => _filter = v);
                  },
                  children: const {
                    _NoteFilter.all: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('All'),
                    ),
                    _NoteFilter.pinned: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('Pinned'),
                    ),
                    _NoteFilter.checklist: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('Checklist'),
                    ),
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _visibleNotes.isEmpty
                  ? Center(
                      key: const ValueKey('notes-empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No notes yet'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => _showNoteEditor(),
                            icon: const Icon(CupertinoIcons.add),
                            label: const Text('Create first note'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      key: const ValueKey('notes-list'),
                      onRefresh: () => _reload(silent: true),
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                        itemCount: _visibleNotes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final note = _visibleNotes[i];
                          final parsed = NoteContentCodec.decode(note.content);
                          final total = parsed.checklist.length;
                          final done =
                              parsed.checklist.where((e) => e.done).length;

                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: TweenAnimationBuilder<double>(
                              key: ValueKey(note.id),
                              tween: Tween(begin: 0, end: 1),
                              duration: Duration(
                                milliseconds:
                                    160 + ((i * 30).clamp(0, 180) as int),
                              ),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Transform.translate(
                                  offset: Offset(0, (1 - value) * 8),
                                  child: Opacity(opacity: value, child: child),
                                );
                              },
                              child: PressableScale(
                                onTap: () => _showNoteEditor(note: note),
                                onLongPress: () => _confirmDeleteNote(note),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              note.title.isEmpty
                                                  ? '(Untitled)'
                                                  : note.title,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip:
                                                note.isPinned ? 'Unpin' : 'Pin',
                                            onPressed: () =>
                                                _togglePinned(note),
                                            icon: Icon(
                                              note.isPinned
                                                  ? CupertinoIcons.pin_fill
                                                  : CupertinoIcons.pin,
                                              size: 18,
                                              color: note.isPinned
                                                  ? const Color(0xFFFB8500)
                                                  : const Color(0xFF8C8C96),
                                            ),
                                          ),
                                          if (total > 0)
                                            Text(
                                              '$done/$total',
                                              style: const TextStyle(
                                                color: Color(0xFF57606A),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (parsed.text.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          parsed.text,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF4A4A54),
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                      if (parsed.checklist.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        ...parsed.checklist.map(
                                          (item) => InkWell(
                                            onTap: () =>
                                                _toggleChecklist(note, item),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 3),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        item.done
                                                            ? CupertinoIcons
                                                                .check_mark_circled_solid
                                                            : CupertinoIcons
                                                                .circle,
                                                        size: 18,
                                                        color: item.done
                                                            ? const Color(
                                                                0xFF34C759)
                                                            : const Color(
                                                                0xFF8C8C96),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          item.text,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            decoration: item
                                                                    .done
                                                                ? TextDecoration
                                                                    .lineThrough
                                                                : null,
                                                          ),
                                                        ),
                                                      ),
                                                      if (item.progressTotal !=
                                                              null &&
                                                          item.progressTotal! >
                                                              0)
                                                        Text(
                                                          '${item.progressCurrent ?? 0}${_unitSuffix(item.progressUnit)}/${item.progressTotal}${_unitSuffix(item.progressUnit)}',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            color: Color(
                                                                0xFF6B7280),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (item.progressTotal !=
                                                          null &&
                                                      item.progressTotal! > 0)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              left: 26, top: 6),
                                                      child:
                                                          LinearProgressIndicator(
                                                        value: _progressValue(
                                                            item),
                                                        minHeight: 5,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(99),
                                                        backgroundColor:
                                                            const Color(
                                                                0xFFE5E7EB),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openReminders,
                  icon: const Icon(CupertinoIcons.bell),
                  label: const Text('Reminders'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showNoteEditor(),
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('New Note'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteEditorResult {
  const _NoteEditorResult({required this.title, required this.content});

  final String title;
  final String content;
}

class _ChecklistDraft {
  _ChecklistDraft({
    required this.id,
    required this.done,
    required String text,
    int? current,
    int? total,
    String? unit,
  })  : controller = TextEditingController(text: text),
        currentCtrl =
            TextEditingController(text: current == null ? '' : '$current'),
        totalCtrl = TextEditingController(text: total == null ? '' : '$total'),
        unit = unit;

  final String id;
  bool done;
  final TextEditingController controller;
  final TextEditingController currentCtrl;
  final TextEditingController totalCtrl;
  String? unit;

  factory _ChecklistDraft.empty() {
    final id = 'item-${DateTime.now().microsecondsSinceEpoch}';
    return _ChecklistDraft(id: id, done: false, text: '');
  }

  factory _ChecklistDraft.fromItem(ChecklistItem item) {
    return _ChecklistDraft(
      id: item.id,
      done: item.done,
      text: item.text,
      current: item.progressCurrent,
      total: item.progressTotal,
      unit: item.progressUnit,
    );
  }

  ChecklistItem toItem() {
    final current = int.tryParse(currentCtrl.text.trim());
    final total = int.tryParse(totalCtrl.text.trim());
    return ChecklistItem(
      id: id,
      text: controller.text,
      done: done,
      progressCurrent: current,
      progressTotal: total,
      progressUnit: unit,
    );
  }

  void dispose() {
    controller.dispose();
    currentCtrl.dispose();
    totalCtrl.dispose();
  }
}

class _NoteEditorPage extends StatefulWidget {
  const _NoteEditorPage({required this.note});

  final Note? note;

  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final List<_ChecklistDraft> _items;
  late final String _initialTitle;
  late final String _initialContent;

  String _unitLabel(String? unit) {
    switch (unit) {
      case 'chapter':
        return 'Chapter';
      case 'page':
        return 'Page';
      default:
        return 'Progress';
    }
  }

  @override
  void initState() {
    super.initState();
    final parsed = NoteContentCodec.decode(widget.note?.content ?? '');
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _bodyCtrl = TextEditingController(text: parsed.text);
    _items = parsed.checklist.map((e) => _ChecklistDraft.fromItem(e)).toList();
    _initialTitle = (widget.note?.title ?? '').trim();
    _initialContent = widget.note?.content ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  String _buildContent() {
    final checklist = _items.map((e) => e.toItem()).toList();
    return NoteContentCodec.encode(
      text: _bodyCtrl.text,
      checklist: checklist,
    );
  }

  void _save() {
    final content = _buildContent();
    Navigator.of(context).pop(
      _NoteEditorResult(
        title: _titleCtrl.text.trim(),
        content: content,
      ),
    );
  }

  bool get _canSave {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final hasChecklistText =
        _items.any((e) => e.controller.text.trim().isNotEmpty);
    return title.isNotEmpty || body.isNotEmpty || hasChecklistText;
  }

  void _autoSaveAndPop() {
    final title = _titleCtrl.text.trim();
    final content = _buildContent();

    if (!_canSave) {
      Navigator.of(context).pop();
      return;
    }

    final unchanged = title == _initialTitle && content == _initialContent;
    if (unchanged) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.of(context).pop(
      _NoteEditorResult(
        title: title,
        content: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _autoSaveAndPop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F7),
        appBar: AppBar(
          title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
          leading: TextButton(
            onPressed: _autoSaveAndPop,
            child: const Text('Back'),
          ),
          leadingWidth: 76,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _editorSection(
              title: 'Title',
              child: TextField(
                controller: _titleCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Enter title'),
              ),
            ),
            const SizedBox(height: 12),
            _editorSection(
              title: 'Description',
              child: TextField(
                controller: _bodyCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 1,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Add details for this note',
                ),
              ),
            ),
            const SizedBox(height: 12),
            _editorSection(
              title: 'Checklist',
              trailing: TextButton.icon(
                onPressed: () =>
                    setState(() => _items.add(_ChecklistDraft.empty())),
                icon: const Icon(CupertinoIcons.add, size: 16),
                label: const Text('Add item'),
              ),
              child: Column(
                children: [
                  if (_items.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'No checklist items yet',
                        style: TextStyle(color: Color(0xFF7A7A84)),
                      ),
                    ),
                  ..._items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    final current =
                        int.tryParse(item.currentCtrl.text.trim()) ?? 0;
                    final total = int.tryParse(item.totalCtrl.text.trim());
                    final showProgress = total != null && total > 0;
                    final progressValue =
                        showProgress ? (current.clamp(0, total!) / total) : 0.0;
                    final suffix = item.unit == 'chapter'
                        ? ' ch'
                        : item.unit == 'page'
                            ? ' p'
                            : '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: item.done,
                                  onChanged: (v) =>
                                      setState(() => item.done = v ?? false),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: item.controller,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      labelText: 'Task',
                                      hintText: 'e.g. Chapter 3 practice',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      item.dispose();
                                      _items.removeAt(i);
                                    });
                                  },
                                  icon: const Icon(
                                    CupertinoIcons.delete,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 12, right: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: item.currentCtrl,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        labelText:
                                            'Current ${_unitLabel(item.unit)}',
                                        hintText: '12',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    '/',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: item.totalCtrl,
                                      keyboardType: TextInputType.number,
                                      onChanged: (_) => setState(() {}),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        labelText:
                                            'Total ${_unitLabel(item.unit)}',
                                        hintText: '40',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding:
                                  const EdgeInsets.only(left: 12, right: 8),
                              child: Row(
                                children: [
                                  _miniUnitChip(
                                    label: 'Chapter',
                                    selected: item.unit == 'chapter',
                                    onTap: () => setState(
                                      () => item.unit = 'chapter',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _miniUnitChip(
                                    label: 'Page',
                                    selected: item.unit == 'page',
                                    onTap: () => setState(
                                      () => item.unit = 'page',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (showProgress) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 12,
                                  right: 8,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${current.clamp(0, total)}$suffix/$total$suffix',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    LinearProgressIndicator(
                                      value: progressValue,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(999),
                                      backgroundColor: const Color(0xFFE5E7EB),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editorSection({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _miniUnitChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0A84FF) : const Color(0xFFECEFF5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF4B5563),
          ),
        ),
      ),
    );
  }
}
