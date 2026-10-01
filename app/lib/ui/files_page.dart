import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../domain/money.dart';
import '../services/desktop_archive.dart';
import '../services/desktop_draft.dart';
import 'library_page.dart';
import 'tones.dart';

class FilesPage extends StatefulWidget {
  final CheckoutStore store;
  const FilesPage({super.key, required this.store});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _busy = false;
  bool _failed = false;
  String? _message;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _failed = false;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      _failed = true;
      _message = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() async {
    String? draftId;
    final parked = await widget.store.parkedDrafts();
    if (parked.isNotEmpty) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Welchen Vorgang exportieren?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'active'),
              child: const Text('Aktiver Vorgang'),
            ),
            for (final draft in parked)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, draft.id),
                child: Text(
                  'Vorgang ${draft.number} · geparkt\n'
                  '${draft.entries.length} Positionen · ${formatCents(draft.totalCents)}',
                ),
              ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice != 'active') draftId = choice;
    }
    final currentNumber = draftId == null
        ? await widget.store.activeDraftNumber()
        : parked.singleWhere((draft) => draft.id == draftId).number;
    final exportNumber = await widget.store.desktopDraftExportNumber(
      draftId: draftId,
    );
    if (exportNumber != null && exportNumber != currentNumber) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Vorgangsnummer anpassen?'),
          content: Text(
            'Für die Desktop-Übergabe wird Vorgang $currentNumber als Vorgang $exportNumber weitergeführt. '
            'Inhalt und Zahlung bleiben erhalten. Die neue Nummer wird auch in dieser Kasse gespeichert.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Anpassen und exportieren'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    final draft = await widget.store.exportDesktopDraft(draftId: draftId);
    final raw = DesktopArchive.encode(
      session: widget.store.session,
      events: await widget.store.events(),
      catalog: await widget.store.allListings(),
      reconciliation: await widget.store.reconciliationStates(),
      consolidated: true,
      draftRaw: draft,
    );
    final uri = await FilePicker.saveFile(
      fileName: 'kasse_${widget.store.session.registerNumber}.json',
      bytes: Uint8List.fromList(utf8.encode(raw)),
      mimeType: 'application/json',
    );
    if (uri != null) {
      final number = (draft?['kunde'] as Map?)?['kunden_nummer'];
      _message =
          'Kassenarchiv gespeichert${number == null ? '' : ' einschließlich Vorgang $number'}. Eine vollständige mobile Sicherung enthält alle Kundenkörbe.';
    }
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty) return;
    final catalog = await widget.store.allListings();
    final local = DesktopArchive.decode(
      DesktopArchive.encode(
        session: widget.store.session,
        events: await widget.store.events(),
        catalog: catalog,
        reconciliation: await widget.store.reconciliationStates(),
        consolidated: true,
      ),
      session: widget.store.session,
      catalog: catalog,
    );
    final archives = [local];
    final sources = <Map<String, Object?>>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      sources.add({
        'name': file.name,
        'sha256': sha256.convert(bytes).toString(),
        'importedAt': DateTime.now().toUtc().toIso8601String(),
      });
      archives.add(
        DesktopArchive.decode(
          utf8.decode(bytes),
          session: widget.store.session,
          catalog: catalog,
        ),
      );
    }
    final merged = DesktopArchive.merge(archives);
    final draftArchives = archives
        .skip(1)
        .where((a) => a.draftRaw != null)
        .toList();
    if (draftArchives.length > 1) {
      throw const FormatException(
        'Kassen mit offenen Entwürfen einzeln in der passenden Kasse importieren.',
      );
    }
    final draft = DesktopDraft.decode(
      draftArchives.isEmpty ? null : draftArchives.single.draftRaw,
      session: widget.store.session,
      catalog: catalog,
      committedEvents: merged.events,
      exportBody: widget.store.session.metadata,
    );
    final fatal = merged.conflicts
        .where((c) => c.kind != 'duplicate_sale' && c.kind != 'reconciliation')
        .toList();
    if (fatal.isNotEmpty) {
      throw FormatException(
        fatal.map((c) => '${c.identifier}: ${c.message}').join('\n'),
      );
    }
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kassen zusammenführen'),
        content: SingleChildScrollView(
          child: Text(
            '${draft == null ? '' : 'Offener Kundenkorb ${draft.customerNumber}: ${draft.positions.length} Positionen werden als Entwurf übernommen, nicht als Verkauf.\n\n'}${merged.events.length} eindeutige Ereignisse aus ${files.length} Dateien und lokaler Kasse.\n\n${merged.conflicts.map((c) => '${c.identifier}: ${c.message}').join('\n')}\n\nMehrfachverkäufe bleiben als Konflikt nachvollziehbar. Über Belege den tatsächlich falschen Verkauf gezielt stornieren. Bei abweichender Rücksortierung den gewünschten Stand auswählen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          if (merged.conflicts.any((c) => c.kind == 'reconciliation'))
            TextButton(
              onPressed: () => Navigator.pop(context, 'incoming'),
              child: const Text('Mit Rücksortierung aus Import'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'local'),
            child: const Text('Zusammenführen · lokalen Stand behalten'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final states = {...merged.reconciliation};
    for (final conflict in merged.conflicts.where(
      (c) => c.kind == 'reconciliation',
    )) {
      if (choice == 'local') {
        final state = local.reconciliation[conflict.identifier];
        if (state != null) states[conflict.identifier] = state;
      } else {
        for (final archive in archives.skip(1)) {
          final state = archive.reconciliation[conflict.identifier];
          if (state != null) states[conflict.identifier] = state;
        }
      }
    }
    if (draft == null) {
      await widget.store.importEvents(
        merged.events,
        reconciliation: states,
        sources: sources,
      );
    } else {
      await widget.store.importEventsAndDraft(
        merged.events,
        draft,
        reconciliation: states,
        sources: sources,
      );
    }
    await widget.store.log(
      'import',
      '${files.length} Kassenarchive zusammengeführt; ${merged.conflicts.length} gemeldete Konflikte.',
    );
    _message =
        'Import gespeichert. ${merged.conflicts.where((c) => c.kind == 'duplicate_sale').length} Mehrfachverkauf-Konflikte prüfen.';
  }

  Future<void> _restore() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null) return;
    final backup = Map<String, Object?>.from(
      jsonDecode(utf8.decode(await file.readAsBytes())) as Map,
    );
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leere Kasse wiederherstellen?'),
        content: const Text(
          'Die Sicherung muss exakt zu Markt, Export und Kassennummer passen. Eine Kasse mit Verkäufen oder Entwurf wird nicht überschrieben.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await widget.store.restoreBackup(backup);
      _message = 'Sicherung wiederhergestellt.';
    }
  }

  Widget _section(
    BuildContext context,
    IconData icon,
    String title,
    String text,
    List<Widget> actions,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 10,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
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
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dateien und Sicherung')),
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
                child: Notice(_message!, error: _failed),
              ),
            _section(
              context,
              Icons.merge,
              'Desktop-Kassen',
              'Kassendateien der Desktop-App einlesen und mit dieser Kasse zusammenführen, oder diese Kasse für den Desktop exportieren.',
              [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(_import),
                  icon: const Icon(Icons.file_open),
                  label: const Text('Importieren / zusammenführen'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_export),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Kassenarchiv exportieren'),
                ),
              ],
            ),
            _section(
              context,
              Icons.backup_outlined,
              'Sicherung',
              'Vollständige Kopie dieser Kasse als Datei. Einlesen ist nur in eine leere Kasse möglich.',
              [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await saveJsonFile(
                            'mobile-kasse-sicherung.json',
                            await widget.store.backup(),
                          );
                        }),
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Sicherung speichern'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_restore),
                  icon: const Icon(Icons.restore),
                  label: const Text('Sicherung einlesen'),
                ),
              ],
            ),
            FutureBuilder<Object?>(
              future: widget.store.setting('consolidationSources'),
              builder: (context, snapshot) {
                final rows = snapshot.data as List? ?? [];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    leading: const Icon(Icons.history),
                    title: Text('Zusammengeführte Dateien (${rows.length})'),
                    children: [
                      if (snapshot.hasError)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Notice(
                            'Quellen nicht lesbar: ${snapshot.error}',
                            error: true,
                          ),
                        ),
                      if (rows.isEmpty && !snapshot.hasError)
                        const ListTile(title: Text('Noch keine.')),
                      for (final row in rows)
                        ListTile(
                          title: Text('${(row as Map)['name']}'),
                          subtitle: Text(
                            '${row['importedAt']}\nPrüfsumme ${row['sha256']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
