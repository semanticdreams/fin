import 'package:flutter/foundation.dart';

import 'account.dart';
import 'account_database.dart';
import 'transaction_record.dart';

class TransactionsController extends ChangeNotifier {
  TransactionsController(this._database);

  final AccountDatabase _database;

  List<TransactionRecord> _transactions = <TransactionRecord>[];
  Map<int, Account> _accountsById = <int, Account>{};
  bool _isLoading = false;

  List<TransactionRecord> get transactions => _transactions;
  Map<int, Account> get accountsById => _accountsById;
  List<Account> get accounts =>
      _accountsById.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  bool get isLoading => _isLoading;
  TransactionRecord? get mostRecentTransaction =>
      _transactions.isEmpty ? null : _transactions.first;

  Future<void> load() async {
    _setLoading(true);
    try {
      final accounts = await _database.fetchAccounts();
      accounts.removeWhere((account) => account.id == null);
      final transactions = await _database.fetchTransactions();
      _accountsById = {
        for (final account in accounts)
          if (account.id != null) account.id!: account
      };
      _transactions = transactions;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addTransaction(TransactionRecord record) async {
    await _database.insertTransaction(record);
    await load();
  }

  Future<void> updateTransaction(TransactionRecord record) async {
    await _database.updateTransaction(record);
    await load();
  }

  Future<void> deleteTransaction(TransactionRecord record) async {
    final id = record.id;
    if (id == null) {
      return;
    }
    await _database.deleteTransaction(id);
    await load();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    _isLoading = value;
    notifyListeners();
  }
}
