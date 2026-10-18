import 'package:flutter/material.dart';

import 'db.dart';
import 'root_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance.database;
  await Settings.instance.load();
  runApp(const CyclogApp());
}

class CyclogApp extends StatefulWidget {
  const CyclogApp({super.key});

  @override
  State<CyclogApp> createState() => _CyclogAppState();
}

class _CyclogAppState extends State<CyclogApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Checkpointing on the way out means the database file on disk is always
    // complete, which is what Android's Auto Backup copies.
    _lifecycle = AppLifecycleListener(
      onPause: _checkpoint,
      onDetach: _checkpoint,
    );
  }

  void _checkpoint() {
    // Best effort: a failed checkpoint must never interfere with the app
    // closing, and the data is already committed either way.
    AppDb.instance.checkpoint().catchError((Object _) {});
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'cyclog',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const RootScreen(),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7E57C2),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      listTileTheme: const ListTileThemeData(
        subtitleTextStyle: TextStyle(height: 1.35),
      ),
    );
  }
}
