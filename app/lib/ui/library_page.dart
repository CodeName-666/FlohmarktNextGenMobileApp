import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/market_library.dart';
import '../data/market_package.dart';
import '../data/legacy_inspection.dart';
import '../data/checkout_store.dart';
import '../data/demo_catalog.dart';
import 'tones.dart';

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
    // Not disposed: the closing dialog still rebuilds its TextField (keyboard
    // insets) during the exit animation. Disposing here caused the red-screen
    // assertion '_dependents.isEmpty'. The controller is garbage-collected.
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
    // Not disposed: the closing dialog still rebuilds its TextField (keyboard
    // insets) during the exit animation. Disposing here caused the red-screen
    // assertion '_dependents.isEmpty'. The controller is garbage-collected.
    if (number != null) await widget.library.createRegister(saved.id, number);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Märkte und Kassen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(_import),
                icon: const Icon(Icons.file_open),
                label: const Text('Marktpaket oder V1-Datei importieren'),
              ),
              const SizedBox(height: 8),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Notice(
                    _message!,
                    error: !_message!.startsWith('Markt importiert'),
                  ),
                ),
              if (_sessions.isEmpty && !_busy)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Noch kein Markt vorhanden. JSON-Datei importieren oder einen Markt über Synchronisation herunterladen.',
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final saved in _sessions) _marketCard(context, saved),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await widget.library.createSession(
                          demoSession,
                          demoCatalog,
                          source: 'demo',
                        );
                      }),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Demomarkt hinzufügen'),
              ),
              SelectableText(
                'Lokale Bibliothek: ${widget.library.directory}',
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marketCard(BuildContext context, SavedSession saved) {
    final scheme = Theme.of(context).colorScheme;
    final session = saved.session;
    final active = saved.id == widget.library.activeId;
    final broken = saved.error != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: active
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: _busy || broken
            ? null
            : () => _run(() async {
                await widget.library.activate(saved.id);
                if (context.mounted) Navigator.pop(context, true);
              }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (active)
                          Tag(
                            'Geöffnet',
                            background: scheme.primary,
                            foreground: scheme.onPrimary,
                          ),
                        Tag(
                          broken
                              ? 'Fehler'
                              : session.isDemo
                              ? 'Demo'
                              : session.exportGeneration == 0
                              ? 'V1'
                              : 'V2 · Export ${session.exportGeneration}',
                          background: broken
                              ? scheme.errorContainer
                              : session.isDemo
                              ? Tones.warningContainer(context)
                              : scheme.primaryContainer,
                          foreground: broken
                              ? scheme.onErrorContainer
                              : session.isDemo
                              ? Tones.onWarningContainer(context)
                              : scheme.onPrimaryContainer,
                        ),
                      ],
                    ),
                    Text(
                      session.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      broken ? saved.error! : 'Kasse ${session.registerNumber}',
                      style: TextStyle(
                        color: broken ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Weitere Kasse anlegen',
                icon: const Icon(Icons.add_business),
                onPressed: _busy || broken
                    ? null
                    : () => _run(() => _newRegister(saved)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
