import 'package:agent_battery_flutter/services/web_billing_expression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sums nested bucket values and divides correctly', () {
    final value = WebBillingExpression.evaluate(
      'sum(data.biz_data.data[*].series[*].buckets[*].data) / 1000000',
      {
        'data': {
          'biz_data': {
            'data': [
              {
                'series': [
                  {
                    'buckets': [
                      {'data': '2500000'},
                      {'data': 500000},
                    ],
                  },
                ],
              },
            ],
          },
        },
      },
    );

    expect(value, 3);
  });

  test('arithmetic parentheses and numeric system variables work', () {
    expect(
      WebBillingExpression.evaluate('(sum(data.items[*].cost) + 5) / 100', {
        'data': {
          'items': [
            {'cost': 10},
            {'cost': '15'},
          ],
        },
      }),
      .3,
    );
    expect(
      WebBillingExpression.evaluate(
        'CURRENT_YEAR - 2000',
        const {},
        systemVariables: const {'CURRENT_YEAR': 2026},
      ),
      26,
    );
  });

  test('invalid expressions fail with a fixed safe error', () {
    for (final expression in [
      'bad(data.value)',
      'data.value / 0',
      'sum(data)',
    ]) {
      expect(
        () => WebBillingExpression.evaluate(expression, {'data': 'private'}),
        throwsA(
          isA<WebBillingExpressionException>().having(
            (error) => error.toString(),
            'does not expose response or expression',
            isNot(contains('private')),
          ),
        ),
      );
    }
  });
}
