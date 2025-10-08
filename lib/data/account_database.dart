import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'account.dart';
import 'transaction_record.dart';
import 'account_update.dart';

class AccountDatabase {
  AccountDatabase._();

  static final AccountDatabase instance = AccountDatabase._();
  static const String _dbName = 'accounts.db';
  static const int _dbVersion = 3;
  static const String accountsTable = 'accounts';
  static const String transactionsTable = 'transactions';
  static const String accountUpdatesTable = 'account_updates';

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
    print('Opening account database at $path');

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createAccountsTable(db);
        await _createTransactionsTable(db);
        await _createAccountUpdatesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createTransactionsTable(db);
        }
        if (oldVersion < 3) {
          await _createAccountUpdatesTable(db);
        }
      },
    );
  }

  Future<void> _createAccountsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $accountsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        currency TEXT NOT NULL DEFAULT 'EUR'
      )
    ''');
  }

  Future<void> _createTransactionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE $transactionsTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        account_id INTEGER NOT NULL,
        FOREIGN KEY(account_id) REFERENCES $accountsTable(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _createAccountUpdatesTable(Database db) async {
    await db.execute('''
      CREATE TABLE $accountUpdatesTable(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL,
        previous_balance REAL NOT NULL,
        new_balance REAL NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(account_id) REFERENCES $accountsTable(id) ON DELETE CASCADE
      )
    ''');
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
    const defaultCurrency = 'EUR';

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
    final existingRows = await db.query(
      accountsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    Account? previousAccount;
    if (existingRows.isNotEmpty) {
      previousAccount = Account.fromMap(existingRows.first);
    }
    await db.update(
      accountsTable,
      account.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (previousAccount != null &&
        previousAccount.balance != account.balance) {
      await db.insert(accountUpdatesTable, <String, Object?>{
        'account_id': id,
        'previous_balance': previousAccount.balance,
        'new_balance': account.balance,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
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

  Future<List<TransactionRecord>> fetchTransactions() async {
    final db = await database;
    final rows = await db.query(
      transactionsTable,
      orderBy: 'datetime(created_at) DESC, id DESC',
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<TransactionRecord> insertTransaction(TransactionRecord record) async {
    final db = await database;
    final data = Map<String, Object?>.from(record.toMap())
      ..remove('id'); // id auto-generates
    final newId = await db.insert(transactionsTable, data);
    return record.copyWith(id: newId);
  }

  Future<TransactionRecord> updateTransaction(TransactionRecord record) async {
    final db = await database;
    final id = record.id;
    if (id == null) {
      throw ArgumentError('Transaction id cannot be null when updating.');
    }
    await db.update(
      transactionsTable,
      record.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return record;
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete(
      transactionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<AccountUpdate>> fetchAccountUpdates() async {
    final db = await database;
    final rows = await db.query(
      accountUpdatesTable,
      orderBy: 'datetime(updated_at) ASC, id ASC',
    );
    return rows.map(AccountUpdate.fromMap).toList();
  }
}
