import 'package:fin/data/account.dart';
import 'package:fin/data/account_database.dart';
import 'package:fin/data/currency_rates_service.dart';
import 'package:fin/data/stats_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

class FakeCurrencyRatesService extends CurrencyRatesService {
  FakeCurrencyRatesService(this._rates);

  final Map<String, double> _rates;

  @override
  Future<Map<String, double>> fetchRates() async => _rates;

  @override
  void dispose() {
    // No network resources to release in the fake implementation.
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupTestDatabase();
  });

  setUp(() async {
    await resetDatabase();
  });

  test('StatsController builds history points from account updates', () async {
    final database = AccountDatabase.instance;
    Account account = await database.createDefaultAccount();

    account = account.copyWith(name: 'Brokerage', currency: 'USD');
    await database.updateAccount(account);

    account = account.copyWith(balance: 100);
    await database.updateAccount(account);

    account = account.copyWith(balance: 250);
    await database.updateAccount(account);

    final controller = StatsController(
      database,
      ratesService: FakeCurrencyRatesService(
        <String, double>{'EUR': 1.0, 'USD': 2.0},
      ),
    );

    await controller.load();

    expect(controller.isLoading, isFalse);
    expect(controller.points, hasLength(2));
    expect(controller.points.first.total, closeTo(50, 0.0001));
    expect(controller.points.last.total, closeTo(125, 0.0001));

    controller.dispose();
  });
}
