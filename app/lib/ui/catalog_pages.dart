import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import '../data/checkout_store.dart';
import '../domain/catalog_search.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../services/catalog_reports.dart';
import 'messages.dart';
import 'tones.dart';

class ArticleSearchPage extends StatefulWidget {
  final CheckoutStore store;
  final bool selectForCheckout, selectForReturn;
  const ArticleSearchPage({
    required this.store,
    super.key,
    this.selectForCheckout = false,
    this.selectForReturn = false,
  });
  @override
  State<ArticleSearchPage> createState() => _ArticleSearchPageState();
}

class _ArticleSearchPageState extends State<ArticleSearchPage> {
  final _query = TextEditingController();
  ArticleSearchMode _mode = ArticleSearchMode.description;
  ArticleStatusFilter _status = ArticleStatusFilter.all;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.selectForCheckout ? 'Artikel auswählen' : 'Artikelsuche',
      ),
    ),
    body: _StoreView(
      store: widget.store,
      builder: (data) {
        final fields = catalogFields(widget.store.session);
        final sold = data.sales.map((e) => e.listing.listingId).toSet();
        final result = filterCatalog(
          listings: data.listings,
          soldListingIds: sold,
          fields: fields,
          query: _query.text,
          mode: _mode,
          status: _status,
        );
        final soldCount = result
            .where((a) => sold.contains(a.listingId))
            .length;
        final value = result.fold(0, (n, a) => n + a.priceCents);
        final minimum = _mode == ArticleSearchMode.description ? 2 : 1;
        final groups = <String, List<ArticleListing>>{};
        for (final article in result) {
          groups.putIfAbsent(article.sellerKey, () => []).add(article);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('article-query'),
              controller: _query,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: switch (_mode) {
                  ArticleSearchMode.description => 'Beschreibung oder Größe',
                  ArticleSearchMode.seller =>
                    'Verkäufer, Box, Kurzcode oder Etikett',
                  ArticleSearchMode.article =>
                    'Artikelnummer über alle Verkäufer',
                },
                suffixIcon: IconButton(
                  tooltip: 'Suche löschen',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(_query.clear),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final mode in ArticleSearchMode.values)
                  ChoiceChip(
                    key: Key('mode-${mode.name}'),
                    label: Text(switch (mode) {
                      ArticleSearchMode.description => 'Beschreibung',
                      ArticleSearchMode.seller => 'Verkäufer / Box',
                      ArticleSearchMode.article => 'Artikelnummer',
                    }),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final status in ArticleStatusFilter.values)
                  ChoiceChip(
                    key: Key('status-${status.name}'),
                    label: Text(switch (status) {
                      ArticleStatusFilter.all => 'Alle',
                      ArticleStatusFilter.available => 'Verfügbar',
                      ArticleStatusFilter.sold => 'Verkauft',
                    }),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_query.text.trim().length < minimum)
              Text(
                _mode == ArticleSearchMode.description
                    ? 'Mindestens 2 Zeichen eingeben.'
                    : 'Nummer oder Etikett eingeben.',
              )
            else ...[
              Text(
                '${result.length} Treffer · ${result.length - soldCount} verfügbar · $soldCount verkauft · ${formatCents(value)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (result.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text('Keine Artikel gefunden.'),
                ),
              for (final group in groups.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Text(
                    'Verkäufer ${group.first.sellerNumber} · ${sellerIdentity(group.first)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final article in group)
                  Card(
                    child: ListTile(
                      key: Key('article-${article.listingId}'),
                      title: Text(
                        article.title.isEmpty
                            ? 'Artikel ${article.articleNumber}'
                            : article.title,
                      ),
                      subtitle: Text(
                        [
                          'Box ${article.boxNumber} · Art. ${article.articleNumber}',
                          ...fields
                              .where(
                                (f) =>
                                    f.id != 'description' &&
                                    f.value(article).isNotEmpty,
                              )
                              .map((f) => f.value(article)),
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        spacing: 4,
                        children: [
                          Text(
                            formatCents(article.priceCents),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          sold.contains(article.listingId)
                              ? Tag(
                                  'Verkauft',
                                  background: Tones.warningContainer(context),
                                  foreground: Tones.onWarningContainer(context),
                                )
                              : Tag(
                                  'Verfügbar',
                                  background: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  foreground: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                        ],
                      ),
                      enabled:
                          !widget.selectForCheckout ||
                          (widget.selectForReturn
                              ? sold.contains(article.listingId) ||
                                    data.cart.any(
                                      (line) =>
                                          line.listing.listingId ==
                                              article.listingId &&
                                          line.cancelOf == null,
                                    )
                              : !sold.contains(article.listingId)),
                      onTap: () {
                        if (widget.selectForCheckout) {
                          Navigator.pop(context, article);
                        } else {
                          _showArticle(
                            context,
                            article,
                            fields,
                            sold.contains(article.listingId),
                          );
                        }
                      },
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    ),
  );
}

void _showArticle(
  BuildContext context,
  ArticleListing article,
  List<CatalogField> fields,
  bool sold,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(article.title.isEmpty ? 'Artikeldetails' : article.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final row in <String, String>{
              'Verkäufernummer': '${article.sellerNumber}',
              'Verkäuferkennung': sellerIdentity(article),
              'Box / Stammnummer': '${article.boxNumber}',
              'Artikelnummer': '${article.articleNumber}',
              for (final field in fields) field.label: field.value(article),
              'Preis': formatCents(article.priceCents),
              'Status': sold ? 'Verkauft' : 'Verfügbar',
              'Etikettenrevision': article.isRevisioned
                  ? '${article.labelRevision}'
                  : 'V1 · revisionslos',
              'Vollcode': article.codeFull,
              'Artikel-ID': article.articleId,
              'Listing-ID': article.listingId,
            }.entries)
              _ValueRow(row.key, row.value),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    ),
  );
}

class CustomerSearchPage extends StatefulWidget {
  final CheckoutStore store;
  const CustomerSearchPage({required this.store, super.key});
  @override
  State<CustomerSearchPage> createState() => _CustomerSearchPageState();
}

class _CustomerSearchPageState extends State<CustomerSearchPage> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kundensuche')),
    body: _StoreView(
      store: widget.store,
      builder: (data) {
        final receipts = findReceipts(_query.text, data.receipts, data.events);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('customer-query'),
              controller: _query,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Kunden-Nr. oder Vorgang-ID',
                prefixIcon: const Icon(Icons.person_search_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Suche löschen',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(_query.clear),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_query.text.trim().isEmpty)
              const Text('Kundennummer oder vollständige Vorgang-ID eingeben.')
            else if (receipts.isEmpty)
              const Text('Kein Beleg gefunden.'),
            for (final receipt in receipts)
              _ReceiptCard(
                session: widget.store.session,
                receipt: receipt,
                events: data.events,
              ),
          ],
        );
      },
    ),
  );
}

class _ReceiptCard extends StatelessWidget {
  final MarketSession session;
  final Receipt receipt;
  final List<SaleEvent> events;
  const _ReceiptCard({
    required this.session,
    required this.receipt,
    required this.events,
  });
  @override
  Widget build(BuildContext context) {
    final history = receiptHistory(receipt, events);
    final cancelled = events.map((e) => e.cancelOf).whereType<String>().toSet();
    final customerNumbers = history
        .where((e) => e.receiptId == receipt.id && e.customerNumber > 0)
        .map((e) => e.customerNumber)
        .toSet();
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Kunde ${customerNumbers.isEmpty ? receipt.number : customerNumbers.join(', ')}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatCents(receipt.totalCents),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              'Beleg ${receipt.number} · Kasse ${receipt.registerNumber} · ${localEventTime(receipt.occurredAt)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text('Ursprünglicher Beleg: ${formatCents(receipt.totalCents)}'),
            Text(
              receipt.tenderedKnown
                  ? 'Gegeben ${formatCents(receipt.tenderedCents)} · Rückgeld ${formatCents(receipt.changeCents)}'
                  : 'Bargeld bestätigt · Betrag nicht erfasst',
            ),
            const Divider(height: 24),
            for (final event in history)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            event.listing.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              decoration: cancelled.contains(event.id)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          Text(
                            'Verk. ${sellerIdentity(event.listing)} · Box ${event.listing.boxNumber} · Art. ${event.listing.articleNumber} · ${localEventTime(event.occurredAt)}',
                            style: muted,
                          ),
                          if (event.cancelOf != null)
                            Tag(
                              'Storno / Rückgabe',
                              background: Tones.warningContainer(context),
                              foreground: Tones.onWarningContainer(context),
                            )
                          else if (cancelled.contains(event.id))
                            Tag(
                              'Verkauf storniert',
                              background: Tones.warningContainer(context),
                              foreground: Tones.onWarningContainer(context),
                            ),
                          if (event.cancelOf != null)
                            SelectableText(
                              'Original: ${event.cancelOf}',
                              style: muted,
                            ),
                          if (event.receiptId != receipt.id)
                            SelectableText(
                              'Rückgabevorgang: ${event.receiptId}',
                              style: muted,
                            ),
                        ],
                      ),
                    ),
                    Text(
                      formatCents(
                        event.cancelOf == null
                            ? event.listing.priceCents
                            : -event.listing.priceCents,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: event.cancelOf != null
                            ? Tones.warning(context)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.print_outlined),
              label: const Text('Bon erneut drucken / PDF'),
              onPressed: () => _print(
                context,
                'Beleg-${receipt.number}',
                () => buildReceiptPdf(session, receipt, events),
              ),
            ),
            const SizedBox(height: 6),
            SelectableText('Vorgang ${receipt.id}', style: muted),
          ],
        ),
      ),
    );
  }
}

class MarketDetailsPage extends StatelessWidget {
  final CheckoutStore store;
  const MarketDetailsPage({required this.store, super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Marktdetails')),
    body: _StoreView(
      store: store,
      showMarketName: false,
      builder: (data) {
        final sold = data.sales.map((e) => e.listing.listingId).toSet();
        final soldCount = data.listings
            .where((a) => sold.contains(a.listingId))
            .length;
        final values = marketDetailValues(store.session);
        final offered = data.listings.fold(0, (n, a) => n + a.priceCents);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              store.session.name,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              '${data.listings.map((a) => a.sellerKey).toSet().length} Verkäufer · ${data.listings.map((a) => a.boxNumber).toSet().length} Boxen',
            ),
            const SizedBox(height: 12),
            FigureGroup(
              children: [
                Figure('Artikel', '${data.listings.length}'),
                Figure('Verkauft', '$soldCount'),
                Figure('Angebotswert', formatCents(offered)),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Als PDF exportieren'),
              onPressed: () => _print(
                context,
                'Markt-${store.session.marketId}',
                () => buildMarketDetailsPdf(
                  store.session,
                  data.listings,
                  data.sales,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in values.entries)
                      _ValueRow(row.key, row.value),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> _print(
  BuildContext context,
  String name,
  Future<Uint8List> Function() build,
) async {
  try {
    final bytes = await build();
    if (!context.mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('Systemdruck / Vorschau'),
              leading: const Icon(Icons.print),
              onTap: () => Navigator.pop(context, 'print'),
            ),
            ListTile(
              title: const Text('PDF teilen'),
              leading: const Icon(Icons.share),
              onTap: () => Navigator.pop(context, 'share'),
            ),
            ListTile(
              title: const Text('PDF speichern'),
              leading: const Icon(Icons.save_alt),
              onTap: () => Navigator.pop(context, 'save'),
            ),
          ],
        ),
      ),
    );
    if (action == 'print') {
      await Printing.layoutPdf(name: '$name.pdf', onLayout: (_) async => bytes);
    } else if (action == 'share') {
      await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
    } else if (action == 'save') {
      await FilePicker.saveFile(
        dialogTitle: 'PDF speichern',
        fileName: '$name.pdf',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF / Druck fehlgeschlagen: $error')),
      );
    }
  }
}

class _ValueRow extends StatelessWidget {
  final String label, value;
  const _ValueRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(value.isEmpty ? 'Nicht angegeben' : value),
      ],
    ),
  );
}

class _Snapshot {
  final List<ArticleListing> listings;
  final List<SaleEvent> sales, events;
  final List<Receipt> receipts;
  final List<CartEntry> cart;
  const _Snapshot(
    this.listings,
    this.sales,
    this.events,
    this.receipts,
    this.cart,
  );
  static Future<_Snapshot> read(CheckoutStore store) async {
    final listings = await store.allListings();
    final sales = await store.activeSales();
    final events = await store.events();
    final receipts = await store.receipts();
    return _Snapshot(
      listings,
      sales,
      events,
      receipts,
      await store.cartLines(),
    );
  }
}

class _StoreView extends StatefulWidget {
  final CheckoutStore store;
  final Widget Function(_Snapshot) builder;
  final bool showMarketName;
  const _StoreView({
    required this.store,
    required this.builder,
    this.showMarketName = true,
  });
  @override
  State<_StoreView> createState() => _StoreViewState();
}

class _StoreViewState extends State<_StoreView> {
  late Future<_Snapshot> _future;
  @override
  void initState() {
    super.initState();
    _future = _Snapshot.read(widget.store);
  }

  @override
  void didUpdateWidget(covariant _StoreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      _future = _Snapshot.read(widget.store);
    }
  }

  void _reload() => setState(() => _future = _Snapshot.read(widget.store));
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.showMarketName ? '${widget.store.session.name} · ' : ''}Kasse ${widget.store.session.registerNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Aktualisieren',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<_Snapshot>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(checkoutError(snapshot.error!)),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: _reload,
                              child: const Text('Erneut versuchen'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return widget.builder(snapshot.data!);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
