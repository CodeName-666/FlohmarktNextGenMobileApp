import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../data/demo_catalog.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../domain/accounting.dart';
import 'camera_page.dart';
import 'catalog_pages.dart';
import 'seller_article_dialog.dart';
import 'messages.dart';
import 'payment_dialog.dart';
import 'receipt_page.dart';
import 'package:printing/printing.dart';
import '../services/catalog_reports.dart';

class RegisterPage extends StatefulWidget {
  final CheckoutStore store;
  const RegisterPage({super.key, required this.store});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _code = TextEditingController();
  final _scanFocus = FocusNode();
  List<CartEntry> _cart = [];
  bool _returnMode = false;
  bool _busy = true, _recovered = false, _modal = false;
  final List<String> _scans = [];
  bool _scanning = false;
  String? _error;
  bool _recoveryChecked = false;
  int _heldCount = 0, _heldTotal = 0, _slot = 0;
  bool _heldNeedsReview = false, _ready = false;
  CartEntry? _lastLine;
  String? _lastRaw;
  String _paymentInput = '';
  int _registerRevenue = 0, _registerItems = 0, _registerCustomers = 0;
  bool get _needsReview => _recovered && !_recoveryChecked;
  bool get _canEdit => _ready && !_busy && !_modal && !_needsReview;
  bool _guard() {
    if (_canEdit) return true;
    if (mounted) {
      setState(
        () => _error = _needsReview
            ? 'Zuerst Artikel und Zahlungsstand prüfen.'
            : 'Kasse beschäftigt. Bitte warten.',
      );
    }
    return false;
  }

  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final success = await _run(() async {
      _cart = await widget.store.cartLines();
      _recovered = _cart.isNotEmpty;
      _heldNeedsReview = (await widget.store.heldCart()).isNotEmpty;
    });
    if (mounted) setState(() => _ready = success);
  }

  @override
  void dispose() {
    _code.dispose();
    _scanFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (!mounted) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      final cart = await widget.store.cartLines();
      final held = await widget.store.heldCart();
      _paymentInput =
          (await widget.store.setting('draftPaymentInput')) as String? ?? '';
      _heldCount = held.length;
      _heldTotal = held.fold(0, (sum, line) => sum + line.signedCents);
      final sales = effectiveSaleEvents(await widget.store.events())
          .where((e) => e.registerNumber == widget.store.session.registerNumber)
          .toList();
      _registerRevenue = sales.fold(0, (sum, e) => sum + e.listing.priceCents);
      _registerItems = sales.length;
      _registerCustomers = sales
          .where((e) => e.customerNumber > 0)
          .map((e) => e.customerNumber)
          .toSet()
          .length;
      if (_lastLine != null &&
          !cart.any((line) => line.entryId == _lastLine!.entryId)) {
        _lastLine = null;
        _lastRaw = null;
      }
      if (mounted) setState(() => _cart = cart);
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = checkoutError(e));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scan(String value) async {
    if (value.trim().isEmpty) return;
    _code.clear();
    if (!_ready || _needsReview || _modal || (_busy && !_scanning)) {
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
        final success = await _run(() async {
          if (_returnMode) {
            final listing = await widget.store.resolve(raw);
            await widget.store.addReturn(listing.listingId);
          } else {
            await widget.store.addScan(raw);
          }
        });
        if (success && _cart.isNotEmpty) {
          setState(() {
            _lastLine = _cart.last;
            _lastRaw = raw;
          });
        }
        firstError ??= _error;
      }
    } finally {
      _scanning = false;
      if (mounted) {
        if (firstError != null) setState(() => _error = firstError);
        _scanFocus.requestFocus();
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      }
    }
  }

  Future<void> _manual() async {
    if (!_guard()) return;
    _scanFocus.unfocus();
    _modal = true;
    final selected = await showDialog<ManualArticleSelection>(
      context: context,
      builder: (_) => SellerArticleDialog(store: widget.store),
    );
    if (!mounted) return;
    if (selected != null) {
      final success = await _run(
        () => _returnMode
            ? widget.store.addReturn(selected.listing.listingId)
            : widget.store.addResolved(
                selected.listing,
                visibleRevision: selected.revision,
              ),
      );
      if (success && _cart.isNotEmpty) {
        setState(() {
          _lastLine = _cart.last;
          _lastRaw = 'Manuell';
        });
      }
    }
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _camera() async {
    if (!_guard()) return;
    _scanFocus.unfocus();
    _modal = true;
    final raw = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(
          store: widget.store,
          onScan: (raw) async {
            if (_recovered && !_recoveryChecked) {
              throw StateError('Zuerst Artikel und Zahlungsstand prüfen.');
            }
            final listing = await widget.store.resolve(raw);
            if (_returnMode) {
              await widget.store.addReturn(listing.listingId);
            } else {
              await widget.store.addScan(raw);
            }
            _lastLine = (await widget.store.cartLines()).last;
            _lastRaw = raw;
            return '${_returnMode ? 'Rückgabe' : 'Im Warenkorb'}: ${listing.title} · ${formatCents(listing.priceCents)}';
          },
        ),
      ),
    );
    _modal = false;
    if (mounted) {
      if (raw != null) {
        await _scan(raw);
      } else {
        await _run(() async {});
      }
    }
  }

  Future<void> _discard() async {
    if (_busy || _modal) return;
    _modal = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Warenkorb verwerfen?'),
        content: const Text(
          'Vorgemerkte Verkäufe und Rückgaben werden entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _run(() async {
        await widget.store.discardCart();
        _recovered = false;
        _recoveryChecked = false;
      });
    }
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _search() async {
    if (!_guard()) return;
    _modal = true;
    _scanFocus.unfocus();
    final listing = await Navigator.push<ArticleListing>(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleSearchPage(
          store: widget.store,
          selectForCheckout: true,
          selectForReturn: _returnMode,
        ),
      ),
    );
    if (!mounted) return;
    if (listing != null) {
      int? revision;
      if (listing.isRevisioned && !_returnMode) {
        final controller = TextEditingController();
        revision = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Etikettenrevision prüfen'),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sichtbare Revision am Etikett',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () {
                  final value = int.tryParse(controller.text);
                  if (value != null) Navigator.pop(context, value);
                },
                child: const Text('Prüfen'),
              ),
            ],
          ),
        );
        controller.dispose();
      }
      if (mounted &&
          (!listing.isRevisioned || revision != null || _returnMode)) {
        final success = await _run(
          () => _returnMode
              ? widget.store.addReturn(listing.listingId)
              : widget.store.addResolved(listing, visibleRevision: revision),
        );
        if (success && _cart.isNotEmpty) {
          setState(() {
            _lastLine = _cart.last;
            _lastRaw = 'Artikelsuche';
          });
        }
      }
    }
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _pay() async {
    if (!_guard()) return;
    _scanFocus.unfocus();
    _modal = true;
    final total = _cart.fold(0, (sum, item) => sum + item.signedCents);
    Receipt? receipt;
    bool parked = false;
    final received = await showDialog<PaymentInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentDialog(
        totalCents: total,
        initialInput: _paymentInput,
        onPark: (value) async {
          await widget.store.setSetting('draftPaymentInput', value);
          parked = true;
        },
        onConfirm: (input) async {
          receipt = await widget.store.checkout(
            input.cents,
            tenderedKnown: input.known,
          );
        },
      ),
    );
    if (!mounted) return;
    if (received != null && receipt != null) {
      _recovered = false;
      _recoveryChecked = false;
      _returnMode = false;
      _lastLine = null;
      _lastRaw = null;
      await _run(() async {});
      if (mounted && receipt != null) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Beleg ${receipt!.number} gespeichert'),
            content: Text(
              receipt!.tenderedKnown
                  ? 'Rückgeld: ${formatCents(receipt!.changeCents)}'
                  : 'Bargeldübergabe bestätigt. Kein Wechselgeld berechnet.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    final bytes = await buildReceiptPdf(
                      widget.store.session,
                      receipt!,
                      await widget.store.events(),
                    );
                    await Printing.layoutPdf(onLayout: (_) async => bytes);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Beleg gespeichert, Druck fehlgeschlagen: $e',
                          ),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Bon drucken'),
              ),
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
    if (parked && mounted) await _swap();
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _swap() async {
    if (_busy || _modal) return;
    final currentNeedsReview = _needsReview;
    final success = await _run(widget.store.swapCustomer);
    if (success && mounted) {
      setState(() {
        _slot = 1 - _slot;
        _recovered = _heldNeedsReview;
        _recoveryChecked = false;
        _heldNeedsReview = currentNeedsReview;
        _returnMode = false;
        _lastLine = null;
        _lastRaw = null;
      });
    }
    if (mounted) _scanFocus.requestFocus();
  }

  Future<void> _controlSum() async {
    _modal = true;
    _scanFocus.unfocus();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kontrollsumme'),
        content: Text(
          'Kundenentwurf ${_slot == 0 ? 'A' : 'B'}: ${_cart.fold(0, (n, l) => n + (l.cancelOf == null ? 1 : -1))} Artikel netto · ${formatCents(_cart.fold(0, (n, l) => n + l.signedCents))}\nGeparkter Entwurf: $_heldCount Positionen · ${formatCents(_heldTotal)}\n\nAbgeschlossen, Kasse ${widget.store.session.registerNumber}: $_registerCustomers Kunden · $_registerItems Artikel · ${formatCents(_registerRevenue)}\nEntwürfe sind noch keine Verkäufe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
    _modal = false;
    if (mounted) _scanFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final total = _cart.fold(0, (sum, item) => sum + item.signedCents);
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
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.store.session.isDemo)
                      const Text(
                        'Demo · Keine echten Verkäufe',
                        style: TextStyle(
                          color: Color(0xffb45309),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.store.session.name} / Kasse ${widget.store.session.registerNumber} · ${_busy
                          ? 'Speicherung läuft'
                          : _error != null
                          ? 'Stand prüfen'
                          : 'Lokal gespeichert'}',
                    ),
                    Text(
                      'Kundenentwurf ${_slot == 0 ? 'A' : 'B'} · Kassenumsatz ${formatCents(_registerRevenue)}',
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Kassieren',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
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
                          onPressed: _canEdit ? _camera : null,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Kamera'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canEdit ? _manual : null,
                          icon: const Icon(Icons.keyboard_outlined),
                          label: const Text('Manuell'),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rückgabe vormerken'),
                      subtitle: const Text(
                        'Erstattung wird erst beim Abschluss gespeichert.',
                      ),
                      value: _returnMode,
                      onChanged: _canEdit
                          ? (value) => setState(() => _returnMode = value)
                          : null,
                    ),
                    OutlinedButton.icon(
                      onPressed: _canEdit ? _search : null,
                      icon: const Icon(Icons.search),
                      label: const Text('Artikel suchen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _modal ? null : _swap,
                      icon: const Icon(Icons.people_alt_outlined),
                      label: Text(
                        'Kundenkorb parken / wechseln · $_heldCount wartend (${formatCents(_heldTotal)})',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy || _modal ? null : _controlSum,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Kontrollsumme'),
                    ),
                    if (_cart.isNotEmpty)
                      TextButton(
                        onPressed: _discard,
                        child: const Text('Warenkorb verwerfen'),
                      ),
                    if (_recovered)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Artikel und Zahlungsstand geprüft'),
                        value: _recoveryChecked,
                        onChanged: (value) =>
                            setState(() => _recoveryChecked = value ?? false),
                      ),
                    if (_recovered)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text(
                          'Offener Warenkorb wiederhergestellt. Vor dem Abschluss prüfen, ob bereits Bargeld übergeben wurde.',
                          style: TextStyle(color: Color(0xffb45309)),
                        ),
                      ),
                    if (!_ready && !_busy)
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Kasse erneut laden'),
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
                      'Warenkorb · ${_cart.fold(0, (n, l) => n + (l.cancelOf == null ? 1 : -1))} Artikel netto · ${_cart.length} Positionen',
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
                    if (_lastLine != null)
                      Card(
                        key: const Key('last-scan'),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Zuletzt: ${_lastLine!.cancelOf == null ? 'Verkauf' : 'Rückgabe'} · ${_lastLine!.listing.title}\nVerkäufer ${_lastLine!.listing.sellerKey} · Box ${_lastLine!.listing.boxNumber} · Artikel ${_lastLine!.listing.articleNumber} · ${formatCents(_lastLine!.signedCents)}\n$_lastRaw',
                          ),
                        ),
                      ),
                    for (final line in _cart)
                      Card(
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
                                      line.listing.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${line.cancelOf == null ? 'Verkauf' : 'Rückgabe'} · Verkäufer ${line.listing.sellerKey} · Box ${line.listing.boxNumber} · Artikel ${line.listing.articleNumber}',
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      formatCents(line.signedCents),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Artikel entfernen',
                                onPressed: !_canEdit
                                    ? null
                                    : () => _run(
                                        () => widget.store.removeEntry(
                                          line.entryId,
                                        ),
                                      ),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Divider(height: 32),
                    if (widget.store.session.isDemo)
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
                              onTap: !_canEdit
                                  ? null
                                  : () async {
                                      if (!_guard()) return;
                                      final success = await _run(
                                        () => _returnMode
                                            ? widget.store.addReturn(
                                                item.listingId,
                                              )
                                            : widget.store.addManual(
                                                item.codeFull,
                                                item.labelRevision,
                                              ),
                                      );
                                      if (success &&
                                          _cart.isNotEmpty &&
                                          mounted) {
                                        setState(() {
                                          _lastLine = _cart.last;
                                          _lastRaw = 'Demo';
                                        });
                                      }
                                    },
                            ),
                        ],
                      ),
                  ],
                ),
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
                  onPressed:
                      !_ready ||
                          _busy ||
                          _cart.isEmpty ||
                          (_recovered && !_recoveryChecked)
                      ? null
                      : _pay,
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
