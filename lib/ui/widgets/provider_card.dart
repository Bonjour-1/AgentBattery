import 'package:flutter/material.dart';

import '../../models/provider_config.dart';
import '../../models/provider_view_state.dart';
import '../theme/app_theme_tokens.dart';
import 'glass_surface.dart';
import 'metric_tile.dart';

class ProviderCard extends StatefulWidget {
  const ProviderCard({
    super.key,
    required this.provider,
    required this.accent,
    this.rechargeUrl = '',
    this.lowBalanceThreshold,
    this.onRecharge,
    this.onEditDailyUsage,
    this.onEditMonthlyUsage,
    this.onOpen,
  });

  final ProviderViewState provider;
  final Color accent;
  final String rechargeUrl;
  final double? lowBalanceThreshold;
  final VoidCallback? onRecharge;
  final VoidCallback? onEditDailyUsage;
  final VoidCallback? onEditMonthlyUsage;
  final VoidCallback? onOpen;

  @override
  State<ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<ProviderCard> {
  bool _hovered = false;

  bool get _hasRechargeShortcut => isValidRechargeUrl(widget.rechargeUrl);
  bool get _isLowBalance =>
      widget.provider.balance != null &&
      widget.lowBalanceThreshold != null &&
      widget.provider.balance! <= widget.lowBalanceThreshold!;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final hoverOffset = _hovered && !reduceMotion ? -3.0 : 0.0;
    final balanceAccent = _isLowBalance ? tokens.error : widget.accent;
    return MouseRegion(
      cursor: widget.onOpen == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpen,
        child: AnimatedContainer(
          key: const Key('provider-card-motion-surface'),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, hoverOffset, 0),
          decoration: const BoxDecoration(),
          child: GlassSurface(
            padding: const EdgeInsets.all(18),
            shadowAlpha: _hovered && !reduceMotion ? .18 : .10,
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final title = _ProviderTitle(
                      provider: widget.provider,
                      accent: widget.accent,
                    );
                    final actions = [
                      if (_hasRechargeShortcut) ...[
                        _RechargeButton(
                          lowBalance: _isLowBalance,
                          onPressed: widget.onRecharge,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _StatusChip(provider: widget.provider),
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
                            if (_hasRechargeShortcut)
                              _RechargeButton(
                                lowBalance: _isLowBalance,
                                onPressed: widget.onRecharge,
                              ),
                            _StatusChip(provider: widget.provider),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (_isLowBalance)
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
                      value: widget.provider.balance == null
                          ? '不可用'
                          : '¥ ${widget.provider.balance!.toStringAsFixed(2)}',
                      accent: balanceAccent,
                    ),
                    const SizedBox(width: 10),
                    MetricTile(
                      label: '今日用量',
                      value: widget.provider.dailyDisplayUsage == null
                          ? '—'
                          : '¥ ${widget.provider.dailyDisplayUsage!.toStringAsFixed(2)}',
                      trailing: widget.onEditDailyUsage == null
                          ? null
                          : IconButton(
                              onPressed: widget.onEditDailyUsage,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: '修改今日用量',
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                    const SizedBox(width: 10),
                    MetricTile(
                      label: '本月用量',
                      value: widget.provider.monthlyDisplayUsage == null
                          ? '—'
                          : '¥ ${widget.provider.monthlyDisplayUsage!.toStringAsFixed(2)}',
                      trailing: widget.onEditMonthlyUsage == null
                          ? null
                          : IconButton(
                              onPressed: widget.onEditMonthlyUsage,
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: '修改本月用量',
                              visualDensity: VisualDensity.compact,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.active && !reduceMotion) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: widget.active ? .58 + .42 * _controller.value : 1,
      child: Transform.scale(
        scale: widget.active ? .88 + .12 * _controller.value : 1,
        child: child,
      ),
    ),
    child: Container(
      key: const Key('provider-card-refresh-status-dot'),
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    ),
  );
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
          _StatusDot(
            color: color,
            active: provider.status == ConnectionStatus.refreshing,
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
