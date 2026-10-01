import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'messages.dart';
import 'package:printing/printing.dart';
import '../services/catalog_reports.dart';
import '../domain/catalog_search.dart';
import 'tones.dart';

class ReceiptPage extends StatefulWidget {
  final CheckoutStore store;
  const ReceiptPage({super.key, required this.store});
  @override
  State<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends State<ReceiptPage> {
  List<Receipt> _receipts = [];
  List<SaleEvent> _events = [];
  bool _busy = true;
  String? _error;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _busy = true;
      });
    }
    try {
      final receipts = await widget.store.receipts();
      final events = await widget.store.events();
      if (mounted) {
        setState(() {
          _receipts = receipts;
          _events = events;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = checkoutError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(SaleEvent sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verkauf stornieren?'),
        content: Text(
          '${sale.listing.title}\nRückzahlung: ${formatCents(sale.listing.priceCents)}\n'
          'Die Position bleibt im Beleg nachvollziehbar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Storno bestätigen'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.cancel(sale.id);
    } catch (e) {
      if (mounted) setState(() => _error = checkoutError(e));
    }
    await _reload();
  }

  Future<void> _print(Receipt receipt) async {
    try {
      final bytes = await buildReceiptPdf(
        widget.store.session,
        receipt,
        _events,
      );
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                title: const Text('Systemdruck / Vorschau'),
                onTap: () => Navigator.pop(context, 'print'),
              ),
              ListTile(
                title: const Text('PDF teilen'),
                onTap: () => Navigator.pop(context, 'share'),
              ),
            ],
          ),
        ),
      );
      if (action == 'print') {
        await Printing.layoutPdf(
          name: 'Beleg-${receipt.number}.pdf',
          onLayout: (_) async => bytes,
        );
      } else if (action == 'share') {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'Beleg-${receipt.number}.pdf',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Beleg bleibt gespeichert. Druck fehlgeschlagen: $e',
        );
      }
    }
  }

  bool _matches(Receipt receipt) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if ('${receipt.number}' == q) return true;
    return receiptHistory(receipt, _events).any(
      (e) =>
          e.listing.title.toLowerCase().contains(q) ||
          e.listing.sellerKey.toLowerCase().contains(q) ||
          '${e.listing.boxNumber}' == q,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cancelled = _events
        .map((e) => e.cancelOf)
        .whereType<String>()
        .toSet();
    final visible = _receipts.where(_matches).toList();
    final total = _receipts.fold(0, (sum, r) => sum + r.totalCents);
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 36 + MediaQuery.textScalerOf(context).scale(28),
          titleSpacing: 20,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Belege',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${widget.store.session.name} · ${_receipts.length} Belege · ${formatCents(total)}',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Aktualisieren',
              onPressed: _busy
                  ? null
                  : () {
                      setState(() => _error = null);
                      _reload();
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Beleg-Nr., Artikel, Verkäufer oder Box',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 10),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Notice(_error!, error: true),
                  if (!_busy && _receipts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Noch keine abgeschlossenen Verkäufe.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  if (!_busy && _receipts.isNotEmpty && visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Keine passenden Belege. Suchbegriff ändern oder leeren.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final receipt in visible)
                    _receiptCard(
                      context,
                      receipt,
                      cancelled,
                      expanded: receipt == visible.first,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptCard(
    BuildContext context,
    Receipt receipt,
    Set<String> cancelled, {
    required bool expanded,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final history = receiptHistory(receipt, _events);
    final time = localEventTime(receipt.occurredAt).split(' ').last;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(receipt.id),
        initiallyExpanded: expanded,
        shape: const Border(),
        title: Text(
          'Beleg ${receipt.number}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$time · ${history.length} ${history.length == 1 ? 'Position' : 'Positionen'}',
        ),
        trailing: Text(
          formatCents(receipt.totalCents),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: receipt.totalCents < 0 ? Tones.warning(context) : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final event in history)
            _position(context, event, cancelled.contains(event.id)),
          const SizedBox(height: 8),
          Text(
            receipt.tenderedKnown
                ? 'Gegeben ${formatCents(receipt.tenderedCents)} · Rückgeld ${formatCents(receipt.changeCents)}'
                : 'Bargeldübergabe bestätigt · Betrag nicht erfasst',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _print(receipt),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Bon erneut drucken / teilen'),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            'Kasse ${receipt.registerNumber} · ${localEventTime(receipt.occurredAt)} · Vorgang ${receipt.id}',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _position(BuildContext context, SaleEvent event, bool isCancelled) {
    final scheme = Theme.of(context).colorScheme;
    final isReturn = event.cancelOf != null;
    final l = event.listing;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  l.title,
                  style: TextStyle(
                    decoration: isCancelled ? TextDecoration.lineThrough : null,
                    color: isCancelled ? scheme.onSurfaceVariant : null,
                  ),
                ),
                Text(
                  'Verk. ${l.sellerKey} · Box ${l.boxNumber} · Art. ${l.articleNumber}',
                  style: muted.copyWith(fontFamily: 'monospace'),
                ),
                if (isReturn || isCancelled)
                  Tag(
                    isReturn ? 'Storno / Rückgabe' : 'Verkauf storniert',
                    background: Tones.warningContainer(context),
                    foreground: Tones.onWarningContainer(context),
                  ),
                if (isReturn)
                  SelectableText('Original: ${event.cancelOf}', style: muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatCents(isReturn ? -l.priceCents : l.priceCents),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isReturn ? Tones.warning(context) : null,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (isReturn || isCancelled)
            const SizedBox(width: 48)
          else
            IconButton(
              tooltip: 'Position stornieren',
              onPressed: _busy ? null : () => _cancel(event),
              icon: const Icon(Icons.undo),
            ),
        ],
      ),
    );
  }
}
