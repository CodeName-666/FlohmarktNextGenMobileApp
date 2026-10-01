import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'tones.dart';
import '../data/market_library.dart';

class ArchivePage extends StatefulWidget {
  final MarketLibrary library;
  const ArchivePage({super.key, required this.library});
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<Map<String, Object?>> _rows = [];
  bool _busy = false, _currentOnly = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _run(_load);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _load() async {
    final rows = <Map<String, Object?>>[];
    for (final saved in await widget.library.sessions()) {
      try {
        rows.add(
          await widget.library.withSession(
            saved.id,
            (store) async => {
              'id': saved.id,
              'marketId': saved.session.marketId,
              'name': saved.session.name,
              'register': saved.session.registerNumber,
              'generation': saved.session.exportGeneration,
              'protocols': await store.setting('syncProtocols') ?? [],
              'referrals': await store.setting('syncReferrals') ?? [],
            },
          ),
        );
      } catch (e) {
        rows.add({
          'id': saved.id,
          'marketId': saved.session.marketId,
          'name': saved.session.name,
          'register': saved.session.registerNumber,
          'error': e.toString(),
        });
      }
    }
    _rows = rows;
  }

  List<Map<String, Object?>> get _visible => _rows
      .where(
        (row) =>
            !_currentOnly ||
            row['marketId'] == widget.library.active?.session.marketId,
      )
      .toList();

  Future<void> _export() async {
    await FilePicker.saveFile(
      fileName: 'marktarchiv.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ').convert({'markets': _visible}),
        ),
      ),
    );
  }

  Future<void> _delete(Map<String, Object?> row, Object? protocol) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dieses Importprotokoll löschen?'),
        content: SingleChildScrollView(
          child: Text(
            '${row['name']} · Kasse ${row['register']}\n${const JsonEncoder.withIndent('  ').convert(protocol)}\n\nVerkäufe, Warteschlange und Verweise bleiben erhalten.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Protokoll löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.library.withSession(row['id'] as String, (store) async {
      final protocols = List<Object?>.from(
        await store.setting('syncProtocols') as List? ?? [],
      );
      final index = protocols.indexWhere(
        (p) => jsonEncode(p) == jsonEncode(protocol),
      );
      if (index < 0) {
        throw StateError(
          'Protokoll wurde inzwischen verändert. Bitte aktualisieren.',
        );
      }
      protocols.removeAt(index);
      await store.setSetting('syncProtocols', protocols);
    });
    await _load();
  }

  Future<void> _source(Map<String, Object?> row) async {
    final source = await widget.library.source(row['id'] as String);
    await FilePicker.saveFile(
      fileName: 'marktpaket_${row['marketId']}.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(source)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Archiv aller Märkte'),
      actions: [
        IconButton(
          tooltip: 'Aktualisieren',
          onPressed: _busy ? null : () => _run(_load),
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Gefiltertes Archiv speichern',
          onPressed: _busy ? null : () => _run(_export),
          icon: const Icon(Icons.save_alt),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          'Alle gespeicherten Märkte mit Importläufen, Konflikten und Originaldateien. Der geöffnete Markt bleibt unverändert.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        FilterChip(
          label: const Text('Nur aktueller Markt'),
          selected: _currentOnly,
          onSelected: widget.library.active == null
              ? null
              : (value) => setState(() => _currentOnly = value),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Notice(_error!, error: true),
        if (!_busy && _visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Noch kein Marktarchiv vorhanden.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final row in _visible)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              title: Text('${row['name']} · Kasse ${row['register']}'),
              subtitle: Text(
                row['error']?.toString() ??
                    'Markt ${row['marketId']} · Generation ${row['generation']}',
              ),
              children: [
                if (row['error'] == null)
                  TextButton.icon(
                    onPressed: _busy ? null : () => _run(() => _source(row)),
                    icon: const Icon(Icons.file_download),
                    label: const Text('Originales Marktpaket speichern'),
                  ),
                if ((row['protocols'] as List? ?? []).isEmpty)
                  const Text('Keine Importprotokolle.'),
                for (final protocol in row['protocols'] as List? ?? [])
                  ExpansionTile(
                    title: Text(
                      '${(protocol as Map)['stage']} · ${protocol['status']}',
                    ),
                    subtitle: Text('${protocol['at']}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          '${protocol['sent'] ?? 0} gesendet · ${protocol['acknowledged'] ?? 0} bestätigt\n${protocol['error'] ?? ''}',
                        ),
                      ),
                      for (final result in protocol['results'] as List? ?? [])
                        ListTile(
                          title: Text('${(result as Map)['result']}'),
                          subtitle: Text(
                            '${result['vorgangId'] ?? result['listingId'] ?? ''}\n${result['message'] ?? result['currentStatus'] ?? ''}',
                          ),
                        ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() => _delete(row, protocol)),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Dieses Protokoll löschen'),
                      ),
                    ],
                  ),
                if ((row['referrals'] as List? ?? []).isNotEmpty)
                  const Text('An Organisator verwiesene Konflikte'),
                for (final referral in row['referrals'] as List? ?? [])
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      'Vorgang ${(referral as Map)['vorgangId']}\n${referral['conflictType'] ?? ''} · ${referral['raisedAt'] ?? ''}',
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
