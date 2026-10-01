import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../data/checkout_store.dart';
import '../data/market_library.dart';
import '../services/api_client.dart';
import '../services/sync_service.dart';
import 'tones.dart';

class SyncPage extends StatefulWidget {
  final CheckoutStore? store;
  final MarketLibrary? library;
  const SyncPage({super.key, this.store, this.library});
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _base = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _organization = TextEditingController(),
      _register = TextEditingController(text: '1');
  ApiClient? _api;
  bool _busy = false;
  bool _conflictsOnly = false;
  bool _editServer = true;
  String? _stageFilter;
  String _marketFilter = '';
  final _dismissed = <String>{};
  String? _message;
  List<Map<String, Object?>> _markets = [], _protocols = [], _referrals = [];
  List<Map<String, Object?>> _audit = [];
  int _pending = 0, _queued = 0;
  SyncService get _service =>
      SyncService(widget.store, _api ?? (throw StateError('Zuerst anmelden.')));
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _setting('apiSettings');
      if (!mounted) return;
      if (settings is Map) {
        _base.text = '${settings['baseUrl'] ?? ''}';
        _email.text = '${settings['email'] ?? ''}';
        _organization.text = '${settings['organizationId'] ?? ''}';
      }
      _register.text = '${widget.store?.session.registerNumber ?? 1}';
      setState(
        () => _editServer = _base.text.isEmpty || _organization.text.isEmpty,
      );
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  Future<Object?> _setting(String key) async => widget.library != null
      ? widget.library!.preference(key)
      : widget.store?.setting(key);
  Future<void> _refresh() async {
    final store = widget.store;
    if (store == null) return;
    final protocols = ((await store.setting('syncProtocols')) as List? ?? [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final referrals = ((await store.setting('syncReferrals')) as List? ?? [])
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final pending = (await store.pendingEvents()).length;
    final audit = (await store.events())
        .where((e) => e.listing.unexpected)
        .map(
          (e) => <String, Object?>{
            'vorgangId': e.id,
            'result': 'missing_listing',
            'message':
                'Verkauf ohne Backend-Listing; Box ${e.listing.boxNumber}, Artikel ${e.listing.articleNumber}',
          },
        )
        .toList();
    final queued =
        ((await store.setting('syncReuploadQueue')) as List? ?? []).length;
    if (mounted) {
      setState(() {
        _protocols = protocols.reversed.toList();
        _referrals = referrals;
        _pending = pending;
        _queued = queued;
        _audit = audit;
      });
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await action();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      final message =
          error is AccountLockedException && error.lockedUntil != null
          ? 'Konto gesperrt bis ${error.lockedUntil}.'
          : error.toString();
      if (mounted) setState(() => _message = message);
    } finally {
      try {
        await _refresh();
      } catch (error) {
        if (mounted) {
          setState(
            () => _message = 'Archiv konnte nicht gelesen werden: $error',
          );
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _login() async {
    _api?.close();
    _api = ApiClient(_base.text);
    try {
      await _api!.login(_email.text, _password.text);
    } finally {
      _password.clear();
    }
    final settings = {
      'baseUrl': _base.text.trim(),
      'email': _email.text.trim(),
      'organizationId': _organization.text.trim(),
    };
    if (widget.library != null) {
      await widget.library!.setPreference('apiSettings', settings);
    } else {
      await widget.store?.setSetting('apiSettings', settings);
    }
    return 'Angemeldet. Die Anmeldung gilt bis zum Verlassen dieser Seite.';
  }

  Future<String> _download(Map<String, Object?> market) async {
    final till = int.tryParse(_register.text);
    if (till == null || till <= 0) {
      throw const FormatException('Positive Kassennummer eingeben.');
    }
    final library = widget.library;
    if (library == null) {
      throw StateError('Marktbibliothek ist nicht verfügbar.');
    }
    final package = await _service.download(
      market['id'] as int,
      registerNumber: till,
    );
    await library.importPackage(package, originalSource: package.rawJson);
    return '${package.session.name} wurde mit ${package.listings.length} Artikeln in die Bibliothek aufgenommen. Dort die Kasse öffnen.';
  }

  Future<String> _upload(Future<SyncResult> Function() action) async {
    final result = await action();
    if (result.sent == 0) return 'Keine Daten für diese Stufe vorhanden.';
    return '${result.stage}: ${result.sent} gesendet, ${result.acknowledged} Verkaufsereignisse bestätigt. Einzelresultate im Archiv prüfen.';
  }

  Future<String> _refer(Map<String, Object?> row) async {
    final id = row['vorgangId'] as String;
    final event = (await widget.store!.events()).singleWhere((e) => e.id == id);
    final type = row['result'] == 'conflict'
        ? 'doppelverkauf'
        : event.cancelOf != null
        ? 'storno_mismatch'
        : 'unerwarteter_verkauf';
    await _service.referConflict(id, type);
    return 'Konflikt an den Organisator verwiesen. Seine Entscheidung steht noch aus.';
  }

  Future<bool> _confirm(String title, String details) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SelectableText(details),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bestätigen'),
            ),
          ],
        ),
      ) ??
      false;

  Future<String> _localAction(Map<String, Object?> row, String action) async {
    final id = row['vorgangId'] as String;
    if (!await _confirm(
      action == 'cancel' ? 'Lokal stornieren?' : 'Konflikt ignorieren?',
      '$id\n${action == 'cancel' ? 'Ein neues Storno wird dauerhaft gespeichert und beim nächsten Upload übertragen.' : 'Nur aus dieser Ansicht ausblenden. Verkauf, Outbox und Protokoll bleiben erhalten.'}',
    )) {
      return 'Abgebrochen.';
    }
    if (action == 'cancel') {
      final client = ApiClient('https://archive.invalid');
      try {
        await SyncService(widget.store, client).cancelConflict(id);
      } finally {
        client.close();
      }
    }
    _dismissed.add('$id:${row['result']}');
    return action == 'cancel'
        ? 'Storno gespeichert; Übertragung ausstehend.'
        : 'Konflikt für diese Ansicht ignoriert.';
  }

  Future<String> _deleteProtocol(Map<String, Object?> protocol) async {
    if (!await _confirm(
      'Dieses Protokoll löschen?',
      '${protocol['stage']}\n${protocol['at']}\nVerkäufe und Wiederholungswarteschlange bleiben erhalten.',
    )) {
      return 'Abgebrochen.';
    }
    final client = ApiClient('https://archive.invalid');
    try {
      await SyncService(widget.store, client).deleteProtocol(protocol);
    } finally {
      client.close();
    }
    return 'Ausgewähltes Protokoll gelöscht.';
  }

  Future<String> _export({bool conflicts = false, bool csv = false}) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/marketmate_${conflicts ? 'conflicts' : 'sync'}_${widget.store!.session.marketId}.${csv ? 'csv' : 'json'}',
    );
    var raw = const JsonEncoder.withIndent('  ').convert({
      'marketId': widget.store!.session.marketId,
      'protocols': _protocols,
      'referrals': _referrals,
    });
    if (conflicts) {
      final client = ApiClient('https://archive.invalid');
      try {
        raw = await SyncService(
          widget.store,
          client,
        ).exportConflicts(csv: csv, stage: _stageFilter);
      } finally {
        client.close();
      }
    }
    await file.writeAsString(raw, flush: true);
    if (!mounted) return 'Archiv gespeichert.';
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return 'Archiv zum Teilen bereitgestellt.';
  }

  @override
  void dispose() {
    _api?.close();
    for (final controller in [
      _base,
      _email,
      _password,
      _organization,
      _register,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static const _problems = {
    'conflict',
    'invalid',
    'not_found',
    'missing_ack',
    'missing_listing',
  };

  bool _visibleProtocol(Map<String, Object?> protocol) =>
      (_stageFilter == null || protocol['stage'] == _stageFilter) &&
      (!_conflictsOnly ||
          (protocol['results'] as List? ?? []).any(
            (r) => r is Map && _problems.contains(r['result']),
          ));

  Widget _step(
    BuildContext context,
    int number,
    String title,
    bool done,
    List<Widget> children,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor: done
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  child: done
                      ? const Icon(Icons.check, size: 16)
                      : Text('$number', style: const TextStyle(fontSize: 13)),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant);
    final store = widget.store;
    final loggedIn = _api?.hasToken ?? false;
    final canUpload =
        loggedIn &&
        store != null &&
        !store.session.isDemo &&
        store.session.exportGeneration > 0;
    final openProblems = [
      for (final protocol in _protocols)
        for (final raw in protocol['results'] as List? ?? [])
          if (raw is Map &&
              _problems.contains(raw['result']) &&
              raw['vorgangId'] is String &&
              !_dismissed.contains('${raw['vorgangId']}:${raw['result']}'))
            Map<String, Object?>.from(raw),
      for (final row in _audit)
        if (!_dismissed.contains('${row['vorgangId']}:${row['result']}')) row,
    ];
    final markets = [
      for (final market in _markets)
        if ('${market['name']} ${market['location']} ${market['id']}'
            .toLowerCase()
            .contains(_marketFilter))
          market,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Notice(_message!),
                ),
              if (openProblems.isNotEmpty)
                Card(
                  color: Tones.warningContainer(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${openProblems.length} Konflikte brauchen eine Entscheidung',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Tones.onWarningContainer(context),
                          ),
                        ),
                        for (final row in openProblems)
                          _resultTile(row, canUpload),
                      ],
                    ),
                  ),
                ),
              _step(context, 1, 'Anmeldung', loggedIn, [
                if (loggedIn)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Angemeldet als ${_email.text}\nGilt bis zum Verlassen dieser Seite.',
                          style: muted,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _api!.clearToken();
                                _message = 'Abgemeldet.';
                              }),
                        child: const Text('Abmelden'),
                      ),
                    ],
                  )
                else ...[
                  if (_editServer) ...[
                    TextField(
                      controller: _base,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'API-Adresse',
                        hintText: 'https://…',
                      ),
                    ),
                    TextField(
                      controller: _organization,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Organisations-ID',
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_base.text}\nOrganisation ${_organization.text}',
                            style: muted,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _editServer = true),
                          child: const Text('Ändern'),
                        ),
                      ],
                    ),
                  TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Organisator-E-Mail',
                    ),
                  ),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Passwort'),
                    onSubmitted: (_) => _run(_login),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : () => _run(_login),
                    child: const Text('Anmelden'),
                  ),
                ],
              ]),
              _step(context, 2, 'Markt herunterladen', false, [
                if (!loggedIn)
                  Text('Nach der Anmeldung verfügbar.', style: muted)
                else ...[
                  Row(
                    spacing: 8,
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _register,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Kassen-Nr.',
                          ),
                        ),
                      ),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _run(() async {
                                  final markets = await _service.markets(
                                    _organization.text,
                                  );
                                  if (mounted) {
                                    setState(() => _markets = markets);
                                  }
                                  return '${markets.length} Märkte geladen.';
                                }),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Märkte laden'),
                        ),
                      ),
                    ],
                  ),
                  if (_markets.length > 5)
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Nach Name, Ort oder ID filtern',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(
                        () => _marketFilter = value.trim().toLowerCase(),
                      ),
                    ),
                  for (final market in markets)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${market['name'] ?? market['id']}'),
                      subtitle: Text(
                        [market['date'], market['location'], market['status']]
                            .where((v) => v != null && '$v'.isNotEmpty)
                            .join(' · '),
                      ),
                      trailing: IconButton.filledTonal(
                        tooltip: 'Geprüftes Paket herunterladen',
                        icon: const Icon(Icons.download),
                        onPressed: _busy || widget.library == null
                            ? null
                            : () => _run(() => _download(market)),
                      ),
                    ),
                  if (_markets.isNotEmpty)
                    Text(
                      'Ein Download öffnet keine andere Kasse. Angezeigt werden die ersten 100 Märkte.',
                      style: muted.copyWith(fontSize: 12),
                    ),
                ],
              ]),
              _step(
                context,
                3,
                'Verkäufe senden',
                store != null &&
                    !store.session.isDemo &&
                    store.session.exportGeneration > 0 &&
                    _pending == 0 &&
                    _queued == 0,
                [
                  if (store == null)
                    Text(
                      'Zuerst eine Kasse in der Bibliothek öffnen.',
                      style: muted,
                    )
                  else ...[
                    Text(
                      _pending == 0
                          ? 'Alle Verkäufe von Kasse ${store.session.registerNumber} sind bestätigt.'
                          : '$_pending Verkaufsereignisse von Kasse ${store.session.registerNumber} noch nicht bestätigt.',
                      style: muted,
                    ),
                    if (store.session.isDemo ||
                        store.session.exportGeneration == 0)
                      Text(
                        'Demo- und V1-Märkte sind für Backend-Uploads gesperrt.',
                        style: TextStyle(color: Tones.warning(context)),
                      ),
                    FilledButton.icon(
                      onPressed: _busy || !canUpload
                          ? null
                          : () => _run(
                              () => _upload(() => _service.uploadSales()),
                            ),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Verkaufsereignisse senden'),
                    ),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      shape: const Border(),
                      title: const Text('Weitere Übertragungen'),
                      children: [
                        for (final (label, enabled, action) in [
                          (
                            'Stornos wiederholen ($_queued)',
                            _queued > 0,
                            () => _service.uploadSales(retryOnly: true),
                          ),
                          (
                            'Listing-Status senden',
                            true,
                            () => _service.uploadListingStatus(),
                          ),
                          (
                            'Tagesumsatz senden',
                            true,
                            () => _service.uploadSummary(),
                          ),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton(
                              onPressed: _busy || !canUpload || !enabled
                                  ? null
                                  : () => _run(() => _upload(action)),
                              child: Text(label),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              if (store != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: const Icon(Icons.history),
                    title: const Text('Protokolle und Exporte'),
                    subtitle: Text(
                      '${_protocols.length} Protokolle · ${_referrals.length} verwiesen',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Nur Konflikte'),
                            selected: _conflictsOnly,
                            onSelected: (value) =>
                                setState(() => _conflictsOnly = value),
                          ),
                          for (final stage in [
                            'sales-batch',
                            'listing-status',
                            'sales-summary',
                          ])
                            FilterChip(
                              label: Text(stage),
                              selected: _stageFilter == stage,
                              onSelected: (value) => setState(
                                () => _stageFilter = value ? stage : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _run(_export),
                            icon: const Icon(Icons.share),
                            label: const Text('Archiv teilen'),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(() => _export(conflicts: true)),
                            child: const Text('Konflikte JSON'),
                          ),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => _export(conflicts: true, csv: true),
                                  ),
                            child: const Text('Konflikte CSV'),
                          ),
                        ],
                      ),
                      for (final protocol in _protocols)
                        if (_visibleProtocol(protocol))
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              '${protocol['stage']} · ${protocol['status']}',
                            ),
                            subtitle: Text(
                              '${protocol['at']} · ${protocol['sent'] ?? 0} gesendet · ${protocol['acknowledged'] ?? 0} bestätigt',
                            ),
                            children: [
                              if (protocol['error'] != null)
                                SelectableText('${protocol['error']}'),
                              for (final raw
                                  in protocol['results'] as List? ?? [])
                                _resultTile(
                                  Map<String, Object?>.from(raw as Map),
                                  canUpload,
                                ),
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _run(() => _deleteProtocol(protocol)),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Dieses Protokoll löschen'),
                              ),
                            ],
                          ),
                      if (_referrals.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Verwiesen – Entscheidung des Organisators ausstehend',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        for (final referral in _referrals)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${referral['vorgangId']}'),
                            subtitle: Text(
                              '${referral['conflictType']} · ${referral['raisedAt']}',
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultTile(Map<String, Object?> row, bool canUpload) =>
      _dismissed.contains('${row['vorgangId']}:${row['result']}')
      ? const SizedBox.shrink()
      : ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${row['vorgangId'] ?? row['listingId']} · ${row['result']}',
          ),
          subtitle: row['message'] == null && row['currentStatus'] == null
              ? null
              : Text('${row['message'] ?? row['currentStatus']}'),
          trailing:
              row['vorgangId'] is String && _problems.contains(row['result'])
              ? PopupMenuButton<String>(
                  enabled: !_busy,
                  tooltip: 'Konflikt bearbeiten',
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Lokal stornieren'),
                    ),
                    PopupMenuItem(
                      value: 'refer',
                      enabled: canUpload,
                      child: const Text('An Organisator verweisen'),
                    ),
                    const PopupMenuItem(
                      value: 'ignore',
                      child: Text('Akzeptieren / ignorieren'),
                    ),
                  ],
                  onSelected: (action) => _run(
                    () => action == 'refer'
                        ? _refer(row)
                        : _localAction(row, action),
                  ),
                )
              : null,
        );
}
