import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonPathExtractor', () {
    test('reads object properties and list indexes', () {
      final value = JsonPathExtractor.extract({
        'data': {
          'balances': [
            {'available': '12.50'},
          ],
        },
      }, 'data.balances[0].available');

      expect(value, '12.50');
    });

    test('returns null for an invalid path', () {
      expect(JsonPathExtractor.extract({'data': []}, 'data[1].amount'), isNull);
      expect(JsonPathExtractor.extract({'data': 3}, 'data.amount'), isNull);
    });
  });
}
