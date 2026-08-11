import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/home_shell.dart';

class BentaGoApp extends StatelessWidget {
  const BentaGoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BentaGo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeShell(),
    );
  }
}
