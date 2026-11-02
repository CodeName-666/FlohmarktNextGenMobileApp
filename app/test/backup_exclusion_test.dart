import 'dart:io';

import 'package:flohmarkt_mobile/services/backup_exclusion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// KAN-592: on iOS the register database folder is excluded from backups.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  final calls = <MethodCall>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_test_');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
          calls.add(call);
          return true;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    await dir.delete(recursive: true);
  });

  test('iOS marks the whole database folder, creating it first', () async {
    final target = '${dir.path}/databases';
    await BackupExclusion.excludeDirectory(target, isIOS: true);
    expect(await Directory(target).exists(), isTrue);
    expect(calls.single.method, 'excludeFromBackup');
    expect(calls.single.arguments, target);
  });

  test('other platforms do nothing', () async {
    await BackupExclusion.excludeDirectory(dir.path, isIOS: false);
    expect(calls, isEmpty);
  });
}
