import 'package:agent_battery_flutter/models/provider_view_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('display values can be cleared without changing raw usage', () {
    const state = ProviderViewState(
      id: 'provider',
      name: 'Provider',
      dailyUsage: 4.25,
      dailyDisplayUsage: 4.25,
      monthlyUsage: 11.75,
      monthlyDisplayUsage: 11.75,
    );

    final hidden = state.copyWith(
      clearDailyDisplayUsage: true,
      clearMonthlyDisplayUsage: true,
    );

    expect(hidden.dailyUsage, 4.25);
    expect(hidden.monthlyUsage, 11.75);
    expect(hidden.dailyDisplayUsage, isNull);
    expect(hidden.monthlyDisplayUsage, isNull);
  });
}
