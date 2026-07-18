import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:agent_battery_flutter/services/storage_service.dart';
import 'package:agent_battery_flutter/state/battery_controller.dart';
import 'package:agent_battery_flutter/ui/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows an explicit exit control that invokes the app exit callback',
    (tester) async {
      final controller = BatteryController(
        storage: StorageService(),
        api: ApiClient(),
      );
      var exitRequested = false;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            controller: controller,
            onExitRequested: () => exitRequested = true,
          ),
        ),
      );

      expect(find.byTooltip('退出 AgentBattery'), findsOneWidget);
      await tester.tap(find.byTooltip('退出 AgentBattery'));

      expect(exitRequested, isTrue);
    },
  );
}
