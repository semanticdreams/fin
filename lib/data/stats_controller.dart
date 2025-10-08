import 'package:flutter/foundation.dart';

import 'account.dart';
import 'account_database.dart';
import 'account_update.dart';
import 'currency_rates_service.dart';

class StatsController extends ChangeNotifier {
  StatsController(
    this._database, {
    CurrencyRatesService? ratesService,
  }) : _ratesService = ratesService ?? CurrencyRatesService();

  final AccountDatabase _database;
  final CurrencyRatesService _ratesService;

  bool _isLoading = false;
  List<StatsPoint> _points = <StatsPoint>[];

  bool get isLoading => _isLoading;
  List<StatsPoint> get points => _points;

  Future<void> load() async {
    if (_isLoading) {
      return;
    }
    _setLoading(true);
    try {
      final accounts = await _database.fetchAccounts();
      final updates = await _database.fetchAccountUpdates();
      final rates = await _ratesService.fetchRates();
      _points = _buildPoints(accounts, updates, rates);
    } finally {
      _setLoading(false);
    }
  }

  List<StatsPoint> _buildPoints(
    List<Account> accounts,
    List<AccountUpdate> updates,
    Map<String, double> rates,
  ) {
    final points = <StatsPoint>[];
    final sortedUpdates = updates.toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));

    final accountCurrencies = <int, String>{};
    final currentBalancesEur = <int, double>{};
    for (final account in accounts) {
      final id = account.id;
      if (id == null) {
        continue;
      }
      final currency = account.currency.toUpperCase();
      accountCurrencies[id] = currency;
      final converted = _convertToEur(account.balance, currency, rates);
      if (converted != null) {
        currentBalancesEur[id] = converted;
      }
    }

    final trackedBalancesEur = <int, double>{};

    for (final AccountUpdate update in sortedUpdates) {
      final currency =
          accountCurrencies[update.accountId] ?? 'EUR';
      final previousEur =
          _convertToEur(update.previousBalance, currency, rates);
      final newEur = _convertToEur(update.newBalance, currency, rates);
      if (previousEur == null || newEur == null) {
        continue;
      }
      trackedBalancesEur.putIfAbsent(update.accountId, () => previousEur);
      trackedBalancesEur[update.accountId] = newEur;
      final total =
          _computeTotal(trackedBalancesEur, currentBalancesEur);
      points.add(StatsPoint(update.updatedAt, total));
    }

    final currentTotal =
        currentBalancesEur.values.fold<double>(0, (sum, value) => sum + value);

    if (points.isEmpty) {
      if (currentBalancesEur.isNotEmpty) {
        points.add(StatsPoint(DateTime.now(), currentTotal));
      }
      return points;
    }

    final lastPoint = points.last;
    const epsilon = 0.0001;
    final now = DateTime.now();
    if ((lastPoint.total - currentTotal).abs() > epsilon ||
        now.difference(lastPoint.time).abs() > const Duration(minutes: 1)) {
      points.add(StatsPoint(now, currentTotal));
    }

    return points;
  }

  double _computeTotal(
    Map<int, double> trackedBalancesEur,
    Map<int, double> currentBalancesEur,
  ) {
    double total = 0;
    final seen = <int>{};
    trackedBalancesEur.forEach((id, value) {
      total += value;
      seen.add(id);
    });
    currentBalancesEur.forEach((id, value) {
      if (!seen.contains(id)) {
        total += value;
      }
    });
    return total;
  }

  double? _convertToEur(
    double amount,
    String currency,
    Map<String, double> rates,
  ) {
    final upper = currency.toUpperCase();
    if (upper == 'EUR') {
      return amount;
    }
    final rate = rates[upper];
    if (rate == null || rate == 0) {
      debugPrint(
        'StatsController: missing rate for $upper, skipping conversion.',
      );
      return null;
    }
    return amount / rate;
  }

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _ratesService.dispose();
    super.dispose();
  }
}

class StatsPoint {
  const StatsPoint(this.time, this.total);

  final DateTime time;
  final double total;
}
