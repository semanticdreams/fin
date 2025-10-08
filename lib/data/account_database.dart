import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'account.dart';
import 'account_update.dart';
import 'currency_rates_service.dart';
import 'transaction_record.dart';

class AccountDatabase {
  AccountDatabase._();

  static final AccountDatabase instance = AccountDatabase._();
  static const String _dbName = 'accounts.db';
  static const int _dbVersion = 3;
  static const String accountsTable = 'accounts';
  static const String transactionsTable = 'transactions';
  static const String accountUpdatesTable = 'account_updates';
  static const double _epsilon = 0.0001;

  final CurrencyRatesService _ratesService = CurrencyRatesService();
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
    final accountId = record.accountId;
    final account = await _fetchAccount(db, accountId);
    final rates = await _ratesService.fetchRates();
    final converted = _convertAmountOrNull(
      record.amount,
      record.currency,
      account.currency,
      rates,
    );
    if (converted == null) {
      debugPrint(
        'AccountDatabase: unable to convert ${record.currency} -> '
        '${account.currency}; skipping account update.',
      );
    } else {
      final newBalance = account.balance + converted;
      await _updateAccountBalance(db, account, newBalance);
    }

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
    final existingRows = await db.query(
      transactionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (existingRows.isEmpty) {
      throw ArgumentError('Transaction with id $id does not exist.');
    }
    final existing = TransactionRecord.fromMap(existingRows.first);
    final rates = await _ratesService.fetchRates();

    if (existing.accountId == record.accountId) {
      final account = await _fetchAccount(db, record.accountId);
      final oldConverted = _convertAmountOrNull(
        existing.amount,
        existing.currency,
        account.currency,
        rates,
      );
      final newConverted = _convertAmountOrNull(
        record.amount,
        record.currency,
        account.currency,
        rates,
      );
      if (oldConverted == null || newConverted == null) {
        debugPrint(
          'AccountDatabase: missing rate for transaction update on account '
          '${account.id}; skipping balance adjustment.',
        );
      } else {
        final delta = newConverted - oldConverted;
        if (delta.abs() > _epsilon) {
          final newBalance = account.balance + delta;
          await _updateAccountBalance(db, account, newBalance);
        }
      }
    } else {
      final oldAccount = await _fetchAccount(db, existing.accountId);
      final oldConverted = _convertAmountOrNull(
        existing.amount,
        existing.currency,
        oldAccount.currency,
        rates,
      );
      if (oldConverted != null) {
        final oldNewBalance = oldAccount.balance - oldConverted;
        await _updateAccountBalance(db, oldAccount, oldNewBalance);
      } else {
        debugPrint(
          'AccountDatabase: missing rate when reverting old transaction '
          'from account ${oldAccount.id}.',
        );
      }

      final newAccount = await _fetchAccount(db, record.accountId);
      final newConverted = _convertAmountOrNull(
        record.amount,
        record.currency,
        newAccount.currency,
        rates,
      );
      if (newConverted != null) {
        final newBalance = newAccount.balance + newConverted;
        await _updateAccountBalance(db, newAccount, newBalance);
      } else {
        debugPrint(
          'AccountDatabase: missing rate when applying transaction to account '
          '${newAccount.id}.',
        );
      }
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
    final existingRows = await db.query(
      transactionsTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (existingRows.isNotEmpty) {
      final existing = TransactionRecord.fromMap(existingRows.first);
      final rates = await _ratesService.fetchRates();
      final account = await _fetchAccount(db, existing.accountId);
      final converted = _convertAmountOrNull(
        existing.amount,
        existing.currency,
        account.currency,
        rates,
      );
      if (converted != null) {
        final newBalance = account.balance - converted;
        await _updateAccountBalance(db, account, newBalance);
      } else {
        debugPrint(
          'AccountDatabase: missing rate when deleting transaction from '
          'account ${account.id}.',
        );
      }
    }
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

  Future<List<AccountUpdate>> fetchAccountUpdatesForAccount(
    int accountId,
  ) async {
    final db = await database;
    final rows = await db.query(
      accountUpdatesTable,
      where: 'account_id = ?',
      whereArgs: <Object?>[accountId],
      orderBy: 'datetime(updated_at) DESC, id DESC',
    );
    return rows.map(AccountUpdate.fromMap).toList();
  }

  Future<AccountUpdate> insertAccountUpdate(AccountUpdate update) async {
    final db = await database;
    final data = Map<String, Object?>.from(update.toMap())
      ..remove('id');
    final newId = await db.insert(accountUpdatesTable, data);
    return update.copyWith(id: newId);
  }

  Future<AccountUpdate> updateAccountUpdate(AccountUpdate update) async {
    final id = update.id;
    if (id == null) {
      throw ArgumentError('Account update id cannot be null when updating.');
    }
    final db = await database;
    await db.update(
      accountUpdatesTable,
      update.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return update;
  }

  Future<void> deleteAccountUpdate(int id) async {
    final db = await database;
    await db.delete(
      accountUpdatesTable,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<Account> _fetchAccount(Database db, int accountId) async {
    final rows = await db.query(
      accountsTable,
      where: 'id = ?',
      whereArgs: <Object?>[accountId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError('Account with id $accountId does not exist.');
    }
    return Account.fromMap(rows.first);
  }

  Future<void> _updateAccountBalance(
    Database db,
    Account account,
    double newBalance,
  ) async {
    if ((account.balance - newBalance).abs() <= _epsilon) {
      return;
    }
    final updatedAccount = account.copyWith(balance: newBalance);
    await db.update(
      accountsTable,
      updatedAccount.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[account.id],
    );
    await db.insert(accountUpdatesTable, <String, Object?>{
      'account_id': account.id,
      'previous_balance': account.balance,
      'new_balance': newBalance,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  double? _convertAmountOrNull(
    double amount,
    String fromCurrency,
    String toCurrency,
    Map<String, double> rates,
  ) {
    final from = fromCurrency.toUpperCase();
    final to = toCurrency.toUpperCase();
    if (from == to) {
      return amount;
    }

    double amountInEur;
    if (from == 'EUR') {
      amountInEur = amount;
    } else {
      final fromRate = rates[from];
      if (fromRate == null || fromRate == 0) {
        return null;
      }
      amountInEur = amount / fromRate;
    }

    if (to == 'EUR') {
      return amountInEur;
    }
    final toRate = rates[to];
    if (toRate == null || toRate == 0) {
      return null;
    }
    return amountInEur * toRate;
  }
}
