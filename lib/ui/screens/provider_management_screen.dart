import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/provider_config.dart';
import '../../models/web_billing_config.dart';
import '../../services/curl_bash_importer.dart';
import '../../services/hermes_provider_importer.dart';
import '../../services/web_billing_expression.dart';
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
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'OpenAI 兼容 /v1 服务商',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _importHermes(context),
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('从 Hermes 导入'),
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
    ),
  );

  Future<void> _importHermes(BuildContext context) async {
    HermesImportPlan plan;
    try {
      plan = await controller.readHermesImportPlan();
    } on HermesImportException catch (error) {
      if (context.mounted) _message(context, error.message);
      return;
    } catch (_) {
      if (context.mounted) _message(context, '读取 Hermes 配置失败。');
      return;
    }
    if (!context.mounted) return;
    if (plan.providers.isEmpty) {
      _message(context, 'Hermes 配置中没有可导入的服务商。');
      return;
    }
    final existingIds = controller.configs.map((item) => item.id).toSet();
    final updates = plan.providers
        .where((item) => existingIds.contains(item.config.id))
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 Hermes 导入服务商？'),
        content: Text(
          '将导入 ${plan.providers.length} 个服务商，其中 $updates 个会更新同 ID 的现有配置；不会删除手动配置。API Key 仅写入 Windows 安全存储。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.importHermesProviders(plan);
      if (context.mounted) {
        _message(
          context,
          '已导入 ${plan.providers.length} 个 Hermes 服务商（$updates 个已更新）。',
        );
      }
    } catch (_) {
      if (context.mounted) _message(context, '导入失败：无法安全保存一个或多个 API Key。');
    }
  }

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

  void _edit(BuildContext context, [ProviderConfig? initial]) =>
      showDialog<void>(
        context: context,
        builder: (_) =>
            ProviderEditorDialog(controller: controller, initial: initial),
      );
  void _message(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
  static const _apiKeyVariableName = 'API_KEY';
  static const _apiKeyVariableDisplayName = 'API Key';
  static const List<String> _requestSystemVariables = [
    'CURRENT_YEAR',
    'CURRENT_MONTH',
    'CURRENT_DAY',
    'CURRENT_DATE',
    'MONTH_START_DATE',
    'DAY_START_UNIX',
    'DAY_END_UNIX',
    'MONTH_START_UNIX',
    'MONTH_END_UNIX',
    'DAY_START_UNIX_MS',
    'DAY_END_UNIX_MS',
    'MONTH_START_UNIX_MS',
    'MONTH_TO_DATE_END_UNIX_MS',
    'UTC_DAY_START_UNIX',
    'UTC_DAY_END_UNIX',
    'UTC_MONTH_START_UNIX',
    'UTC_MONTH_TO_DATE_END_UNIX',
    'UTC_CURRENT_YEAR',
    'UTC_CURRENT_MONTH',
    'UTC_CURRENT_DAY',
    'UTC_CURRENT_DATE',
    'UTC_MONTH_START_DATE',
    'CURRENT_UNIX',
    'CURRENT_UNIX_MS',
    'UTC_CURRENT_UNIX',
    'UTC_CURRENT_UNIX_MS',
    'TZ_HOURS',
  ];

  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final baseUrl = TextEditingController(
    text: widget.initial?.baseUrl ?? '',
  );
  late final model = TextEditingController(
    text: widget.initial?.defaultModel ?? '',
  );
  late final rechargeUrl = TextEditingController(
    text: widget.initial?.rechargeUrl ?? '',
  );
  late final lowBalanceThreshold = TextEditingController(
    text: widget.initial?.lowBalanceThreshold?.toString() ?? '',
  );
  final List<_VariableEditor> variables = [];
  final Map<String, String> _secretCandidates = {};
  late final Map<WebBillingMetricKind, _CurlImportEditor> _curlImports;
  final Map<String, _MetricRuleEditor> _metricEditors = {};
  final Map<String, _RequestTemplateEditor> _requestEditors = {};
  late WebBillingConfig web;
  bool validating = false;
  String? result;

  @override
  void initState() {
    super.initState();
    web =
        widget.initial?.webBillingConfig ??
        const WebBillingConfig(schemaVersion: 1);
    _syncVariables(_definitionsWithApiKey(web.secretVariableDefinitions));
    _apiKeyEditor.saved = widget.initial?.apiKey.isNotEmpty == true;
    _loadSecretMasks();
    _syncMetricEditors();
    _syncRequestEditors();
    _curlImports = {
      for (final kind in WebBillingMetricKind.values) kind: _CurlImportEditor(),
    };
  }

  Future<void> _loadSecretMasks() async {
    final providerId = widget.initial?.id;
    if (providerId == null || providerId.isEmpty) return;
    final genericMasks = await widget.controller
        .providerWebBillingVariableMasks(
          providerId,
          web.secretVariableDefinitions.map((definition) => definition.name),
        );
    final apiKeyMask = await widget.controller.providerApiKeyMask(providerId);
    if (!mounted) return;
    setState(() {
      for (final variable in variables) {
        final mask = variable.isApiKey
            ? apiKeyMask
            : genericMasks[variable.name.text];
        if (mask != null) variable.showSavedMask(mask);
      }
      // A legacy hydrated key can reside in the model temporarily. Derive a
      // mask only; never put that key into a UI controller.
      final legacyApiKey = widget.initial?.apiKey;
      if (_apiKeyEditor.value.text.isEmpty &&
          legacyApiKey?.isNotEmpty == true) {
        _apiKeyEditor.showSavedMask('•' * legacyApiKey!.length.clamp(0, 256));
      }
    });
  }

  void _syncVariables(List<SecretVariableDefinition> definitions) {
    final previous = {for (final editor in variables) editor.name.text: editor};
    for (final editor in variables) {
      if (!definitions.any(
        (definition) => definition.name == editor.name.text,
      )) {
        editor.dispose();
      }
    }
    variables
      ..clear()
      ..addAll(
        definitions.map(
          (definition) =>
              previous[definition.name] ?? _VariableEditor(definition),
        ),
      );
  }

  List<SecretVariableDefinition> _definitionsWithApiKey(
    List<SecretVariableDefinition> definitions,
  ) => [
    if (!definitions.any(
      (definition) => definition.name == _apiKeyVariableName,
    ))
      const SecretVariableDefinition(
        id: 'api_key',
        name: _apiKeyVariableName,
        displayName: _apiKeyVariableDisplayName,
        type: SecretVariableType.bearerToken,
        required: true,
      ),
    ...definitions,
  ];

  void _syncMetricEditors() {
    final nextIds = web.metricRules.map((rule) => rule.id).toSet();
    final removed = _metricEditors.keys
        .where((id) => !nextIds.contains(id))
        .toList();
    for (final id in removed) {
      _metricEditors.remove(id)?.dispose();
    }
    for (final rule in web.metricRules) {
      _metricEditors.putIfAbsent(
        rule.id,
        () => _MetricRuleEditor.fromRule(rule),
      );
    }
  }

  void _syncRequestEditors() {
    final nextIds = web.requestTemplates.map((request) => request.id).toSet();
    final removed = _requestEditors.keys
        .where((id) => !nextIds.contains(id))
        .toList();
    for (final id in removed) {
      _requestEditors.remove(id)?.dispose();
    }
    for (final request in web.requestTemplates) {
      _requestEditors.putIfAbsent(
        request.id,
        () => _RequestTemplateEditor.fromRequest(request),
      );
    }
  }

  ProviderConfig get config => ProviderConfig(
    id: widget.initial?.id ?? '',
    name: name.text.trim(),
    colorValue: widget.initial?.colorValue ?? 0xff39c5bb,
    order: widget.initial?.order ?? 0,
    enabled: widget.initial?.enabled ?? true,
    baseUrl: baseUrl.text.trim(),
    apiKey: _apiKeyEditor.submittedValue,
    defaultModel: model.text.trim(),
    rechargeUrl: rechargeUrl.text.trim(),
    lowBalanceThreshold: parseLowBalanceThreshold(lowBalanceThreshold.text),
    webBillingConfig: web,
  );

  _VariableEditor get _apiKeyEditor =>
      variables.firstWhere((variable) => variable.isApiKey);

  @override
  void dispose() {
    for (final controller in [
      name,
      baseUrl,
      model,
      rechargeUrl,
      lowBalanceThreshold,
    ]) {
      controller.dispose();
    }
    for (final import in _curlImports.values) {
      import.dispose();
    }
    for (final editor in _metricEditors.values) {
      editor.dispose();
    }
    for (final editor in _requestEditors.values) {
      editor.dispose();
    }
    for (final variable in variables) {
      variable.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(widget.initial == null ? '添加服务商' : '编辑服务商'),
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('基本服务商设置'),
              _field(name, '显示名称'),
              _field(baseUrl, 'OpenAI Base URL（自动规范化为 /v1）'),
              _field(model, '默认模型（可选）'),
              _field(rechargeUrl, '充值/余额管理地址（可选）'),
              _field(
                lowBalanceThreshold,
                '低余额阈值（元，可选）',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 4),
              const _SectionTitle('通用网页账单'),
              for (final kind in WebBillingMetricKind.values) ...[
                _metricSection(kind),
                const SizedBox(height: 16),
              ],
              _variableSection(),
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

  Widget _metricSection(WebBillingMetricKind kind) {
    final import = _curlImports[kind]!;
    final draft = import.result?.draft;
    final rule = _ruleFor(kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_kindLabel(kind)} ${_englishKindLabel(kind)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(rule == null ? '未配置' : '已配置'),
                const SizedBox(height: 8),
                _field(
                  import.source,
                  '粘贴浏览器复制的 cURL bash',
                  key: ValueKey('curl-source-${kind.name}'),
                  maxLines: 4,
                  helperText: '解析后仅保留安全的请求模板；原始密钥不会出现在预览或配置中。',
                ),
                OutlinedButton(
                  key: ValueKey('parse-curl-${kind.name}'),
                  onPressed: () => _parseCurl(kind),
                  child: const Text('解析 cURL'),
                ),
                if (import.result?.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('解析失败：${_safeError(import.result!.error!)}'),
                  ),
                if (draft != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '安全预览：${draft.requestTemplate.method} ${draft.requestTemplate.urlTemplate}',
                  ),
                  Text(
                    '非敏感 Headers：${draft.requestTemplate.headersTemplate.keys.isEmpty ? '无' : draft.requestTemplate.headersTemplate.keys.join('、')}',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      key: ValueKey('apply-curl-${kind.name}'),
                      onPressed: () => _applyCurlImport(kind),
                      child: const Text('应用导入模板'),
                    ),
                  ),
                ],
                if (rule != null) _metricEditor(rule),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _variableSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _SectionTitle('安全变量'),
      const Text(
        '变量值仅写入安全存储，不会保存到配置 JSON。',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _addVariable,
          icon: const Icon(Icons.add),
          label: const Text('添加安全变量'),
        ),
      ),
      for (final variable in variables) _variableFields(variable),
    ],
  );

  Widget _variableFields(_VariableEditor variable) => Card(
    key: ValueKey('variable-${variable.original.id}-${variable.name.text}'),
    margin: const EdgeInsets.only(top: 10),
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (variable.isApiKey)
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _apiKeyVariableDisplayName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 2),
                Text(
                  '变量名：API_KEY',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  r'请求中请使用 ${API_KEY}。API Key 只是显示名称。',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                SizedBox(height: 8),
              ],
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: ValueKey('delete-variable-${variable.original.id}'),
                onPressed: () => _deleteVariable(variable),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除安全变量'),
              ),
            ),
            const SizedBox(height: 12),
            _field(variable.displayName, '变量显示名称'),
            _field(variable.name, '变量名（A-Z、0-9、_）'),
            DropdownButtonFormField<SecretVariableType>(
              initialValue: variable.type,
              decoration: const InputDecoration(labelText: '变量类型'),
              items: SecretVariableType.values
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => variable.type = value);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('必填'),
              value: variable.required,
              onChanged: (value) => setState(() => variable.required = value),
            ),
          ],
          ListenableBuilder(
            listenable: variable.focusNode,
            builder: (context, _) {
              final isEmptyAndUnfocused =
                  variable.value.text.isEmpty &&
                  !variable.focusNode.hasFocus &&
                  !variable.saved;
              return _field(
                variable.value,
                '安全变量值',
                obscure: true,
                focusNode: variable.focusNode,
                labelStyle: isEmptyAndUnfocused
                    ? const TextStyle(color: Color(0x59000000), fontSize: 10)
                    : null,
                helperText: variable.saved
                    ? '已安全保存；输入新值才替换'
                    : variable.focusNode.hasFocus
                    ? null
                    : '尚未填写安全变量值',
                helperStyle: variable.saved
                    ? const TextStyle(color: Color(0x8A000000), fontSize: 11)
                    : const TextStyle(color: Color(0x59000000), fontSize: 10),
                onTap: variable.selectSavedMask,
                onChanged: variable.markEdited,
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _metricEditor(MetricRule rule) {
    final matchingRequests = web.requestTemplates
        .where((item) => item.id == rule.requestTemplateId)
        .toList();
    final request = matchingRequests.isEmpty ? null : matchingRequests.first;
    final editor = _metricEditors.putIfAbsent(
      rule.id,
      () => _MetricRuleEditor.fromRule(rule),
    );
    final requestEditor = request == null
        ? null
        : _requestEditors.putIfAbsent(
            request.id,
            () => _RequestTemplateEditor.fromRequest(request),
          );
    return Card(
      key: ValueKey('metric-rule-${rule.id}'),
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _kindLabel(rule.kind),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            if ((request, requestEditor) case (
              final request?,
              final requestEditor?,
            )) ...[
              const Text(
                '最终请求模板',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _field(
                requestEditor.method,
                '请求方法',
                key: ValueKey('request-method-${request.id}'),
                onChanged: (_) => _replaceRequest(request, requestEditor),
              ),
              _field(
                requestEditor.url,
                'URL 模板',
                key: ValueKey('request-url-${request.id}'),
                onChanged: (_) => _replaceRequest(request, requestEditor),
              ),
              _field(
                requestEditor.query,
                'Query 参数模板（JSON）',
                key: ValueKey('request-query-${request.id}'),
                maxLines: 4,
                helperText: '请输入 JSON 对象，值可保留变量占位符。',
                onChanged: (_) => _replaceRequest(request, requestEditor),
              ),
              _field(
                requestEditor.headers,
                'Headers 模板（JSON）',
                key: ValueKey('request-headers-${request.id}'),
                maxLines: 4,
                helperText: '请输入 JSON 对象，值可保留变量占位符。',
                onChanged: (_) => _replaceRequest(request, requestEditor),
              ),
              _field(
                requestEditor.body,
                'Body 模板',
                key: ValueKey('request-body-${request.id}'),
                maxLines: 4,
                onChanged: (_) => _replaceRequest(request, requestEditor),
              ),
              Text('变量：${_variablesFor(request).join('、').ifEmpty('无')}'),
            ] else
              const Text('未找到请求模板'),
            const SizedBox(height: 12),
            _field(
              editor.processingExpression,
              '数据处理',
              key: ValueKey('metric-processing-${rule.id}'),
              maxLines: 3,
              onChanged: (_) => _replaceRule(
                rule,
                processingExpression: editor.processingExpression.text,
              ),
            ),
            DropdownButtonFormField<MetricFailureDisplay>(
              key: ValueKey('metric-failure-display-${rule.kind.name}'),
              initialValue: _displayFor(rule.kind),
              decoration: const InputDecoration(labelText: '请求失败时显示'),
              items: MetricFailureDisplay.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_displayLabel(value)),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(
                    () => web = _copyWeb(
                      displayPolicy: _replaceDisplay(rule.kind, value),
                    ),
                  );
                }
              },
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '表达式的最终数值即显示结果。',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text('示例：data.balance'),
                  Text('示例：sum(data.items[*].cost) / 1000000'),
                  Text('示例：(sum(rows[*].amount) + 5) / 100'),
                  SizedBox(height: 6),
                  Text('允许语法：JSON 路径、sum(...)、数字、+ - * /、括号'),
                  Text('这是安全受限表达式，不是 JS/Python。'),
                ],
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 12),
              title: const Text('可用时间变量'),
              subtitle: const Text(
                '可写在请求 URL / query / header / body 中，例如 \${CURRENT_DATE}',
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final name in _requestSystemVariables)
                        Text('\${$name}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _replaceRule(MetricRule old, {required String processingExpression}) {
    setState(() {
      web = _copyWeb(
        metricRules: [
          for (final rule in web.metricRules)
            if (rule.id == old.id)
              MetricRule(
                id: rule.id,
                kind: rule.kind,
                requestTemplateId: rule.requestTemplateId,
                responseRule: rule.responseRule,
                processingExpression: processingExpression,
                multiplier: rule.multiplier,
                divisor: rule.divisor,
                unit: rule.unit,
              )
            else
              rule,
        ],
      );
      _syncMetricEditors();
    });
  }

  Map<String, String>? _stringMapFromJson(String source) {
    try {
      final decoded = jsonDecode(source.trim().isEmpty ? '{}' : source);
      if (decoded is! Map) return null;
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on FormatException {
      return null;
    }
  }

  void _replaceRequest(RequestTemplate old, _RequestTemplateEditor editor) {
    final query = _stringMapFromJson(editor.query.text);
    final headers = _stringMapFromJson(editor.headers.text);
    if (query == null || headers == null) return;
    setState(() {
      web = _copyWeb(
        requests: [
          for (final request in web.requestTemplates)
            if (request.id == old.id)
              RequestTemplate(
                id: request.id,
                method: editor.method.text.trim(),
                urlTemplate: editor.url.text.trim(),
                queryTemplate: query,
                headersTemplate: headers,
                bodyTemplate: editor.body.text,
                successRule: request.successRule,
              )
            else
              request,
        ],
      );
      _syncRequestEditors();
    });
  }

  WebBillingConfig _copyWeb({
    List<MetricRule>? metricRules,
    List<RequestTemplate>? requests,
    List<SecretVariableDefinition>? definitions,
    DisplayPolicy? displayPolicy,
  }) => WebBillingConfig(
    schemaVersion: web.schemaVersion,
    requestTemplates: requests ?? web.requestTemplates,
    secretVariableDefinitions: definitions ?? web.secretVariableDefinitions,
    metricRules: metricRules ?? web.metricRules,
    displayPolicy: displayPolicy ?? web.displayPolicy,
    source: web.source,
    migrationMetadata: web.migrationMetadata,
  );
  MetricFailureDisplay _displayFor(WebBillingMetricKind kind) => switch (kind) {
    WebBillingMetricKind.balance => web.displayPolicy.balance,
    WebBillingMetricKind.daily => web.displayPolicy.daily,
    WebBillingMetricKind.monthly => web.displayPolicy.monthly,
  };
  DisplayPolicy _replaceDisplay(
    WebBillingMetricKind kind,
    MetricFailureDisplay value,
  ) => DisplayPolicy(
    balance: kind == WebBillingMetricKind.balance
        ? value
        : web.displayPolicy.balance,
    daily: kind == WebBillingMetricKind.daily ? value : web.displayPolicy.daily,
    monthly: kind == WebBillingMetricKind.monthly
        ? value
        : web.displayPolicy.monthly,
  );

  MetricRule? _ruleFor(WebBillingMetricKind kind) {
    for (final rule in web.metricRules) {
      if (rule.kind == kind) return rule;
    }
    return null;
  }

  void _parseCurl(WebBillingMetricKind kind) {
    final editor = _curlImports[kind]!;
    final parsed = const CurlBashImporter().parse(editor.source.text);
    setState(() {
      editor.result = parsed;
      if (parsed.draft != null) {
        _mergeVariables(parsed.draft!.secretVariableDefinitions);
      }
    });
    if (parsed.draft != null) editor.source.clear();
  }

  void _applyCurlImport(WebBillingMetricKind kind) {
    final parsed = _curlImports[kind]!.result;
    final draft = parsed?.draft;
    if (draft == null || parsed == null) return;
    final names = variables.map((item) => item.name.text.trim()).toList();
    if (names.any((name) => !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(name)) ||
        names.toSet().length != names.length) {
      setState(() => result = '变量名必须符合 [A-Z][A-Z0-9_]* 且在配置内唯一');
      return;
    }
    final originals = {for (final item in variables) item.original.name: item};
    String rename(String value) => value.replaceAllMapped(
      RegExp(r'\$\{([A-Z][A-Z0-9_]*)\}'),
      (match) =>
          '\${${originals[match.group(1)]?.name.text.trim() ?? match.group(1)!}}',
    );
    for (final candidate in parsed.secretValueCandidates) {
      final variableName =
          originals[candidate.variableName]?.name.text.trim() ??
          candidate.variableName;
      if (variableName == _apiKeyVariableName) {
        if (!_apiKeyEditor.saved && !_apiKeyEditor.userEdited) {
          _apiKeyEditor.pendingValue = candidate.value;
          _apiKeyEditor.showSavedMask(
            '•' * candidate.value.length.clamp(0, 256),
          );
        }
      } else {
        _secretCandidates[variableName] = candidate.value;
        final editor = variables.where(
          (item) => item.name.text.trim() == variableName,
        );
        if (editor.isNotEmpty) {
          editor.first.pendingValue = candidate.value;
          editor.first.showSavedMask(
            '•' * candidate.value.length.clamp(0, 256),
          );
        }
      }
    }
    final requestId =
        'imported-${kind.name}-${DateTime.now().microsecondsSinceEpoch}';
    final request = RequestTemplate(
      id: requestId,
      method: draft.requestTemplate.method,
      urlTemplate: rename(draft.requestTemplate.urlTemplate),
      queryTemplate: draft.requestTemplate.queryTemplate.map(
        (key, value) => MapEntry(key, rename(value)),
      ),
      headersTemplate: draft.requestTemplate.headersTemplate.map(
        (key, value) => MapEntry(key, rename(value)),
      ),
      bodyTemplate: draft.requestTemplate.bodyTemplate == null
          ? null
          : rename(draft.requestTemplate.bodyTemplate!),
    );
    final definitions = variables
        .map(
          (item) => SecretVariableDefinition(
            id: item.name.text.trim().toLowerCase(),
            name: item.name.text.trim(),
            displayName: item.displayName.text.trim().isEmpty
                ? item.name.text.trim()
                : item.displayName.text.trim(),
            type: item.type,
            required: item.required,
          ),
        )
        .toList();
    for (final item in variables.where((item) => !item.isApiKey)) {
      if (item.userEdited && item.value.text.isNotEmpty) {
        _secretCandidates[item.name.text.trim()] = item.value.text;
      }
      item.saved = item.userEdited && item.value.text.isNotEmpty || item.saved;
    }
    setState(() {
      final replacedIds = web.metricRules
          .where((rule) => rule.kind == kind)
          .map((rule) => rule.requestTemplateId)
          .toSet();
      final remainingRules = web.metricRules
          .where((rule) => rule.kind != kind)
          .toList();
      final stillUsedIds = remainingRules
          .map((rule) => rule.requestTemplateId)
          .toSet();
      web = _copyWeb(
        requests: [
          ...web.requestTemplates.where(
            (request) =>
                !replacedIds.contains(request.id) ||
                stillUsedIds.contains(request.id),
          ),
          request,
        ],
        definitions: definitions,
        metricRules: [
          ...remainingRules,
          MetricRule(
            id: 'imported-${kind.name}',
            kind: kind,
            requestTemplateId: requestId,
            responseRule: const ResponseRule(scalarPath: ''),
          ),
        ],
      );
      _syncMetricEditors();
      _syncRequestEditors();
      result = '已应用通用账单模板；可在下方编辑请求、解析、缩放和显示策略。';
    });
  }

  void _mergeVariables(List<SecretVariableDefinition> discovered) {
    final byName = {for (final item in variables) item.name.text.trim(): item};
    for (final definition in discovered) {
      final existing = byName[definition.name];
      if (existing == null) {
        variables.add(_VariableEditor(definition));
      } else if (existing.displayName.text.trim().isEmpty) {
        existing.displayName.text = definition.displayName;
        existing.type = definition.type;
        existing.required = definition.required;
      }
    }
  }

  void _addVariable() {
    final names = variables.map((item) => item.name.text.trim()).toSet();
    var index = 0;
    var next = 'NEW_VARIABLE';
    while (names.contains(next)) {
      index++;
      next = 'NEW_VARIABLE_$index';
    }
    setState(
      () => variables.add(
        _VariableEditor(
          SecretVariableDefinition(
            id: next.toLowerCase(),
            name: next,
            displayName: next,
            type: SecretVariableType.genericHeaderValue,
            required: false,
          ),
        ),
      ),
    );
  }

  void _deleteVariable(_VariableEditor variable) {
    final variableName = variable.name.text.trim();
    if (variable.isApiKey || variableName == _apiKeyVariableName) return;
    final isReferenced =
        web.requestTemplates.any(
          (request) => _variablesFor(request).contains(variableName),
        ) ||
        _requestEditors.values.any(
          (editor) =>
              [
                editor.url.text,
                editor.query.text,
                editor.headers.text,
                editor.body.text,
              ].any(
                (template) => RegExp(
                  r'\$\{' + RegExp.escape(variableName) + r'\}',
                ).hasMatch(template),
              ),
        );
    if (isReferenced) {
      setState(() => result = '无法删除安全变量 $variableName：它仍被请求模板使用。');
      return;
    }
    setState(() {
      variables.remove(variable);
      variable.dispose();
      _secretCandidates.remove(variableName);
      web = _copyWeb(
        definitions: web.secretVariableDefinitions
            .where((definition) => definition.name != variableName)
            .toList(),
      );
      result = null;
    });
  }

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
        parseLowBalanceThreshold(lowBalanceThreshold.text) == null) {
      setState(() => result = '低余额阈值必须是大于或等于 0 的有限数字');
      return;
    }
    final names = variables.map((item) => item.name.text.trim()).toList();
    if (names.any((name) => !RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(name)) ||
        names.toSet().length != names.length) {
      setState(() => result = '变量名必须符合 [A-Z][A-Z0-9_]* 且在配置内唯一');
      return;
    }
    for (final request in web.requestTemplates) {
      final editor = _requestEditors[request.id];
      if (editor == null ||
          _stringMapFromJson(editor.query.text) == null ||
          _stringMapFromJson(editor.headers.text) == null) {
        setState(() => result = 'Query 参数模板和 Headers 模板必须是 JSON 对象');
        return;
      }
      _replaceRequest(request, editor);
    }
    final requestVariableError = _requestVariableValidationError();
    if (requestVariableError != null) {
      setState(() => result = requestVariableError);
      return;
    }
    for (final rule in web.metricRules) {
      final expression = rule.processingExpression?.trim() ?? '';
      if (expression.isEmpty) continue;
      if (!_isValidProcessingExpression(expression)) {
        setState(() => result = '数据处理表达式无效，请检查语法后再保存');
        return;
      }
    }
    for (final item in variables.where((item) => !item.isApiKey)) {
      if (item.userEdited && item.value.text.isNotEmpty) {
        _secretCandidates[item.name.text.trim()] = item.value.text;
      }
    }
    web = _copyWeb(definitions: _definitionsFromVariables());
    await widget.controller.saveProvider(
      config,
      webBillingSecretCandidates: _secretCandidates,
    );
    if (mounted) Navigator.pop(context);
  }

  bool _isValidProcessingExpression(String expression) {
    final sumsNormalised = expression.replaceAllMapped(
      RegExp(r'sum\s*\([^)]*\)'),
      (_) => 'sum(values[*])',
    );
    final source = sumsNormalised.replaceAllMapped(
      RegExp(
        r'\$?[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[(?:\*|[0-9]+)\])*',
      ),
      (match) => switch (match.group(0)) {
        'sum' || 'values[*]' => match.group(0)!,
        _ => '1',
      },
    );
    try {
      WebBillingExpression.evaluate(source, {
        'values': [1],
      });
      return true;
    } on WebBillingExpressionException {
      return false;
    }
  }

  String? _requestVariableValidationError() {
    final definedNames = {
      ...variables.map((item) => item.name.text.trim()),
      ..._requestSystemVariables,
    };
    for (final editor in _requestEditors.values) {
      for (final template in [
        editor.url.text,
        editor.query.text,
        editor.headers.text,
        editor.body.text,
      ]) {
        for (final match in RegExp(r'\$\{([^}]*)\}').allMatches(template)) {
          final variableName = match.group(1)!;
          if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(variableName)) {
            return r'请求占位符变量名只能包含字母、数字和下划线；模型 API Key 请使用 ${API_KEY}';
          }
          if (!definedNames.contains(variableName)) {
            return '未定义请求变量：$variableName';
          }
        }
      }
    }
    return null;
  }

  List<SecretVariableDefinition> _definitionsFromVariables() => variables
      .map(
        (item) => SecretVariableDefinition(
          id: item.name.text.trim().toLowerCase(),
          name: item.name.text.trim(),
          displayName: item.displayName.text.trim().isEmpty
              ? item.name.text.trim()
              : item.displayName.text.trim(),
          type: item.type,
          required: item.required,
        ),
      )
      .toList();

  Widget _field(
    TextEditingController controller,
    String label, {
    Key? key,
    bool obscure = false,
    int maxLines = 1,
    String? helperText,
    String? hintText,
    TextStyle? labelStyle,
    TextStyle? hintStyle,
    TextStyle? helperStyle,
    FocusNode? focusNode,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
    TextInputType? keyboardType,
  }) => _ProviderTextField(
    key: ObjectKey(controller),
    fieldKey: key,
    controller: controller,
    label: label,
    obscure: obscure,
    maxLines: maxLines,
    helperText: helperText,
    hintText: hintText,
    labelStyle: labelStyle,
    hintStyle: hintStyle,
    helperStyle: helperStyle,
    focusNode: focusNode,
    onTap: onTap,
    onChanged: onChanged,
    keyboardType: keyboardType,
  );
  static String _kindLabel(WebBillingMetricKind kind) => switch (kind) {
    WebBillingMetricKind.balance => '余额',
    WebBillingMetricKind.daily => '今日',
    WebBillingMetricKind.monthly => '本月',
  };
  static String _englishKindLabel(WebBillingMetricKind kind) => switch (kind) {
    WebBillingMetricKind.balance => 'Balance',
    WebBillingMetricKind.daily => 'Today',
    WebBillingMetricKind.monthly => 'Month',
  };
  static String _displayLabel(MetricFailureDisplay value) => switch (value) {
    MetricFailureDisplay.hide => '隐藏',
    MetricFailureDisplay.showCached => '显示缓存值',
    MetricFailureDisplay.estimateFallback => '显示估算值',
  };
  static String _safeError(String value) =>
      value.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
  static List<String> _variablesFor(RequestTemplate? request) {
    if (request == null) return const [];
    final text = [
      request.urlTemplate,
      ...request.queryTemplate.values,
      ...request.headersTemplate.values,
      request.bodyTemplate ?? '',
    ].join(' ');
    return RegExp(
      r'\$\{([A-Z][A-Z0-9_]*)\}',
    ).allMatches(text).map((match) => match.group(1)!).toSet().toList();
  }
}

class _ProviderTextField extends StatefulWidget {
  const _ProviderTextField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.obscure,
    required this.maxLines,
    this.helperText,
    this.hintText,
    this.labelStyle,
    this.hintStyle,
    this.helperStyle,
    this.focusNode,
    this.onTap,
    this.onChanged,
    this.keyboardType,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final int maxLines;
  final String? helperText;
  final String? hintText;
  final TextStyle? labelStyle;
  final TextStyle? hintStyle;
  final TextStyle? helperStyle;
  final FocusNode? focusNode;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  State<_ProviderTextField> createState() => _ProviderTextFieldState();
}

class _ProviderTextFieldState extends State<_ProviderTextField> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) _ownedFocusNode = FocusNode();
    _focusNode.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(_ProviderTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocusNode)?.removeListener(_refresh);
      _ownedFocusNode?.dispose();
      _ownedFocusNode = widget.focusNode == null ? FocusNode() : null;
      _focusNode.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    _focusNode.removeListener(_refresh);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isEmptyAndUnfocused =
        widget.controller.text.isEmpty && !_focusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        obscureText: widget.obscure,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        focusNode: _focusNode,
        onTap: widget.onTap,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle:
              widget.labelStyle ??
              (isEmptyAndUnfocused
                  ? const TextStyle(color: Color(0x59000000), fontSize: 10)
                  : null),
          helperText: widget.helperText,
          hintText: _focusNode.hasFocus ? null : widget.hintText,
          hintStyle:
              widget.hintStyle ??
              TextStyle(
                color: Theme.of(context).hintColor.withValues(alpha: 0.65),
                fontSize: 12,
              ),
          helperStyle:
              widget.helperStyle ??
              TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}

class _CurlImportEditor {
  final source = TextEditingController();
  CurlParseResult? result;
  void dispose() => source.dispose();
}

class _VariableEditor {
  _VariableEditor(this.original)
    : displayName = TextEditingController(text: original.displayName),
      name = TextEditingController(text: original.name),
      value = TextEditingController();
  final SecretVariableDefinition original;
  final TextEditingController displayName;
  final TextEditingController name;
  final TextEditingController value;
  final FocusNode focusNode = FocusNode();
  late SecretVariableType type = original.type;
  late bool required = original.required;
  bool saved = false;
  bool userEdited = false;
  String pendingValue = '';
  String get submittedValue => userEdited ? value.text.trim() : pendingValue;
  void showSavedMask(String mask) {
    saved = true;
    if (!userEdited) value.text = mask;
  }

  void selectSavedMask() {
    if (saved && !userEdited) {
      value.selection = TextSelection(
        baseOffset: 0,
        extentOffset: value.text.length,
      );
    }
  }

  void markEdited(String _) {
    userEdited = true;
    pendingValue = '';
  }

  bool get isApiKey => original.name == 'API_KEY';
  void dispose() {
    focusNode.dispose();
    displayName.dispose();
    name.dispose();
    value.dispose();
  }
}

class _MetricRuleEditor {
  _MetricRuleEditor({required String processingExpression})
    : processingExpression = TextEditingController(text: processingExpression);

  factory _MetricRuleEditor.fromRule(MetricRule rule) => _MetricRuleEditor(
    processingExpression: rule.processingExpression?.trim().isNotEmpty == true
        ? rule.processingExpression!.trim()
        : _legacyProcessingExpression(rule),
  );

  final TextEditingController processingExpression;

  static String _legacyProcessingExpression(MetricRule rule) {
    final response = rule.responseRule;
    String? base;
    if (response.aggregation == ResponseAggregation.none) {
      base = response.scalarPath.trim();
    } else if (response.aggregation == ResponseAggregation.sum) {
      final combined = _composeSumPath(
        response.itemPath?.trim() ?? '',
        response.scalarPath.trim(),
      );
      if (combined != null) base = 'sum($combined)';
    }
    if (base == null || base.isEmpty) return '';
    final parts = <String>[base];
    if (rule.multiplier != 1) {
      parts.add('* ${_ProviderEditorDialogState._number(rule.multiplier)}');
    }
    if (rule.divisor != 1) {
      parts.add('/ ${_ProviderEditorDialogState._number(rule.divisor)}');
    }
    return parts.join(' ');
  }

  static String? _composeSumPath(String itemPath, String scalarPath) {
    if (itemPath.isEmpty) return null;
    if (scalarPath.isEmpty) return itemPath;
    final scalarIsSafe = RegExp(
      r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*|\[[0-9]+\])*$',
    ).hasMatch(scalarPath);
    if (!scalarIsSafe) return null;
    return itemPath.endsWith('.')
        ? '$itemPath$scalarPath'
        : '$itemPath.$scalarPath';
  }

  void dispose() => processingExpression.dispose();
}

class _RequestTemplateEditor {
  _RequestTemplateEditor({
    required String method,
    required String url,
    required String query,
    required String headers,
    required String body,
  }) : method = TextEditingController(text: method),
       url = TextEditingController(text: url),
       query = TextEditingController(text: query),
       headers = TextEditingController(text: headers),
       body = TextEditingController(text: body);

  factory _RequestTemplateEditor.fromRequest(RequestTemplate request) =>
      _RequestTemplateEditor(
        method: request.method,
        url: request.urlTemplate,
        query: const JsonEncoder.withIndent(
          '  ',
        ).convert(request.queryTemplate),
        headers: const JsonEncoder.withIndent(
          '  ',
        ).convert(request.headersTemplate),
        body: request.bodyTemplate ?? '',
      );

  final TextEditingController method;
  final TextEditingController url;
  final TextEditingController query;
  final TextEditingController headers;
  final TextEditingController body;

  void dispose() {
    method.dispose();
    url.dispose();
    query.dispose();
    headers.dispose();
    body.dispose();
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
