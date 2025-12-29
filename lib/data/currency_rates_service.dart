import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'currency_rates_cache.dart';

/// Lightweight client to fetch EUR-based exchange rates.
class CurrencyRatesService {
  CurrencyRatesService({
    http.Client? client,
    Duration? cacheDuration,
    CurrencyRatesStore? store,
  })  : _client = client ?? http.Client(),
        _cacheDuration = cacheDuration ?? const Duration(hours: 24),
        _store = store ?? CurrencyRatesCacheDatabase.instance;

  static final Uri _endpoint = Uri.parse(
    'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
  );
  static const List<String> _cryptoSymbols = <String>[
    'BTC',
    'ETH',
    'SOL',
    'ARB',
    'XMR',
  ];
  static final Uri _cryptoEndpoint = Uri.parse(
    'https://raw.githubusercontent.com/semanticdreams/crypto-price-tracker/refs/heads/main/data/latest.json',
  );

  final http.Client _client;
  Map<String, double>? _cachedRates;
  DateTime? _lastFetchTime;
  final Duration _cacheDuration;
  final CurrencyRatesStore _store;
  bool _hasLoadedFromStorage = false;

  Future<Map<String, double>> fetchRates() async {
    await _primeFromStorage();

    final cached = _cachedRates;
    final lastFetch = _lastFetchTime;
    final DateTime now = DateTime.now();
    if (cached != null &&
        lastFetch != null &&
        now.difference(lastFetch) < _cacheDuration) {
      debugPrint(
        'CurrencyRatesService: returning cached rates from $_lastFetchTime.',
      );
      return cached;
    }

    final Map<String, double> combined = <String, double>{};

    try {
      final Map<String, double> baseRates = await _fetchEcbRates();
      combined.addAll(baseRates);

      try {
        final cryptoRates = await _fetchCryptoRates(baseRates);
        combined.addAll(cryptoRates);
      } catch (error, stackTrace) {
        debugPrint(
          'CurrencyRatesService: failed to fetch crypto rates: $error\n'
          '$stackTrace',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'CurrencyRatesService: failed to refresh exchange rates: $error\n'
        '$stackTrace',
      );
      if (cached != null) {
        debugPrint(
          'CurrencyRatesService: falling back to cached rates from $_lastFetchTime.',
        );
        return cached;
      }
      rethrow;
    }

    final DateTime fetchedAt = DateTime.now();
    final unmodifiable = Map<String, double>.unmodifiable(combined);
    _cachedRates = unmodifiable;
    _lastFetchTime = fetchedAt;
    try {
      await _store.saveRates(unmodifiable, fetchedAt);
    } catch (error, stackTrace) {
      debugPrint(
        'CurrencyRatesService: failed to persist exchange rates: $error\n'
        '$stackTrace',
      );
    }
    return unmodifiable;
  }

  Future<Map<String, double>?> loadStoredRates() async {
    await _primeFromStorage();
    return _cachedRates;
  }

  bool get isCacheStale {
    final lastFetch = _lastFetchTime;
    if (lastFetch == null) {
      return true;
    }
    return DateTime.now().difference(lastFetch) >= _cacheDuration;
  }

  Future<Map<String, double>> _fetchEcbRates() async {
    debugPrint('CurrencyRatesService: fetching ECB rates from $_endpoint');
    final response = await _client.get(_endpoint);
    if (response.statusCode != 200) {
      debugPrint(
        'CurrencyRatesService: non-200 status ${response.statusCode}, body: '
        '${response.body}',
      );
      throw CurrencyRatesException(
        'Failed to load exchange rates (status ${response.statusCode}).',
      );
    }

    try {
      final document = XmlDocument.parse(response.body);
      final cubes = document
          .findAllElements('Cube')
          .where((node) => node.getAttribute('currency') != null);

      if (cubes.isEmpty) {
        debugPrint(
          'CurrencyRatesService: no currency nodes found in ECB payload.',
        );
        throw const CurrencyRatesException('Exchange rates payload malformed.');
      }

      final result = <String, double>{'EUR': 1.0};
      for (final cube in cubes) {
        final currency = cube.getAttribute('currency');
        final rateString = cube.getAttribute('rate');
        if (currency == null || rateString == null) {
          continue;
        }
        final parsedRate = double.tryParse(rateString);
        if (parsedRate == null) {
          debugPrint(
            'CurrencyRatesService: could not parse rate "$rateString" for '
            '$currency',
          );
          continue;
        }
        result[currency.toUpperCase()] = parsedRate;
      }

      debugPrint(
        'CurrencyRatesService: received ${result.length} rates (including EUR); '
        'sample: ${result.keys.take(5).join(', ')}',
      );
      return Map<String, double>.unmodifiable(result);
    } on XmlParserException catch (error, stackTrace) {
      debugPrint(
        'CurrencyRatesService: XML parsing failed: $error\n$stackTrace',
      );
      throw const CurrencyRatesException('Exchange rates payload malformed.');
    }
  }

  Future<Map<String, double>> _fetchCryptoRates(
    Map<String, double> baseRates,
  ) async {
    final usdRate = baseRates['USD'];
    if (usdRate == null || usdRate == 0) {
      debugPrint(
        'CurrencyRatesService: cannot convert crypto prices from USD '
        'without USD base rate.',
      );
      return const <String, double>{};
    }

    final pricesUsd = await _fetchCryptoPricesUsd();
    if (pricesUsd.isEmpty) {
      return const <String, double>{};
    }

    final cryptoRates = <String, double>{};
    for (final symbol in _cryptoSymbols) {
      final priceUsd = pricesUsd[symbol];
      if (priceUsd == null || priceUsd <= 0) {
        debugPrint(
          'CurrencyRatesService: missing coingecko price for $symbol.',
        );
        continue;
      }
      final priceEur = priceUsd / usdRate;
      if (priceEur <= 0) {
        continue;
      }
      cryptoRates[symbol] = 1 / priceEur;
    }

    if (cryptoRates.isNotEmpty) {
      debugPrint(
        'CurrencyRatesService: added crypto rates for '
        '${cryptoRates.keys.join(', ')}.',
      );
    }
    return cryptoRates;
  }

  Future<Map<String, double>> _fetchCryptoPricesUsd() async {
    debugPrint('CurrencyRatesService: fetching crypto prices from $_cryptoEndpoint');
    http.Response response;
    try {
      response = await _client.get(_cryptoEndpoint);
    } on Exception catch (error) {
      debugPrint('CurrencyRatesService: crypto request failed: $error');
      return const <String, double>{};
    }
    if (response.statusCode != 200) {
      debugPrint(
        'CurrencyRatesService: crypto source responded with status '
        '${response.statusCode}.',
      );
      return const <String, double>{};
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CurrencyRatesException('Malformed crypto price payload.');
    }
    final quotes = decoded['quotes'];
    if (quotes is! List) {
      throw const CurrencyRatesException('Malformed crypto price payload.');
    }

    final prices = <String, double>{};
    for (final dynamic entry in quotes) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final source = entry['source'] as String?;
      final currency = entry['currency'] as String?;
      final symbol = entry['symbol'] as String?;
      final price = (entry['price'] as num?)?.toDouble();
      if (source == null ||
          currency == null ||
          symbol == null ||
          price == null) {
        continue;
      }
      if (source.toLowerCase() != 'coingecko') {
        continue;
      }
      if (currency.toUpperCase() != 'USD') {
        continue;
      }
      final upperSymbol = symbol.toUpperCase();
      if (!_cryptoSymbols.contains(upperSymbol)) {
        continue;
      }
      prices[upperSymbol] = price;
    }

    return prices;
  }

  void dispose() {
    _client.close();
  }

  void clearCache() {
    _cachedRates = null;
    _lastFetchTime = null;
    _hasLoadedFromStorage = false;
  }

  Future<void> _primeFromStorage() async {
    if (_hasLoadedFromStorage) {
      return;
    }
    _hasLoadedFromStorage = true;
    try {
      final CachedCurrencyRates? stored = await _store.loadRates();
      if (stored == null) {
        return;
      }
      _cachedRates = stored.rates;
      _lastFetchTime = stored.fetchedAt;
      debugPrint(
        'CurrencyRatesService: loaded stored rates fetched at ${stored.fetchedAt}.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'CurrencyRatesService: failed to load stored rates: $error\n'
        '$stackTrace',
      );
    }
  }
}

class CurrencyRatesException implements Exception {
  const CurrencyRatesException(this.message);

  final String message;

  @override
  String toString() => 'CurrencyRatesException: $message';
}
