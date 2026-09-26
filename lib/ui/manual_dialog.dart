import 'package:flutter/material.dart';
import '../domain/barcode.dart';

class ManualDialog extends StatefulWidget {
  const ManualDialog({super.key});
  @override
  State<ManualDialog> createState() => _ManualDialogState();
}

class _ManualDialogState extends State<ManualDialog> {
  final _code = TextEditingController();
  final _revision = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    _revision.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      final revision = int.tryParse(_revision.text.trim()) ?? 0;
      final label = LabelCode.manual(_code.text, revision);
      Navigator.pop(context, label);
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Etikett eingeben'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Vollständiger Artikelcode',
              helperText: '14 oder 15 Ziffern vom Etikett',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _revision,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Aufgedruckte Revision',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: _confirm,
        child: const Text('Artikel übernehmen'),
      ),
    ],
  );
}
