import 'package:flutter/material.dart';

import '../../models/provider_config.dart';
import '../../models/provider_view_state.dart';
import '../theme/app_theme_tokens.dart';
import '../widgets/provider_card.dart';

class ProviderDetailScreen extends StatelessWidget {
  const ProviderDetailScreen({
    super.key,
    required this.config,
    required this.provider,
  });

  final ProviderConfig config;
  final ProviderViewState provider;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('服务商详情')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Hero(
            key: Key('provider-detail-hero-${config.id}'),
            tag: 'provider-card-${config.id}',
            child: ProviderCard(
              provider: provider,
              accent: Color(config.colorValue),
              rechargeUrl: config.rechargeUrl,
              lowBalanceThreshold: config.lowBalanceThreshold,
            ),
          ),
          const SizedBox(height: 20),
          Text('连接信息', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          _DetailRow(label: 'Base URL', value: config.normalizedBaseUrl),
          _DetailRow(
            label: '默认模型',
            value: config.defaultModel.isEmpty ? '未设置' : config.defaultModel,
          ),
          _DetailRow(label: '连接状态', value: provider.message),
          _DetailRow(
            label: '低余额阈值',
            value: config.lowBalanceThreshold == null
                ? '未设置'
                : '¥ ${config.lowBalanceThreshold!.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 16),
          Text(
            '配置与安全凭据请在“管理服务商”中修改。',
            style: TextStyle(color: tokens.mutedText),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: .76),
        borderRadius: BorderRadius.circular(tokens.controlRadius),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: tokens.mutedText, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: tokens.text)),
        ],
      ),
    );
  }
}
