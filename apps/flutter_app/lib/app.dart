import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class NotesBridgeApp extends StatelessWidget {
  const NotesBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes Bridge',
      theme: AppTheme.light,
      routes: AppRouter.routes,
      initialRoute: AppRouter.notes,
    );
  }
}

