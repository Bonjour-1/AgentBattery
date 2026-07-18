import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/provider_view_state.dart';
import 'package:agent_battery_flutter/ui/theme/app_theme_tokens.dart';
import 'package:agent_battery_flutter/ui/widgets/provider_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ProviderCard card) => MaterialApp(
  theme: AppThemeTokens.forTheme(AppTheme.cute).materialTheme(),
  home: Scaffold(body: SizedBox(width: 700, child: card)),
);

ProviderViewState _provider({
  double? balance = 10,
  double dailyUsage = 0,
  double monthlyUsage = 0,
}) => ProviderViewState(
  id: 'test',
  name: 'Test Provider',
  balance: balance,
  dailyUsage: dailyUsage,
  monthlyUsage: monthlyUsage,
  status: ConnectionStatus.connected,
  message: '已连接',
);

void main() {
  testWidgets('shows recharge button only for a valid recharge URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ProviderCard(
          provider: _provider(),
          accent: Colors.teal,
          rechargeUrl: 'https://example.com/billing',
        ),
      ),
    );
    expect(find.text('前往充值'), findsOneWidget);

    await tester.pumpWidget(
      _host(ProviderCard(provider: _provider(), accent: Colors.teal)),
    );
    expect(find.text('前往充值'), findsNothing);
  });

  testWidgets('warns when the balance equals the configured threshold', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ProviderCard(
          provider: _provider(balance: 10),
          accent: Colors.teal,
          rechargeUrl: 'https://example.com/billing',
          lowBalanceThreshold: 10,
        ),
      ),
    );
    expect(find.text('余额偏低'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        ProviderCard(
          provider: _provider(balance: null),
          accent: Colors.teal,
          rechargeUrl: 'https://example.com/billing',
          lowBalanceThreshold: 10,
        ),
      ),
    );
    expect(find.text('余额偏低'), findsNothing);
  });

  testWidgets('exposes independent usage edit actions without changing recharge', (
    tester,
  ) async {
    var dailyEdits = 0;
    var monthlyEdits = 0;
    await tester.pumpWidget(
      _host(
        ProviderCard(
          provider: _provider(dailyUsage: 1.2, monthlyUsage: 3.4),
          accent: Colors.teal,
          rechargeUrl: 'https://example.com/billing',
          onEditDailyUsage: () => dailyEdits++,
          onEditMonthlyUsage: () => monthlyEdits++,
        ),
      ),
    );

    expect(find.byTooltip('修改今日用量'), findsOneWidget);
    expect(find.byTooltip('修改本月用量'), findsOneWidget);
    expect(find.text('前往充值'), findsOneWidget);
    expect(
      tester.getCenter(find.text('前往充值')).dx,
      lessThan(tester.getCenter(find.text('已连接')).dx),
    );

    await tester.tap(find.byTooltip('修改今日用量'));
    expect(dailyEdits, 1);
    expect(monthlyEdits, 0);
    await tester.tap(find.byTooltip('修改本月用量'));
    expect(dailyEdits, 1);
    expect(monthlyEdits, 1);
  });

  testWidgets('keeps usage edit actions available when balance is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ProviderCard(
          provider: _provider(balance: null),
          accent: Colors.teal,
          onEditDailyUsage: () {},
          onEditMonthlyUsage: () {},
        ),
      ),
    );

    expect(find.byTooltip('修改今日用量'), findsOneWidget);
    expect(find.byTooltip('修改本月用量'), findsOneWidget);
  });
}
