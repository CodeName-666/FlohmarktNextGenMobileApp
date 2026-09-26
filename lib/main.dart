import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'data/checkout_store.dart';
import 'ui/register_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await CheckoutStore.open(
      factory: databaseFactory,
      path: p.join(await getDatabasesPath(), 'marketmate_demo_v1.db'),
    );
    runApp(MarketMateApp(store: store));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Die lokale Kasse konnte nicht geöffnet werden. App erneut starten. '
                  'App-Daten nicht löschen, wenn Testbelege erhalten bleiben sollen.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MarketMateApp extends StatelessWidget {
  final CheckoutStore store;
  const MarketMateApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MarketMate · Mobile Kasse',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff006a68)),
      scaffoldBackgroundColor: const Color(0xfff4f7fa),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfff4f7fa),
        foregroundColor: Color(0xff182b3a),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
      useMaterial3: true,
    ),
    home: RegisterPage(store: store),
  );
}
