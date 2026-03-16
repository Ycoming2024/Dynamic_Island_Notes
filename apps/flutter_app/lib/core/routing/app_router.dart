import 'package:flutter/material.dart';

import '../../features/notes/presentation/notes_page.dart';
import '../../features/reminders/presentation/reminders_page.dart';

class AppRouter {
  static const notes = '/';
  static const reminders = '/reminders';

  static final routes = <String, WidgetBuilder>{
    notes: (_) => const NotesPage(),
    reminders: (_) => const RemindersPage(),
  };
}
