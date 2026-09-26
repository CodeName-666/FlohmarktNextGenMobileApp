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
import 'ui/library_page.dart';
import 'ui/archive_page.dart';
import 'ui/catalog_pages.dart';
import 'ui/operations_pages.dart';
import 'ui/files_page.dart';
import 'ui/settings_page.dart';
import 'ui/sync_page.dart';
import 'domain/money.dart';

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
        home: Scaffold(
          body: SafeArea(
            child: Padding(
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

  ThemeData _design(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff006a68),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
    ),
    useMaterial3: true,
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MarketMate · Mobile Kasse',
    debugShowCheckedModeBanner: false,
    theme: _design(Brightness.light),
    darkTheme: _design(Brightness.dark),
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

class HomePage extends StatefulWidget {
  final MarketLibrary library;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final String? startupError;
  const HomePage({
    super.key,
    required this.library,
    required this.themeMode,
    required this.onThemeChanged,
    this.startupError,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String? _error = widget.startupError;
  int _sold = 0, _revenue = 0, _pending = 0, _draft = 0;
  CheckoutStore? get _store => widget.library.active;
  Future<void> _changeTheme() async {
    final next = widget.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    try {
      if (_store != null) {
        final saved = await _store!.setting('uiSettings');
        await _store!.setSetting('uiSettings', {
          if (saved is Map) ...Map<String, Object?>.from(saved),
          'themeMode': next.name,
        });
      } else {
        await widget.library.setPreference('theme', next.name);
      }
      widget.onThemeChanged(next);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final store = _store;
      if (store != null) {
        final settings = await store.setting('uiSettings');
        final theme = settings is Map ? settings['themeMode'] : null;
        if (theme == 'dark' || theme == 'light' || theme == 'system') {
          widget.onThemeChanged(ThemeMode.values.byName(theme as String));
        }
        final sales = await store.activeSales();
        _sold = sales.length;
        _revenue = sales.fold(0, (sum, e) => sum + e.listing.priceCents);
        _pending = (await store.pendingEvents()).length;
        _draft =
            (await store.cartLines()).length + (await store.heldCart()).length;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    await _refresh();
  }

  Widget _action(
    String title,
    IconData icon,
    Widget Function(CheckoutStore) page,
  ) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: _store == null ? null : () => _open(page(_store!)),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('MarketMate'),
      actions: [
        IconButton(
          tooltip: 'Darstellung wechseln',
          onPressed: _changeTheme,
          icon: const Icon(Icons.contrast),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _store?.session.name ?? 'Mobile Kasse',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            if (_store != null) ...[
              Text(
                'Kasse ${_store!.session.registerNumber} · ${_store!.session.isDemo
                    ? 'Demo'
                    : _store!.session.exportGeneration == 0
                    ? 'V1 lokal'
                    : 'V2'}',
              ),
              const SizedBox(height: 12),
              Text(
                '$_sold verkaufte Artikel · ${formatCents(_revenue)}\n$_pending Vorgänge noch nicht bestätigt · $_draft vorgemerkte Positionen',
              ),
            ] else
              const Text(
                'Zuerst einen Markt importieren oder vom Server herunterladen.',
              ),
            if (_error != null) SelectableText(_error!),
            const SizedBox(height: 24),
            Text('Vorbereiten', style: Theme.of(context).textTheme.titleLarge),
            Card(
              child: ListTile(
                leading: const Icon(Icons.storefront),
                title: const Text('Märkte und Kassen'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(LibraryPage(library: widget.library)),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Anmelden, Download und Synchronisation'),
                onTap: () =>
                    _open(SyncPage(store: _store, library: widget.library)),
              ),
            ),
            _action(
              'Marktdetails',
              Icons.info_outline,
              (store) => MarketDetailsPage(store: store),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Archiv aller Märkte'),
                onTap: () => _open(ArchivePage(library: widget.library)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Kassieren', style: Theme.of(context).textTheme.titleLarge),
            _action(
              'Kassenbetrieb',
              Icons.point_of_sale,
              (store) => RegisterPage(store: store),
            ),
            _action(
              'Artikel suchen',
              Icons.search,
              (store) => ArticleSearchPage(store: store),
            ),
            _action(
              'Kunden und Belege',
              Icons.receipt_long,
              (store) => CustomerSearchPage(store: store),
            ),
            const SizedBox(height: 20),
            Text(
              'Nach dem Markt',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            _action(
              'Rücksortierlisten',
              Icons.inventory_2_outlined,
              (store) => UnsoldPage(store: store),
            ),
            _action(
              'Scan-Rücksortierung',
              Icons.qr_code_scanner,
              (store) => ReconciliationPage(store: store),
            ),
            _action(
              'Abrechnung',
              Icons.calculate_outlined,
              (store) => AccountingPage(store: store),
            ),
            _action(
              'Statistik',
              Icons.bar_chart,
              (store) => StatisticsPage(store: store),
            ),
            _action(
              'Dateien, Zusammenführung und Sicherung',
              Icons.folder_open,
              (store) => FilesPage(store: store),
            ),
            _action(
              'Einstellungen, Protokolle und Über',
              Icons.settings_outlined,
              (store) => SettingsPage(
                store: store,
                library: widget.library,
                themeMode: widget.themeMode,
                onThemeChanged: widget.onThemeChanged,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
