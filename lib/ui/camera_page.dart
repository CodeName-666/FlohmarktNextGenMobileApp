import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  bool _returned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Etikett scannen')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            // The owned controller is lifecycle-managed and disposed by MobileScanner.
            onDetect: (capture) {
              if (_returned) return;
              final values = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .where((s) => s.isNotEmpty)
                  .toSet();
              if (values.length != 1) {
                return; // Aim at one label, never choose arbitrarily.
              }
              _returned = true;
              Navigator.pop(context, values.single);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Kamera nicht verfügbar. Kamerazugriff in den Einstellungen erlauben oder das Etikett manuell eingeben.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Zur manuellen Eingabe zurück'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Ein Etikett ruhig ins Bild halten. Der erste erkannte Code wird geprüft.',
            ),
          ),
        ),
      ],
    ),
  );
}
