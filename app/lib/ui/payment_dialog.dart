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

  /// Exact amount plus the next common notes above it.
  List<int> get _quick => widget.totalCents <= 0
      ? const []
      : [
          widget.totalCents,
          ...[
            500,
            1000,
            2000,
            5000,
            10000,
          ].where((n) => n > widget.totalCents).take(3),
        ];

  Future<void> _park() async {
    setState(() => _saving = true);
    try {
      await widget.onPark!(_input.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = checkoutError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final refund = widget.totalCents < 0;
    return PopScope(
      canPop: !_saving,
      child: Material(
        color: scheme.surfaceContainerLowest,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        refund ? 'Barauszahlung' : 'Barzahlung',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Abbrechen',
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, value, child) {
                    int? difference;
                    try {
                      difference = parseCents(value.text) - widget.totalCents;
                    } catch (_) {}
                    final short = difference != null && difference < 0;
                    return Row(
                      spacing: 10,
                      children: [
                        _Amount(
                          refund ? 'Auszuzahlen' : 'Zu zahlen',
                          formatCents(widget.totalCents.abs()),
                          scheme.surfaceContainerHighest,
                          scheme.onSurface,
                        ),
                        _Amount(
                          short ? 'Fehlbetrag' : 'Rückgeld',
                          difference == null
                              ? '–'
                              : formatCents(difference.abs()),
                          short
                              ? scheme.errorContainer
                              : scheme.primaryContainer,
                          short
                              ? scheme.onErrorContainer
                              : scheme.onPrimaryContainer,
                        ),
                      ],
                    );
                  },
                ),
                TextField(
                  key: const Key('tendered'),
                  controller: _input,
                  enabled: !_saving,
                  autofocus: true,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Erhalten in Euro (optional)',
                    helperText:
                        'Leer: Bargeld bestätigen ohne Wechselgeldberechnung',
                    errorText: _error,
                    suffixText: '€',
                  ),
                  onSubmitted: (_) => _confirm(),
                ),
                if (_quick.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cents in _quick)
                        ActionChip(
                          label: Text(
                            cents == widget.totalCents
                                ? 'Passend'
                                : '${cents ~/ 100} €',
                          ),
                          onPressed: _saving
                              ? null
                              : () => _input.text = formatCents(
                                  cents,
                                ).replaceAll(' €', ''),
                        ),
                    ],
                  ),
                Text(
                  'Erst bestätigen, wenn die Bargeldübergabe geprüft ist.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                if (_saving) const LinearProgressIndicator(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  onPressed: _saving ? null : _confirm,
                  icon: const Icon(Icons.check),
                  label: Text(
                    refund
                        ? 'Barauszahlung bestätigen'
                        : 'Barzahlung bestätigen',
                  ),
                ),
                if (widget.onPark != null)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _park,
                    icon: const Icon(Icons.pause),
                    label: const Text('Vorgang parken'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  final String label, value;
  final Color background, foreground;
  const _Amount(this.label, this.value, this.background, this.foreground);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: foreground, fontSize: 13)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: foreground,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
