import 'package:flutter/material.dart';
import '../domain/money.dart';

class PaymentDialog extends StatefulWidget {
  final int totalCents;
  const PaymentDialog({super.key, required this.totalCents});
  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  final _input = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      final cents = parseCents(_input.text);
      if (cents < widget.totalCents) {
        setState(() => _error = 'Der erhaltene Betrag reicht nicht aus.');
        return;
      }
      Navigator.pop(context, cents);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Barzahlung'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Zu zahlen: ${formatCents(widget.totalCents)}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('tendered'),
            controller: _input,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Erhalten in Euro',
              errorText: _error,
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 12),
          const Text('Erst bestätigen, wenn das Bargeld vorliegt.'),
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
        child: const Text('Barzahlung bestätigen'),
      ),
    ],
  );
}
