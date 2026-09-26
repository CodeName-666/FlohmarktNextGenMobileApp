import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/checkout_store.dart';
import '../services/desktop_archive.dart';
import '../services/desktop_draft.dart';
import 'library_page.dart';
import 'receipt_page.dart';

class FilesPage extends StatefulWidget {
  final CheckoutStore store;
  const FilesPage({super.key, required this.store});
  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  bool _busy = false;
  String? _message;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      _message = e.toString();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _export() async {
    bool held = false;
    if ((await widget.store.heldCart()).isNotEmpty) {
      if (!mounted) return;
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Welchen Kundenkorb exportieren?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Aktiver Kundenkorb'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Geparkter Kundenkorb'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      held = choice;
    }
    final draft = await widget.store.exportDesktopDraft(held: held);
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
      _message =
          'Kassenarchiv gespeichert${draft == null ? '' : ' einschließlich gewähltem Kundenentwurf'}. Eine vollständige mobile Sicherung enthält beide Kundenkörbe.';
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dateien und Sicherung')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.store.session.name,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Dateien werden über die Dokumentverwaltung des Mobilgeräts ausgewählt und gespeichert.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(_import),
          icon: const Icon(Icons.merge),
          label: const Text('Desktop-Kassen importieren / zusammenführen'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(_export),
          child: const Text('Desktop-Kassenarchiv exportieren'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await saveJsonFile(
                    'mobile-kasse-sicherung.json',
                    await widget.store.backup(),
                  );
                }),
          child: const Text('Vollständige mobile Sicherung speichern'),
        ),
        OutlinedButton(
          onPressed: _busy ? null : () => _run(_restore),
          child: const Text('Sicherung in leere Kasse einlesen'),
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptPage(store: widget.store),
                  ),
                ),
          child: const Text('Belege und Konfliktverkäufe prüfen'),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) SelectableText(_message!),
        FutureBuilder<Object?>(
          future: widget.store.setting('consolidationSources'),
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text('Bisher zusammengeführte Dateien'),
              if (snapshot.hasError)
                Text('Quellen nicht lesbar: ${snapshot.error}'),
              for (final row in snapshot.data as List? ?? [])
                ListTile(
                  title: Text('${(row as Map)['name']}'),
                  subtitle: Text(
                    '${row['importedAt']}\nPrüfsumme: ${row['sha256']}',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
