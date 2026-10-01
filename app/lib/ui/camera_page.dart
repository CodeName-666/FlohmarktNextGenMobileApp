import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/checkout_store.dart';

class CameraPage extends StatefulWidget {
  final CheckoutStore? store;
  final Future<String> Function(String)? onScan;
  const CameraPage({super.key, this.store, this.onScan});
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  MobileScannerController? _controller;
  bool _returned = false, _processing = false, _paused = false;
  String? _feedback, _failure, _last;
  DateTime? _lastAt;
  final _pending = <String>[];
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final settings = await widget.store?.setting('uiSettings');
      final values = settings is Map ? settings : {};
      if (values['cameraEnabled'] == false) {
        throw StateError('Kamera ist in den Einstellungen deaktiviert.');
      }
      final facing = values['cameraFacing'],
          torch = values['cameraTorch'],
          format = values['barcodeFormat'];
      final formats = switch (format) {
        'ean8' => [BarcodeFormat.ean8],
        'ean13' => [BarcodeFormat.ean13],
        'code128' => [BarcodeFormat.code128],
        'qrCode' => [BarcodeFormat.qrCode],
        _ => <BarcodeFormat>[],
      };
      if (!mounted) return;
      setState(
        () => _controller = MobileScannerController(
          facing: facing == 'front' ? CameraFacing.front : CameraFacing.back,
          torchEnabled: torch == true,
          formats: formats,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _failure = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _pending.clear();
    final controller = _controller;
    if (controller == null || !controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed && !_paused) {
      unawaited(_cameraAction(controller.start));
    } else if (state != AppLifecycleState.resumed) {
      unawaited(_cameraAction(controller.stop));
    }
  }

  Future<void> _cameraAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _failure = e.toString());
    }
  }

  @override
  void dispose() {
    _pending.clear();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _detect(BarcodeCapture capture) async {
    if (!mounted || _returned || _paused || !_foreground) return;
    final values = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    if (values.length != 1) return;
    final raw = values.single, now = DateTime.now();
    if (_last == raw &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _last = raw;
    _lastAt = now;
    if (widget.onScan == null) {
      _returned = true;
      Navigator.pop(context, raw);
      return;
    }
    if (_pending.contains(raw)) return;
    _pending.add(raw);
    if (_processing) return;
    setState(() => _processing = true);
    try {
      while (_pending.isNotEmpty && mounted && !_paused && _foreground) {
        final next = _pending.removeAt(0);
        try {
          final text = await widget.onScan!(next);
          if (mounted) setState(() => _feedback = text);
        } catch (e) {
          if (mounted) setState(() => _feedback = e.toString());
        }
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_processing,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Etiketten scannen'),
        actions: [
          if (_controller != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller!,
              builder: (context, state, _) => IconButton(
                tooltip:
                    'Kamera wechseln (${state.availableCameras ?? 0} verfügbar)',
                icon: const Icon(Icons.cameraswitch_outlined),
                onPressed: (state.availableCameras ?? 0) < 2 || _processing
                    ? null
                    : () => _cameraAction(() async {
                        await _controller!.switchCamera();
                        final saved = await widget.store?.setting('uiSettings');
                        await widget.store?.setSetting('uiSettings', {
                          if (saved is Map) ...Map<String, Object?>.from(saved),
                          'cameraFacing':
                              _controller!.value.cameraDirection ==
                                  CameraFacing.front
                              ? 'front'
                              : 'back',
                        });
                      }),
              ),
            ),
          if (_controller != null)
            IconButton(
              tooltip: _paused ? 'Kamera starten' : 'Kamera stoppen',
              icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
              onPressed: () async {
                final next = !_paused;
                if (next) _pending.clear();
                await _cameraAction(
                  next ? _controller!.stop : _controller!.start,
                );
                if (mounted) setState(() => _paused = next);
              },
            ),
          if (_controller != null)
            IconButton(
              tooltip: 'Licht umschalten',
              icon: const Icon(Icons.flash_on),
              onPressed: () => _cameraAction(_controller!.toggleTorch),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _failure != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('Kamera nicht verfügbar: $_failure'),
                    ),
                  )
                : _controller == null
                ? const Center(child: CircularProgressIndicator())
                : MobileScanner(
                    controller: _controller,
                    onDetect: _detect,
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.no_photography_outlined, size: 48),
                            const SizedBox(height: 16),
                            const Text(
                              'Kamera nicht verfügbar. Kamerazugriff erlauben oder manuell eingeben.',
                              textAlign: TextAlign.center,
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Zurück'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          if (_processing) const LinearProgressIndicator(),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _feedback == null
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _feedback ??
                            (widget.onScan == null
                                ? 'Etikett ruhig ins Bild halten.'
                                : 'Etiketten nacheinander ins Bild halten. Jedes Ergebnis erscheint hier.'),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  if (widget.onScan != null)
                    FilledButton.icon(
                      onPressed: _processing
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.check),
                      label: const Text('Fertig'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
