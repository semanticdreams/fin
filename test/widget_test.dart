import 'package:fin/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('suggestPrecision', () {
    test('returns eight decimals for BTC', () {
      expect(suggestPrecision('btc'), 8);
      expect(suggestPrecision('BTC'), 8);
    });

    test('returns six decimals for ETH', () {
      expect(suggestPrecision('eth'), 6);
    });

    test('defaults to two decimals for other currencies', () {
      expect(suggestPrecision('usd'), 2);
      expect(suggestPrecision('JPY'), 2);
    });
  });
}
