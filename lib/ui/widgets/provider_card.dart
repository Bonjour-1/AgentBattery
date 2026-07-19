import 'package:flutter/material.dart';

import '../../models/provider_config.dart';
import '../../models/provider_view_state.dart';
import '../theme/app_theme_tokens.dart';
import 'glass_surface.dart';
import 'metric_tile.dart';

class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.accent,
    this.rechargeUrl = '',
    this.lowBalanceThreshold,
    this.onRecharge,
    this.onEditDailyUsage,
    this.onEditMonthlyUsage,
  });

  final ProviderViewState provider;
  final Color accent;
  final String rechargeUrl;
  final double? lowBalanceThreshold;
  final VoidCallback? onRecharge;
  final VoidCallback? onEditDailyUsage;
  final VoidCallback? onEditMonthlyUsage;

  bool get hasRechargeShortcut => isValidRechargeUrl(rechargeUrl);
  bool get isLowBalance =>
      provider.balance != null &&
      lowBalanceThreshold != null &&
      provider.balance! <= lowBalanceThreshold!;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final balanceAccent = isLowBalance ? tokens.error : accent;
    return GlassSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = _ProviderTitle(provider: provider, accent: accent);
              final actions = [
                if (hasRechargeShortcut) ...[
                  _RechargeButton(
                    lowBalance: isLowBalance,
                    onPressed: onRecharge,
                  ),
                  const SizedBox(width: 8),
                ],
                _StatusChip(provider: provider),
              ];
              if (constraints.maxWidth >= 480) {
                return Row(
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 8),
                    ...actions,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  title,
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (hasRechargeShortcut)
                        _RechargeButton(
                          lowBalance: isLowBalance,
                          onPressed: onRecharge,
                        ),
                      _StatusChip(provider: provider),
                    ],
                  ),
                ],
              );
            },
          ),
          if (isLowBalance)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '余额偏低',
                  style: TextStyle(
                    color: tokens.error,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              MetricTile(
                label: '当前余额',
                value: provider.balance == null
                    ? '不可用'
                    : '¥ ${provider.balance!.toStringAsFixed(2)}',
                accent: balanceAccent,
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: '今日用量',
                value: provider.dailyDisplayUsage == null
                    ? '—'
                    : '¥ ${provider.dailyDisplayUsage!.toStringAsFixed(2)}',
                trailing: onEditDailyUsage == null
                    ? null
                    : IconButton(
                        onPressed: onEditDailyUsage,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '修改今日用量',
                        visualDensity: VisualDensity.compact,
                      ),
              ),
              const SizedBox(width: 10),
              MetricTile(
                label: '本月用量',
                value: provider.monthlyDisplayUsage == null
                    ? '—'
                    : '¥ ${provider.monthlyDisplayUsage!.toStringAsFixed(2)}',
                trailing: onEditMonthlyUsage == null
                    ? null
                    : IconButton(
                        onPressed: onEditMonthlyUsage,
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: '修改本月用量',
                        visualDensity: VisualDensity.compact,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderTitle extends StatelessWidget {
  const _ProviderTitle({required this.provider, required this.accent});
  final ProviderViewState provider;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 34,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            provider.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _RechargeButton extends StatelessWidget {
  const _RechargeButton({required this.lowBalance, required this.onPressed});
  final bool lowBalance;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final color = lowBalance ? tokens.error : tokens.primary;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.open_in_new_rounded, size: 16),
      label: const Text('前往充值'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.provider});
  final ProviderViewState provider;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final color =
        provider.status == ConnectionStatus.connected ||
            provider.status == ConnectionStatus.unavailable
        ? tokens.success
        : provider.status == ConnectionStatus.error
        ? tokens.error
        : tokens.statusIdle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            provider.message,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
