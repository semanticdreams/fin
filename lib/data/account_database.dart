import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'account.dart';

class AccountDatabase {
  AccountDatabase._();

  static final AccountDatabase instance = AccountDatabase._();
  static const String _dbName = 'accounts.db';
  static const int _dbVersion = 1;
  static const String accountsTable = 'accounts';

  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final db = await _openDatabase();
    _database = db;
    return db;
  }

  Future<Database> _openDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $accountsTable(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            balance REAL NOT NULL DEFAULT 0,
            currency TEXT NOT NULL DEFAULT 'USD'
          )
        ''');
      },
    );
  }

  Future<List<Account>> fetchAccounts() async {
    final db = await database;
    final rows = await db.query(
      accountsTable,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<Account> createDefaultAccount() async {
    const defaultName = 'New Account';
    const defaultBalance = 0.0;
    const defaultCurrency = 'USD';

    final db = await database;
    final newId = await db.insert(
      accountsTable,
      <String, Object?>{
        'name': defaultName,
        'balance': defaultBalance,
        'currency': defaultCurrency,
      },
    );
    return Account(
      id: newId,
      name: defaultName,
      balance: defaultBalance,
      currency: defaultCurrency,
    );
  }

  Future<Account> updateAccount(Account account) async {
    final db = await database;
    final id = account.id;
    if (id == null) {
      throw ArgumentError('Account id cannot be null when updating.');
    }
    await db.update(
      accountsTable,
      account.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return account;
  }

  Future<void> deleteAccount(int id) async {
    final db = await database;
    await db.delete(
      accountsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
