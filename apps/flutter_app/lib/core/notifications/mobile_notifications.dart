import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class MobileNotifications {
  MobileNotifications._();

  static final MobileNotifications instance = MobileNotifications._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  final Set<String> _firedImmediate = <String>{};

  bool get _supportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> initialize() async {
    if (_initialized || !_supportedPlatform) return;

    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidInit,
      iOS: ios,
    );

    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'notes_reminders',
        'Reminders',
        description: 'Reminder notifications',
        importance: Importance.max,
      ),
    );

    _initialized = true;
  }

  Future<void> ensurePermissions() async {
    if (!_supportedPlatform) return;
    await initialize();

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  int idForReminder(String reminderId) {
    return reminderId.hashCode & 0x7fffffff;
  }

  Future<void> scheduleReminder({
    required String reminderId,
    required String title,
    String? body,
    required DateTime dueAt,
  }) async {
    if (!_supportedPlatform) return;
    await initialize();

    final when = dueAt.toLocal();
    final now = DateTime.now();
    final fireKey = '$reminderId|${when.toIso8601String()}';

    final details = _buildDetails();

    if (!when.isAfter(now)) {
      if (_firedImmediate.contains(fireKey)) return;
      await _plugin.show(
        idForReminder(reminderId),
        title,
        (body == null || body.trim().isEmpty) ? 'Reminder is due now' : body,
        details,
        payload: reminderId,
      );
      _firedImmediate.add(fireKey);
      return;
    }

    try {
      await _plugin.zonedSchedule(
        idForReminder(reminderId),
        title,
        (body == null || body.trim().isEmpty) ? 'Reminder is due now' : body,
        tz.TZDateTime.from(when, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: reminderId,
      );
    } catch (_) {
      // Fallback for devices/ROMs where exact alarms are restricted.
      await _plugin.zonedSchedule(
        idForReminder(reminderId),
        title,
        (body == null || body.trim().isEmpty) ? 'Reminder is due now' : body,
        tz.TZDateTime.from(when, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminderId,
      );
    }
  }

  Future<void> cancelReminder(String reminderId) async {
    if (!_supportedPlatform) return;
    await initialize();
    await _plugin.cancel(idForReminder(reminderId));
    _firedImmediate.removeWhere((k) => k.startsWith('$reminderId|'));
  }

  Future<List<PendingNotificationRequest>> pendingRequests() async {
    if (!_supportedPlatform) return const <PendingNotificationRequest>[];
    await initialize();
    return _plugin.pendingNotificationRequests();
  }

  Future<void> debugShowNow() async {
    if (!_supportedPlatform) return;
    await initialize();
    await _plugin.show(
      2147483000,
      'Debug reminder',
      'Immediate test notification',
      _buildDetails(),
      payload: 'debug-now',
    );
  }

  Future<void> debugScheduleInSeconds({int seconds = 30}) async {
    if (!_supportedPlatform) return;
    await initialize();
    final when = DateTime.now().add(Duration(seconds: seconds));
    await scheduleReminder(
      reminderId: 'debug-$seconds',
      title: 'Debug scheduled',
      body: 'Should fire in $seconds seconds',
      dueAt: when,
    );
  }

  NotificationDetails _buildDetails() {
    return NotificationDetails(
      android: const AndroidNotificationDetails(
        'notes_reminders',
        'Reminders',
        channelDescription: 'Reminder notifications',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }
}
