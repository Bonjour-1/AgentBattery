import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:agent_battery_flutter/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

ProviderConfig _postConfig({required String body}) => ProviderConfig(
  id: 'test',
  name: 'Test provider',
  colorValue: 0,
  order: 0,
  enabled: true,
  baseUrl: 'https://example.com',
  apiKey: 'runtime-api-key',
  advancedEnabled: true,
  balanceUrl: '/balance',
  balanceMethod: BalanceRequestMethod.post,
  balanceBody: body,
  balanceJsonPath: 'data.balance',
);

void main() {
  test(
    'POST balance request replaces the API key placeholder in its body',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url, Uri.parse('https://example.com/balance'));
        expect(request.headers['Authorization'], 'Bearer runtime-api-key');
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.body, '{"api_key":"runtime-api-key","scope":"all"}');

        return http.Response('{"data":{"balance":12.5}}', 200);
      });
      final api = ApiClient(client: client);
      addTearDown(api.close);

      final response = await api.fetchBalance(
        _postConfig(body: r'{"api_key":"${API_KEY}","scope":"all"}'),
      );

      expect(response.balance, 12.5);
    },
  );

  test(
    'POST balance request preserves a JSON body without the API key placeholder',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.body, '{"account":"primary","scope":"all"}');

        return http.Response('{"data":{"balance":0}}', 200);
      });
      final api = ApiClient(client: client);
      addTearDown(api.close);

      await api.fetchBalance(
        _postConfig(body: '{"account":"primary","scope":"all"}'),
      );
    },
  );
}
