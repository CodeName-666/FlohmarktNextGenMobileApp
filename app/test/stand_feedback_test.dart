import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flohmarkt_mobile/data/checkout_store.dart';
import 'package:flohmarkt_mobile/data/demo_catalog.dart';
import 'package:flohmarkt_mobile/ui/register_page.dart';

import 'register_safety_test.dart' show settleDatabase;

/// KAN-593: the register keeps the display on and vibrates differently on
/// accepted and rejected articles; both can be switched off.
void main() {
  setUpAll(sqfliteFfiInit);
  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments ?? 'long'}');
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<CheckoutStore> openStore(Map<String, Object?>? settings) async {
    final store = await CheckoutStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    if (settings != null) await store.setSetting('uiSettings', settings);
    return store;
  }

  testWidgets('wake lock follows visibility, background and leaving', (
    tester,
  ) async {
    final calls = <bool>[];
    Future<void> wakelock(bool enable) async => calls.add(enable);
    await tester.runAsync(() async {
      final store = await openStore(null);
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: wakelock),
        ),
      );
      await settleDatabase(tester);
      expect(calls, [true]);

      void lifecycle(List<AppLifecycleState> states) {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      // A short interruption keeps the display on; the background releases it.
      lifecycle([AppLifecycleState.inactive]);
      await tester.pump();
      expect(calls, [true]);
      lifecycle([AppLifecycleState.hidden, AppLifecycleState.paused]);
      await tester.pump();
      expect(calls, [true, false]);
      lifecycle([
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump();
      expect(calls, [true, false, true]);

      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, active: false, wakelock: wakelock),
        ),
      );
      await settleDatabase(tester);
      expect(calls.last, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: wakelock),
        ),
      );
      await settleDatabase(tester);
      expect(calls.last, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      expect(calls.last, isFalse);
      await store.close();
    });
  });

  testWidgets('switched off, the display follows the normal timeout', (
    tester,
  ) async {
    final calls = <bool>[];
    Future<void> wakelock(bool enable) async => calls.add(enable);
    await tester.runAsync(() async {
      final store = await openStore({'keepScreenOn': false});
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: wakelock),
        ),
      );
      await settleDatabase(tester);
      expect(calls, isEmpty);
      await store.close();
    });
  });

  testWidgets('accepted and rejected scans vibrate differently', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = await openStore(null);
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: (_) async {}),
        ),
      );
      await settleDatabase(tester);
      final scan = tester.widget<TextField>(
        find.byKey(const Key('scan-input')),
      );
      scan.onSubmitted!(demoPayload);
      await settleDatabase(tester);
      scan.onSubmitted!('MM1|keine-gueltige-marke|1|00000000');
      await settleDatabase(tester);
      expect(haptics, ['HapticFeedbackType.lightImpact', 'long']);
      await store.close();
    });
  });

  testWidgets('vibration can be switched off', (tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      final store = await openStore({'scanVibration': false});
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterPage(store: store, wakelock: (_) async {}),
        ),
      );
      await settleDatabase(tester);
      final scan = tester.widget<TextField>(
        find.byKey(const Key('scan-input')),
      );
      scan.onSubmitted!('MM1|keine-gueltige-marke|1|00000000');
      await settleDatabase(tester);
      expect(haptics, isEmpty);
      await store.close();
    });
  });
}
