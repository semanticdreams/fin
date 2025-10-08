import 'package:fin/data/account.dart';
import 'package:fin/data/account_database.dart';
import 'package:fin/data/accounts_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupTestDatabase();
  });

  setUp(() async {
    await resetDatabase();
  });

  test('AccountsController loads, creates, updates, and deletes accounts',
      () async {
    final controller = AccountsController(AccountDatabase.instance);

    await controller.loadAccounts();
    expect(controller.accounts, isEmpty);
    expect(controller.isLoading, isFalse);

    await controller.createAccount();
    expect(controller.accounts, hasLength(1));

    final created = controller.accounts.first;
    expect(created.name, 'New Account');
    expect(created.currency, 'EUR');

    final updated = created.copyWith(
      name: 'Checking',
      balance: 125.75,
      currency: 'USD',
    );
    await controller.updateAccount(updated);
    expect(controller.accounts, hasLength(1));

    final persisted = controller.accounts.first;
    expect(persisted.name, 'Checking');
    expect(persisted.currency, 'USD');
    expect(persisted.balance, closeTo(125.75, 0.0001));

    await controller.deleteAccount(persisted);
    expect(controller.accounts, isEmpty);

    controller.dispose();
  });
}
