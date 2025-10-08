import 'package:flutter/foundation.dart';

import 'account_database.dart';
import 'account_update.dart';

class AccountUpdatesController extends ChangeNotifier {
  AccountUpdatesController(this._database, this.accountId);

  final AccountDatabase _database;
  final int accountId;

  List<AccountUpdate> _updates = <AccountUpdate>[];
  bool _isLoading = false;

  List<AccountUpdate> get updates => _updates;
  bool get isLoading => _isLoading;

  Future<void> loadUpdates() async {
    _setLoading(true);
    try {
      final fetched = await _database.fetchAccountUpdatesForAccount(accountId);
      _updates = fetched;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> addUpdate(AccountUpdate update) async {
    await _database.insertAccountUpdate(update);
    await loadUpdates();
  }

  Future<void> updateUpdate(AccountUpdate update) async {
    await _database.updateAccountUpdate(update);
    await loadUpdates();
  }

  Future<void> deleteUpdate(AccountUpdate update) async {
    final id = update.id;
    if (id == null) {
      return;
    }
    await _database.deleteAccountUpdate(id);
    await loadUpdates();
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    _isLoading = value;
    notifyListeners();
  }
}
