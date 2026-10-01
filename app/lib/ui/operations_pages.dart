import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'tones.dart';
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
  // Not disposed: the closing dialog still rebuilds its TextField (keyboard
  // insets) during the exit animation. Disposing here caused the red-screen
  // assertion '_dependents.isEmpty'. The controller is garbage-collected.
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
    title: 'Abrechnung',
    children: (context, data, reload) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final settlements = data.accounting.settlements();
      final visible = settlements
          .where(
            (s) =>
                s.sellerKey.toLowerCase().contains(_search.toLowerCase()) ||
                s.boxNumbers.any((b) => '$b' == _search),
          )
          .toList();
      int sum(int Function(SellerSettlement) f) =>
          settlements.fold(0, (total, s) => total + f(s));
      return [
        FigureGroup(
          children: [
            Figure('Umsatz', formatCents(sum((s) => s.revenueCents))),
            Figure('Gebühren', formatCents(sum((s) => s.feeCents))),
            Figure('Auszahlung', formatCents(sum((s) => s.payoutCents))),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton.icon(
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
            ),
            IconButton.outlined(
              tooltip: 'Textbericht',
              onPressed: () => _textReport(
                context,
                'Abrechnungen',
                OperationsReports.settlementsText(
                  widget.store.session,
                  settlements,
                ),
                'txt',
              ),
              icon: const Icon(Icons.notes),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Verkäufer oder Box suchen',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (s) => setState(() => _search = s.trim()),
        ),
        const SizedBox(height: 6),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Keine Abrechnung gefunden.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final seller in visible)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: ValueKey(seller.sellerKey),
              shape: const Border(),
              title: Text(
                'Verkäufer ${seller.sellerKey}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Box ${seller.boxNumbers.join(', ')} · ${seller.sold.length} von ${seller.offered.length} verkauft',
                  ),
                  Text(
                    'Auszahlung ${formatCents(seller.payoutCents)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FigureGroup(
                  children: [
                    Figure('Umsatz', formatCents(seller.revenueCents)),
                    Figure('Gebühren', formatCents(seller.feeCents)),
                    Figure('Rest', '${seller.unsold.length} Artikel'),
                  ],
                ),
                const SizedBox(height: 8),
                for (final box in seller.boxSettlements)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Box ${box.boxNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${box.soldCount} von ${box.offeredCount} verkauft · Rest ${box.unsoldCount} (${formatCents(box.unsoldCents)})${box.openCount > 0 ? ' · ${box.openCount} noch nicht rücksortiert' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCents(box.payoutCents),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                _warning(seller.missingCatalog),
                const SizedBox(height: 8),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _report(
                          context,
                          'Abrechnung_${seller.sellerKey}',
                          () => OperationsReports.settlementPdf(
                            widget.store.session,
                            [seller],
                          ),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Einzelabrechnung als PDF'),
                      ),
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
                  ],
                ),
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
      final scheme = Theme.of(context).colorScheme;
      final registers = {
        widget.store.session.registerNumber,
        ...data.accounting.events.map((e) => e.registerNumber),
      }.toList()..sort();
      final stats = data.accounting.statistics(registerNumber: _register);
      return [
        if (registers.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Alle Kassen'),
                selected: _register == null,
                onSelected: (_) => setState(() => _register = null),
              ),
              for (final n in registers)
                ChoiceChip(
                  label: Text('Kasse $n'),
                  selected: _register == n,
                  onSelected: (_) => setState(() => _register = n),
                ),
            ],
          ),
        const SizedBox(height: 10),
        FigureGroup(
          children: [
            Figure('Umsatz', formatCents(stats.revenueCents)),
            Figure('Verkauft', '${stats.soldCount} / ${stats.offeredCount}'),
            Figure('Kunden', '${stats.customerCount}'),
          ],
        ),
        const SizedBox(height: 10),
        _warning(stats.missingCatalog),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                for (final row in OperationsReports.statisticsRows(stats))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row[0],
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                        Text(
                          row[1],
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Angebotswerte beziehen sich auf den ganzen Katalog, Verkäufe nur auf lokal erfasste oder importierte Kassen.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton.icon(
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
            ),
            IconButton.outlined(
              tooltip: 'Textbericht',
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
              icon: const Icon(Icons.notes),
            ),
          ],
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

  Future<void> _pickSlots(BuildContext context) async {
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Verkäufernummern pro PDF-Seite'),
        children: [
          SizedBox(
            height: 320,
            width: 280,
            child: ListView(
              children: [
                for (var i = 1; i <= 28; i++)
                  ListTile(
                    title: Text('$i'),
                    trailing: i == _slots ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (value == null) return;
    try {
      await widget.store.setSetting('ruecksortier_spalten_pro_seite', value);
      if (mounted) setState(() => _slots = value);
    } catch (e) {
      if (context.mounted) _error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => _OperationsView(
    store: widget.store,
    title: 'Rücksortierlisten',
    children: (context, data, reload) {
      final scheme = Theme.of(context).colorScheme;
      final sellers = data.accounting.settlements();
      final open = sellers.fold(0, (n, s) => n + s.unsold.length);
      return [
        FigureGroup(
          children: [
            Figure('Nicht verkauft', '$open Artikel'),
            Figure('Verkäufer', '${sellers.length}'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Vor dem Sortieren alle Kassen zusammenführen. Die Liste nutzt den aktuell geladenen Bestand.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _report(
                  context,
                  'Ruecksortierliste',
                  () => OperationsReports.unsoldPdf(
                    widget.store.session,
                    data.accounting,
                    numberSlots: _slots,
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Rücksortierliste als PDF'),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Weitere Exporte',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => switch (value) {
                'slots' => _pickSlots(context),
                'json' => _textReport(
                  context,
                  'NichtVerkauft',
                  OperationsReports.unsoldJson(
                    widget.store.session,
                    data.accounting,
                  ),
                  'json',
                ),
                _ => _textReport(
                  context,
                  'NichtVerkauft',
                  OperationsReports.unsoldText(
                    widget.store.session,
                    data.accounting,
                  ),
                  'txt',
                ),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'slots',
                  child: Text('Verkäufer pro PDF-Seite: $_slots'),
                ),
                const PopupMenuItem(
                  value: 'json',
                  child: Text('JSON exportieren'),
                ),
                const PopupMenuItem(
                  value: 'txt',
                  child: Text('Text exportieren'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Verkäufer oder Box suchen',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _filter = v.trim()),
        ),
        const SizedBox(height: 6),
        for (final seller in sellers.where(
          (s) =>
              s.sellerKey.toLowerCase().contains(_filter.toLowerCase()) ||
              s.boxNumbers.any((b) => '$b' == _filter),
        ))
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              title: Text(
                'Verkäufer ${seller.sellerKey}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Box ${seller.boxNumbers.join(', ')}'),
              trailing: seller.unsold.isEmpty
                  ? Icon(Icons.check_circle, color: scheme.primary)
                  : Tag(
                      '${seller.unsold.length} zurück',
                      background: Tones.warningContainer(context),
                      foreground: Tones.onWarningContainer(context),
                    ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              children: [
                if (seller.unsold.isEmpty)
                  const ListTile(title: Text('Alle Artikel verkauft')),
                for (final a in seller.unsold) _articleRow(context, a),
              ],
            ),
          ),
      ];
    },
  );
}

Widget _articleRow(BuildContext context, ArticleListing a, {String? note}) {
  final muted = TextStyle(
    fontSize: 12,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            '${a.boxNumber}/${a.articleNumber}',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.title.isEmpty ? 'Artikel ${a.articleNumber}' : a.title),
              if (note != null || a.size.isNotEmpty)
                Text(
                  [?note, if (a.size.isNotEmpty) a.size].join(' · '),
                  style: muted,
                ),
            ],
          ),
        ),
        Text(
          formatCents(a.priceCents),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    ),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = _session?.report;
    final boxesBySeller = <String, Set<int>>{};
    for (final a in _listings) {
      boxesBySeller.putIfAbsent(a.sellerKey, () => {}).add(a.boxNumber);
    }
    final sellers = boxesBySeller.keys.toList()..sort();
    final expected = report?.expected.length ?? 0;
    final matched = report?.matched.length ?? 0;
    final unexpectedCount =
        (report?.unexpected.length ?? 0) + (report?.unknownCodes.length ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rücksortierung'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'Abgleich als CSV exportieren',
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
              icon: const Icon(Icons.ios_share),
            ),
          IconButton(
            tooltip: 'Neu laden',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_failure != null)
                Notice('Laden fehlgeschlagen: $_failure', error: true),
              DropdownButtonFormField<String>(
                key: ValueKey(_seller),
                initialValue: _seller ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Verkäufer'),
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Alle Verkäufer'),
                  ),
                  for (final seller in sellers)
                    DropdownMenuItem(
                      value: seller,
                      child: Text(
                        '$seller · Box ${(boxesBySeller[seller]!.toList()..sort()).join(', ')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) =>
                          _load(seller: v == '' ? null : v, changeSeller: true),
              ),
              const SizedBox(height: 10),
              if (report != null)
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 8,
                      children: [
                        Text(
                          report.isFinalized
                              ? 'Alle $expected Artikel zurück'
                              : '$matched von $expected zurück',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // A plain bar: LinearProgressIndicator means "busy" here.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Container(
                            height: 10,
                            color: scheme.surfaceContainerHighest,
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: expected == 0
                                  ? 0
                                  : matched / expected,
                              child: Container(color: scheme.primary),
                            ),
                          ),
                        ),
                        Text(
                          'Erwartet: $expected · Gefunden: $matched · Fehlend: ${report.missing.length} · Verkauft: ${report.soldCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('reconciliation-code'),
                      controller: _code,
                      focusNode: _focus,
                      enabled: _session != null,
                      decoration: const InputDecoration(
                        labelText: 'Etikett scannen',
                        hintText: 'Scanner mit Enter-Abschluss',
                        prefixIcon: Icon(Icons.qr_code_scanner),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _submit,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Kamera',
                    onPressed: _busy ? null : _camera,
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                  IconButton.outlined(
                    tooltip: 'Verkäufer und Artikel eingeben',
                    onPressed: _busy ? null : _manual,
                    icon: const Icon(Icons.keyboard_outlined),
                  ),
                ],
              ),
              if (_feedback.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Notice(
                    _feedback,
                    error:
                        !_feedback.startsWith('Gefunden') &&
                        !_feedback.startsWith('Doppelscan'),
                  ),
                ),
              const SizedBox(height: 10),
              if (report != null) ...[
                _group(
                  context,
                  'Fehlt noch',
                  report.missing,
                  highlight: scheme.errorContainer,
                  expanded: true,
                ),
                if (unexpectedCount > 0)
                  _group(
                    context,
                    'Unerwartet',
                    report.unexpected,
                    highlight: Tones.warningContainer(context),
                    extra: [
                      for (final entry in report.unknownCodes.entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.key),
                          subtitle: Text(
                            '${entry.value} Scans · nicht im geladenen Markt',
                          ),
                        ),
                    ],
                    count: unexpectedCount,
                  ),
                if (report.duplicates.isNotEmpty)
                  _group(context, 'Doppelscans', report.duplicates),
                if (report.invalidCodes.isNotEmpty)
                  _group(
                    context,
                    'Ungültige Codes',
                    const [],
                    extra: [
                      for (final code in report.invalidCodes)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(code),
                        ),
                    ],
                    count: report.invalidCodes.length,
                  ),
                _group(context, 'Zurück', report.matched),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    List<ArticleListing> articles, {
    Color? highlight,
    bool expanded = false,
    List<Widget> extra = const [],
    int? count,
  }) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      shape: const Border(),
      initiallyExpanded: expanded,
      backgroundColor: null,
      collapsedBackgroundColor: highlight,
      title: Text(
        '$title (${count ?? articles.length})',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      children: [
        for (final a in articles)
          _articleRow(context, a, note: 'Verkäufer ${a.sellerKey}'),
        ...extra,
      ],
    ),
  );
}
