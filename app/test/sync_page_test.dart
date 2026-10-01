import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flohmarkt_mobile/ui/sync_page.dart';

void main() {
  testWidgets('download login is available without an active market', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SyncPage()));
    await tester.pumpAndSettle();
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Markt herunterladen'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Zuerst eine Kasse in der Bibliothek öffnen.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Zuerst eine Kasse in der Bibliothek öffnen.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
