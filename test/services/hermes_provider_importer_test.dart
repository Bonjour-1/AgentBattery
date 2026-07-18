import 'package:agent_battery_flutter/services/hermes_provider_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const importer = HermesProviderImporter();

  test(
    'imports declared metadata and API keys without putting keys in config',
    () {
      final plan = importer.parse(
        configYaml: '''
providers:
  glm:
    name: GLM
    base_url: https://open.bigmodel.cn/api/paas/v4
    key_env: GLM_API_KEY
    default_model: glm-5
  codeapi:
    name: CodeAPI
    base_url: http://127.0.0.1:9090/v1
    api_key: inline-test-key
    model: code-model
    balance_token: must-not-import
    balance_url: https://billing.example.test
    headers: '{"Cookie":"must-not-import"}'
    json_path: data.balance
''',
        envFile: 'GLM_API_KEY=env-test-key\nUNRELATED_SECRET=must-not-read\n',
      );

      expect(plan.providers, hasLength(2));
      final glm = plan.providers.firstWhere((item) => item.config.id == 'glm');
      final codeApi = plan.providers.firstWhere(
        (item) => item.config.id == 'codeapi',
      );
      expect(glm.baseMetadataOnly, isTrue);
      expect(glm.config.name, 'GLM');
      expect(glm.config.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
      expect(glm.config.defaultModel, 'glm-5');
      expect(glm.apiKey, 'env-test-key');
      expect(glm.config.apiKey, isEmpty);
      expect(glm.config.webBillingConfig, isNull);
      expect(codeApi.config.defaultModel, 'code-model');
      expect(codeApi.apiKey, 'inline-test-key');
      expect(codeApi.config.apiKey, isEmpty);
      expect(codeApi.config.advancedEnabled, isFalse);
      expect(codeApi.config.balanceRequest.isConfigured, isFalse);
      expect(codeApi.config.webBillingConfig, isNull);
    },
  );

  test(
    'creates a basic DeepSeek skeleton from a recognizable environment key',
    () {
      final plan = importer.parse(
        configYaml: '''
providers:
  no-key:
    name: No Key Provider
    base_url: https://example.test/v1
''',
        envFile: 'DEEPSEEK_API_KEY=deepseek-test-key\n',
      );

      final deepSeek = plan.providers.singleWhere(
        (item) => item.config.id == 'deepseek',
      );
      expect(deepSeek.config.name, 'DeepSeek');
      expect(deepSeek.config.baseUrl, 'https://api.deepseek.com/v1');
      expect(deepSeek.config.defaultModel, 'deepseek-chat');
      expect(deepSeek.config.enabled, isFalse);
      expect(deepSeek.apiKey, 'deepseek-test-key');
      expect(deepSeek.config.apiKey, isEmpty);
      expect(deepSeek.config.webBillingConfig, isNull);
      expect(deepSeek.config.advancedEnabled, isFalse);
    },
  );

  test('does not create DeepSeek skeleton when it is explicitly declared', () {
    final plan = importer.parse(
      configYaml: '''
providers:
  deepseek:
    name: My DeepSeek
    base_url: https://gateway.example/v1
    key_env: DEEPSEEK_API_KEY
''',
      envFile: 'DEEPSEEK_API_KEY=deepseek-test-key\n',
    );

    expect(plan.providers, hasLength(1));
    expect(plan.providers.single.config.name, 'My DeepSeek');
    expect(plan.providers.single.apiKey, 'deepseek-test-key');
  });

  test('imports a declared provider without an API key', () {
    final plan = importer.parse(
      configYaml: '''
custom_providers:
  - name: Chat2API
    base_url: http://172.31.96.1:8080/v1
    model: deepseek-v4-pro
''',
    );

    final provider = plan.providers.single;
    expect(provider.config.name, 'Chat2API');
    expect(provider.config.defaultModel, 'deepseek-v4-pro');
    expect(provider.apiKey, isEmpty);
    expect(provider.config.webBillingConfig, isNull);
  });

  test('decodes quoted unicode-escaped explicit provider names to Chinese', () {
    final plan = importer.parse(
      configYaml: r'''
providers:
  glm:
    name: "\u667A\u8C31\u6E05\u8A00 GLM"
    base_url: https://open.bigmodel.cn/api/paas/v4
    default_model: glm-5
''',
    );

    final provider = plan.providers.single;
    expect(provider.config.name, '智谱清言 GLM');
    expect(provider.config.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    expect(provider.config.defaultModel, 'glm-5');
  });

  test('decodes quoted unicode-escaped custom provider names to Chinese', () {
    final plan = importer.parse(
      configYaml: r'''
custom_providers:
  - name: "\u667A\u8C31\u6E05\u8A00 GLM"
    base_url: https://open.bigmodel.cn/api/paas/v4
    model: glm-5
''',
    );

    final provider = plan.providers.single;
    expect(provider.config.name, '智谱清言 GLM');
    expect(provider.config.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    expect(provider.config.defaultModel, 'glm-5');
  });

  test('keeps ordinary plain strings unchanged', () {
    final plan = importer.parse(
      configYaml: '''
providers:
  plain-provider:
    name: Plain Provider
    base_url: https://example.test/v1
    default_model: plain-model
''',
    );

    final provider = plan.providers.single;
    expect(provider.config.name, 'Plain Provider');
    expect(provider.config.baseUrl, 'https://example.test/v1');
    expect(provider.config.defaultModel, 'plain-model');
  });

  test('decodes escaped URLs into correct standard strings', () {
    final plan = importer.parse(
      configYaml: r'''
providers:
  glm:
    name: GLM
    base_url: "https:\/\/open.bigmodel.cn\/api\/paas\/v4"
    default_model: "glm\u002D5"
''',
    );

    final provider = plan.providers.single;
    expect(provider.config.baseUrl, 'https://open.bigmodel.cn/api/paas/v4');
    expect(provider.config.defaultModel, 'glm-5');
    expect(provider.config.name, 'GLM');
  });
}
