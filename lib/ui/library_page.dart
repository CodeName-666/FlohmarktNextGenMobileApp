import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/market_library.dart';
import '../data/market_package.dart';
import '../data/legacy_inspection.dart';
import '../data/checkout_store.dart';
import '../data/demo_catalog.dart';

Future<void> saveJsonFile(String name, Object data) async {
  await FilePicker.saveFile(
    fileName: name,
    bytes: Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
    ),
    mimeType: 'application/json',
  );
}

class LibraryPage extends StatefulWidget {
  final MarketLibrary library;
  const LibraryPage({super.key, required this.library});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<SavedSession> _sessions = [];
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
      _sessions = await widget.library.sessions(validate: true);
    } catch (e) {
      _message = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || !mounted) return;
    final raw = utf8.decode(await file.readAsBytes());
    if (!mounted) return;
    final number = TextEditingController(text: '1'),
        name = TextEditingController(text: file.name.replaceAll('.json', ''));
    final options = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Markt importieren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Marktname für V1'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Kassennummer'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vorschau'),
          ),
        ],
      ),
    );
    final register = int.tryParse(number.text) ?? 0,
        marketName = name.text.trim();
    number.dispose();
    name.dispose();
    if (options != true) return;
    if (register < 1) {
      throw const FormatException('Kassennummer muss positiv sein.');
    }
    final decoded = jsonDecode(raw);
    final inspection = decoded is List
        ? LegacyInspection.inspect(
            raw,
            name: marketName,
            registerNumber: register,
          )
        : null;
    final package = inspection != null
        ? inspection.package
        : MarketPackage.parse(raw, registerNumber: register);
    final report =
        inspection?.report ??
        {
          'source': file.name,
          'sha256': package!.sourceSha256,
          'articles': package.listings.length,
          'valid': true,
        };
    if (!mounted) return;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(package?.session.name ?? 'Importprüfung fehlgeschlagen'),
        content: SingleChildScrollView(
          child: Text(
            inspection != null
                ? '${inspection.validRows} übernehmbare Artikel · ${inspection.ignoredRows} leere Zeilen · ${inspection.boxCount} Boxen · ${inspection.sellerCount} Verkäufer\n\n${inspection.issues.isEmpty ? 'Prüfung erfolgreich. Originaldatei wird mitgespeichert.' : inspection.issues.join('\n')}'
                : '${package!.listings.length} Artikel · Generation ${package.session.exportGeneration} · Kasse $register\nPrüfsumme und Zuordnungen erfolgreich geprüft.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await saveJsonFile('import-pruefung.json', report);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Prüfbericht nicht gespeichert: $e'),
                    ),
                  );
                }
              }
            },
            child: const Text('Prüfbericht speichern'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: package == null
                ? null
                : () => Navigator.pop(context, true),
            child: const Text('Importieren'),
          ),
        ],
      ),
    );
    if (accept == true) {
      await widget.library.importPackage(package!, originalSource: raw);
      _message = 'Markt importiert. Kasse zum Öffnen auswählen.';
    }
  }

  Future<void> _newRegister(SavedSession saved) async {
    final input = TextEditingController(
      text: '${saved.session.registerNumber + 1}',
    );
    final number = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weitere Kasse'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Kassennummer (1–9999)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final number = int.tryParse(input.text);
              if (number != null) Navigator.pop(context, number);
            },
            child: const Text('Anlegen'),
          ),
        ],
      ),
    );
    input.dispose();
    if (number != null) await widget.library.createRegister(saved.id, number);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Märkte und Kassen')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Lokale Bibliothek',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        SelectableText(widget.library.directory),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(_import),
          icon: const Icon(Icons.file_open),
          label: const Text('Marktpaket oder V1-Datei importieren'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await widget.library.createSession(
                    demoSession,
                    demoCatalog,
                    source: 'demo',
                  );
                }),
          child: const Text('Demomarkt hinzufügen'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) SelectableText(_message!),
        if (_sessions.isEmpty && !_busy)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Noch kein Markt vorhanden. JSON-Datei importieren oder einen Markt über Synchronisation herunterladen.',
            ),
          ),
        for (final saved in _sessions)
          Card(
            child: ListTile(
              trailing: IconButton(
                tooltip: 'Weitere Kasse anlegen',
                icon: const Icon(Icons.add_business),
                onPressed: _busy || saved.error != null
                    ? null
                    : () => _run(() => _newRegister(saved)),
              ),
              isThreeLine: true,
              leading: Icon(
                saved.error != null
                    ? Icons.error_outline
                    : saved.id == widget.library.activeId
                    ? Icons.check_circle
                    : Icons.storefront,
              ),
              title: Text(saved.session.name),
              enabled: saved.error == null,
              subtitle: Text(
                saved.error ??
                    'Kasse ${saved.session.registerNumber} · ${saved.session.isDemo
                        ? 'Demo'
                        : saved.session.exportGeneration == 0
                        ? 'V1'
                        : 'V2 / Generation ${saved.session.exportGeneration}'}\nMarkt ${saved.session.marketId}',
              ),
              onTap: _busy
                  ? null
                  : () => _run(() async {
                      await widget.library.activate(saved.id);
                      if (context.mounted) Navigator.pop(context, true);
                    }),
            ),
          ),
      ],
    ),
  );
}
