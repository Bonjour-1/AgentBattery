import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderUsage.recordBalance', () {
    test('adds only a balance decrease', () {
      const previous = ProviderUsage(
        date: '2026-07-11',
        month: '2026-07',
        lastBalance: 10,
        dailyUsage: 1.25,
        monthlyUsage: 4,
      );
      final result = previous.recordBalance(8.75, DateTime(2026, 7, 11));
      expect(result.dailyUsage, 2.5);
      expect(result.monthlyUsage, 5.25);
      expect(result.lastBalance, 8.75);

      final toppedUp = result.recordBalance(20, DateTime(2026, 7, 11));
      expect(toppedUp.dailyUsage, 2.5);
      expect(toppedUp.monthlyUsage, 5.25);
    });

    test('resets daily usage on a new date before accumulating', () {
      const previous = ProviderUsage(
        date: '2026-07-10',
        month: '2026-07',
        lastBalance: 10,
        dailyUsage: 6,
        monthlyUsage: 9,
      );
      final result = previous.recordBalance(9, DateTime(2026, 7, 11));
      expect(result.dailyUsage, 1);
      expect(result.monthlyUsage, 10);
    });

    test('resets both counters on a new month', () {
      const previous = ProviderUsage(
        date: '2026-06-30',
        month: '2026-06',
        lastBalance: 10,
        dailyUsage: 6,
        monthlyUsage: 9,
      );
      final result = previous.recordBalance(9.5, DateTime(2026, 7, 1));
      expect(result.dailyUsage, 0.5);
      expect(result.monthlyUsage, 0.5);
    });

    test('first observation establishes a baseline without usage', () {
      const previous = ProviderUsage();
      final result = previous.recordBalance(7.2, DateTime(2026, 7, 11));
      expect(result.dailyUsage, 0);
      expect(result.monthlyUsage, 0);
      expect(result.lastBalance, 7.2);
    });
  });

  group('ProviderUsage manual usage overrides', () {
    const original = ProviderUsage(
      date: '2026-07-11',
      month: '2026-07',
      lastBalance: 12.34,
      dailyUsage: 1.25,
      monthlyUsage: 4.56,
    );

    test(
      'overrides daily usage to two decimals without changing other state',
      () {
        final result = original.withDailyUsage(6.789);

        expect(result.dailyUsage, 6.79);
        expect(result.monthlyUsage, 4.56);
        expect(result.date, '2026-07-11');
        expect(result.month, '2026-07');
        expect(result.lastBalance, 12.34);
      },
    );

    test('overrides monthly usage without changing daily usage', () {
      final result = original.withMonthlyUsage(9.876);

      expect(result.dailyUsage, 1.25);
      expect(result.monthlyUsage, 9.88);
      expect(result.date, '2026-07-11');
      expect(result.month, '2026-07');
      expect(result.lastBalance, 12.34);
    });

    test('rejects negative and non-finite manual amounts', () {
      expect(() => original.withDailyUsage(-0.01), throwsArgumentError);
      expect(() => original.withDailyUsage(double.nan), throwsArgumentError);
      expect(
        () => original.withMonthlyUsage(double.infinity),
        throwsArgumentError,
      );
    });
  });
}
