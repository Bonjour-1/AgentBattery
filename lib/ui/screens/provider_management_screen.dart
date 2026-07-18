import 'package:flutter/material.dart';

import '../../models/provider_config.dart';
import '../../state/battery_controller.dart';
import '../theme/app_theme_tokens.dart';

class ProviderManagementScreen extends StatelessWidget {
  const ProviderManagementScreen({super.key, required this.controller});
  final BatteryController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('管理服务商')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _edit(context),
      icon: const Icon(Icons.add),
      label: const Text('添加服务商'),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'OpenAI 兼容 /v1 服务商',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        for (final entry in controller.configs.indexed)
          Card(
            child: ListTile(
              leading: Container(
                width: 14,
                height: 36,
                decoration: BoxDecoration(
                  color: Color(entry.$2.colorValue),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              title: Text(entry.$2.name),
              subtitle: Text(
                '${entry.$2.normalizedBaseUrl}\nKey：${entry.$2.maskedApiKey}',
              ),
              isThreeLine: true,
              trailing: Wrap(
                spacing: 0,
                children: [
                  Switch(
                    value: entry.$2.enabled,
                    onChanged: (value) =>
                        controller.toggleProvider(entry.$2.id, value),
                  ),
                  IconButton(
                    onPressed: entry.$1 == 0
                        ? null
                        : () => controller.moveProvider(entry.$2.id, -1),
                    tooltip: '上移',
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    onPressed: entry.$1 == controller.configs.length - 1
                        ? null
                        : () => controller.moveProvider(entry.$2.id, 1),
                    tooltip: '下移',
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    onPressed: () => _edit(context, entry.$2),
                    tooltip: '编辑',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    onPressed: () => _confirmDelete(context, entry.$2),
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Future<void> _confirmDelete(
    BuildContext context,
    ProviderConfig config,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${config.name}？'),
        content: const Text('仅删除 Flutter 本地配置、Key 与使用缓存，不会修改旧版文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteProvider(config.id);
  }

  Future<void> _edit(BuildContext context, [ProviderConfig? initial]) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            ProviderEditorDialog(controller: controller, initial: initial),
      );
}

class ProviderEditorDialog extends StatefulWidget {
  const ProviderEditorDialog({
    super.key,
    required this.controller,
    this.initial,
  });
  final BatteryController controller;
  final ProviderConfig? initial;
  @override
  State<ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<ProviderEditorDialog> {
  late final TextEditingController name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController baseUrl = TextEditingController(
    text: widget.initial?.baseUrl ?? '',
  );
  late final TextEditingController key = TextEditingController();
  late final TextEditingController balanceToken = TextEditingController();
  late final TextEditingController model = TextEditingController(
    text: widget.initial?.defaultModel ?? '',
  );
  late final TextEditingController rechargeUrl = TextEditingController(
    text: widget.initial?.rechargeUrl ?? '',
  );
  late final TextEditingController lowBalanceThreshold = TextEditingController(
    text: widget.initial?.lowBalanceThreshold?.toString() ?? '',
  );
  late final TextEditingController balanceUrl = TextEditingController(
    text: widget.initial?.balanceUrl ?? '',
  );
  late final TextEditingController body = TextEditingController(
    text: widget.initial?.balanceBody ?? '',
  );
  late final TextEditingController headers = TextEditingController(
    text: widget.initial?.balanceHeaders ?? '',
  );
  late final TextEditingController balancePath = TextEditingController(
    text: widget.initial?.balanceJsonPath ?? '',
  );
  late final TextEditingController dailyPath = TextEditingController(
    text: widget.initial?.dailyUsageJsonPath ?? '',
  );
  late final TextEditingController monthlyPath = TextEditingController(
    text: widget.initial?.monthlyUsageJsonPath ?? '',
  );
  late bool advanced = widget.initial?.advancedEnabled ?? false;
  late BalanceRequestMethod method =
      widget.initial?.balanceMethod ?? BalanceRequestMethod.get;
  bool validating = false;
  String? result;

  ProviderConfig get config => ProviderConfig(
    id: widget.initial?.id ?? '',
    name: name.text.trim(),
    colorValue: widget.initial?.colorValue ?? 0xff39c5bb,
    order: widget.initial?.order ?? 0,
    enabled: widget.initial?.enabled ?? true,
    baseUrl: baseUrl.text.trim(),
    apiKey: key.text.trim(),
    balanceToken: balanceToken.text.trim(),
    defaultModel: model.text.trim(),
    advancedEnabled: advanced,
    rechargeUrl: rechargeUrl.text.trim(),
    lowBalanceThreshold: _parsedLowBalanceThreshold,
    balanceUrl: balanceUrl.text.trim(),
    balanceMethod: method,
    balanceBody: body.text.trim(),
    balanceHeaders: headers.text.trim(),
    balanceJsonPath: balancePath.text.trim(),
    dailyUsageJsonPath: dailyPath.text.trim(),
    monthlyUsageJsonPath: monthlyPath.text.trim(),
  );
  @override
  void dispose() {
    for (final c in [
      name,
      baseUrl,
      key,
      balanceToken,
      model,
      rechargeUrl,
      lowBalanceThreshold,
      balanceUrl,
      body,
      headers,
      balancePath,
      dailyPath,
      monthlyPath,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '添加服务商' : '编辑服务商'),
    content: SizedBox(
      width: 550,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _field(name, '显示名称'),
            _field(baseUrl, 'OpenAI Base URL（自动规范化为 /v1）'),
            _field(key, 'API Key', obscure: true),
            if (widget.initial?.id == 'pucoding')
              _field(
                balanceToken,
                'PuCoding Dashboard JWT（仅用于余额）',
                obscure: true,
              ),
            _field(model, '默认模型（可选）'),
            _field(rechargeUrl, '充值/余额管理地址（可选）'),
            _field(
              lowBalanceThreshold,
              '低余额阈值（元，可选）',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            ExpansionTile(
              title: const Text('高级余额设置'),
              initiallyExpanded: advanced,
              onExpansionChanged: (value) => setState(() => advanced = value),
              children: [
                _field(balanceUrl, '余额查询 URL（完整 URL 或相对路径）'),
                DropdownButtonFormField<BalanceRequestMethod>(
                  initialValue: method,
                  decoration: const InputDecoration(labelText: '请求方式'),
                  items: BalanceRequestMethod.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.name.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => method = value);
                  },
                ),
                _field(body, 'JSON 请求体（仅 POST）', maxLines: 3),
                _field(headers, '自定义 Headers JSON', maxLines: 3),
                _field(balancePath, '余额 JSON Path'),
                _field(dailyPath, '今日用量 JSON Path（可选）'),
                _field(monthlyPath, '本月用量 JSON Path（可选）'),
              ],
            ),
            if (result != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  result!,
                  style: TextStyle(
                    color: result == '验证成功'
                        ? AppThemeTokens.of(context).success
                        : AppThemeTokens.of(context).error,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      OutlinedButton(
        onPressed: validating ? null : _validate,
        child: validating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('验证'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Future<void> _validate() async {
    setState(() => validating = true);
    final error = await widget.controller.validate(config);
    if (mounted) {
      setState(() {
        validating = false;
        result = error ?? '验证成功';
      });
    }
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty || baseUrl.text.trim().isEmpty) {
      setState(() => result = '请填写显示名称和 Base URL');
      return;
    }
    if (!isValidBaseUrl(baseUrl.text)) {
      setState(() => result = 'Base URL 必须是带非空域名的完整 HTTP 或 HTTPS 地址');
      return;
    }
    if (rechargeUrl.text.trim().isNotEmpty &&
        !isValidRechargeUrl(rechargeUrl.text)) {
      setState(() => result = '充值/余额管理地址必须是完整的 HTTP 或 HTTPS 地址');
      return;
    }
    if (lowBalanceThreshold.text.trim().isNotEmpty &&
        _parsedLowBalanceThreshold == null) {
      setState(() => result = '低余额阈值必须是大于或等于 0 的有限数字');
      return;
    }
    await widget.controller.saveProvider(config);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  double? get _parsedLowBalanceThreshold {
    final input = lowBalanceThreshold.text.trim();
    if (input.isEmpty) return null;
    final value = double.tryParse(input);
    return value != null && value.isFinite && value >= 0 ? value : null;
  }
}
