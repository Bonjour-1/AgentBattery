import 'package:agent_battery_flutter/app.dart';
import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'saving auto-refresh settings closes without a disposed controller',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = BatteryController(
        storage: StorageService(),
        api: ApiClient(),
      );
      await tester.pumpWidget(
        AgentBatteryApp(controller: controller, initializeServices: false),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('自动更新设置'));
      await tester.pump();
      await tester.tap(find.text('打开自动更新'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.pump();

      expect(find.text('自动更新设置'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'renders every persisted theme without overflow on a compact view',
    (tester) async {
      tester.view.physicalSize = const Size(620, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final theme in AppTheme.values) {
        SharedPreferences.setMockInitialValues({});
        final controller = BatteryController(
          storage: StorageService(),
          api: ApiClient(),
        );
        await controller.selectTheme(theme);
        await tester.pumpWidget(
          AgentBatteryApp(controller: controller, initializeServices: false),
        );
        await tester.pump();

        expect(
          find.text(
            theme == AppTheme.mita ? 'AGENT BATTERY · MITA' : 'AGENT BATTERY',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            theme == AppTheme.mita
                ? '彩铅小屋里的 AI 能量记录册'
                : '${switch (theme) {
                    AppTheme.miku => 'MIKU',
                    AppTheme.glass => '玻璃',
                    AppTheme.cute => '可爱风',
                    AppTheme.mita => 'MITA',
                    AppTheme.nailong => '奶龙',
                  }} · 模型能量与用量中心',
          ),
          findsOneWidget,
        );
        expect(find.byTooltip('立即刷新'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
