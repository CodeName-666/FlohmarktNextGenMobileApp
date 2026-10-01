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
import 'tones.dart';

class RegisterPage extends StatefulWidget {
  final CheckoutStore store;

  /// False while another tab of the app shell is shown.
  final bool active;
  const RegisterPage({super.key, required this.store, this.active = true});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _code = TextEditingController();
  late final FocusNode _scanFocus;
  List<CartEntry> _cart = [];
  bool _returnMode = false;
  bool _busy = true, _recovered = false, _modal = false;
  final List<String> _scans = [];
  bool _scanning = false;
  String? _error;
  bool _recoveryChecked = false;
  int _heldCount = 0, _heldTotal = 0, _draftNumber = 1;
  List<ParkedDraft> _parkedDrafts = [];
  final Set<String> _unreviewedEntries = {};
  bool _ready = false;
  CartEntry? _lastLine;
  String? _lastRaw;
  String _paymentInput = '';
  int _registerRevenue = 0, _registerItems = 0, _registerCustomers = 0;
  bool get _needsReview => _recovered && !_recoveryChecked;
  bool get _canEdit =>
      widget.active && _ready && !_busy && !_modal && !_needsReview;
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
    _scanFocus = FocusNode(canRequestFocus: widget.active);
    _load();
  }

  Future<void> _load() async {
    final success = await _run(() async {
      _cart = await widget.store.cartLines();
      _recovered = _cart.isNotEmpty;
      _unreviewedEntries.addAll(
        (await widget.store.heldCart()).map((e) => e.entryId),
      );
      _unreviewedEntries.addAll(_cart.map((e) => e.entryId));
    });
    if (mounted) setState(() => _ready = success);
  }

  @override
  void didUpdateWidget(RegisterPage old) {
    super.didUpdateWidget(old);
    _scanFocus.canRequestFocus = widget.active;
    if (!widget.active) {
      _scanFocus.unfocus();
    }
    // Back on the tab: totals may have changed (storno), scanner needs focus.
    if (widget.active && !old.active && _ready && !_busy && !_modal) {
      _run(() async {});
      _focusScanner();
    }
  }

  void _focusScanner() {
    if (mounted && widget.active) {
      _scanFocus.requestFocus();
    }
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
      _parkedDrafts = await widget.store.parkedDrafts();
      _draftNumber = await widget.store.activeDraftNumber();
      final held = _parkedDrafts.expand((d) => d.entries).toList();
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
    if (!mounted || !widget.active || value.trim().isEmpty) return;
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
        _focusScanner();
        if (_scroll.hasClients) {
          _scroll.animateTo(
            0,
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
    if (mounted) _focusScanner();
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
    if (mounted) _focusScanner();
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
        // Not disposed: the closing dialog still rebuilds its TextField (keyboard
        // insets) during the exit animation. Disposing here caused the red-screen
        // assertion '_dependents.isEmpty'. The controller is garbage-collected.
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
    if (mounted) _focusScanner();
  }

  Future<void> _pay() async {
    if (!_guard()) return;
    _scanFocus.unfocus();
    _modal = true;
    final total = _cart.fold(0, (sum, item) => sum + item.signedCents);
    Receipt? receipt;
    bool parked = false;
    final received = await showModalBottomSheet<PaymentInput>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      useSafeArea: true,
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
          builder: (context) => _SavedScreen(
            receipt: receipt!,
            onPrint: () async {
              final bytes = await buildReceiptPdf(
                widget.store.session,
                receipt!,
                await widget.store.events(),
              );
              await Printing.layoutPdf(onLayout: (_) async => bytes);
            },
          ),
        );
      }
    }
    _modal = false;
    if (parked && mounted) await _park();
    if (mounted) _focusScanner();
  }

  Future<void> _changeDraft(Future<void> Function() action) async {
    if (_busy || _modal) return;
    if (_recovered && _recoveryChecked) {
      _unreviewedEntries.removeAll(_cart.map((e) => e.entryId));
    }
    final success = await _run(action);
    if (success && mounted) {
      setState(() {
        _recovered = _cart.any((e) => _unreviewedEntries.contains(e.entryId));
        _recoveryChecked = false;
        _returnMode = false;
        _lastLine = null;
        _lastRaw = null;
      });
    }
    if (mounted) _focusScanner();
  }

  Future<void> _park() => _changeDraft(widget.store.parkCart);

  Future<void> _chooseParked() async {
    if (_busy || _modal) return;
    _scanFocus.unfocus();
    setState(() => _modal = true);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Geparkte Vorgänge'),
        children: [
          for (final draft in _parkedDrafts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, draft.id),
              child: Text(
                'Vorgang ${draft.number} · ${formatCents(draft.totalCents)}\n${draft.entries.length} Positionen',
              ),
            ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _modal = false);
    if (selected != null) {
      await _changeDraft(() => widget.store.resumeDraft(selected));
    }
    if (mounted) _focusScanner();
  }

  Future<void> _controlSum() async {
    _modal = true;
    _scanFocus.unfocus();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kontrollsumme'),
        content: Text(
          'Vorgang $_draftNumber: ${_cart.fold(0, (n, l) => n + (l.cancelOf == null ? 1 : -1))} Artikel netto · ${formatCents(_cart.fold(0, (n, l) => n + l.signedCents))}\n${_parkedDrafts.length} geparkte Vorgänge: $_heldCount Positionen · ${formatCents(_heldTotal)}\n\nAbgeschlossen, Kasse ${widget.store.session.registerNumber}: $_registerCustomers Vorgänge · $_registerItems Artikel · ${formatCents(_registerRevenue)}\nEntwürfe sind noch keine Verkäufe.',
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
    if (mounted) _focusScanner();
  }

  Future<void> _openReceipts() async {
    _scanFocus.unfocus();
    _modal = true;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => ReceiptPage(store: widget.store)),
    );
    _modal = false;
    if (mounted) {
      await _run(() async {});
      _focusScanner();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = widget.store.session;
    final total = _cart.fold(0, (sum, item) => sum + item.signedCents);
    final net = _cart.fold(0, (n, l) => n + (l.cancelOf == null ? 1 : -1));
    final accent = _returnMode ? Tones.warning(context) : scheme.primary;
    final canPay =
        widget.active &&
        _ready &&
        !_busy &&
        _cart.isNotEmpty &&
        !(_recovered && !_recoveryChecked);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kasse ${session.registerNumber}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${session.name} · ${_busy
                  ? 'Speicherung läuft'
                  : _error != null
                  ? 'Stand prüfen'
                  : 'Lokal gespeichert'}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _error != null
                    ? Tones.warning(context)
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Kontrollsumme',
            onPressed: _busy || _modal ? null : _controlSum,
            icon: const Icon(Icons.calculate_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Weitere Aktionen',
            enabled: !_busy,
            onSelected: (value) =>
                value == 'receipts' ? _openReceipts() : _discard(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'receipts',
                child: Text('Belege dieser Kasse'),
              ),
              if (_cart.isNotEmpty)
                const PopupMenuItem(
                  value: 'discard',
                  child: Text('Warenkorb verwerfen'),
                ),
            ],
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    if (session.isDemo)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Tag(
                          'Demo · Keine echten Verkäufe',
                          background: Tones.warningContainer(context),
                          foreground: Tones.onWarningContainer(context),
                        ),
                      ),
                    if (_recovered) _recoveryBanner(context),
                    if (!_ready && !_busy)
                      FilledButton(
                        onPressed: _load,
                        child: const Text('Kasse erneut laden'),
                      ),
                    Text(
                      'Vorgang $_draftNumber · $net Artikel',
                      style: theme.textTheme.titleMedium,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || _modal || _cart.isEmpty
                              ? null
                              : _park,
                          icon: const Icon(Icons.pause_circle_outline),
                          label: const Text('Vorgang parken'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy || _modal || _parkedDrafts.isEmpty
                              ? null
                              : _chooseParked,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text('Geparkt (${_parkedDrafts.length})'),
                        ),
                      ],
                    ),
                    TextField(
                      key: const Key('scan-input'),
                      controller: _code,
                      focusNode: _scanFocus,
                      canRequestFocus: widget.active,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 17),
                      decoration: InputDecoration(
                        labelText: _returnMode
                            ? 'Rückgabe-Etikett scannen'
                            : 'Etikett scannen',
                        hintText: 'Scanner mit Enter-Abschluss',
                        prefixIcon: Icon(
                          _returnMode ? Icons.undo : Icons.qr_code_scanner,
                          color: accent,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: accent, width: 2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: accent, width: 2.5),
                        ),
                        suffixIcon: Padding(
                          padding: const EdgeInsets.all(4),
                          child: IconButton.filled(
                            tooltip: 'Code übernehmen',
                            style: IconButton.styleFrom(
                              backgroundColor: accent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => _scan(_code.text),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                      onSubmitted: _scan,
                      // Keep HID focus across Enter; serialize writes in _scan.
                      onEditingComplete: () {},
                    ),
                    AdaptiveActions(
                      children: [
                        for (final (icon, label, action) in [
                          (Icons.photo_camera_outlined, 'Kamera', _camera),
                          (Icons.keyboard_outlined, 'Manuell', _manual),
                          (Icons.search, 'Suchen', _search),
                        ])
                          OutlinedButton.icon(
                            onPressed: _canEdit ? action : null,
                            icon: Icon(icon, size: 20),
                            label: Text(label),
                          ),
                      ],
                    ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 8,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 20,
                                color: scheme.onErrorContainer,
                              ),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: scheme.onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Warenkorb · $net Artikel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        FilterChip(
                          avatar: Icon(
                            Icons.undo,
                            size: 18,
                            color: Tones.warning(context),
                          ),
                          label: const Text('Rückgabe'),
                          tooltip:
                              'Erstattung wird erst beim Abschluss gespeichert.',
                          selected: _returnMode,
                          showCheckmark: false,
                          selectedColor: Tones.warningContainer(context),
                          onSelected: _canEdit
                              ? (value) => setState(() => _returnMode = value)
                              : null,
                        ),
                      ],
                    ),
                    if (_cart.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'Bereit für den ersten Artikel.\nEtikett scannen oder manuell eingeben.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    // Newest first: the last scan is on top and highlighted.
                    for (final line in _cart.reversed)
                      _CartLine(
                        key: line.entryId == _lastLine?.entryId
                            ? const Key('last-scan')
                            : null,
                        line: line,
                        latest: line.entryId == _lastLine?.entryId,
                        source: _lastRaw,
                        onRemove: !_canEdit
                            ? null
                            : () => _run(
                                () => widget.store.removeEntry(line.entryId),
                              ),
                      ),
                    if (session.isDemo) _demoArticles(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final summary = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          total < 0 ? 'Auszuzahlen' : 'Gesamt · $net Artikel',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(
                          formatCents(total.abs()),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: total < 0 ? Tones.warning(context) : null,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    );
                    final payment = FilledButton.icon(
                      key: const Key('checkout'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 60),
                        backgroundColor: total < 0
                            ? Tones.warning(context)
                            : null,
                      ),
                      onPressed: canPay ? _pay : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        _recovered && !_recoveryChecked && _cart.isNotEmpty
                            ? 'Erst prüfen'
                            : total < 0
                            ? 'Bar auszahlen'
                            : 'Bar kassieren',
                      ),
                    );
                    if (constraints.maxWidth < 420 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          summary,
                          const SizedBox(height: 10),
                          payment,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: summary),
                        const SizedBox(width: 16),
                        Expanded(child: payment),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recoveryBanner(BuildContext context) => Material(
    color: Tones.warningContainer(context),
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Tones.onWarningContainer(context),
              ),
              Expanded(
                child: Text(
                  'Offener Warenkorb wiederhergestellt. Vor dem Abschluss prüfen, ob bereits Bargeld übergeben wurde.',
                  style: TextStyle(color: Tones.onWarningContainer(context)),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Artikel und Zahlungsstand geprüft',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Tones.onWarningContainer(context),
              ),
            ),
            value: _recoveryChecked,
            onChanged: (value) =>
                setState(() => _recoveryChecked = value ?? false),
          ),
        ],
      ),
    ),
  );

  Widget _demoArticles() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Demoartikel zum Ausprobieren'),
    children: [
      for (final item in demoCatalog)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.title),
          subtitle: Text('${formatCents(item.priceCents)} · Revision 1'),
          trailing: const Icon(Icons.add_circle_outline),
          onTap: !_canEdit
              ? null
              : () async {
                  if (!_guard()) return;
                  final success = await _run(
                    () => _returnMode
                        ? widget.store.addReturn(item.listingId)
                        : widget.store.addManual(
                            item.codeFull,
                            item.labelRevision,
                          ),
                  );
                  if (success && _cart.isNotEmpty && mounted) {
                    setState(() {
                      _lastLine = _cart.last;
                      _lastRaw = 'Demo';
                    });
                  }
                },
        ),
    ],
  );
}

class _CartLine extends StatelessWidget {
  final CartEntry line;
  final bool latest;
  final String? source;
  final VoidCallback? onRemove;
  const _CartLine({
    super.key,
    required this.line,
    required this.latest,
    required this.source,
    required this.onRemove,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isReturn = line.cancelOf != null;
    final muted = latest
        ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
        : scheme.onSurfaceVariant;
    final l = line.listing;
    return Card(
      margin: EdgeInsets.zero,
      color: latest ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  if (latest)
                    Text(
                      'ZULETZT · ${isReturn ? 'RÜCKGABE' : 'VERKAUF'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    )
                  else if (isReturn)
                    Tag(
                      'RÜCKGABE',
                      background: Tones.warningContainer(context),
                      foreground: Tones.onWarningContainer(context),
                    ),
                  Text(
                    l.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: latest ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Verk. ${l.sellerKey} · Box ${l.boxNumber} · Art. ${l.articleNumber}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      color: muted,
                    ),
                  ),
                  if (latest && source != null)
                    Text(
                      source!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                ],
              ),
            ),
            Text(
              formatCents(line.signedCents),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: isReturn ? Tones.warning(context) : null,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
            IconButton(
              tooltip: 'Artikel entfernen',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen confirmation after the sale is durably stored.
class _SavedScreen extends StatelessWidget {
  final Receipt receipt;
  final Future<void> Function() onPrint;
  const _SavedScreen({required this.receipt, required this.onPrint});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onPrimary;
    final soft = fg.withValues(alpha: 0.75);
    return Dialog.fullscreen(
      backgroundColor: scheme.primary,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.check_circle, size: 72, color: fg),
              const SizedBox(height: 12),
              Text(
                'Beleg ${receipt.number} gespeichert',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Lokal gesichert · ${formatCents(receipt.totalCents)}',
                textAlign: TextAlign.center,
                style: TextStyle(color: soft),
              ),
              const SizedBox(height: 32),
              if (receipt.tenderedKnown) ...[
                Text(
                  'Rückgeld',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: soft, fontSize: 16),
                ),
                Text(
                  formatCents(receipt.changeCents),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ] else
                Text(
                  'Bargeldübergabe bestätigt. Kein Wechselgeld berechnet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: fg, fontSize: 18),
                ),
              const Spacer(),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  backgroundColor: Colors.transparent,
                  side: BorderSide(color: soft),
                ),
                onPressed: () async {
                  try {
                    await onPrint();
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
                icon: const Icon(Icons.print_outlined),
                label: const Text('Bon drucken'),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 64),
                  backgroundColor: scheme.onPrimary,
                  foregroundColor: scheme.primary,
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Nächster Vorgang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
