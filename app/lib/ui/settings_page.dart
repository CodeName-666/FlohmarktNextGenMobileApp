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
import 'tones.dart';

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
          isExpanded: true,
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

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Abbrechen'),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving || _values.isEmpty ? null : _save,
                        child: Text(
                          _saving ? 'Speichern …' : 'Einstellungen speichern',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      if (_error != null) Notice(_error!, error: true),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                        child: Text(
                          'Gilt für Kasse ${widget.store.session.registerNumber} · ${widget.store.session.name}',
                          style: muted,
                        ),
                      ),
                      _section('Darstellung', [
                        _choice('themeMode', 'Farbschema', {
                          'system': 'Wie System',
                          'light': 'Hell',
                          'dark': 'Dunkel',
                        }),
                      ]),
                      _section('Kamera', [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Kamera aktivieren'),
                          subtitle: const Text(
                            'Läuft nur im Scanbildschirm. Manuelle Eingabe bleibt immer möglich.',
                          ),
                          value: _values['cameraEnabled'] == true,
                          onChanged: _saving
                              ? null
                              : (v) => setState(
                                  () => _values['cameraEnabled'] = v,
                                ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Licht beim Scanstart'),
                          value: _values['cameraTorch'] == true,
                          onChanged: _saving
                              ? null
                              : (v) =>
                                    setState(() => _values['cameraTorch'] = v),
                        ),
                        _choice('cameraFacing', 'Kamera', {
                          'back': 'Rückkamera',
                          'front': 'Frontkamera',
                        }),
                        _choice('barcodeFormat', 'Scanformat', {
                          'all': 'Automatisch',
                          'ean8': 'EAN-8',
                          'ean13': 'EAN-13',
                          'code128': 'Code 128',
                          'qrCode': 'QR-Code (MM1)',
                        }),
                      ]),
                      _section('Drucken', [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Belege und Berichte gehen über den Druckdialog des Geräts. Dort den Drucker wählen.',
                            style: muted.copyWith(fontSize: 14),
                          ),
                        ),
                      ]),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          shape: const Border(),
                          maintainState: true,
                          title: const Text(
                            'Diagnose und Protokolle',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Level ${_values['logLevel']} · ${_days.text} Tage',
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            12,
                          ),
                          expandedCrossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _logs,
                              icon: const Icon(Icons.article_outlined),
                              label: const Text('Protokolle anzeigen / teilen'),
                            ),
                            _choice('logLevel', 'Diagnoselevel', {
                              'DEBUG': 'DEBUG',
                              'INFO': 'INFO',
                              'WARNING': 'WARNING',
                              'ERROR': 'ERROR',
                            }),
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final category in [
                                  'scanner',
                                  'sync',
                                  'io',
                                ])
                                  FilterChip(
                                    label: Text(category),
                                    selected:
                                        (_values['logCategories'] as List? ??
                                                [])
                                            .contains(category),
                                    onSelected: _saving
                                        ? null
                                        : (checked) => setState(() {
                                            final categories =
                                                List<String>.from(
                                                  _values['logCategories']
                                                          as List? ??
                                                      [],
                                                );
                                            checked
                                                ? categories.add(category)
                                                : categories.remove(category);
                                            _values['logCategories'] =
                                                categories;
                                          }),
                                  ),
                              ],
                            ),
                            _number(_days, 'Aufbewahrung (Tage)', 1, 365),
                            _number(
                              _bytes,
                              'Maximale Größe je Logabschnitt (Bytes)',
                              1024,
                              52428800,
                            ),
                            _number(
                              _backups,
                              'Aufbewahrte Logabschnitte',
                              1,
                              30,
                            ),
                            Text(
                              'Älteste Einträge werden zuerst entfernt. Obergrenze: Abschnittsgröße × (Abschnitte + 1).',
                              style: muted,
                            ),
                            if (widget.library != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SelectableText(
                                  'Datenablage: ${widget.library!.directory}',
                                  style: muted,
                                ),
                              ),
                            if (widget.store.loggingFailure != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Notice(
                                  'Diagnose konnte nicht gespeichert werden: ${widget.store.loggingFailure}',
                                  error: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: const Text('Über MarketMate'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(const _AboutPage()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
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
