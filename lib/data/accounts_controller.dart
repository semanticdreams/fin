import 'package:flutter/foundation.dart';

import 'account.dart';
import 'account_database.dart';

class AccountsController extends ChangeNotifier {
  AccountsController(this._database);

  final AccountDatabase _database;

  List<Account> _accounts = <Account>[];
  bool _isLoading = false;

  List<Account> get accounts => _accounts;
  bool get isLoading => _isLoading;

  Future<void> loadAccounts() async {
    _setLoading(true);
    try {
      final fetched = await _database.fetchAccounts();
      _accounts = fetched;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> createAccount() async {
    await _database.createDefaultAccount();
    await loadAccounts();
  }

  Future<void> updateAccount(Account account) async {
    await _database.updateAccount(account);
    await loadAccounts();
  }

  Future<void> deleteAccount(Account account) async {
    final id = account.id;
    if (id == null) {
      return;
    }
    await _database.deleteAccount(id);
    await loadAccounts();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    _isLoading = value;
    notifyListeners();
  }
}
