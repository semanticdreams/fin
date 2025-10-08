import 'package:fin/data/account_database.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _isDatabaseInitialized = false;

/// Configure the sqflite factory to use the ffi implementation for tests.
void setupTestDatabase() {
  if (_isDatabaseInitialized) {
    return;
  }
  sqfliteFfiInit();
  sqflite.databaseFactory = databaseFactoryFfi;
  _isDatabaseInitialized = true;
}

/// Delete all persisted data so each test can start from a clean slate.
Future<void> resetDatabase() async {
  final db = await AccountDatabase.instance.database;
  await db.delete(AccountDatabase.accountUpdatesTable);
  await db.delete(AccountDatabase.transactionsTable);
  await db.delete(AccountDatabase.accountsTable);
}
