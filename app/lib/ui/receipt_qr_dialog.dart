import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/checkout_store.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import '../services/receipt_qr.dart';

/// Whether the register offers the offline QR receipt (setting, default on).
Future<bool> receiptQrEnabled(CheckoutStore store) async {
  try {
    final saved = await store.setting('uiSettings');
    return saved is! Map || saved['receiptQr'] != false;
  } catch (_) {
    return true;
  }
}

/// Opens the offline QR receipt full screen; built locally, no network.
Future<void> showReceiptQr(
  BuildContext context,
  CheckoutStore store,
  Receipt receipt,
) async {
  final text = receiptQrText(store.session, receipt, await store.events());
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => ReceiptQrDialog(receipt: receipt, text: text),
  );
}

class ReceiptQrDialog extends StatelessWidget {
  final Receipt receipt;
  final String text;
  const ReceiptQrDialog({super.key, required this.receipt, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      // Dark modules on white give every camera app the contrast it needs.
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Beleg ${receipt.number} · ${formatCents(receipt.totalCents)}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Mit der Kamera-App scannen. Der Beleg erscheint als Text.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87),
              ),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: QrImageView(
                      key: const Key('receipt-qr-code'),
                      data: text,
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                label: const Text('Schließen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
