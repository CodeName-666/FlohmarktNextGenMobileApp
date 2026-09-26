import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../data/checkout_store.dart';
import '../domain/accounting.dart';
import '../domain/barcode.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/reconciliation.dart';
import '../services/operations_reports.dart';
import 'camera_page.dart';
import 'seller_article_dialog.dart';

void _error(BuildContext context, Object error) {
  final text = error is FormatException
      ? error.message
      : error is StateError
      ? error.message
      : 'Aktion fehlgeschlagen: $error';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 7)),
  );
}

Future<void> _report(
  BuildContext context,
  String name,
  Future<Uint8List> Function() build, {
  String extension = 'pdf',
}) async {
  try {
    final bytes = await build();
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(name),
              subtitle: Text(
                '${bytes.length} Bytes · ${extension.toUpperCase()}',
              ),
            ),
            if (extension == 'pdf')
              ListTile(
                leading: const Icon(Icons.print),
                title: const Text('Systemdruck / Vorschau'),
                onTap: () => Navigator.pop(context, 'print'),
              ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Teilen'),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Datei speichern'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
          ],
        ),
      ),
    );
    if (action == 'print') {
      await Printing.layoutPdf(name: '$name.pdf', onLayout: (_) async => bytes);
    }
    if (action == 'share') {
      if (extension == 'pdf') {
        await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: extension == 'csv' ? 'text/csv' : 'text/plain',
              ),
            ],
            fileNameOverrides: ['$name.$extension'],
          ),
        );
      }
    }
    if (action == 'save') {
      await FilePicker.saveFile(
        dialogTitle: 'Bericht speichern',
        fileName: '$name.$extension',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
      );
    }
  } catch (error) {
    if (context.mounted) _error(context, error);
  }
}

Future<void> _textReport(
  BuildContext context,
  String name,
  String text,
  String extension,
) => _report(
  context,
  name,
  () async => Uint8List.fromList(utf8.encode(text)),
  extension: extension,
);

class _OperationsData {
  final AccountingService accounting;
  final bool bulkFees, overrideFees;
  const _OperationsData(this.accounting, this.bulkFees, this.overrideFees);
  static Future<_OperationsData> load(CheckoutStore store) async {
    final listings = await store.allListings(), events = await store.events();
    final saved = await store.reconciliationStates();
    final override = await store.setting('gebuehren_ueberschreiben') == true;
    final root = store.session.metadata;
    final market = root['market'] is Map
        ? Map<String, Object?>.from(root['market'] as Map)
        : root;
    final settings = root['fees'] is Map
        ? Map<String, Object?>.from(root['fees'] as Map)
        : market['settings'] is Map
        ? Map<String, Object?>.from(market['settings'] as Map)
        : market;
    Object? value(String snake, String camel) =>
        settings[snake] ?? settings[camel] ?? market[snake] ?? market[camel];
    final bulkShare = value('revenue_share_percent', 'revenueSharePercent');
    final bulkBox = value(
      'seller_fee_per_stammnummer',
      'sellerFeePerStammnummer',
    );
    final bulk = bulkShare != null || bulkBox != null;
    final share = (!override && bulk)
        ? bulkShare
        : await store.setting('umsatzanteil_prozent');
    final box = (!override && bulk)
        ? bulkBox
        : await store.setting('gebuehr_pro_stammnummer');
    // Decimal text becomes exact basis points/cents; no monetary double math.
    final bp = share == null ? 0 : parseCents('$share'),
        cents = box == null ? 0 : parseCents('$box');
    if (bp > 10000) {
      throw const FormatException(
        'Umsatzanteil muss zwischen 0 und 100 Prozent liegen.',
      );
    }
    return _OperationsData(
      AccountingService(
        listings: listings,
        events: events,
        fees: FeePolicy(revenueShareBasisPoints: bp, feePerBoxCents: cents),
        reconciledListingIds: saved.entries
            .where(
              (e) => ['gefunden', 'doppelscan'].contains(e.value['status']),
            )
            .map((e) => e.key)
            .toSet(),
      ),
      bulk,
      override,
    );
  }
}

class _OperationsView extends StatefulWidget {
  final CheckoutStore store;
  final String title;
  final List<Widget> Function(BuildContext, _OperationsData, VoidCallback)
  children;
  const _OperationsView({
    required this.store,
    required this.title,
    required this.children,
  });
  @override
  State<_OperationsView> createState() => _OperationsViewState();
}

class _OperationsViewState extends State<_OperationsView> {
  _OperationsData? _data;
  Object? _failure;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final data = await _OperationsData.load(widget.store);
      if (mounted) setState(() => _data = data);
    } catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Gebühren',
          icon: const Icon(Icons.percent),
          onPressed: _data == null
              ? null
              : () async {
                  await _fees(context, widget.store, _data!);
                  _reload();
                },
        ),
        IconButton(
          tooltip: 'Aktualisieren',
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const LinearProgressIndicator()
        : _failure != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Daten konnten nicht geladen werden: $_failure'),
                FilledButton(
                  onPressed: _reload,
                  child: const Text('Erneut versuchen'),
                ),
              ],
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${widget.store.session.name}${widget.store.session.isDemo ? ' · DEMO' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ...widget.children(context, _data!, _reload),
            ],
          ),
  );
}

Future<void> _fees(
  BuildContext context,
  CheckoutStore store,
  _OperationsData data,
) async {
  final share = TextEditingController(
    text:
        '${data.accounting.fees.revenueShareBasisPoints ~/ 100},${(data.accounting.fees.revenueShareBasisPoints % 100).toString().padLeft(2, '0')}',
  );
  final box = TextEditingController(
    text: formatCents(data.accounting.fees.feePerBoxCents).replaceAll(' €', ''),
  );
  var override = data.overrideFees;
  String? error;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Gebühren'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.bulkFees
                    ? 'Quelle: Marktexport'
                    : 'Quelle: lokale Einstellungen',
              ),
              if (data.bulkFees)
                SwitchListTile(
                  title: const Text('Marktgebühren überschreiben'),
                  value: override,
                  onChanged: saving
                      ? null
                      : (v) => setState(() => override = v),
                ),
              TextField(
                controller: share,
                enabled: !saving && (!data.bulkFees || override),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Umsatzanteil (%)',
                ),
              ),
              TextField(
                controller: box,
                enabled: !saving && (!data.bulkFees || override),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Gebühr je Stamm-/Boxnummer (€)',
                ),
              ),
              const Text(
                'Nur der Umsatzanteil wird von der Auszahlung abgezogen. Die Boxgebühr ist gesonderter Markterlös. Rundung: exakte Cent, halbe Cent zur geraden Zahl.',
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    try {
                      final bp = parseCents(share.text);
                      parseCents(box.text);
                      if (bp > 10000) {
                        throw const FormatException('Maximal 100 Prozent.');
                      }
                      setState(() => saving = true);
                      await store.setSettings({
                        'umsatzanteil_prozent': share.text.replaceAll(',', '.'),
                        'gebuehr_pro_stammnummer': box.text.replaceAll(
                          ',',
                          '.',
                        ),
                        'gebuehren_ueberschreiben': override,
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) {
                        setState(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    }
                  },
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
  share.dispose();
  box.dispose();
}

Widget _warning(List<SaleEvent> events) => events.isEmpty
    ? const SizedBox.shrink()
    : Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(OperationsReports.missingWarning(events)),
        ),
      );

class AccountingPage extends StatefulWidget {
  final CheckoutStore store;
  const AccountingPage({super.key, required this.store});
  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  String _search = '';
  @override
  Widget build(BuildContext context) => _OperationsView(
    store: widget.store,
    title: 'Abrechnung / Auszahlung',
    children: (context, data, reload) {
      final settlements = data.accounting.settlements();
      final visible = settlements
          .where(
            (s) =>
                s.sellerKey.contains(_search) ||
                s.boxNumbers.any((b) => '$b' == _search),
          )
          .toList();
      return [
        Text(
          'Verkäufer: ${settlements.length} · Umsatz ${formatCents(settlements.fold(0, (sum, s) => sum + s.revenueCents))}',
        ),
        Text(
          'Gebühren ${formatCents(settlements.fold(0, (sum, s) => sum + s.feeCents))} · Auszahlung ${formatCents(settlements.fold(0, (sum, s) => sum + s.payoutCents))}',
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Verkäuferkennung oder Boxnummer suchen',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() => _search = s.trim()),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: settlements.isEmpty
                  ? null
                  : () => _report(
                      context,
                      'Abrechnungen',
                      () => OperationsReports.settlementPdf(
                        widget.store.session,
                        settlements,
                      ),
                    ),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Alle Abrechnungen als PDF'),
            ),
            TextButton(
              onPressed: () => _textReport(
                context,
                'Abrechnungen',
                OperationsReports.settlementsText(
                  widget.store.session,
                  settlements,
                ),
                'txt',
              ),
              child: const Text('Textbericht'),
            ),
          ],
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Keine Abrechnung gefunden.'),
          ),
        for (final seller in visible)
          Card(
            child: ExpansionTile(
              key: ValueKey(seller.sellerKey),
              title: Text(seller.sellerKey),
              subtitle: Text(
                'Boxen ${seller.boxNumbers.join(', ')} · Auszahlung ${formatCents(seller.payoutCents)}',
              ),
              children: [
                ListTile(
                  title: Text(
                    'Angeboten ${seller.offered.length} · Verkauft ${seller.sold.length} · Rest ${seller.unsold.length}',
                  ),
                  subtitle: Text(
                    'Umsatz ${formatCents(seller.revenueCents)} · Gebühren ${formatCents(seller.feeCents)}',
                  ),
                ),
                for (final box in seller.boxSettlements)
                  ListTile(
                    title: Text(
                      'Box ${box.boxNumber} · ${formatCents(box.payoutCents)}',
                    ),
                    subtitle: Text(
                      'Angeboten ${box.offeredCount} (${formatCents(box.offeredCents)})\nVerkauft ${box.soldCount} · Rest ${box.unsoldCount} (${formatCents(box.unsoldCents)}) · Rücksortierung offen ${box.openCount}',
                    ),
                  ),
                _warning(seller.missingCatalog),
                FilledButton(
                  onPressed: () => _report(
                    context,
                    'Abrechnung_${seller.sellerKey}',
                    () => OperationsReports.settlementPdf(
                      widget.store.session,
                      [seller],
                    ),
                  ),
                  child: const Text('Einzelabrechnung als PDF'),
                ),
                if (seller.missingCatalog.isNotEmpty)
                  TextButton(
                    onPressed: () => _textReport(
                      context,
                      'Pruefliste_${seller.sellerKey}',
                      OperationsReports.auditCsv(seller.missingCatalog),
                      'csv',
                    ),
                    child: const Text('Prüfliste als CSV'),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
      ];
    },
  );
}

class StatisticsPage extends StatefulWidget {
  final CheckoutStore store;
  const StatisticsPage({super.key, required this.store});
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int? _register;
  @override
  Widget build(BuildContext context) => _OperationsView(
    store: widget.store,
    title: 'Statistik',
    children: (context, data, reload) {
      final registers = {
        widget.store.session.registerNumber,
        ...data.accounting.events.map((e) => e.registerNumber),
      }.toList()..sort();
      final stats = data.accounting.statistics(registerNumber: _register);
      return [
        DropdownButtonFormField<int>(
          initialValue: _register ?? 0,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Kassenumfang'),
          items: [
            const DropdownMenuItem(
              value: 0,
              child: Text(
                'Alle geladenen Kassen',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final n in registers)
              DropdownMenuItem(value: n, child: Text('Kasse $n')),
          ],
          onChanged: (v) => setState(() => _register = v == 0 ? null : v),
        ),
        const Text(
          'Angebotswerte beziehen sich auf den gesamten geladenen Katalog. Nur importierte oder lokal erfasste Verkäufe sind enthalten.',
        ),
        _warning(stats.missingCatalog),
        for (final row in OperationsReports.statisticsRows(stats))
          ListTile(dense: true, title: Text(row[0]), trailing: Text(row[1])),
        FilledButton.icon(
          onPressed: () => _report(
            context,
            'Verkaufsstatistik',
            () => OperationsReports.statisticsPdf(
              widget.store.session,
              stats,
              registerNumber: _register,
            ),
          ),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Statistik als PDF'),
        ),
        TextButton(
          onPressed: () => _textReport(
            context,
            'Verkaufsstatistik',
            OperationsReports.statisticsText(
              widget.store.session,
              stats,
              registerNumber: _register,
            ),
            'txt',
          ),
          child: const Text('Textbericht'),
        ),
        if (stats.missingCatalog.isNotEmpty)
          TextButton(
            onPressed: () => _textReport(
              context,
              'Stammdaten_Pruefliste',
              OperationsReports.auditCsv(stats.missingCatalog),
              'csv',
            ),
            child: const Text('Prüfliste als CSV'),
          ),
      ];
    },
  );
}

class UnsoldPage extends StatefulWidget {
  final CheckoutStore store;
  const UnsoldPage({super.key, required this.store});
  @override
  State<UnsoldPage> createState() => _UnsoldPageState();
}

class _UnsoldPageState extends State<UnsoldPage> {
  int _slots = 25;
  String _filter = '';
  @override
  void initState() {
    super.initState();
    widget.store.setting('ruecksortier_spalten_pro_seite').then((v) {
      if (mounted && v is int && v >= 1 && v <= 28) setState(() => _slots = v);
    });
  }

  @override
  Widget build(BuildContext context) => _OperationsView(
    store: widget.store,
    title: 'Nicht verkauft / Rücksortierliste',
    children: (context, data, reload) {
      final sellers = data.accounting.settlements();
      return [
        const Text(
          'Vor dem Sortieren alle Kassendateien zusammenführen. Diese Liste verwendet den aktuell geladenen Bestand.',
        ),
        DropdownButtonFormField<int>(
          key: ValueKey(_slots),
          initialValue: _slots,
          decoration: const InputDecoration(
            labelText: 'Verkäufernummern pro PDF-Seite',
          ),
          items: [
            for (var i = 1; i <= 28; i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            try {
              await widget.store.setSetting(
                'ruecksortier_spalten_pro_seite',
                v,
              );
              if (mounted) setState(() => _slots = v);
            } catch (e) {
              if (context.mounted) _error(context, e);
            }
          },
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () => _report(
                context,
                'Ruecksortierliste',
                () => OperationsReports.unsoldPdf(
                  widget.store.session,
                  data.accounting,
                  numberSlots: _slots,
                ),
              ),
              child: const Text('Rücksortierliste als PDF'),
            ),
            TextButton(
              onPressed: () => _textReport(
                context,
                'NichtVerkauft',
                OperationsReports.unsoldJson(
                  widget.store.session,
                  data.accounting,
                ),
                'json',
              ),
              child: const Text('JSON exportieren'),
            ),
            TextButton(
              onPressed: () => _textReport(
                context,
                'NichtVerkauft',
                OperationsReports.unsoldText(
                  widget.store.session,
                  data.accounting,
                ),
                'txt',
              ),
              child: const Text('Text exportieren'),
            ),
          ],
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Verkäuferkennung oder Box suchen',
          ),
          onChanged: (v) => setState(() => _filter = v.trim()),
        ),
        for (final seller in sellers.where(
          (s) =>
              s.sellerKey.contains(_filter) ||
              s.boxNumbers.any((b) => '$b' == _filter),
        ))
          ExpansionTile(
            title: Text(
              '${seller.sellerKey} · ${seller.unsold.length} nicht verkauft',
            ),
            subtitle: Text('Boxen ${seller.boxNumbers.join(', ')}'),
            children: [
              if (seller.unsold.isEmpty)
                const ListTile(title: Text('Alle Artikel verkauft')),
              for (final a in seller.unsold)
                ListTile(
                  title: Text('${a.boxNumber}/${a.articleNumber} · ${a.title}'),
                  subtitle: Text(a.size),
                  trailing: Text(formatCents(a.priceCents)),
                ),
            ],
          ),
      ];
    },
  );
}

class ReconciliationPage extends StatefulWidget {
  final CheckoutStore store;
  const ReconciliationPage({super.key, required this.store});
  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends State<ReconciliationPage> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  ReconciliationSession? _session;
  List<ArticleListing> _listings = [];
  String? _seller, _failure;
  bool _busy = true;
  String _feedback = '';
  Future<void> _queue = Future.value();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load({String? seller, bool changeSeller = false}) async {
    setState(() => _busy = true);
    try {
      final listings = await widget.store.allListings(),
          events = await widget.store.events();
      final saved = await widget.store.reconciliationStates();
      final session = ReconciliationSession(
        listings: listings,
        events: events,
        sellerKey: changeSeller ? seller : _seller,
        saved: saved.map(
          (key, value) => MapEntry(key, ReconciliationState.fromMap(value)),
        ),
      );
      if (mounted) {
        setState(() {
          _listings = listings;
          if (changeSeller) _seller = seller;
          _session = session;
          _failure = null;
          _feedback = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _failure = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit(String raw, {int? revision}) {
    if (raw.trim().isEmpty) return;
    _code.clear();
    _queue = _queue.then((_) => _record(raw, revision));
  }

  Future<void> _record(String raw, int? revision) async {
    if (!mounted || _session == null) return;
    setState(() => _busy = true);
    try {
      ArticleListing? article;
      Object? invalid;
      try {
        article = await widget.store.resolve(raw, revision: revision);
      } catch (e) {
        invalid = e;
      }
      final candidate = _session!.copy();
      var unknownLabel = false;
      if (article == null && raw.trim().startsWith('MM1|')) {
        try {
          final parsed = LabelCode.parse(raw.trim());
          unknownLabel = !_listings.any((a) => a.codeFull == parsed.codeFull);
        } on FormatException {
          /* Invalid checksum stays invalid. */
        }
      }
      final result = unknownLabel
          ? candidate.scanUnknown(raw)
          : candidate.scan(article, rawCode: raw);
      await widget.store.saveReconciliation(
        candidate.persistedStates.map(
          (key, value) => MapEntry(key, value.toMap()),
        ),
      );
      if (!mounted) return;
      setState(() {
        _session = candidate;
        _feedback = unknownLabel
            ? '${result.scanCount > 1 ? 'Doppelscan' : 'Unerwartet'}: gültiges Etikett, Artikel nicht im geladenen Markt'
            : invalid != null
            ? 'Ungültig: $invalid'
            : switch (result.status) {
                ReconciliationStatus.matched =>
                  'Gefunden: Box ${article!.boxNumber}, Artikel ${article.articleNumber}',
                ReconciliationStatus.duplicate =>
                  'Doppelscan: Box ${article!.boxNumber}, Artikel ${article.articleNumber}',
                ReconciliationStatus.unexpected =>
                  'Unerwartet: Box ${article!.boxNumber}, Artikel ${article.articleNumber}',
                _ => 'Ungültiger Code',
              };
      });
    } catch (e) {
      if (mounted) {
        setState(() => _feedback = 'Nicht gespeichert. Scan erneut versuchen.');
        _error(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  Future<void> _manual() async {
    final selected = await showDialog<ManualArticleSelection>(
      context: context,
      builder: (_) => SellerArticleDialog(store: widget.store),
    );
    if (selected != null && mounted) {
      final article = selected.listing;
      _submit(
        article.isRevisioned
            ? article.codeFull
            : '${article.boxNumber}-${article.articleNumber}',
        revision: selected.revision,
      );
    }
  }

  Future<void> _camera() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          store: widget.store,
          onScan: (code) async {
            _queue = _queue.then((_) => _record(code, null));
            await _queue;
            return _feedback;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _session?.report;
    final sellers = _listings.map((a) => a.sellerKey).toSet().toList()..sort();
    final boxes = <int, String>{
      for (final a in _listings) a.boxNumber: a.sellerKey,
    };
    final boxNumbers = boxes.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rücksortierung: Soll / Ist'),
        actions: [
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_failure != null) Text('Laden fehlgeschlagen: $_failure'),
          Text(
            widget.store.session.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_seller),
            initialValue: _seller ?? '',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Verkäufer (alle zugehörigen Boxen)',
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('Alle Verkäufer')),
              for (final seller in sellers)
                DropdownMenuItem(value: seller, child: Text(seller)),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    _load(seller: v == '' ? null : v, changeSeller: true);
                  },
          ),
          DropdownButtonFormField<int>(
            initialValue: null,
            decoration: const InputDecoration(
              labelText: 'Verkäufer über Stamm-/Boxnummer wählen',
            ),
            items: [
              for (final box in boxNumbers)
                DropdownMenuItem(
                  value: box,
                  child: Text('Box $box · ${boxes[box]}'),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) {
                      _load(seller: boxes[v], changeSeller: true);
                    }
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reconciliation-code'),
            controller: _code,
            focusNode: _focus,
            enabled: _session != null,
            decoration: const InputDecoration(
              labelText: 'Etikett / HID-Scanner',
              helperText: 'Scanner mit Enter abschließen',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: _submit,
          ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _camera,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Kamera'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _manual,
                child: const Text('Verkäufer und Artikel eingeben'),
              ),
            ],
          ),
          if (_feedback.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _feedback,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          if (report != null) ...[
            Text(
              'Erwartet: ${report.expected.length} · Gefunden: ${report.matched.length} · Fehlend: ${report.missing.length}',
            ),
            Text(
              'Verkauft: ${report.soldCount} · Unerwartet: ${report.unexpected.length + report.unknownCodes.length} · Doppelt: ${report.duplicates.length + report.unknownCodes.values.where((n) => n > 1).length} · Ungültig: ${report.invalidCodes.length}',
            ),
            if (report.isFinalized)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Alle erwarteten Artikel gefunden. Unerwartete Artikel und Doppelscans gesondert prüfen.',
                  ),
                ),
              ),
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _textReport(
                      context,
                      'Ruecksortierung',
                      OperationsReports.reconciliationCsv(
                        widget.store.session,
                        report,
                      ),
                      'csv',
                    ),
              icon: const Icon(Icons.download),
              label: const Text('Abgleich als CSV exportieren'),
            ),
            for (final group in [
              ('Offen / fehlend', report.missing),
              ('Gefunden', report.matched),
              ('Unerwartet', report.unexpected),
              ('Doppelscans', report.duplicates),
            ])
              ExpansionTile(
                title: Text('${group.$1} (${group.$2.length})'),
                initiallyExpanded: group.$1 == 'Offen / fehlend',
                children: [
                  for (final a in group.$2)
                    ListTile(
                      title: Text(
                        '${a.boxNumber}/${a.articleNumber} · ${a.title}',
                      ),
                      subtitle: Text('Verkäufer ${a.sellerKey} · ${a.size}'),
                      trailing: Text(formatCents(a.priceCents)),
                    ),
                ],
              ),
            if (report.unknownCodes.isNotEmpty)
              ExpansionTile(
                title: Text(
                  'Unbekannte gültige Etiketten (${report.unknownCodes.length})',
                ),
                children: [
                  for (final entry in report.unknownCodes.entries)
                    ListTile(
                      title: Text(entry.key),
                      subtitle: Text(
                        '${entry.value} Scans · unerwarteter Artikel',
                      ),
                    ),
                ],
              ),
            if (report.invalidCodes.isNotEmpty)
              ExpansionTile(
                title: Text('Ungültige Codes (${report.invalidCodes.length})'),
                children: [
                  for (final code in report.invalidCodes)
                    ListTile(title: Text(code)),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
