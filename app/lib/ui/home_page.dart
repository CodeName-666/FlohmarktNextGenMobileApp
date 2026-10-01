import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../data/market_library.dart';
import '../domain/money.dart';
import 'archive_page.dart';
import 'catalog_pages.dart';
import 'files_page.dart';
import 'library_page.dart';
import 'operations_pages.dart';
import 'receipt_page.dart';
import 'register_page.dart';
import 'settings_page.dart';
import 'sync_page.dart';
import 'tones.dart';

/// App shell: Start · Kasse · Belege · Mehr. The register stays mounted while
/// other tabs are shown so an open basket and HID focus survive tab changes.
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
  int _tab = 0;
  bool _registerOpened = false;
  CheckoutStore? get _store => widget.library.active;

  Future<void> _setTheme(ThemeMode next) async {
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
        final parked = await store.parkedDrafts();
        _draft =
            (await store.cartLines()).length +
            parked.fold(0, (count, draft) => count + draft.entries.length);
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

  void _select(int tab) {
    setState(() {
      _tab = tab;
      if (tab == 1) _registerOpened = true;
    });
    if (tab == 0) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final showRegister = _tab == 1 && store != null;
    return Scaffold(
      body: Stack(
        children: [
          if (_registerOpened && store != null)
            Offstage(
              offstage: !showRegister,
              child: TickerMode(
                enabled: showRegister,
                child: RegisterPage(
                  key: ValueKey(widget.library.activeId),
                  store: store,
                  active: showRegister,
                ),
              ),
            ),
          if (!showRegister)
            switch (_tab) {
              0 => _start(context),
              3 => _more(context),
              _ when store == null => _noMarket(context),
              _ => ReceiptPage(store: store),
            },
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Kasse',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Belege',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Mehr',
          ),
        ],
      ),
    );
  }

  Widget _page(BuildContext context, String title, List<Widget> children) =>
      SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ),
      );

  Widget _noMarket(BuildContext context) => _page(context, 'MarketMate', [
    Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Noch kein Markt geöffnet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Marktpaket importieren oder über die Synchronisation herunterladen.',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _open(LibraryPage(library: widget.library)),
              icon: const Icon(Icons.storefront),
              label: const Text('Markt auswählen'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  _open(SyncPage(store: _store, library: widget.library)),
              icon: const Icon(Icons.sync),
              label: const Text('Anmelden und herunterladen'),
            ),
          ],
        ),
      ),
    ),
    if (_error != null) _ErrorBox(_error!),
  ]);

  Widget _start(BuildContext context) {
    final store = _store;
    if (store == null) return _noMarket(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = store.session;
    return _page(context, 'MarketMate', [
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 64)),
        onPressed: () => _select(1),
        icon: const Icon(Icons.point_of_sale),
        label: Text(
          _draft > 0 ? 'Kasse öffnen · $_draft vorgemerkt' : 'Kasse öffnen',
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Tag(
                    session.isDemo
                        ? 'Demo'
                        : session.exportGeneration == 0
                        ? 'V1 lokal'
                        : 'V2 · Export ${session.exportGeneration}',
                    background: session.isDemo
                        ? Tones.warningContainer(context)
                        : scheme.primaryContainer,
                    foreground: session.isDemo
                        ? Tones.onWarningContainer(context)
                        : scheme.onPrimaryContainer,
                  ),
                  TextButton(
                    onPressed: () =>
                        _open(LibraryPage(library: widget.library)),
                    child: const Text('Wechseln'),
                  ),
                ],
              ),
              Text(
                session.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Kasse ${session.registerNumber}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: FigureGroup(
                  children: [
                    Figure('Umsatz', formatCents(_revenue)),
                    Figure('Artikel', '$_sold'),
                    Figure('Vorgemerkt', '$_draft'),
                  ],
                ),
              ),
              if (_pending > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10, right: 10),
                  child: Material(
                    color: Tones.warningContainer(context),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _open(
                        SyncPage(store: store, library: widget.library),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sync_problem,
                              size: 18,
                              color: Tones.onWarningContainer(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_pending Vorgänge noch nicht vom Server bestätigt',
                                style: TextStyle(
                                  color: Tones.onWarningContainer(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (_error != null) _ErrorBox(_error!),
      const SizedBox(height: 24),
      const _Heading('Nach dem Markt'),
      AdaptiveActions(
        children: [
          _Tile(
            icon: Icons.inventory_2_outlined,
            title: 'Rücksortierung',
            subtitle: 'Scan-Abgleich Soll / Ist',
            onTap: () => _open(ReconciliationPage(store: store)),
          ),
          _Tile(
            icon: Icons.calculate_outlined,
            title: 'Abrechnung',
            subtitle: 'Auszahlung je Verkäufer',
            onTap: () => _open(AccountingPage(store: store)),
          ),
        ],
      ),
    ]);
  }

  Widget _more(BuildContext context) {
    final store = _store;
    Widget item(
      IconData icon,
      String title,
      Widget Function(CheckoutStore)? page, {
      Widget? trailing,
      Widget? always,
    }) => ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      enabled: always != null || store != null,
      onTap: always != null
          ? () => _open(always)
          : store == null
          ? null
          : () => _open(page!(store)),
    );
    return _page(context, 'Mehr', [
      const _Heading('Markt und Daten'),
      _Group([
        item(
          Icons.storefront,
          'Märkte und Kassen',
          null,
          always: LibraryPage(library: widget.library),
        ),
        item(
          Icons.sync,
          'Anmelden und Synchronisation',
          null,
          always: SyncPage(store: store, library: widget.library),
          trailing: _pending > 0
              ? Tag(
                  '$_pending offen',
                  background: Tones.warningContainer(context),
                  foreground: Tones.onWarningContainer(context),
                )
              : null,
        ),
        item(
          Icons.info_outline,
          'Marktdetails',
          (s) => MarketDetailsPage(store: s),
        ),
        item(
          Icons.folder_open,
          'Dateien, Zusammenführung, Sicherung',
          (s) => FilesPage(store: s),
        ),
        item(
          Icons.archive_outlined,
          'Archiv aller Märkte',
          null,
          always: ArchivePage(library: widget.library),
        ),
      ]),
      const SizedBox(height: 16),
      const _Heading('Suchen und Auswerten'),
      _Group([
        item(
          Icons.search,
          'Artikel suchen',
          (s) => ArticleSearchPage(store: s),
        ),
        item(
          Icons.person_search_outlined,
          'Kunden und Belege',
          (s) => CustomerSearchPage(store: s),
        ),
        item(Icons.list_alt, 'Rücksortierlisten', (s) => UnsoldPage(store: s)),
        item(
          Icons.qr_code_scanner,
          'Scan-Rücksortierung',
          (s) => ReconciliationPage(store: s),
        ),
        item(
          Icons.calculate_outlined,
          'Abrechnung',
          (s) => AccountingPage(store: s),
        ),
        item(Icons.bar_chart, 'Statistik', (s) => StatisticsPage(store: s)),
      ]),
      const SizedBox(height: 16),
      const _Heading('App'),
      _Group([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              const Text('Darstellung'),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      label: Text(switch (mode) {
                        ThemeMode.light => 'Hell',
                        ThemeMode.dark => 'Dunkel',
                        ThemeMode.system => 'System',
                      }),
                      selected: widget.themeMode == mode,
                      onSelected: (_) => _setTheme(mode),
                    ),
                ],
              ),
            ],
          ),
        ),
        item(
          Icons.settings_outlined,
          'Einstellungen, Protokolle und Über',
          (s) => SettingsPage(
            store: s,
            library: widget.library,
            themeMode: widget.themeMode,
            onThemeChanged: widget.onThemeChanged,
          ),
        ),
      ]),
    ]);
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group(this.children);
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: ListTile.divideTiles(
        context: context,
        tiles: children,
      ).toList(),
    ),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox(this.text);
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        text,
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}
