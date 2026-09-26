import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../data/demo_catalog.dart';
import '../domain/barcode.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'camera_page.dart';
import 'manual_dialog.dart';
import 'messages.dart';
import 'payment_dialog.dart';
import 'receipt_page.dart';

class RegisterPage extends StatefulWidget {
  final CheckoutStore store;
  const RegisterPage({super.key, required this.store});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _code = TextEditingController();
  final _scanFocus = FocusNode();
  List<ArticleListing> _cart = [];
  bool _busy = true, _recovered = false, _modal = false;
  final List<String> _scans = [];
  bool _scanning = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _run(() async {
      _cart = await widget.store.cart();
      _recovered = _cart.isNotEmpty;
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final cart = await widget.store.cart();
      if (mounted) setState(() => _cart = cart);
    } catch (e) {
      if (mounted) setState(() => _error = checkoutError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan(String value) async {
    if (value.trim().isEmpty) return;
    _code.clear();
    if (_modal || (_busy && !_scanning)) {
      setState(
        () =>
            _error = 'Kasse beschäftigt. Diesen Artikel bitte erneut scannen.',
      );
      return;
    }
    _scans.add(value);
    if (_scanning) return;
    _scanning = true;
    String? firstError;
    try {
      while (_scans.isNotEmpty && mounted) {
        final raw = _scans.removeAt(0);
        await _run(() => widget.store.addScan(raw));
        firstError ??= _error;
      }
    } finally {
      _scanning = false;
      if (mounted) {
        if (firstError != null) setState(() => _error = firstError);
        _scanFocus.requestFocus();
      }
    }
  }

  Future<void> _manual() async {
    _scanFocus.unfocus();
    _modal = true;
    final label = await showDialog<LabelCode>(
      context: context,
      builder: (_) => const ManualDialog(),
    );
    if (!mounted) return;
    if (label != null) {
      await _run(() => widget.store.addManual(label.codeFull, label.revision));
    }
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _camera() async {
    _scanFocus.unfocus();
    _modal = true;
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CameraPage()),
    );
    _modal = false;
    if (mounted && raw != null) await _scan(raw);
  }

  Future<void> _pay() async {
    _scanFocus.unfocus();
    _modal = true;
    final total = _cart.fold(0, (sum, item) => sum + item.priceCents);
    final received = await showDialog<int>(
      context: context,
      builder: (_) => PaymentDialog(totalCents: total),
    );
    if (!mounted) return;
    if (received != null) {
      Receipt? receipt;
      await _run(() async {
        receipt = await widget.store.checkout(received);
        _recovered = false;
      });
      if (mounted && receipt != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Beleg ${receipt!.number} gespeichert'),
            content: Text('Rückgeld: ${formatCents(receipt!.changeCents)}'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Nächster Kunde'),
              ),
            ],
          ),
        );
      }
    }
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final total = _cart.fold(0, (sum, item) => sum + item.priceCents);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MarketMate'),
        actions: [
          IconButton(
            tooltip: 'Belege',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: _busy
                ? null
                : () async {
                    _scanFocus.unfocus();
                    _modal = true;
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReceiptPage(store: widget.store),
                      ),
                    );
                    _modal = false;
                    if (mounted) {
                      await _run(() async {});
                      _scanFocus.requestFocus();
                    }
                  },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Demo · Keine echten Verkäufe',
                    style: TextStyle(
                      color: Color(0xffb45309),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Demomarkt / Kasse 1 · Lokal gespeichert'),
                  const SizedBox(height: 24),
                  Text(
                    'Kassieren',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('scan-input'),
                    controller: _code,
                    focusNode: _scanFocus,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Etikett scannen',
                      hintText: 'Scanner mit Enter-Abschluss',
                      suffixIcon: IconButton(
                        tooltip: 'Code übernehmen',
                        onPressed: () => _scan(_code.text),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ),
                    onSubmitted: _scan,
                    // Keep HID focus across Enter; serialize writes in _scan.
                    onEditingComplete: () {},
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _camera,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Kamera'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _manual,
                        icon: const Icon(Icons.keyboard_outlined),
                        label: const Text('Manuell'),
                      ),
                    ],
                  ),
                  if (_recovered)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Offener Warenkorb wiederhergestellt. Vor dem Abschluss prüfen, ob bereits Bargeld übergeben wurde.',
                        style: TextStyle(color: Color(0xffb45309)),
                      ),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Warenkorb · ${_cart.length} Artikel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_cart.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Bereit für den ersten Artikel.\nEtikett scannen oder manuell eingeben.',
                      ),
                    ),
                  for (final item in _cart)
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 4, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Verkäufer ${item.sellerNumber} · Artikel ${item.articleNumber}',
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    formatCents(item.priceCents),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Artikel entfernen',
                              onPressed: () => _run(
                                () => widget.store.remove(item.listingId),
                              ),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Divider(height: 32),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Demoartikel zum Ausprobieren'),
                    children: [
                      for (final item in demoCatalog)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.title),
                          subtitle: Text(
                            '${formatCents(item.priceCents)} · Revision 1',
                          ),
                          trailing: const Icon(Icons.add_circle_outline),
                          onTap: () => _run(
                            () => widget.store.addManual(
                              item.codeFull,
                              item.labelRevision,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) const LinearProgressIndicator(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gesamt'),
                  Text(
                    formatCents(total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('checkout'),
                  onPressed: _busy || _cart.isEmpty ? null : _pay,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Bar kassieren'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
