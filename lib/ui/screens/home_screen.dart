import 'dart:async';
import 'dart:io';

import 'package:agent_battery_flutter/models/provider_config.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/custom_theme.dart';
import '../../models/provider_usage.dart';
import '../../state/battery_controller.dart';
import '../theme/app_theme_tokens.dart';
import '../window_layout_policy.dart';
import '../widgets/provider_card.dart';
import 'provider_management_screen.dart';
import 'theme_studio_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, this.onExitRequested});
  final BatteryController controller;
  final VoidCallback? onExitRequested;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<File?>? _backgroundFuture;
  String? _backgroundThemeId;

  @override
  void initState() {
    super.initState();
    _loadBackground();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadBackground();
  }

  void _loadBackground() {
    final themeId = widget.controller.themeReference.customThemeId;
    if (_backgroundThemeId == themeId) return;
    _backgroundThemeId = themeId;
    _backgroundFuture = widget.controller.resolveActiveThemeBackground();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTheme = widget.controller.resolvedTheme;
    if (resolvedTheme.layout == WindowLayoutPolicy.mikuStage) {
      final builtinTheme = widget.controller.themeReference.builtinTheme;
      if (builtinTheme == AppTheme.miku ||
          builtinTheme == AppTheme.mita ||
          builtinTheme == AppTheme.nailong) {
        return _CharacterStage(
          controller: widget.controller,
          onExitRequested: widget.onExitRequested,
          theme: builtinTheme!,
        );
      }
      return _CustomStage(
        controller: widget.controller,
        onExitRequested: widget.onExitRequested,
        background: _backgroundFuture,
      );
    }
    final tokens = AppThemeTokens.of(context);
    final matchingCustomThemes = widget.controller.themeReference.isBuiltin
        ? const <CustomTheme>[]
        : widget.controller.customThemes
              .where(
                (theme) =>
                    theme.id == widget.controller.themeReference.customThemeId,
              )
              .toList();
    final activeCustomTheme = matchingCustomThemes.isEmpty
        ? null
        : matchingCustomThemes.first;
    final backgroundFit = _backgroundFit(activeCustomTheme?.backgroundImageFit);
    final backgroundAlignment = _backgroundAlignment(
      activeCustomTheme?.backgroundImageAlignment,
    );
    final backgroundOpacity = (activeCustomTheme?.backgroundImageOpacity ?? 1)
        .clamp(0.0, 1.0)
        .toDouble();
    return Scaffold(
      body: ColoredBox(
        key: const Key('custom-dashboard-page-background'),
        color: tokens.pageBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_backgroundFuture != null)
              FutureBuilder<File?>(
                future: _backgroundFuture,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  return file == null
                      ? const SizedBox.expand()
                      : Opacity(
                          key: const Key('custom-dashboard-background-opacity'),
                          opacity: backgroundOpacity,
                          child: Image.file(
                            file,
                            key: const Key('custom-dashboard-background'),
                            fit: backgroundFit,
                            alignment: backgroundAlignment,
                            errorBuilder: (_, _, _) => const SizedBox.expand(),
                          ),
                        );
                },
              ),
            SafeArea(
              child: Column(
                children: [
                  _Header(
                    controller: widget.controller,
                    onExitRequested: widget.onExitRequested,
                    onPageBackground: true,
                  ),
                  Expanded(
                    child: _Content(
                      controller: widget.controller,
                      presentation: _dashboardPresentation(activeCustomTheme),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAutoRefreshSettings(
  BuildContext context,
  BatteryController controller,
) async {
  final seconds = TextEditingController(
    text: controller.autoRefreshIntervalSeconds.toString(),
  );
  var enabled = controller.autoRefreshEnabled;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('自动更新设置'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('打开自动更新'),
                subtitle: const Text('按设定间隔查询已启用服务商'),
                value: enabled,
                onChanged: (value) => setDialogState(() => enabled = value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: seconds,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '更新间隔（秒）',
                  helperText: '可设置 1～86400 秒，默认 60 秒',
                  suffixText: '秒',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final interval = int.tryParse(seconds.text.trim());
              if (interval == null || interval < 1 || interval > 86400) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入 1～86400 之间的秒数')),
                );
                return;
              }
              await controller.setAutoRefresh(
                enabled: enabled,
                intervalSeconds: interval,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  seconds.dispose();
}

Future<void> _showManualUsageDialog(
  BuildContext context,
  BatteryController controller,
  ProviderConfig config,
  UsagePeriod period,
  double existingAmount,
) async {
  final amount = TextEditingController(text: existingAmount.toStringAsFixed(2));
  var errorText = '';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final periodLabel = period == UsagePeriod.daily ? '今日' : '本月';
        return AlertDialog(
          title: Text('修改 ${config.name} $periodLabel用量'),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: '$periodLabel用量',
                errorText: errorText.isEmpty ? null : errorText,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final value = double.tryParse(amount.text.trim());
                if (value == null || !value.isFinite || value < 0) {
                  setDialogState(() => errorText = '请输入有限且不小于 0 的金额');
                  return;
                }
                await controller.setManualUsage(
                  providerId: config.id,
                  period: period,
                  amount: value,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => amount.dispose());
}

class _CustomStage extends StatelessWidget {
  const _CustomStage({
    required this.controller,
    required this.onExitRequested,
    required this.background,
  });

  final BatteryController controller;
  final VoidCallback? onExitRequested;
  final Future<File?>? background;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final customTheme = controller.customThemes
        .where((theme) => theme.id == controller.themeReference.customThemeId)
        .toList();
    final theme = customTheme.isEmpty ? null : customTheme.first;
    final double overlayOpacity = theme?.stageOverlayOpacity ?? 0;
    final backgroundFit = _backgroundFit(theme?.backgroundImageFit);
    final backgroundAlignment = _backgroundAlignment(
      theme?.backgroundImageAlignment,
    );
    final backgroundOpacity = (theme?.backgroundImageOpacity ?? 1)
        .clamp(0.0, 1.0)
        .toDouble();
    return Scaffold(
      body: Container(
        key: const Key('custom-stage-wrapper'),
        decoration: BoxDecoration(gradient: tokens.stageGradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (background != null)
              FutureBuilder<File?>(
                future: background,
                builder: (context, snapshot) {
                  final file = snapshot.data;
                  return file == null
                      ? const SizedBox.expand()
                      : Opacity(
                          key: const Key('custom-stage-background-opacity'),
                          opacity: backgroundOpacity,
                          child: Image.file(
                            file,
                            key: const Key('custom-stage-background'),
                            fit: backgroundFit,
                            alignment: backgroundAlignment,
                            errorBuilder: (_, _, _) => const SizedBox.expand(),
                          ),
                        );
                },
              ),
            if (overlayOpacity > 0)
              ColoredBox(
                color: tokens.stageGradient.colors.first.withValues(
                  alpha: overlayOpacity,
                ),
              ),
            SafeArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: .55,
                  child: Column(
                    children: [
                      _Header(
                        controller: controller,
                        onExitRequested: onExitRequested,
                      ),
                      Expanded(
                        child: _Content(
                          controller: controller,
                          stage: true,
                          presentation: _dashboardPresentation(theme),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxFit _backgroundFit(BackgroundImageFit? fit) => switch (fit) {
  BackgroundImageFit.contain => BoxFit.contain,
  BackgroundImageFit.fill => BoxFit.fill,
  BackgroundImageFit.cover || null => BoxFit.cover,
};

Alignment _backgroundAlignment(BackgroundImageAlignment? alignment) =>
    switch (alignment) {
      BackgroundImageAlignment.left => Alignment.centerLeft,
      BackgroundImageAlignment.right => Alignment.centerRight,
      BackgroundImageAlignment.top => Alignment.topCenter,
      BackgroundImageAlignment.bottom => Alignment.bottomCenter,
      BackgroundImageAlignment.center || null => Alignment.center,
    };

class _CharacterStage extends StatelessWidget {
  const _CharacterStage({
    required this.controller,
    required this.onExitRequested,
    required this.theme,
  });

  final BatteryController controller;
  final VoidCallback? onExitRequested;
  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          final mita = theme == AppTheme.mita;
          final nailong = theme == AppTheme.nailong;
          final content = Column(
            children: [
              _Header(controller: controller, onExitRequested: onExitRequested),
              Expanded(child: _Content(controller: controller, stage: true)),
            ],
          );
          return Container(
            decoration: BoxDecoration(
              gradient: AppThemeTokens.of(context).stageGradient,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  nailong
                      ? 'assets/images/nailong_dashboard_background.png'
                      : mita
                      ? 'assets/images/mita_colored_pencil_dashboard_background.png'
                      : 'assets/images/miku_stage_background.png',
                  key: ValueKey(
                    '${nailong
                        ? 'nailong'
                        : mita
                        ? 'mita'
                        : 'miku'}-stage-${compact ? 'compact' : 'wide'}',
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: compact ? 1 : .56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: nailong
                              ? (compact
                                    ? const [
                                        Color(0xf5fff5c5),
                                        Color(0xccffe78e),
                                      ]
                                    : const [
                                        Color(0xfafff9df),
                                        Color(0xd9ffec9f),
                                        Color(0x12ffdf77),
                                      ])
                              : (mita
                                    ? (compact
                                          ? const [
                                              Color(0xf01e1648),
                                              Color(0xcf4a397d),
                                            ]
                                          : const [
                                              Color(0xf51e1648),
                                              Color(0xcc3b2d70),
                                              Color(0x123b2d70),
                                            ])
                                    : (compact
                                          ? const [
                                              Color(0xee063f43),
                                              Color(0xc20d7773),
                                            ]
                                          : const [
                                              Color(0xf5084548),
                                              Color(0xc20a6564),
                                              Color(0x0a0a6564),
                                            ])),
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: compact
                      ? content
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: .55,
                            child: content,
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThemeMenuAction {
  const _ThemeMenuAction._({this.reference, this.openStudio = false});

  final ThemeReference? reference;
  final bool openStudio;

  _ThemeMenuAction.builtin(AppTheme theme)
    : this._(reference: ThemeReference.builtin(theme));

  _ThemeMenuAction.custom(String id)
    : this._(reference: ThemeReference.custom(id));

  static final miku = _ThemeMenuAction.builtin(AppTheme.miku);
  static final glass = _ThemeMenuAction.builtin(AppTheme.glass);
  static final cute = _ThemeMenuAction.builtin(AppTheme.cute);
  static final mita = _ThemeMenuAction.builtin(AppTheme.mita);
  static final nailong = _ThemeMenuAction.builtin(AppTheme.nailong);
  static const studio = _ThemeMenuAction._(openStudio: true);
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    this.onExitRequested,
    this.onPageBackground = false,
  });
  final BatteryController controller;
  final VoidCallback? onExitRequested;
  final bool onPageBackground;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final headerText = onPageBackground ? tokens.text : tokens.onStage;
    final actions = [
      PopupMenuButton<_ThemeMenuAction>(
        tooltip: '切换主题',
        onSelected: (action) {
          if (action.reference != null) {
            controller.applyThemeReference(action.reference!);
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThemeStudioScreen(controller: controller),
            ),
          );
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: _ThemeMenuAction.miku,
            child: const Text('MIKU'),
          ),
          PopupMenuItem(value: _ThemeMenuAction.glass, child: const Text('玻璃')),
          PopupMenuItem(value: _ThemeMenuAction.cute, child: const Text('可爱风')),
          PopupMenuItem(
            value: _ThemeMenuAction.mita,
            child: const Text('米塔彩铅'),
          ),
          PopupMenuItem(
            value: _ThemeMenuAction.nailong,
            child: const Text('奶龙'),
          ),
          if (controller.customThemes.isNotEmpty) ...[
            const PopupMenuDivider(),
            const PopupMenuItem<_ThemeMenuAction>(
              enabled: false,
              child: Text('自定义主题'),
            ),
            for (final theme in controller.customThemes)
              PopupMenuItem(
                value: _ThemeMenuAction.custom(theme.id),
                child: Text(theme.name),
              ),
          ],
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _ThemeMenuAction.studio,
            child: Text('主题工作台'),
          ),
        ],
        icon: const Icon(Icons.palette_outlined),
      ),
      IconButton.filledTonal(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProviderManagementScreen(controller: controller),
          ),
        ),
        tooltip: '管理服务商',
        icon: const Icon(Icons.tune_rounded),
      ),
      IconButton.filledTonal(
        onPressed: () => _showAutoRefreshSettings(context, controller),
        tooltip: '自动更新设置',
        icon: Icon(
          controller.autoRefreshEnabled
              ? Icons.autorenew_rounded
              : Icons.autorenew_outlined,
        ),
      ),
      IconButton.filledTonal(
        onPressed: controller.refreshing ? null : controller.refresh,
        tooltip: '立即刷新',
        icon: controller.refreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
      ),
      if (onExitRequested != null)
        IconButton.filledTonal(
          onPressed: onExitRequested,
          tooltip: '退出 AgentBattery',
          icon: const Icon(Icons.close_rounded),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 8,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tokens.surface.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                border: Border.all(color: tokens.outline),
              ),
              child: Icon(
                Icons.battery_charging_full_rounded,
                color: tokens.primary,
                size: 28,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth < 500
                  ? constraints.maxWidth - 56
                  : 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tokens.kind == AppTheme.mita
                        ? 'AGENT BATTERY · MITA'
                        : 'AGENT BATTERY',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: headerText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    tokens.kind == AppTheme.mita
                        ? '彩铅小屋里的 AI 能量记录册'
                        : '${tokens.name} · 模型能量与用量中心',
                    style: TextStyle(
                      color: headerText.withValues(alpha: .76),
                      fontSize: 13,
                    ),
                  ),
                  if (tokens.kind == AppTheme.cute)
                    Text(
                      '✦  ♥',
                      style: TextStyle(
                        color: headerText.withValues(alpha: .76),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

class _DashboardPresentation {
  const _DashboardPresentation({required this.mode, required this.density});

  final DashboardLayoutMode mode;
  final DashboardDensity density;

  bool get isFocus => mode == DashboardLayoutMode.focus;
  bool get isCompact => density == DashboardDensity.compact;
  EdgeInsets get contentPadding => isCompact
      ? const EdgeInsets.fromLTRB(16, 14, 16, 12)
      : const EdgeInsets.fromLTRB(24, 23, 24, 18);
  double get summaryGap => isCompact ? 8 : 16;
  double get providerGap => isCompact ? 8 : 12;
}

_DashboardPresentation _dashboardPresentation(CustomTheme? theme) =>
    _DashboardPresentation(
      mode: theme?.dashboardLayoutMode ?? DashboardLayoutMode.standard,
      density: theme?.dashboardDensity ?? DashboardDensity.comfortable,
    );

class _Content extends StatelessWidget {
  const _Content({
    required this.controller,
    this.stage = false,
    this.presentation,
  });
  final BatteryController controller;
  final bool stage;
  final _DashboardPresentation? presentation;

  Future<void> _openRechargePage(
    BuildContext context,
    ProviderConfig config,
  ) async {
    try {
      final opened = await launchUrl(
        Uri.parse(config.rechargeUrl.trim()),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开充值页面，请检查服务商地址。')));
      }
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开充值页面，请检查服务商地址。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final dashboard =
        presentation ??
        const _DashboardPresentation(
          mode: DashboardLayoutMode.standard,
          density: DashboardDensity.comfortable,
        );
    return Container(
      key: dashboard.isFocus
          ? const Key('custom-dashboard-focus')
          : const Key('custom-dashboard-standard'),
      width: double.infinity,
      padding: dashboard.contentPadding,
      decoration: BoxDecoration(
        gradient: stage && tokens.kind == AppTheme.miku
            ? const LinearGradient(
                colors: [Color(0xddedfffe), Color(0xcce0fbf7)],
              )
            : tokens.contentGradient,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.contentRadius),
        ),
        border: stage
            ? Border.all(color: Colors.white.withValues(alpha: .38))
            : null,
      ),
      child: ListView(
        key: dashboard.isCompact
            ? const Key('custom-dashboard-density-compact')
            : const Key('custom-dashboard-density-comfortable'),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final summaries = [
                _Summary(
                  label: tokens.kind == AppTheme.mita ? '能量小金库' : '余额合计',
                  value: '¥ ${controller.totalBalance.toStringAsFixed(2)}',
                  icon: Icons.account_balance_wallet_rounded,
                ),
                _Summary(
                  label: tokens.kind == AppTheme.mita ? '今天的小消耗' : '今日消耗',
                  value: '¥ ${controller.totalDaily.toStringAsFixed(2)}',
                  icon: Icons.bolt_rounded,
                ),
                _Summary(
                  label: tokens.kind == AppTheme.mita ? '本月努力值' : '本月消耗',
                  value: '¥ ${controller.totalMonthly.toStringAsFixed(2)}',
                  icon: Icons.calendar_month_rounded,
                ),
              ];
              if (dashboard.isFocus) {
                return Wrap(
                  key: const Key('custom-dashboard-focus-summary'),
                  spacing: dashboard.isCompact ? 6 : 10,
                  runSpacing: dashboard.isCompact ? 6 : 10,
                  children: summaries
                      .map(
                        (item) => SizedBox(
                          width: constraints.maxWidth < 520
                              ? double.infinity
                              : (constraints.maxWidth -
                                        (dashboard.isCompact ? 6 : 10)) /
                                    2,
                          child: item,
                        ),
                      )
                      .toList(),
                );
              }
              if (constraints.maxWidth < 520) {
                return Column(
                  children: [
                    for (final item in summaries) ...[
                      item,
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (final item in summaries)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: item,
                      ),
                    ),
                ],
              );
            },
          ),
          SizedBox(height: dashboard.summaryGap),
          if (controller.visibleProviders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  '没有启用的服务商\n请通过“管理服务商”添加或启用。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.mutedText),
                ),
              ),
            ),
          for (final entry in controller.enabledConfigs.indexed) ...[
            ProviderCard(
              provider: controller.providers[entry.$2.id]!,
              accent: Color(entry.$2.colorValue),
              rechargeUrl: entry.$2.rechargeUrl,
              lowBalanceThreshold: entry.$2.lowBalanceThreshold,
              onRecharge: () => _openRechargePage(context, entry.$2),
              onEditDailyUsage: () => _showManualUsageDialog(
                context,
                controller,
                entry.$2,
                UsagePeriod.daily,
                controller.providers[entry.$2.id]!.dailyUsage,
              ),
              onEditMonthlyUsage: () => _showManualUsageDialog(
                context,
                controller,
                entry.$2,
                UsagePeriod.monthly,
                controller.providers[entry.$2.id]!.monthlyUsage,
              ),
            ),
            SizedBox(height: dashboard.providerGap),
          ],
          Text(
            controller.lastRefresh == null
                ? '缓存已就绪 · 正在后台同步'
                : '最近更新 ${controller.lastRefresh!.hour.toString().padLeft(2, '0')}:${controller.lastRefresh!.minute.toString().padLeft(2, '0')} · Key 已安全保存在本地',
            style: TextStyle(color: tokens.mutedText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: tokens.cardGradient,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tokens.primary),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: tokens.mutedText)),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: tokens.text,
            ),
          ),
        ],
      ),
    );
  }
}
