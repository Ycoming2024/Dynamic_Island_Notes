import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/di.dart';
import '../../../core/notifications/desktop_island.dart';
import '../../../core/notifications/desktop_reminder_notifier.dart';
import '../../../core/notifications/mobile_notifications.dart';
import '../../../shared/widgets/pressable_scale.dart';
import '../domain/reminder.dart';

enum _ReminderFilter { all, active, done, overdue }

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});

  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  List<Reminder> _reminders = const [];
  bool _loading = true;
  int _pendingCount = 0;
  String _query = '';
  _ReminderFilter _filter = _ReminderFilter.all;
  Timer? _autoSyncTimer;
  final bool _enableDebugPanel = kDebugMode;

  @override
  void initState() {
    super.initState();
    MobileNotifications.instance.ensurePermissions();
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
      final reminders = await AppDI.reminderRepo.list();
      for (final reminder in reminders) {
        if (reminder.status == 'done') {
          await MobileNotifications.instance.cancelReminder(reminder.id);
          continue;
        }
        final triggerAt = reminder.snoozeUntil ?? reminder.dueAt;
        await MobileNotifications.instance.scheduleReminder(
          reminderId: reminder.id,
          title: reminder.title,
          body: reminder.body,
          dueAt: triggerAt,
        );
      }
      await DesktopReminderNotifier.onRemindersUpdated(reminders);
      if (!mounted) return;
      setState(() => _reminders = reminders);
      await _refreshPendingCount();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load reminders')),
      );
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _openNotificationDebugPanel() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        List<String> lines = const <String>[];
        bool loading = true;

        Future<void> loadData(StateSetter setSheetState) async {
          setSheetState(() => loading = true);
          final pending = await MobileNotifications.instance.pendingRequests();
          final now = DateTime.now();
          final reminderLines = _reminders.map((r) {
            final trigger = (r.snoozeUntil ?? r.dueAt).toLocal();
            return '${r.id.substring(0, r.id.length > 8 ? 8 : r.id.length)} '
                'status=${r.status} trigger=$trigger';
          }).toList();
          lines = <String>[
            'now=$now',
            'reminders=${_reminders.length}',
            'pending_notifications=${pending.length}',
            ...pending.map((e) => 'pending id=${e.id} payload=${e.payload ?? "-"}'),
            '--- reminders ---',
            ...reminderLines,
          ];
          setSheetState(() => loading = false);
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (loading && lines.isEmpty) {
              loadData(setSheetState);
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FC),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Notification Debug',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            onPressed: () => loadData(setSheetState),
                            icon: const Icon(CupertinoIcons.refresh),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: () async {
                              await MobileNotifications.instance
                                  .ensurePermissions();
                              await loadData(setSheetState);
                            },
                            child: const Text('Request Permission'),
                          ),
                          FilledButton.tonal(
                            onPressed: () async {
                              await MobileNotifications.instance.debugShowNow();
                              await loadData(setSheetState);
                            },
                            child: const Text('Notify Now'),
                          ),
                          FilledButton.tonal(
                            onPressed: () async {
                              await MobileNotifications.instance
                                  .debugScheduleInSeconds(seconds: 30);
                              await loadData(setSheetState);
                            },
                            child: const Text('Schedule +30s'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101114),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                child: Text(
                                  lines.join('\n'),
                                  style: const TextStyle(
                                    fontFamily: 'Consolas',
                                    color: Color(0xFF7FFFB4),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

  Future<void> _showCreateReminderDialog() async {
    final titleCtrl = TextEditingController();
    DateTime selectedDueAt = DateTime.now().add(const Duration(minutes: 15));
    int selectedPresetMinutes = 15;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final dueLabel =
                '${selectedDueAt.year}-${selectedDueAt.month.toString().padLeft(2, '0')}-${selectedDueAt.day.toString().padLeft(2, '0')} '
                '${selectedDueAt.hour.toString().padLeft(2, '0')}:${selectedDueAt.minute.toString().padLeft(2, '0')}';

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 14,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FC),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.9)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 32,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0D0D8),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'New Reminder',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Title (required)'),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _timePresetChip(
                            label: '15m',
                            selected: selectedPresetMinutes == 15,
                            onTap: () {
                              setSheetState(() {
                                selectedPresetMinutes = 15;
                                selectedDueAt =
                                    DateTime.now().add(const Duration(minutes: 15));
                              });
                            },
                          ),
                          _timePresetChip(
                            label: '30m',
                            selected: selectedPresetMinutes == 30,
                            onTap: () {
                              setSheetState(() {
                                selectedPresetMinutes = 30;
                                selectedDueAt =
                                    DateTime.now().add(const Duration(minutes: 30));
                              });
                            },
                          ),
                          _timePresetChip(
                            label: '1h',
                            selected: selectedPresetMinutes == 60,
                            onTap: () {
                              setSheetState(() {
                                selectedPresetMinutes = 60;
                                selectedDueAt =
                                    DateTime.now().add(const Duration(hours: 1));
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedDueAt,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (pickedDate == null || !context.mounted) return;
                        final pickedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(selectedDueAt),
                        );
                        if (pickedTime == null) return;
                        setSheetState(() {
                          selectedDueAt = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                        });
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Reminder time',
                        ),
                        child: Row(
                          children: [
                            const Icon(CupertinoIcons.calendar, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(dueLabel)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Create'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (ok != true) return;
    if (titleCtrl.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    final dueAt = selectedDueAt;
    final temp = Reminder(
      id: 'ui-reminder-${DateTime.now().microsecondsSinceEpoch}',
      title: titleCtrl.text.trim(),
      body: null,
      dueAt: dueAt.toUtc(),
      repeatRule: 'none',
      status: 'pending',
      snoozeUntil: null,
      version: 1,
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() {
      _reminders = [..._reminders, temp];
    });

    Future<void>(() async {
      final reminder = await AppDI.reminderRepo.create(
        title: titleCtrl.text.trim(),
        dueAt: dueAt,
        repeatRule: 'none',
      );
      await MobileNotifications.instance.scheduleReminder(
        reminderId: reminder.id,
        title: reminder.title,
        body: reminder.body,
        // Use user-selected local time directly to avoid server roundtrip
        // timezone/serialization drift on some devices.
        dueAt: dueAt,
      );
      if (!mounted) return;
      if (reminder.id.startsWith('local-reminder-')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved offline, sync queued')),
        );
      }
      await DesktopIsland.show(
        title: reminder.title,
        body: 'Reminder created',
      );
      await _reload(silent: true);
    });
  }

  Future<void> _markDone(Reminder reminder) async {
    setState(() {
      _reminders = _reminders
          .map(
            (r) => r.id == reminder.id
                ? Reminder(
                    id: r.id,
                    title: r.title,
                    body: r.body,
                    dueAt: r.dueAt,
                    repeatRule: r.repeatRule,
                    status: 'done',
                    snoozeUntil: r.snoozeUntil,
                    version: r.version + 1,
                    updatedAt: DateTime.now().toUtc(),
                  )
                : r,
          )
          .toList();
    });
    await AppDI.reminderRepo.done(reminder.id);
    await MobileNotifications.instance.cancelReminder(reminder.id);
    if (!mounted) return;
    await DesktopIsland.show(
      title: 'Marked done',
      body: reminder.title,
    );
    await _reload(silent: true);
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    setState(() {
      _reminders = _reminders.where((r) => r.id != reminder.id).toList();
    });
    await AppDI.reminderRepo.remove(reminder.id);
    await MobileNotifications.instance.cancelReminder(reminder.id);
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

  List<Reminder> get _visibleReminders {
    final now = DateTime.now();
    return _reminders.where((r) {
      final isDone = r.status == 'done';
      final isOverdue = !isDone && r.dueAt.toLocal().isBefore(now);
      final q = _query.trim().toLowerCase();
      final matchesQuery = q.isEmpty ||
          r.title.toLowerCase().contains(q) ||
          (r.body?.toLowerCase().contains(q) ?? false);
      if (!matchesQuery) return false;
      return switch (_filter) {
        _ReminderFilter.all => true,
        _ReminderFilter.active => !isDone,
        _ReminderFilter.done => isDone,
        _ReminderFilter.overdue => isOverdue,
      };
    }).toList();
  }

  String _formatDueLabel(Reminder reminder) {
    final due = reminder.dueAt.toLocal();
    final now = DateTime.now().toLocal();
    final dueDateOnly = DateTime(due.year, due.month, due.day);
    final nowDateOnly = DateTime(now.year, now.month, now.day);
    final dayDelta = dueDateOnly.difference(nowDateOnly).inDays;
    final hh = due.hour.toString().padLeft(2, '0');
    final mm = due.minute.toString().padLeft(2, '0');
    if (dayDelta == 0) return 'Today $hh:$mm';
    if (dayDelta == 1) return 'Tomorrow $hh:$mm';
    final m = due.month.toString().padLeft(2, '0');
    final d = due.day.toString().padLeft(2, '0');
    return '$m/$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: _enableDebugPanel
            ? GestureDetector(
                onLongPress: _openNotificationDebugPanel,
                child: const Text('Reminders'),
              )
            : const Text('Reminders'),
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
                    hintText: 'Search reminders',
                    prefixIcon: Icon(CupertinoIcons.search),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoSlidingSegmentedControl<_ReminderFilter>(
                  groupValue: _filter,
                  onValueChanged: (v) {
                    if (v == null) return;
                    setState(() => _filter = v);
                  },
                  children: const {
                    _ReminderFilter.all: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('All'),
                    ),
                    _ReminderFilter.active: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('Active'),
                    ),
                    _ReminderFilter.done: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('Done'),
                    ),
                    _ReminderFilter.overdue: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Text('Overdue'),
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
              child: _visibleReminders.isEmpty
                  ? Center(
                      key: const ValueKey('reminders-empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No reminders yet'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _showCreateReminderDialog,
                            icon: const Icon(CupertinoIcons.add),
                            label: const Text('Create first reminder'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      key: const ValueKey('reminders-list'),
                      onRefresh: () => _reload(silent: true),
                      child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: _visibleReminders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final reminder = _visibleReminders[i];
                      final done = reminder.status == 'done';
                      final overdue = !done &&
                          reminder.dueAt.toLocal().isBefore(DateTime.now());
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(reminder.id),
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(
                          milliseconds:
                              170 + ((i * 35).clamp(0, 180) as int),
                        ),
                        curve: Curves.easeOutCubic,
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      done
                                          ? CupertinoIcons
                                              .check_mark_circled_solid
                                          : CupertinoIcons.bell_fill,
                                      color: done
                                          ? const Color(0xFF34C759)
                                          : const Color(0xFF007AFF),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        reminder.title,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: done
                                            ? const Color(0xFFEAF8EF)
                                            : overdue
                                                ? const Color(0xFFFFEBEA)
                                                : const Color(0xFFEAF2FF),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        done
                                            ? 'Done'
                                            : overdue
                                                ? 'Overdue'
                                                : 'Active',
                                        style: TextStyle(
                                          color: done
                                              ? const Color(0xFF027A48)
                                              : overdue
                                                  ? const Color(0xFFB42318)
                                                  : const Color(0xFF175CD3),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F8FC),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.time,
                                        size: 15,
                                        color: overdue
                                            ? const Color(0xFFB42318)
                                            : const Color(0xFF4D4D57),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _formatDueLabel(reminder),
                                        style: TextStyle(
                                          color: overdue
                                              ? const Color(0xFFB42318)
                                              : const Color(0xFF4D4D57),
                                          fontWeight: overdue
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _miniAction(
                                      icon: CupertinoIcons.timer,
                                      label: 'Snooze',
                                      onTap: () async {
                                        final snoozeUntilLocal =
                                            DateTime.now().add(
                                          const Duration(minutes: 10),
                                        );
                                        final snoozeUntil =
                                            snoozeUntilLocal.toUtc();
                                        setState(() {
                                          _reminders = _reminders
                                              .map((r) => r.id == reminder.id
                                                  ? Reminder(
                                                      id: r.id,
                                                      title: r.title,
                                                      body: r.body,
                                                      dueAt: r.dueAt,
                                                      repeatRule: r.repeatRule,
                                                      status: r.status,
                                                      snoozeUntil: snoozeUntil,
                                                      version: r.version + 1,
                                                      updatedAt: DateTime.now()
                                                          .toUtc(),
                                                    )
                                                  : r)
                                              .toList();
                                        });
                                        await MobileNotifications.instance
                                            .scheduleReminder(
                                          reminderId: reminder.id,
                                          title: reminder.title,
                                          body: reminder.body,
                                          dueAt: snoozeUntilLocal,
                                        );
                                        await AppDI.reminderRepo
                                            .snooze(reminder.id, 10);
                                        if (!mounted) return;
                                        await DesktopIsland.show(
                                          title: 'Snoozed 10 minutes',
                                          body: reminder.title,
                                        );
                                        await _reload(silent: true);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    _miniAction(
                                      icon: CupertinoIcons.check_mark,
                                      label: 'Done',
                                      onTap: done
                                          ? null
                                          : () => _markDone(reminder),
                                    ),
                                    const SizedBox(width: 8),
                                    _miniAction(
                                      icon: CupertinoIcons.delete,
                                      label: 'Delete',
                                      danger: true,
                                      onTap: () => _deleteReminder(reminder),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        builder: (context, value, child) {
                          return Transform.translate(
                            offset: Offset(0, (1 - value) * 8),
                            child: Opacity(opacity: value, child: child),
                          );
                        },
                      );
                    },
                  ),
                  ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateReminderDialog,
        label: const Text('New Reminder'),
        icon: const Icon(CupertinoIcons.add),
      ),
    );
  }

  Widget _miniAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFFFF3B30) : const Color(0xFF007AFF);
    return PressableScale(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: danger ? const Color(0xFFFFEBEA) : const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timePresetChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0A84FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF3B3B44),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
