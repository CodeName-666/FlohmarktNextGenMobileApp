import 'dart:convert';
import 'dart:io';

/// Last-resort local diagnostics independent of market database availability.
class AppDiagnostics {
  static File? _file;
  static Future<void> _tail = Future<void>.value();
  static String? writeFailure;
  static void initialize(String directory) {
    _file = File('$directory/startup-errors.jsonl');
  }

  static String redact(String text) => text
      .replaceAll(
        RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
        'Bearer [redigiert]',
      )
      .replaceAllMapped(
        RegExp(
          r'''["']?(password|passwort|token|authorization)["']?\s*[:=]\s*["']?[^\s,;}"']+''',
          caseSensitive: false,
        ),
        (m) => '${m[1]}=[redigiert]',
      );
  static Future<void> record(String category, Object error, StackTrace? stack) {
    _tail = _tail.then((_) async {
      final file = _file;
      if (file == null) return;
      try {
        await file.parent.create(recursive: true);
        if (await file.exists() && await file.length() > 1048576) {
          final previous = File('${file.path}.previous');
          await previous.writeAsBytes(await file.readAsBytes(), flush: true);
          await file.writeAsString('', flush: true);
        }
        await file.writeAsString(
          '${jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'category': category, 'message': redact(error.toString()), 'stack': redact(stack?.toString() ?? '')})}\n',
          mode: FileMode.append,
          flush: true,
        );
        writeFailure = null;
      } catch (e) {
        writeFailure = 'Diagnose nicht speicherbar: ${e.runtimeType}';
      }
    });
    return _tail;
  }

  static Future<String> read() async {
    await _tail;
    final file = _file;
    return file != null && await file.exists() ? file.readAsString() : '';
  }
}
