import 'package:flutter/material.dart';
import '../domain/money.dart';
import 'messages.dart';

class PaymentInput {
  final int cents;
  final bool known;
  const PaymentInput(this.cents, this.known);
}

class PaymentDialog extends StatefulWidget {
  final int totalCents;
  final Future<void> Function(PaymentInput)? onConfirm;
  final String initialInput;
  final Future<void> Function(String)? onPark;
  const PaymentDialog({
    super.key,
    required this.totalCents,
    this.onConfirm,
    this.initialInput = '',
    this.onPark,
  });
  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final _input = TextEditingController(text: widget.initialInput);
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_saving) return;
    try {
      final cents = _input.text.trim().isEmpty
          ? (widget.totalCents < 0 ? 0 : widget.totalCents)
          : parseCents(_input.text);
      if (cents < widget.totalCents) {
        setState(() => _error = 'Der erhaltene Betrag reicht nicht aus.');
        return;
      }
      final input = PaymentInput(cents, _input.text.trim().isNotEmpty);
      setState(() {
        _saving = true;
        _error = null;
      });
      await widget.onConfirm?.call(input);
      if (mounted) Navigator.pop(context, input);
    } catch (error) {
      if (mounted) setState(() => _error = checkoutError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(widget.totalCents < 0 ? 'Barauszahlung' : 'Barzahlung'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.totalCents < 0
                  ? 'Auszuzahlen: ${formatCents(-widget.totalCents)}'
                  : 'Zu zahlen: ${formatCents(widget.totalCents)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('tendered'),
              controller: _input,
              enabled: !_saving,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Erhalten in Euro (optional)',
                helperText:
                    'Leer: Bargeld bestätigen ohne Wechselgeldberechnung',
                errorText: _error,
              ),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 12),
            const Text(
              'Erst bestätigen, wenn die Bargeldübergabe geprüft ist.',
            ),
            if (_saving) const LinearProgressIndicator(),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (context, value, child) {
                try {
                  final cents = parseCents(value.text);
                  final difference = cents - widget.totalCents;
                  return Text(
                    difference >= 0
                        ? 'Rückgeld: ${formatCents(difference)}'
                        : 'Fehlbetrag: ${formatCents(-difference)}',
                  );
                } catch (_) {
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onPark != null)
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    setState(() => _saving = true);
                    try {
                      await widget.onPark!(_input.text);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (mounted) setState(() => _error = checkoutError(e));
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: const Text('Kunde parken'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: const Text('Barzahlung bestätigen'),
        ),
      ],
    ),
  );
}
