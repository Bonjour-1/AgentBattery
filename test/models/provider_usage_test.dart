import 'package:agent_battery_flutter/models/provider_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful server metrics override cached and estimated usage', () {
    const cached = ProviderUsage(
      date: '2026-02-15',
      month: '2026-02',
      lastBalance: 100,
      dailyUsage: 20,
      monthlyUsage: 50,
    );

    final usage = cached.recordMetrics(
      80,
      DateTime(2026, 2, 15),
      dailyUsage: 4.25,
      monthlyUsage: 11.75,
    );

    expect(usage.dailyUsage, 4.25);
    expect(usage.monthlyUsage, 11.75);
  });

  test('estimation can be enabled independently for daily and monthly', () {
    const cached = ProviderUsage(
      date: '2026-02-15',
      month: '2026-02',
      lastBalance: 100,
      dailyUsage: 4,
      monthlyUsage: 10,
    );

    final usage = cached.recordMetrics(
      80,
      DateTime(2026, 2, 15),
      estimateDailyFromBalance: true,
      estimateMonthlyFromBalance: false,
    );

    expect(usage.dailyUsage, 24);
    expect(usage.monthlyUsage, 10);
  });
}
