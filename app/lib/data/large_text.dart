import 'package:sqflite/sqflite.dart';

/// Android's CursorWindow rejects a row larger than about 2 MB, so large TEXT
/// cells (original market packages) are read in slices. Returns null when no
/// row matches or the cell is NULL.
Future<String?> readLargeText(
  DatabaseExecutor db,
  String table,
  String column,
  String where,
  List<Object?> args,
) async {
  final rows = await db.rawQuery(
    'SELECT length($column) AS n FROM $table WHERE $where',
    args,
  );
  if (rows.isEmpty) return null;
  final length = rows.single['n'] as int?;
  if (length == null) return null;
  // Characters, not bytes: 256 Ki characters stay below 1 MiB in UTF-8.
  const slice = 256 * 1024;
  final text = StringBuffer();
  for (var start = 1; start <= length; start += slice) {
    final part = await db.rawQuery(
      'SELECT substr($column, ?, ?) AS s FROM $table WHERE $where',
      [start, slice, ...args],
    );
    text.write(part.single['s']);
  }
  return text.toString();
}
