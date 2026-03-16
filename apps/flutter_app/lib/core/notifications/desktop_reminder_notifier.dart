import 'package:flutter/foundation.dart';
import 'dart:async';

import '../../features/reminders/domain/reminder.dart';
import 'desktop_island.dart';

class DesktopReminderNotifier {
  DesktopReminderNotifier._();

  static final Set<String> _firedKeys = <String>{};
  static Timer? _watchTimer;
  static bool _runningTick = false;

  static bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  static Future<void> onRemindersUpdated(List<Reminder> reminders) async {
    if (!_supported) return;

    final now = DateTime.now();
    final aliveKeys = <String>{};

    for (final reminder in reminders) {
      if (reminder.status == 'done') continue;

      final triggerAt = (reminder.snoozeUntil ?? reminder.dueAt).toLocal();
      final fireKey = '${reminder.id}|${triggerAt.toIso8601String()}';
      aliveKeys.add(fireKey);

      if (triggerAt.isAfter(now)) continue;
      if (_firedKeys.contains(fireKey)) continue;

      await DesktopIsland.show(
        title: reminder.title,
        body: (reminder.body == null || reminder.body!.trim().isEmpty)
            ? 'Reminder is due now'
            : reminder.body!.trim(),
      );
      _firedKeys.add(fireKey);
    }

    // Remove stale fired keys so snoozed/updated reminders can re-notify.
    _firedKeys.removeWhere((key) => !aliveKeys.contains(key));
  }

  static Future<void> startAutoWatch({
    required Future<List<Reminder>> Function() loader,
    Duration interval = const Duration(seconds: 20),
  }) async {
    if (!_supported) return;
    _watchTimer?.cancel();

    await _safeTick(loader);
    _watchTimer = Timer.periodic(interval, (_) {
      _safeTick(loader);
    });
  }

  static void stopAutoWatch() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  static Future<void> _safeTick(
    Future<List<Reminder>> Function() loader,
  ) async {
    if (_runningTick) return;
    _runningTick = true;
    try {
      final reminders = await loader();
      await onRemindersUpdated(reminders);
    } catch (_) {
      // Ignore transient sync/network errors.
    } finally {
      _runningTick = false;
    }
  }
}
