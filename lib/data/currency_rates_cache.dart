import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Cached snapshot of currency exchange rates.
class CachedCurrencyRates {
  const CachedCurrencyRates({required this.rates, required this.fetchedAt});

  final Map<String, double> rates;
  final DateTime fetchedAt;
}

/// Persistence contract for storing exchange rates.
abstract class CurrencyRatesStore {
  Future<CachedCurrencyRates?> loadRates();
  Future<void> saveRates(
    Map<String, double> rates,
    DateTime fetchedAt,
  );

  Future<void> clear();
}

class CurrencyRatesCacheDatabase implements CurrencyRatesStore {
  CurrencyRatesCacheDatabase._();

  static final CurrencyRatesCacheDatabase instance =
      CurrencyRatesCacheDatabase._();

  static const String _dbName = 'currency_rates.db';
  static const int _dbVersion = 1;
  static const String _tableName = 'rates';

  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final path = join(await getDatabasesPath(), _dbName);
    final database = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName(
            currency TEXT PRIMARY KEY,
            rate REAL NOT NULL,
            fetched_at TEXT NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  @override
  Future<CachedCurrencyRates?> loadRates() async {
    final db = await _db;
    final rows = await db.query(_tableName);
    if (rows.isEmpty) {
      return null;
    }
    final rates = <String, double>{};
    DateTime? fetchedAt;
    for (final row in rows) {
      final currency = row['currency'] as String?;
      final rate = row['rate'] as num?;
      final fetched = row['fetched_at'] as String?;
      if (currency == null || rate == null) {
        continue;
      }
      rates[currency.toUpperCase()] = rate.toDouble();
      if (fetchedAt == null && fetched != null) {
        fetchedAt = DateTime.tryParse(fetched);
      }
    }
    if (rates.isEmpty || fetchedAt == null) {
      return null;
    }
    return CachedCurrencyRates(
      rates: Map<String, double>.unmodifiable(rates),
      fetchedAt: fetchedAt!,
    );
  }

  @override
  Future<void> saveRates(
    Map<String, double> rates,
    DateTime fetchedAt,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(_tableName);
      final String fetchedIso = fetchedAt.toIso8601String();
      for (final MapEntry<String, double> entry in rates.entries) {
        await txn.insert(
          _tableName,
          <String, Object?>{
            'currency': entry.key.toUpperCase(),
            'rate': entry.value,
            'fetched_at': fetchedIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> clear() async {
    final existing = _database;
    if (existing != null) {
      await existing.delete(_tableName);
      return;
    }
    final db = await _db;
    await db.delete(_tableName);
  }
}
