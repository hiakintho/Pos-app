import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _configured = false;

Future<void> configureDatabaseFactory() async {
  if (_configured) return;

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  _configured = true;
}
