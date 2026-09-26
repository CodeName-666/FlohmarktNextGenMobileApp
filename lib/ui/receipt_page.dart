import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'messages.dart';

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

  @override
  Widget build(BuildContext context) {
    final cancelled = _events
        .map((e) => e.cancelOf)
        .whereType<String>()
        .toSet();
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Belege · Demo')),
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
                          'Kasse 1 · ${DateTime.parse(receipt.occurredAt).toLocal().toString().substring(0, 16)}',
                        ),
                        Text(
                          'Gegeben ${formatCents(receipt.tenderedCents)} · Rückgeld ${formatCents(receipt.changeCents)}',
                        ),
                        for (final sale in _events.where(
                          (e) =>
                              e.receiptId == receipt.id && e.cancelOf == null,
                        ))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(sale.listing.title),
                            subtitle: Text(
                              '${formatCents(sale.listing.priceCents)} · ${cancelled.contains(sale.id) ? 'Storniert' : 'Verkauft'}',
                            ),
                            trailing: cancelled.contains(sale.id)
                                ? const Icon(Icons.undo)
                                : IconButton(
                                    tooltip: 'Position stornieren',
                                    onPressed: _busy
                                        ? null
                                        : () => _cancel(sale),
                                    icon: const Icon(Icons.undo),
                                  ),
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
