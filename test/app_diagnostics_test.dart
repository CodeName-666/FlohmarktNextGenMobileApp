import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/services/app_diagnostics.dart';

void main() {
  test(
    'startup diagnostics serialize writes and redact secrets without market database',
    () async {
      final dir = await Directory.systemTemp.createTemp('startup_log_');
      AppDiagnostics.initialize(dir.path);
      await Future.wait([
        AppDiagnostics.record(
          'startup',
          'token=secret-value Bearer abc123',
          null,
        ),
        AppDiagnostics.record(
          'framework',
          'password: hidden',
          StackTrace.fromString('token=hidden-stack'),
        ),
      ]);
      final text = await AppDiagnostics.read();
      expect(text.split('\n').where((l) => l.isNotEmpty), hasLength(2));
      for (final secret in [
        'secret-value',
        'abc123',
        'hidden',
        'hidden-stack',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(AppDiagnostics.writeFailure, isNull);
      await dir.delete(recursive: true);
    },
  );
}
