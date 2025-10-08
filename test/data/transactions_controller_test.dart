import 'package:fin/data/account.dart';
import 'package:fin/data/account_database.dart';
import 'package:fin/data/transaction_record.dart';
import 'package:fin/data/transactions_controller.dart';
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

  test('TransactionsController manages lifecycle of transactions', () async {
    final database = AccountDatabase.instance;
    Account account = await database.createDefaultAccount();
    account = account.copyWith(name: 'Daily Spending');
    await database.updateAccount(account);

    final controller = TransactionsController(database);
    await controller.load();

    expect(controller.transactions, isEmpty);
    expect(controller.accountsById[account.id!]?.name, 'Daily Spending');

    final olderTransaction = TransactionRecord(
      title: 'Coffee',
      amount: 4.5,
      currency: 'EUR',
      createdAt: DateTime(2024, 1, 15),
      accountId: account.id!,
    );
    final recentTransaction = TransactionRecord(
      title: 'Salary',
      amount: 1500,
      currency: 'EUR',
      createdAt: DateTime(2024, 6, 1),
      accountId: account.id!,
    );

    await controller.addTransaction(olderTransaction);
    expect(controller.transactions, hasLength(1));
    expect(controller.transactions.first.title, 'Coffee');

    await controller.addTransaction(recentTransaction);
    expect(controller.transactions, hasLength(2));
    expect(controller.transactions.first.title, 'Salary');
    expect(controller.mostRecentTransaction?.title, 'Salary');

    final coffeeRecord = controller.transactions
        .firstWhere((transaction) => transaction.title == 'Coffee');
    await controller.updateTransaction(
      coffeeRecord.copyWith(title: 'Latte', amount: 5.25),
    );
    expect(
      controller.transactions.map((transaction) => transaction.title),
      containsAll(<String>['Salary', 'Latte']),
    );

    final latteRecord = controller.transactions
        .firstWhere((transaction) => transaction.title == 'Latte');
    await controller.deleteTransaction(latteRecord);
    expect(controller.transactions, hasLength(1));
    expect(controller.transactions.first.title, 'Salary');

    controller.dispose();
  });
}
