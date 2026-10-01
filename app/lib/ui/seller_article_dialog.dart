import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../domain/models.dart';

class ManualArticleSelection {
  final ArticleListing listing;
  final int? revision;
  const ManualArticleSelection(this.listing, this.revision);
}

class SellerArticleDialog extends StatefulWidget {
  final CheckoutStore store;
  const SellerArticleDialog({super.key, required this.store});
  @override
  State<SellerArticleDialog> createState() => _SellerArticleDialogState();
}

class _SellerArticleDialogState extends State<SellerArticleDialog> {
  final _seller = TextEditingController(),
      _article = TextEditingController(),
      _revision = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _seller.dispose();
    _article.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final seller = int.tryParse(_seller.text),
          article = int.tryParse(_article.text),
          revision = int.tryParse(_revision.text);
      if (seller == null || seller < 1 || article == null || article < 1) {
        throw const FormatException(
          'Verkäufer- und Artikelnummer müssen positive Ganzzahlen sein.',
        );
      }
      if (widget.store.session.exportGeneration > 0 &&
          (revision == null || revision < 1)) {
        throw const FormatException(
          'Sichtbare Etikettenrevision ist erforderlich.',
        );
      }
      final matches = await widget.store.sellerArticle(seller, article);
      if (matches.isEmpty) {
        throw StateError('Artikel in diesem Markt nicht gefunden.');
      }
      if (!mounted) return;
      ArticleListing? selected;
      if (matches.length == 1) {
        selected = matches.single;
      } else {
        selected = await showDialog<ArticleListing>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Verkäuferidentität auswählen'),
            children: [
              for (final a in matches)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, a),
                  child: Text(
                    '${a.title}\nIdentität ${a.sellerKey} · Box ${a.boxNumber}\nCode ${a.codeFull}',
                  ),
                ),
            ],
          ),
        );
      }
      if (selected == null) return;
      if (selected.isRevisioned && selected.labelRevision != revision) {
        throw const FormatException(
          'Etikettenrevision veraltet. Aktuelles Etikett verwenden.',
        );
      }
      if (mounted) {
        Navigator.pop(context, ManualArticleSelection(selected, revision));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Artikel manuell eingeben'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _seller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: widget.store.session.exportGeneration == 0
                  ? 'Stammnummer / Box'
                  : 'Verkäufernummer auf Etikett',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _article,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Artikelnummer'),
          ),
          if (widget.store.session.exportGeneration > 0) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _revision,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Sichtbare Etikettenrevision',
              ),
              onSubmitted: (_) => _busy ? null : _find(),
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_busy) const LinearProgressIndicator(),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _busy ? null : _find,
        child: const Text('Artikel übernehmen'),
      ),
    ],
  );
}
