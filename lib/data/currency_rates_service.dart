import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Lightweight client to fetch EUR-based exchange rates.
class CurrencyRatesService {
  CurrencyRatesService({http.Client? client})
      : _client = client ?? http.Client();

  static final Uri _endpoint = Uri.parse(
    'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
  );

  final http.Client _client;
  Map<String, double>? _cachedRates;
  DateTime? _lastFetchTime;

  Future<Map<String, double>> fetchRates() async {
    final cached = _cachedRates;
    if (cached != null) {
      debugPrint(
        'CurrencyRatesService: returning cached rates from $_lastFetchTime.',
      );
      return cached;
    }

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
      final unmodifiable = Map<String, double>.unmodifiable(result);
      _cachedRates = unmodifiable;
      _lastFetchTime = DateTime.now();
      return unmodifiable;
    } on XmlParserException catch (error, stackTrace) {
      debugPrint(
        'CurrencyRatesService: XML parsing failed: $error\n$stackTrace',
      );
      throw const CurrencyRatesException('Exchange rates payload malformed.');
    }
  }

  void dispose() {
    _client.close();
  }

  void clearCache() {
    _cachedRates = null;
    _lastFetchTime = null;
  }
}

class CurrencyRatesException implements Exception {
  const CurrencyRatesException(this.message);

  final String message;

  @override
  String toString() => 'CurrencyRatesException: $message';
}
