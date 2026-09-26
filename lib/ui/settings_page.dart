import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/checkout_store.dart';
import '../data/market_library.dart';
import '../services/app_diagnostics.dart';
import 'files_page.dart';
import 'library_page.dart';
import 'operations_pages.dart';
import 'sync_page.dart';

class SettingsPage extends StatefulWidget {
  final CheckoutStore store;
  final MarketLibrary? library;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  const SettingsPage({
    super.key,
    required this.store,
    this.library,
    required this.themeMode,
    required this.onThemeChanged,
  });
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, Object?> _values = {};
  bool _loading = true, _saving = false;
  String? _error;
  final _form = GlobalKey<FormState>();
  final _days = TextEditingController();
  final _bytes = TextEditingController();
  final _backups = TextEditingController();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _days.dispose();
    _bytes.dispose();
    _backups.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.store.setting('uiSettings');
      if (!mounted) return;
      _values = {
        'themeMode': widget.themeMode.name,
        'cameraEnabled': true,
        'cameraFacing': 'back',
        'cameraTorch': false,
        'barcodeFormat': 'all',
        'logLevel': 'INFO',
        'logCategories': ['scanner', 'sync', 'io'],
        'logRetentionDays': 7,
        'logMaxBytes': 5242880,
        'logBackups': 7,
        if (saved is Map) ...Map<String, Object?>.from(saved),
      };
      for (final entry in <String, List<String>>{
        'themeMode': ['system', 'light', 'dark'],
        'cameraFacing': ['back', 'front'],
        'barcodeFormat': ['all', 'ean8', 'ean13', 'code128', 'qrCode'],
        'logLevel': ['INFO', 'DEBUG', 'WARNING', 'ERROR'],
      }.entries) {
        if (!entry.value.contains(_values[entry.key])) {
          _values[entry.key] = entry.value.first;
        }
      }
      final categories = _values['logCategories'];
      _values['logCategories'] = categories is List
          ? categories
                .whereType<String>()
                .where((c) => const ['scanner', 'sync', 'io'].contains(c))
                .toSet()
                .toList()
          : <String>['scanner', 'sync', 'io'];
      _days.text = '${_values['logRetentionDays']}';
      _bytes.text = '${_values['logMaxBytes']}';
      _backups.text = '${_values['logBackups']}';
      setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Einstellungen konnten nicht geladen werden: $error';
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final values = {
        ..._values,
        'logRetentionDays': int.parse(_days.text),
        'logMaxBytes': int.parse(_bytes.text),
        'logBackups': int.parse(_backups.text),
      };
      // A single SQLite row is the commit boundary for every preference here.
      await widget.store.setSetting('uiSettings', values);
      if (!mounted) return;
      widget.onThemeChanged(
        ThemeMode.values.firstWhere(
          (m) => m.name == values['themeMode'],
          orElse: () => ThemeMode.system,
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Nicht gespeichert: $error';
        });
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    // A library change closes the old store; return to Home to rebuild its session.
    if (mounted &&
        widget.library != null &&
        widget.library!.active != widget.store) {
      Navigator.pop(context);
    }
  }

  Widget _choice(String key, String label, Map<String, String> choices) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DropdownButtonFormField<String>(
          initialValue: choices.containsKey(_values[key])
              ? _values[key] as String
              : choices.keys.first,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final item in choices.entries)
              DropdownMenuItem(value: item.key, child: Text(item.value)),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _values[key] = value),
        ),
      );
  Widget _number(
    TextEditingController controller,
    String label,
    int min,
    int max,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (text) {
        final value = int.tryParse(text ?? '');
        return value == null || value < min || value > max
            ? 'Ganzzahl von $min bis $max eingeben.'
            : null;
      },
    ),
  );
  Future<void> _logs() async {
    try {
      final logs = [...await widget.store.logs()];
      final startup = await AppDiagnostics.read();
      if (startup.isNotEmpty) {
        logs.insert(0, {
          'message': startup,
          'category': 'Start / Absturz',
          'at': '',
          'level': 'ERROR',
        });
      }
      if (AppDiagnostics.writeFailure != null) {
        logs.insert(0, {
          'message': AppDiagnostics.writeFailure,
          'category': 'Diagnosefehler',
          'at': '',
          'level': 'ERROR',
        });
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('Diagnoseprotokoll'),
              actions: [
                IconButton(
                  tooltip: 'Protokoll teilen',
                  icon: const Icon(Icons.share),
                  onPressed: logs.isEmpty
                      ? null
                      : () async {
                          try {
                            final data = Uint8List.fromList(
                              utf8.encode(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(logs),
                              ),
                            );
                            final box =
                                context.findRenderObject() as RenderBox?;
                            await SharePlus.instance.share(
                              ShareParams(
                                files: [
                                  XFile.fromData(
                                    data,
                                    mimeType: 'application/json',
                                  ),
                                ],
                                fileNameOverrides: ['marketmate-diagnose.json'],
                                sharePositionOrigin: box == null
                                    ? null
                                    : box.localToGlobal(Offset.zero) & box.size,
                              ),
                            );
                          } catch (error) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Teilen fehlgeschlagen: $error',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                ),
              ],
            ),
            body: logs.isEmpty
                ? const Center(child: Text('Keine Diagnoseeinträge.'))
                : ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) => ListTile(
                      title: SelectableText('${logs[i]['message']}'),
                      subtitle: Text(
                        '${logs[i]['at']} · ${logs[i]['category']} · ${logs[i]['level'] ?? 'INFO'}',
                      ),
                    ),
                  ),
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Protokoll nicht verfügbar: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Einstellungen')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null)
                  SelectableText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Text(
                  'Kasse ${widget.store.session.registerNumber} · ${widget.store.session.name}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                ListTile(
                  title: const Text('Markt, Kasse und Datenablage'),
                  subtitle: Text(
                    widget.library?.directory ??
                        'Lokale App-Datenbank; Marktwechsel über die Startseite.',
                  ),
                  trailing: widget.library == null
                      ? null
                      : const Icon(Icons.chevron_right),
                  onTap: widget.library == null
                      ? null
                      : () => _open(LibraryPage(library: widget.library!)),
                ),
                ListTile(
                  title: const Text('Dateien und Sicherung'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(FilesPage(store: widget.store)),
                ),
                ListTile(
                  title: const Text('Gebühren und Abrechnung'),
                  subtitle: const Text(
                    'Exportgebühren, Herkunft und explizites Überschreiben',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(AccountingPage(store: widget.store)),
                ),
                ListTile(
                  title: const Text('Backend und Anmeldung'),
                  subtitle: const Text('Server, Organisation und Login-E-Mail'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                    SyncPage(store: widget.store, library: widget.library),
                  ),
                ),
                const Divider(),
                _choice('themeMode', 'Darstellung', {
                  'system': 'System',
                  'light': 'Hell',
                  'dark': 'Dunkel',
                }),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kamera aktivieren'),
                  subtitle: const Text(
                    'Kamera läuft ausschließlich im Scanbildschirm.',
                  ),
                  value: _values['cameraEnabled'] == true,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _values['cameraEnabled'] = v),
                ),
                _choice('cameraFacing', 'Kamerarichtung', {
                  'back': 'Rückkamera',
                  'front': 'Frontkamera',
                }),
                const Text(
                  'Verfügbarkeit und Berechtigung werden beim Öffnen des Scanners geprüft. Manuelle Eingabe bleibt verfügbar.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Blitz beim Scanstart'),
                  value: _values['cameraTorch'] == true,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _values['cameraTorch'] = v),
                ),
                _choice('barcodeFormat', 'Scanformat', {
                  'all': 'Automatisch',
                  'ean8': 'EAN-8',
                  'ean13': 'EAN-13',
                  'code128': 'Code 128',
                  'qrCode': 'QR-Code (MM1)',
                }),
                const Text(
                  'Das Scanformat begrenzt die Kameraerkennung. Der erkannte Code muss zusätzlich zur aktiven Marktidentität und Etikettenrevision passen.',
                ),
                const Divider(),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.print),
                  title: Text('Drucken über das Betriebssystem'),
                  subtitle: Text(
                    'Drucker im Systemdruckdialog beim Beleg oder Bericht wählen. Verfügbarkeit hängt von Gerät und Druckerdienst ab.',
                  ),
                ),
                _choice('logLevel', 'Diagnoselevel', {
                  'DEBUG': 'DEBUG',
                  'INFO': 'INFO',
                  'WARNING': 'WARNING',
                  'ERROR': 'ERROR',
                }),
                const Text('Diagnosekategorien'),
                for (final category in ['scanner', 'sync', 'io'])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(category),
                    value: (_values['logCategories'] as List? ?? []).contains(
                      category,
                    ),
                    onChanged: _saving
                        ? null
                        : (checked) => setState(() {
                            final categories = List<String>.from(
                              _values['logCategories'] as List? ?? [],
                            );
                            checked == true
                                ? categories.add(category)
                                : categories.remove(category);
                            _values['logCategories'] = categories;
                          }),
                  ),
                _number(_days, 'Aufbewahrung (Tage)', 1, 365),
                _number(
                  _bytes,
                  'Maximale Größe je Logabschnitt (Bytes)',
                  1024,
                  52428800,
                ),
                _number(_backups, 'Aufbewahrte Logabschnitte', 1, 30),
                const Text(
                  'SQLite begrenzt die Diagnose nach Alter und Gesamtgröße: Abschnittsgröße × (aufbewahrte Abschnitte + 1). Älteste Einträge werden zuerst entfernt.',
                ),
                if (widget.store.loggingFailure != null)
                  Text(
                    'Diagnose konnte nicht gespeichert werden: ${widget.store.loggingFailure}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ListTile(
                  title: const Text('Protokolle anzeigen / teilen'),
                  leading: const Icon(Icons.article_outlined),
                  onTap: _logs,
                ),
                ListTile(
                  title: const Text('Über MarketMate'),
                  leading: const Icon(Icons.info_outline),
                  onTap: () => _open(const _AboutPage()),
                ),
                const Text(
                  'Speichern übernimmt Darstellung, Kamera und Diagnose gemeinsam. Andere Seiten speichern ihre eigenen Änderungen ausdrücklich.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving || _values.isEmpty ? null : _save,
                  child: Text(
                    _saving ? 'Speichern …' : 'Einstellungen speichern',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
              ],
            ),
          ),
  );
}

class _AboutPage extends StatelessWidget {
  const _AboutPage();
  Future<void> _launch(BuildContext context, String url) async {
    try {
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Keine passende Anwendung verfügbar.');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link konnte nicht geöffnet werden: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Über MarketMate')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'MarketMate · Mobile Kasse',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Kassenprogramm für Flohmärkte\n\nMarketMate digitalisiert den Kassenbetrieb auf Flohmärkten: Stammnummern und Barcodes scannen, Verkäufe erfassen, Abrechnung und Auszahlung pro Verkäufer.',
        ),
        const SizedBox(height: 20),
        const SelectableText(
          'Entwickler / Firma: Christof Seidel\nSupport: seidelchristof@googlemail.com\nLizenz: Proprietary – siehe Projektlizenz\n© 2025–2026 Christof Seidel',
        ),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snapshot) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Anwendungsversion'),
            subtitle: Text(
              snapshot.hasError
                  ? 'Versionsinformationen nicht verfügbar'
                  : snapshot.hasData
                  ? '${snapshot.data!.version} · Build ${snapshot.data!.buildNumber}'
                  : 'Wird ermittelt …',
            ),
          ),
        ),
        SelectableText(
          'Flutter: ${FlutterVersion.version ?? 'nicht im Build hinterlegt'}\nDart: ${Platform.version}\nBetriebssystem: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ),
        TextButton(
          onPressed: () => _launch(
            context,
            'https://github.com/CodeName-666/FlohmarktNextGenApp',
          ),
          child: const Text('Projektseite'),
        ),
        TextButton(
          onPressed: () => _launch(
            context,
            'https://github.com/CodeName-666/FlohmarktNextGenApp/issues',
          ),
          child: const Text('Fehler melden'),
        ),
        TextButton(
          onPressed: () =>
              _launch(context, 'mailto:seidelchristof@googlemail.com'),
          child: const Text('Support kontaktieren'),
        ),
        TextButton(
          onPressed: () => _launch(
            context,
            'https://github.com/CodeName-666/FlohmarktNextGenApp/blob/main/LICENSE',
          ),
          child: const Text('Projektlizenz'),
        ),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'MarketMate Mobile',
          ),
          child: const Text('Open-Source-Lizenzen'),
        ),
      ],
    ),
  );
}
