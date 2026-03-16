import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/di.dart';
import 'core/notifications/desktop_reminder_notifier.dart';
import 'core/notifications/mobile_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileNotifications.instance.initialize();
  await MobileNotifications.instance.ensurePermissions();
  await DesktopReminderNotifier.startAutoWatch(
    loader: () => AppDI.reminderRepo.list(),
  );
  runApp(const ProviderScope(child: NotesBridgeApp()));
}
