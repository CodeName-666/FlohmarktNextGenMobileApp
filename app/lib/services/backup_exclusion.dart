import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the register databases out of iOS iCloud and device backups (KAN-592).
/// Android already disables app backups in the manifest.
class BackupExclusion {
  static const channel = MethodChannel('marketmate/storage');

  /// Marks [directory] and everything in it as excluded; a no-op off iOS.
  static Future<void> excludeDirectory(String directory, {bool? isIOS}) async {
    if (!(isIOS ?? Platform.isIOS)) return;
    await Directory(directory).create(recursive: true);
    await channel.invokeMethod<bool>('excludeFromBackup', directory);
  }
}
