import 'package:agent_battery_flutter/models/app_snapshot.dart';
import 'package:agent_battery_flutter/models/custom_theme.dart';
import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/services/web_billing_migrations.dart';
import 'package:flutter_test/flutter_test.dart';

const _themeId = '1b4e28ba-2fa1-11d2-883f-0016d3cca427';

void main() {
  test(
    'v3 snapshot round trip preserves theme and provider billing metadata',
    () {
      final customTheme = CustomTheme(
        id: _themeId,
        name: 'Billing Theme',
        layout: ThemeLayout.stage,
        palette: const ThemePalette(
          primary: 0xff15968e,
          secondary: 0xffff8fab,
          stage: 0xff0d5753,
          content: 0xffe9fffd,
          card: 0xfff3fffe,
          cardAlt: 0xffddf8f5,
          text: 0xff123f3d,
          mutedText: 0xff557a77,
          onStage: 0xffffffff,
          outline: 0xffb6e4df,
          success: 0xff13867f,
          error: 0xffc34c70,
          statusIdle: 0xff687b79,
          shadow: 0xff0d5c57,
        ),
        cardRadius: 24,
        controlRadius: 16,
        contentRadius: 34,
        shadowOpacity: .45,
        stageOverlayOpacity: .28,
        backgroundImageFileName: 'billing-background.webp',
      );
      final provider = ProviderConfig(
        id: 'deepseek',
        name: 'DeepSeek',
        colorValue: 0xff365edc,
        order: 0,
        enabled: true,
        baseUrl: 'https://api.deepseek.com/v1',
        rechargeUrl: 'https://platform.deepseek.com/top_up',
        lowBalanceThreshold: 9.5,
        webBillingConfig: deepSeekWebBillingConfig(),
      );
      final snapshot = AppSnapshot(
        providerConfigs: [provider],
        themeReference: const ThemeReference.custom(_themeId),
        customThemes: [customTheme],
      );

      final json = snapshot.toJson();
      final restored = AppSnapshot.fromJson(json);

      expect(json['version'], 3);
      expect(restored.themeReference, const ThemeReference.custom(_themeId));
      expect(restored.customThemes, [customTheme]);
      final restoredProvider = restored.providerConfigs.single;
      expect(restoredProvider.rechargeUrl, provider.rechargeUrl);
      expect(
        restoredProvider.lowBalanceThreshold,
        provider.lowBalanceThreshold,
      );
      expect(
        restoredProvider.webBillingConfig?.toJson(),
        provider.webBillingConfig?.toJson(),
      );
    },
  );
}
