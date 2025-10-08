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
  static const List<String> _cryptoSymbols = <String>['BTC', 'ETH'];
  static const Map<String, String> _yahooHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0 Safari/537.36',
    'Accept': 'application/json',
  };
  static final Uri _yahooCookieEndpoint = Uri.parse('https://fc.yahoo.com');

  final http.Client _client;
  Map<String, double>? _cachedRates;
  DateTime? _lastFetchTime;
  final Duration _cacheDuration;
  final CurrencyRatesStore _store;
  bool _hasLoadedFromStorage = false;
  String? _yahooCookie;
  DateTime? _yahooCookieFetchedAt;

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
    final symbolsEur =
        _cryptoSymbols.map((symbol) => '$symbol-EUR').toList(growable: false);
    final quotesEur = await _fetchYahooQuotes(symbolsEur);
    final missing = <String>[];
    final cryptoRates = <String, double>{};

    for (final symbol in _cryptoSymbols) {
      final price = quotesEur['$symbol-EUR'];
      if (price == null || price <= 0) {
        missing.add(symbol);
        continue;
      }
      final perEur = 1 / price;
      cryptoRates[symbol] = perEur;
    }

    if (missing.isNotEmpty) {
      final usdRate = baseRates['USD'];
      if (usdRate == null || usdRate == 0) {
        debugPrint(
          'CurrencyRatesService: cannot convert crypto prices from USD '
          'without USD base rate.',
        );
      } else {
        final usdSymbols =
            missing.map((symbol) => '$symbol-USD').toList(growable: false);
        final quotesUsd = await _fetchYahooQuotes(usdSymbols);
        for (final symbol in missing) {
          final priceUsd = quotesUsd['$symbol-USD'];
          if (priceUsd == null || priceUsd <= 0) {
            debugPrint(
              'CurrencyRatesService: missing Yahoo Finance price for $symbol.',
            );
            continue;
          }
          final priceEur = priceUsd / usdRate;
          if (priceEur <= 0) {
            continue;
          }
          cryptoRates[symbol] = 1 / priceEur;
        }
      }
    }

    if (cryptoRates.isNotEmpty) {
      debugPrint(
        'CurrencyRatesService: added crypto rates for '
        '${cryptoRates.keys.join(', ')}.',
      );
    }
    return cryptoRates;
  }

  Future<Map<String, double>> _fetchYahooQuotes(
    List<String> symbols, {
    bool allowRetry = true,
  }) async {
    if (symbols.isEmpty) {
      return const <String, double>{};
    }
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v7/finance/quote',
      <String, String>{'symbols': symbols.join(',')},
    );
    debugPrint('CurrencyRatesService: fetching Yahoo quotes for $symbols');
    http.Response response;
    try {
      final headers = Map<String, String>.from(_yahooHeaders)
        ..addAll(await _getYahooCookieHeader());
      response = await _client.get(uri, headers: headers);
    } on Exception catch (error) {
      debugPrint('CurrencyRatesService: Yahoo request failed: $error');
      return const <String, double>{};
    }
    if (response.statusCode != 200) {
      debugPrint(
        'CurrencyRatesService: Yahoo Finance responded with status '
        '${response.statusCode}; skipping crypto rates.',
      );
      if (response.statusCode == 401) {
        debugPrint(
          'Hint: Yahoo sometimes requires cookies. Clearing cached cookie '
          'and retrying once.',
        );
        _yahooCookie = null;
        _yahooCookieFetchedAt = null;
        if (response.body.isNotEmpty) {
          final preview = response.body.length > 512
              ? '${response.body.substring(0, 512)}…'
              : response.body;
          debugPrint('Yahoo 401 body preview: $preview');
        }
        final authHeader = response.headers['www-authenticate'];
        if (authHeader != null) {
          debugPrint('Yahoo 401 authenticate header: $authHeader');
        }
        if (allowRetry) {
          return _fetchYahooQuotes(symbols, allowRetry: false);
        }
      } else if (response.body.isNotEmpty) {
        final preview = response.body.length > 512
            ? '${response.body.substring(0, 512)}…'
            : response.body;
        debugPrint('Yahoo response body preview: $preview');
      }
      return const <String, double>{};
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final quoteResponse = decoded['quoteResponse'];
    if (quoteResponse is! Map<String, dynamic>) {
      throw const CurrencyRatesException('Malformed Yahoo Finance payload.');
    }
    final results = quoteResponse['result'];
    if (results is! List) {
      throw const CurrencyRatesException('Malformed Yahoo Finance payload.');
    }
    final map = <String, double>{};
    for (final dynamic entry in results) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final symbol = entry['symbol'] as String?;
      final price = (entry['regularMarketPrice'] as num?)?.toDouble();
      if (symbol == null || price == null) {
        continue;
      }
      map[symbol.toUpperCase()] = price;
    }
    return map;
  }

  Future<Map<String, String>> _getYahooCookieHeader() async {
    final now = DateTime.now();
    if (_yahooCookie != null) {
      final fetched = _yahooCookieFetchedAt;
      if (fetched != null && now.difference(fetched) < const Duration(hours: 6)) {
        return <String, String>{'Cookie': _yahooCookie!};
      }
    }
    try {
      final response = await _client.get(_yahooCookieEndpoint, headers: _yahooHeaders);
      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        final cookie = setCookie.split(';').first.trim();
        if (cookie.isNotEmpty) {
          _yahooCookie = cookie;
          _yahooCookieFetchedAt = now;
          return <String, String>{'Cookie': cookie};
        }
      }
    } catch (error) {
      debugPrint('CurrencyRatesService: failed to acquire Yahoo cookie: $error');
    }
    return const <String, String>{};
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
