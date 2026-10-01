import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'services/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'data/checkout_store.dart';
import 'data/market_library.dart';
import 'data/demo_catalog.dart';
import 'ui/register_page.dart';
import 'ui/home_page.dart';
import 'ui/tones.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final directory = await getDatabasesPath();
    AppDiagnostics.initialize(directory);
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(
        AppDiagnostics.record('flutter', details.exception, details.stack),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(AppDiagnostics.record('unhandled', error, stack));
      return true;
    };
    String? startupError;
    final library = await MarketLibrary.open(
      factory: databaseFactory,
      directory: p.join(directory, 'marketmate'),
    );
    // Preserve the original installed demo and its draft during the first upgrade.
    final legacy = p.join(directory, 'marketmate_demo_v1.db');
    if ((await library.sessions()).isEmpty && await File(legacy).exists()) {
      final previous = await CheckoutStore.open(
        factory: databaseFactory,
        path: legacy,
      );
      final backup = await previous.backup();
      await previous.close();
      final saved = await library.createSession(
        demoSession,
        demoCatalog,
        source: 'migrated-demo',
      );
      final target = await library.activate(saved.id);
      await target.restoreBackup(backup);
    }
    final last = await library.preference('lastSession');
    if (last is String && library.active == null) {
      try {
        await library.activate(last);
      } catch (e, stack) {
        startupError = 'Letzte Kasse konnte nicht geöffnet werden: $e';
        await AppDiagnostics.record('startup', e, stack);
      }
    }
    final activeSettings = await library.active?.setting('uiSettings');
    final mode = activeSettings is Map
        ? activeSettings['themeMode'] ?? await library.preference('theme')
        : await library.preference('theme');
    runApp(
      MarketMateApp(
        library: library,
        startupError: startupError,
        initialTheme: ThemeMode.values.firstWhere(
          (m) => m.name == mode,
          orElse: () => ThemeMode.system,
        ),
      ),
    );
  } catch (error, stack) {
    await AppDiagnostics.record('startup', error, stack);
    runApp(
      MaterialApp(
        theme: marketTheme(Brightness.light),
        darkTheme: marketTheme(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Die lokale Kasse konnte nicht geöffnet werden. App-Daten nicht löschen.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText(error.toString()),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: main,
                    child: const Text('Erneut versuchen'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketMateApp extends StatefulWidget {
  final CheckoutStore? store;
  final MarketLibrary? library;
  final ThemeMode initialTheme;
  final String? startupError;
  const MarketMateApp({
    super.key,
    this.store,
    this.library,
    this.initialTheme = ThemeMode.system,
    this.startupError,
  }) : assert(store != null || library != null);
  @override
  State<MarketMateApp> createState() => _MarketMateAppState();
}

class _MarketMateAppState extends State<MarketMateApp> {
  late ThemeMode _mode = widget.initialTheme;
  void _theme(ThemeMode mode) {
    if (mounted) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MarketMate · Mobile Kasse',
    debugShowCheckedModeBanner: false,
    theme: marketTheme(Brightness.light),
    darkTheme: marketTheme(Brightness.dark),
    themeMode: _mode,
    home: widget.library == null
        ? RegisterPage(store: widget.store!)
        : HomePage(
            library: widget.library!,
            startupError: widget.startupError,
            themeMode: _mode,
            onThemeChanged: _theme,
          ),
  );
}
