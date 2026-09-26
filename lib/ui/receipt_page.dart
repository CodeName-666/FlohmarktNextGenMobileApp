import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'messages.dart';
import 'package:printing/printing.dart';
import '../services/catalog_reports.dart';
import '../domain/catalog_search.dart';

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

  @override
  Widget build(BuildContext context) {
    final cancelled = _events
        .map((e) => e.cancelOf)
        .whereType<String>()
        .toSet();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Belege · ${widget.store.session.name}'),
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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!_busy && _receipts.isEmpty)
                const Text('Noch keine abgeschlossenen Verkäufe.'),
              for (final receipt in _receipts)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Beleg ${receipt.number} · ${formatCents(receipt.totalCents)}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Kasse ${receipt.registerNumber} · ${localEventTime(receipt.occurredAt)}',
                        ),
                        Text(
                          receipt.tenderedKnown
                              ? 'Gegeben ${formatCents(receipt.tenderedCents)} · Rückgeld ${formatCents(receipt.changeCents)}'
                              : 'Bargeldübergabe bestätigt · Betrag nicht erfasst',
                        ),
                        SelectableText('Vorgang: ${receipt.id}'),
                        for (final event in receiptHistory(receipt, _events))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(event.listing.title),
                            subtitle: Text(
                              '${formatCents(event.cancelOf == null ? event.listing.priceCents : -event.listing.priceCents)} · ${event.cancelOf != null
                                  ? 'Storno / Rückgabe'
                                  : cancelled.contains(event.id)
                                  ? 'Verkauf storniert'
                                  : 'Verkauft'}\n${event.listing.sellerKey} · Box ${event.listing.boxNumber} · Artikel ${event.listing.articleNumber}\n${localEventTime(event.occurredAt)} · ${event.id}${event.cancelOf == null ? '' : '\nOriginal: ${event.cancelOf}'}',
                            ),
                            trailing:
                                event.cancelOf != null ||
                                    cancelled.contains(event.id)
                                ? const Icon(Icons.undo)
                                : IconButton(
                                    tooltip: 'Position stornieren',
                                    onPressed: _busy
                                        ? null
                                        : () => _cancel(event),
                                    icon: const Icon(Icons.undo),
                                  ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () => _print(receipt),
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Bon erneut drucken / teilen'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
