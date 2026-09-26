import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'market_package.dart';

/// Read-only, exhaustive preview. A rejected source never yields an importable
/// partial package. The exact inspected source is passed to the final validator.
class LegacyInspection {
  final MarketPackage? package;
  final int validRows, ignoredRows, boxCount, sellerCount;
  final String sourceSha256;
  final List<String> issues;
  final Map<String, Object?> report;

  LegacyInspection._({
    required this.package,
    required this.validRows,
    required this.ignoredRows,
    required this.boxCount,
    required this.sellerCount,
    required this.sourceSha256,
    required List<String> issues,
    required Map<String, Object?> report,
  }) : issues = List.unmodifiable(issues),
       report = Map.unmodifiable(report);

  factory LegacyInspection.inspect(
    String raw, {
    required String name,
    int registerNumber = 1,
  }) {
    final digest = sha256.convert(utf8.encode(raw)).toString();
    final issues = <String>[];
    final boxes = <int>{}, seen = <String>{};
    final assignments = <String, int>{};
    var valid = 0, ignored = 0, sellers = 0;
    Object? body;
    try {
      body = jsonDecode(raw);
    } catch (_) {
      issues.add('Die Quelle enthält kein gültiges JSON.');
    }
    if (name.trim().isEmpty) issues.add('Marktname fehlt.');
    if (registerNumber < 1 || registerNumber > 9999) {
      issues.add('Kassennummer muss zwischen 1 und 9999 liegen.');
    }
    if (body is! List) {
      if (issues.isEmpty || body != null) {
        issues.add('V1-Export benötigt eine JSON-Liste.');
      }
    } else {
      for (var tableIndex = 0; tableIndex < body.length; tableIndex++) {
        final table = body[tableIndex];
        if (table is! Map || table['type'] != 'table') continue;
        final tableName = '${table['name'] ?? ''}';
        if (tableName == 'verkaeufer') {
          if (table['data'] is List) {
            sellers += (table['data'] as List).length;
          } else {
            issues.add('verkaeufer: ungültige Verkäuferliste.');
          }
        }
        if (!tableName.startsWith('stnr')) continue;
        final suffix = tableName.substring(4);
        final box = RegExp(r'^\d+$').hasMatch(suffix)
            ? int.tryParse(suffix)
            : null;
        final rows = table['data'];
        if (box == null || box < 0 || box > 999 || rows is! List) {
          issues.add('$tableName: ungültige Artikeltabelle.');
          continue;
        }
        boxes.add(box);
        assignments.putIfAbsent('$box', () => 0);
        for (var index = 0; index < rows.length; index++) {
          final row = rows[index];
          final location = '$tableName, Zeile ${index + 1}';
          if (row is! Map) {
            issues.add('$location: ungültiger Datensatz.');
            continue;
          }
          final title = '${row['beschreibung'] ?? ''}'.trim();
          final size = '${row['groesse'] ?? ''}'.trim();
          final price = '${row['preis'] ?? ''}'.trim();
          if (title.isEmpty && size.isEmpty && price.isEmpty) {
            ignored++;
            continue;
          }
          final number = int.tryParse('${row['artikelnummer'] ?? ''}'.trim());
          var usable = true;
          if (title.isEmpty) {
            issues.add('$location: Beschreibung fehlt.');
            usable = false;
          }
          if (number == null || number < 0 || number > 9999) {
            issues.add(
              '$location: Artikelnummer muss zwischen 0 und 9999 liegen.',
            );
            usable = false;
          } else if (!seen.add('$box:$number')) {
            issues.add(
              '$location, Artikel $number: doppelte Artikelnummer für Stammnummer $box.',
            );
            usable = false;
          }
          try {
            euroToCents(price);
          } on FormatException catch (error) {
            issues.add('$location: ${error.message}');
            usable = false;
          }
          if (usable) {
            valid++;
            assignments['$box'] = assignments['$box']! + 1;
          }
        }
      }
      if (valid == 0) issues.add('Keine übernehmbaren Artikel gefunden.');
    }
    MarketPackage? package;
    if (issues.isEmpty) {
      try {
        package = MarketPackage.fromLegacy(
          raw,
          name: name,
          registerNumber: registerNumber,
        );
      } on FormatException catch (error) {
        issues.add('Paketprüfung: ${error.message}');
      } on StateError catch (error) {
        issues.add('Paketprüfung: ${error.message}');
      }
    }
    final report = <String, Object?>{
      'format': 'marketmate-v1-inspection',
      'reportVersion': 1,
      'name': name.trim(),
      'registerNumber': registerNumber,
      'sourceSha256': digest,
      'sourceBytes': utf8.encode(raw).length,
      'importable': package != null && issues.isEmpty,
      'validRows': valid,
      'ignoredRows': ignored,
      'boxCount': boxes.length,
      'sellerCount': sellers,
      'boxes': (boxes.toList()..sort()),
      'articleAssignmentsByBox': Map<String, int>.unmodifiable(assignments),
      'issues': List<String>.unmodifiable(issues),
    };
    return LegacyInspection._(
      package: package,
      validRows: valid,
      ignoredRows: ignored,
      boxCount: boxes.length,
      sellerCount: sellers,
      sourceSha256: digest,
      issues: issues,
      report: report,
    );
  }
}
