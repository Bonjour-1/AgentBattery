import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/models/provider_view_state.dart';
import 'package:agent_battery_flutter/ui/theme/app_theme_tokens.dart';
import 'package:agent_battery_flutter/ui/widgets/provider_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(ProviderCard card) => MaterialApp(
  theme: AppThemeTokens.forTheme(AppTheme.cute).materialTheme(),
  home: Scaffold(body: SizedBox(width: 700, child: card)),
);
const _splitPalette = ThemePalette(
  primary: 0xff102030,
  secondary: 0xff203040,
  stage: 0xff304050,
  content: 0xff405060,
  pageBackground: 0xff506070,
  card: 0xff607080,
  dialogBackground: 0xff708090,
  cardAlt: 0xff8090a0,
  text: 0xff101112,
  mutedText: 0xff505152,
  onStage: 0xffffffff,
  outline: 0xffa0a1a2,
  success: 0xff208060,
  error: 0xffb03040,
  statusIdle: 0xff707172,
  shadow: 0xff000000,
);

final _splitTokens = AppThemeTokens.custom(
  CustomTheme(
    id: 'f1b2c3d4-e5f6-4789-8123-456789abcdef',
    name: 'Split surfaces',
    layout: ThemeLayout.dashboard,
    palette: _splitPalette,
    cardRadius: 18,
    controlRadius: 12,
    contentRadius: 24,
    shadowOpacity: .3,
    stageOverlayOpacity: .4,
  ),
);

ProviderViewState _provider({
  double? balance = 10,
  double dailyUsage = 0,
  double monthlyUsage = 0,
  double? dailyDisplayUsage,
  double? monthlyDisplayUsage,
}) => ProviderViewState(
  id: 'test',
  name: 'Test Provider',
  balance: balance,
  dailyUsage: dailyUsage,
  monthlyUsage: monthlyUsage,
  dailyDisplayUsage: dailyDisplayUsage ?? dailyUsage,
  monthlyDisplayUsage: monthlyDisplayUsage ?? monthlyUsage,
  status: ConnectionStatus.connected,
  message: '已连接',
);

void main() {
  testWidgets('keeps provider card and dialog surfaces independent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _splitTokens.materialTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ProviderCard(provider: _provider(), accent: Colors.teal),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      key: Key('split-surface-dialog'),
                      title: Text('Surface dialog'),
                    ),
                  ),
                  child: const Text('Open dialog'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final cardSurface = find.descendant(
      of: find.byType(ProviderCard),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).gradient != null,
      ),
    );
    final card = tester.widget<Container>(cardSurface);
    final cardGradient = (card.decoration! as BoxDecoration).gradient!;
    expect(cardGradient.colors.first, const Color(0xff607080));

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    final dialogMaterial = find.descendant(
      of: find.byKey(const Key('split-surface-dialog')),
      matching: find.byWidgetPredicate(
        (widget) => widget is Material && widget.type == MaterialType.card,
      ),
    );
    expect(
      tester.widget<Material>(dialogMaterial).color,
      const Color(0xff708090),
    );
    expect(cardGradient.colors.first, isNot(const Color(0xff708090)));
  });

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

  testWidgets(
    'exposes independent usage edit actions without changing recharge',
    (tester) async {
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
    },
  );

  testWidgets(
    'uses display-policy usage values and shows dashes for hidden metrics',
    (tester) async {
      const provider = ProviderViewState(
        id: 'test',
        name: 'Test Provider',
        balance: 10,
        dailyUsage: 91.25,
        monthlyUsage: 182.5,
        dailyDisplayUsage: null,
        monthlyDisplayUsage: null,
        status: ConnectionStatus.connected,
        message: '已连接',
      );
      await tester.pumpWidget(
        _host(
          ProviderCard(
            provider: provider,
            accent: Colors.teal,
            onEditDailyUsage: () {},
            onEditMonthlyUsage: () {},
          ),
        ),
      );

      expect(find.text('¥ 91.25'), findsNothing);
      expect(find.text('¥ 182.50'), findsNothing);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.byTooltip('修改今日用量'), findsOneWidget);
      expect(find.byTooltip('修改本月用量'), findsOneWidget);
    },
  );

  testWidgets(
    'keeps usage edit actions available when balance is unavailable',
    (tester) async {
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
    },
  );
}
