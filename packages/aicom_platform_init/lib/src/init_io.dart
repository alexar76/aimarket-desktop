/// Shared SQLite FFI init for desktop Flutter apps (skipped on web).
///
/// This was a Python triple-quoted docstring, which is not Dart syntax — the file
/// failed to compile with "Expected a declaration". Every desktop SKU depends on this
/// package, so none of them could be built until now; the web builds never noticed
/// because the conditional export keeps this file out of the web path.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initDatabaseFactory() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
