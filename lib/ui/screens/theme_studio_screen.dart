import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/custom_theme.dart';
import '../../models/provider_view_state.dart';
import '../../state/battery_controller.dart';
import '../theme/app_theme_tokens.dart';
import '../theme/resolved_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/provider_card.dart';

typedef ThemeBackgroundPicker = Future<XFile?> Function();
typedef ThemePackagePicker = Future<XFile?> Function();
typedef ThemePackageImportAction =
    Future<CustomTheme> Function(File packageFile);
typedef ThemePackageSavePicker =
    Future<FileSaveLocation?> Function(String suggestedName);
typedef ThemePackageExportAction =
    Future<void> Function(CustomTheme theme, File destination);

/// GUI-first editor for a single, unsaved custom-theme draft.
class ThemeStudioScreen extends StatefulWidget {
  const ThemeStudioScreen({
    super.key,
    required this.controller,
    this.backgroundPicker,
    this.themePackagePicker,
    this.themePackageImportAction,
    this.themePackageSavePicker,
    this.themePackageExportAction,
  });

  final BatteryController controller;
  final ThemeBackgroundPicker? backgroundPicker;
  final ThemePackagePicker? themePackagePicker;
  final ThemePackageImportAction? themePackageImportAction;
  final ThemePackageSavePicker? themePackageSavePicker;
  final ThemePackageExportAction? themePackageExportAction;

  @override
  State<ThemeStudioScreen> createState() => _ThemeStudioScreenState();
}

class _ThemeStudioScreenState extends State<ThemeStudioScreen> {
  static const _colorFields = <String, String>{
    'primary': '主色',
    'secondary': '辅助色',
    'stage': '舞台背景',
    'content': '数据面板背景',
    'pageBackground': '页面背景',
    'card': '卡片',
    'dialogBackground': '对话框背景',
    'cardAlt': '卡片辅助色',
    'text': '正文',
    'mutedText': '弱化正文',
    'onStage': '舞台文字',
    'outline': '描边',
    'success': '成功',
    'error': '错误',
    'statusIdle': '空闲状态',
    'shadow': '阴影',
  };

  CustomTheme? _draft;
  CustomTheme? _savedDraft;
  File? _pendingBackground;
  bool _backgroundRemovalPending = false;
  bool _narrowPreview = false;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _draft != null &&
      (_savedDraft == null ||
          _draft != _savedDraft ||
          _pendingBackground != null ||
          _backgroundRemovalPending);

  void _beginDraft(CustomTheme draft, {CustomTheme? savedDraft}) {
    setState(() {
      _draft = draft;
      _savedDraft = savedDraft;
      _pendingBackground = null;
      _backgroundRemovalPending = false;
      _nameController.text = draft.name;
    });
  }

  void _newTheme() => _beginDraft(_copyFromResolved());

  void _restoreSavedDraft() {
    final savedDraft = _savedDraft;
    if (savedDraft != null) _beginDraft(savedDraft, savedDraft: savedDraft);
  }

  void _resetToBuiltinCopy() => _beginDraft(_copyFromResolved());

  Future<void> _renameCustomTheme(CustomTheme theme) async {
    final nameController = TextEditingController(text: theme.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名自定义主题'),
        content: TextField(
          key: const Key('theme-rename-field'),
          controller: nameController,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(labelText: '主题名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('确认重命名'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    await widget.controller.renameCustomTheme(theme.id, name);
    if (!mounted || _draft?.id != theme.id) return;
    final renamedDraft = _draft!.copyWith(name: name);
    setState(() {
      _draft = renamedDraft;
      if (_savedDraft?.id == theme.id) {
        _savedDraft = _savedDraft!.copyWith(name: name);
      }
      _nameController.text = name;
    });
  }

  Future<void> _deleteCustomTheme(CustomTheme theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义主题？'),
        content: Text('“${theme.name}”将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.controller.deleteCustomTheme(theme.id);
    if (mounted && _draft?.id == theme.id) {
      setState(() {
        _draft = null;
        _savedDraft = null;
        _pendingBackground = null;
        _backgroundRemovalPending = false;
        _nameController.clear();
      });
    }
  }

  CustomTheme _copyFromResolved() {
    final active = widget.controller.themeReference.builtinTheme;
    if (active != null) return widget.controller.copyBuiltinTheme(active);
    final selected = widget.controller.customThemes
        .where(
          (theme) => theme.id == widget.controller.themeReference.customThemeId,
        )
        .firstOrNull;
    if (selected != null) {
      return selected.copyWith(
        id: widget.controller.copyBuiltinTheme(AppTheme.miku).id,
        name: '${selected.name} 副本',
      );
    }
    return widget.controller.copyBuiltinTheme(AppTheme.miku);
  }

  void _update(CustomTheme Function(CustomTheme) update) {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _draft = update(draft));
  }

  void _applyStylePreset(_ThemeStylePreset preset) {
    _update((theme) => preset.apply(theme));
  }

  Future<void> _selectBackground() async {
    final pick = widget.backgroundPicker ?? _pickBackground;
    final selected = await pick();
    if (selected == null || !mounted || _draft == null) return;
    setState(() {
      _pendingBackground = File(selected.path);
      _backgroundRemovalPending = false;
      _draft = _draft!.copyWith(
        backgroundImageFileName: selected.name.isEmpty
            ? 'background-image'
            : selected.name,
      );
    });
  }

  Future<XFile?> _pickBackground() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: '背景图片', extensions: ['png', 'jpg', 'jpeg', 'webp']),
    ],
  );

  Future<void> _importThemePackage() async {
    final pick = widget.themePackagePicker ?? _pickThemePackage;
    final selected = await pick();
    if (selected == null) return;
    try {
      final importAction =
          widget.themePackageImportAction ??
          ((file) => widget.controller.importCustomTheme(file, apply: false));
      final imported = await importAction(File(selected.path));
      if (!mounted) return;
      _beginDraft(imported, savedDraft: imported);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主题包已导入')));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导入主题失败，请检查主题包后重试')));
      }
    }
  }

  Future<XFile?> _pickThemePackage() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Agent Battery 主题包',
        extensions: ['agentbattery-theme'],
      ),
    ],
  );

  Future<void> _exportThemePackage(CustomTheme theme) async {
    final pick = widget.themePackageSavePicker ?? _pickThemePackageSaveLocation;
    final location = await pick(_themePackageSuggestedName(theme));
    if (location == null) return;
    try {
      final exportAction =
          widget.themePackageExportAction ??
          ((draft, destination) =>
              widget.controller.exportCustomTheme(draft.id, destination));
      await exportAction(theme, File(_themePackagePath(location.path)));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主题包已导出')));
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导出主题失败，请选择其他位置后重试')));
      }
    }
  }

  Future<FileSaveLocation?> _pickThemePackageSaveLocation(
    String suggestedName,
  ) => getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Agent Battery 主题包',
        extensions: ['agentbattery-theme'],
      ),
    ],
    suggestedName: suggestedName,
  );

  String _themePackageSuggestedName(CustomTheme theme) =>
      _themePackagePath(theme.name);

  String _themePackagePath(String path) =>
      path.toLowerCase().endsWith('.agentbattery-theme')
      ? path
      : '$path.agentbattery-theme';

  void _markBackgroundForRemoval() {
    _update((theme) => theme.copyWith(clearBackgroundImage: true));
    setState(() {
      _pendingBackground = null;
      _backgroundRemovalPending = true;
    });
  }

  Future<void> _saveAndApply() async {
    final draft = _draft;
    if (draft == null) return;
    try {
      final persistable = _pendingBackground != null
          ? draft.copyWith(
              backgroundImageFileName: _savedDraft?.backgroundImageFileName,
            )
          : draft;
      await widget.controller.saveCustomTheme(persistable);
      final source = _pendingBackground;
      if (source != null) {
        await widget.controller.importCustomThemeBackground(draft.id, source);
      } else if (_backgroundRemovalPending &&
          _savedDraft?.backgroundImageFileName != null) {
        await widget.controller.removeCustomThemeBackground(draft.id);
      }
      await widget.controller.applyThemeReference(
        ThemeReference.custom(draft.id),
      );
      if (!mounted) return;
      setState(() {
        _draft = widget.controller.customThemes
            .where((theme) => theme.id == draft.id)
            .firstOrNull;
        _savedDraft = _draft;
        _pendingBackground = null;
        _backgroundRemovalPending = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('主题已保存并应用')));
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存主题失败，请检查背景图片后重试')));
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final decision = await showDialog<_LeaveDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存草稿更改？'),
        content: const Text('离开主题工作台前，是否保存并应用当前草稿？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveDecision.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _LeaveDecision.discard),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _LeaveDecision.save),
            child: const Text('保存并应用'),
          ),
        ],
      ),
    );
    if (decision == _LeaveDecision.save) await _saveAndApply();
    return decision == _LeaveDecision.save ||
        decision == _LeaveDecision.discard;
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        final canLeave = await _confirmLeave();
        if (mounted && canLeave) Navigator.of(this.context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('主题工作台'),
          actions: [
            if (draft != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: FilledButton.icon(
                  key: const Key('theme-studio-save-apply-button'),
                  onPressed: _saveAndApply,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('保存并应用'),
                ),
              ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panes = [
              _EditorPane(
                draft: draft,
                canRestoreSaved: _savedDraft != null && _draft != _savedDraft,
                nameController: _nameController,
                colorFields: _colorFields,
                stylePresets: _stylePresets,
                onChanged: _update,
                onApplyStylePreset: _applyStylePreset,
                onRestoreSaved: _restoreSavedDraft,
                onResetToBuiltinCopy: _resetToBuiltinCopy,
                onBackgroundPick: _selectBackground,
                onBackgroundRemove: _markBackgroundForRemoval,
                scrollable: constraints.maxWidth >= 1050,
              ),
              _PreviewPane(
                draft: draft,
                previewBackground: _pendingBackground,
                resolveSavedBackground:
                    widget.controller.resolveCustomThemeBackground,
                narrow: _narrowPreview,
                onNarrow: () => setState(() => _narrowPreview = true),
                onWide: () => setState(() => _narrowPreview = false),
              ),
              _ThemeManagerPane(
                controller: widget.controller,
                selectedId: draft?.id,
                onNew: _newTheme,
                onImport: _importThemePackage,
                onCopyBuiltin: (theme) =>
                    _beginDraft(widget.controller.copyBuiltinTheme(theme)),
                onEdit: (theme) => _beginDraft(theme, savedDraft: theme),
                onRename: _renameCustomTheme,
                onDelete: _deleteCustomTheme,
                onExport: _exportThemePackage,
                scrollable: constraints.maxWidth >= 1050,
              ),
            ];
            if (constraints.maxWidth < 1050) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  panes[2],
                  const SizedBox(height: 16),
                  panes[0],
                  const SizedBox(height: 16),
                  SizedBox(height: 620, child: panes[1]),
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 310, child: panes[0]),
                  const SizedBox(width: 16),
                  Expanded(child: panes[1]),
                  const SizedBox(width: 16),
                  SizedBox(width: 255, child: panes[2]),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

enum _LeaveDecision { save, discard, cancel }

class _ThemeStylePreset {
  const _ThemeStylePreset({
    required this.key,
    required this.label,
    required this.layout,
    required this.dashboardLayoutMode,
    required this.dashboardDensity,
    required this.palette,
    required this.cardRadius,
    required this.controlRadius,
    required this.contentRadius,
    required this.shadowOpacity,
    required this.stageOverlayOpacity,
    this.stageGradientSecondary,
    this.contentGradientSecondary,
    this.cardGradientSecondary,
    this.stageGradientDirection = GradientDirection.topBottom,
    this.contentGradientDirection = GradientDirection.topBottom,
    this.cardGradientDirection = GradientDirection.topBottom,
  });

  final String key;
  final String label;
  final ThemeLayout layout;
  final DashboardLayoutMode dashboardLayoutMode;
  final DashboardDensity dashboardDensity;
  final ThemePalette palette;
  final double cardRadius;
  final double controlRadius;
  final double contentRadius;
  final double shadowOpacity;
  final double stageOverlayOpacity;
  final int? stageGradientSecondary;
  final int? contentGradientSecondary;
  final int? cardGradientSecondary;
  final GradientDirection stageGradientDirection;
  final GradientDirection contentGradientDirection;
  final GradientDirection cardGradientDirection;

  CustomTheme apply(CustomTheme theme) {
    var updated = theme.copyWith(
      layout: layout,
      palette: palette,
      cardRadius: cardRadius,
      controlRadius: controlRadius,
      contentRadius: contentRadius,
      shadowOpacity: shadowOpacity,
      stageOverlayOpacity: stageOverlayOpacity,
      dashboardLayoutMode: dashboardLayoutMode,
      dashboardDensity: dashboardDensity,
      clearStageGradientSecondary: true,
      clearContentGradientSecondary: true,
      clearCardGradientSecondary: true,
    );
    if (stageGradientSecondary != null) {
      updated = updated.copyWith(
        stageGradientSecondary: stageGradientSecondary,
        stageGradientDirection: stageGradientDirection,
      );
    }
    if (contentGradientSecondary != null) {
      updated = updated.copyWith(
        contentGradientSecondary: contentGradientSecondary,
        contentGradientDirection: contentGradientDirection,
      );
    }
    if (cardGradientSecondary != null) {
      updated = updated.copyWith(
        cardGradientSecondary: cardGradientSecondary,
        cardGradientDirection: cardGradientDirection,
      );
    }
    return updated;
  }
}

const _stylePresets = <_ThemeStylePreset>[
  _ThemeStylePreset(
    key: 'theme-preset-focus',
    label: '数据聚焦',
    layout: ThemeLayout.dashboard,
    dashboardLayoutMode: DashboardLayoutMode.focus,
    dashboardDensity: DashboardDensity.compact,
    palette: ThemePalette(
      primary: 0xff2563eb,
      secondary: 0xff0ea5e9,
      stage: 0xff0f172a,
      content: 0xffe2e8f0,
      pageBackground: 0xffe2e8f0,
      card: 0xffffffff,
      dialogBackground: 0xffffffff,
      cardAlt: 0xfff1f5f9,
      text: 0xff0f172a,
      mutedText: 0xff475569,
      onStage: 0xfff8fafc,
      outline: 0xffcbd5e1,
      success: 0xff16a34a,
      error: 0xffdc2626,
      statusIdle: 0xff64748b,
      shadow: 0xff0f172a,
    ),
    cardRadius: 10,
    controlRadius: 8,
    contentRadius: 16,
    shadowOpacity: 0.12,
    stageOverlayOpacity: 0.12,
  ),
  _ThemeStylePreset(
    key: 'theme-preset-glass',
    label: '柔和玻璃',
    layout: ThemeLayout.dashboard,
    dashboardLayoutMode: DashboardLayoutMode.standard,
    dashboardDensity: DashboardDensity.comfortable,
    palette: ThemePalette(
      primary: 0xff8b5cf6,
      secondary: 0xffec4899,
      stage: 0xff312e81,
      content: 0xffe0e7ff,
      pageBackground: 0xffe0e7ff,
      card: 0xd9ffffff,
      dialogBackground: 0xd9ffffff,
      cardAlt: 0xbff5f3ff,
      text: 0xff312e81,
      mutedText: 0xff6d5f99,
      onStage: 0xffffffff,
      outline: 0x99c4b5fd,
      success: 0xff10b981,
      error: 0xfff43f5e,
      statusIdle: 0xff8b5cf6,
      shadow: 0xff312e81,
    ),
    cardRadius: 24,
    controlRadius: 18,
    contentRadius: 30,
    shadowOpacity: 0.2,
    stageOverlayOpacity: 0.2,
    stageGradientSecondary: 0xff7c3aed,
    contentGradientSecondary: 0xfffce7f3,
    cardGradientSecondary: 0xe6ddd6fe,
    stageGradientDirection: GradientDirection.diagonal,
    contentGradientDirection: GradientDirection.leftRight,
  ),
  _ThemeStylePreset(
    key: 'theme-preset-night',
    label: '深色舞台',
    layout: ThemeLayout.stage,
    dashboardLayoutMode: DashboardLayoutMode.focus,
    dashboardDensity: DashboardDensity.comfortable,
    palette: ThemePalette(
      primary: 0xfff59e0b,
      secondary: 0xffef4444,
      stage: 0xff09090b,
      content: 0xff18181b,
      pageBackground: 0xff18181b,
      card: 0xff27272a,
      dialogBackground: 0xff27272a,
      cardAlt: 0xff3f3f46,
      text: 0xfffafafa,
      mutedText: 0xffa1a1aa,
      onStage: 0xffffffff,
      outline: 0xff52525b,
      success: 0xff22c55e,
      error: 0xfffb7185,
      statusIdle: 0xff71717a,
      shadow: 0xff000000,
    ),
    cardRadius: 14,
    controlRadius: 10,
    contentRadius: 20,
    shadowOpacity: 0.5,
    stageOverlayOpacity: 0.5,
    stageGradientSecondary: 0xff3f1d2e,
    contentGradientSecondary: 0xff27272a,
    cardGradientSecondary: 0xff3f3f46,
    stageGradientDirection: GradientDirection.diagonal,
    contentGradientDirection: GradientDirection.topBottom,
    cardGradientDirection: GradientDirection.leftRight,
  ),
  _ThemeStylePreset(
    key: 'theme-preset-fresh',
    label: '清爽亮色',
    layout: ThemeLayout.dashboard,
    dashboardLayoutMode: DashboardLayoutMode.standard,
    dashboardDensity: DashboardDensity.comfortable,
    palette: ThemePalette(
      primary: 0xff059669,
      secondary: 0xff14b8a6,
      stage: 0xffd1fae5,
      content: 0xffecfdf5,
      pageBackground: 0xffecfdf5,
      card: 0xffffffff,
      dialogBackground: 0xffffffff,
      cardAlt: 0xfff0fdf4,
      text: 0xff064e3b,
      mutedText: 0xff3f7667,
      onStage: 0xff064e3b,
      outline: 0xffa7f3d0,
      success: 0xff16a34a,
      error: 0xffdc2626,
      statusIdle: 0xff6b9b8b,
      shadow: 0xff064e3b,
    ),
    cardRadius: 18,
    controlRadius: 14,
    contentRadius: 24,
    shadowOpacity: 0.1,
    stageOverlayOpacity: 0.05,
    contentGradientSecondary: 0xffccfbf1,
    contentGradientDirection: GradientDirection.diagonal,
  ),
];

class _EditorPane extends StatelessWidget {
  const _EditorPane({
    required this.draft,
    required this.canRestoreSaved,
    required this.nameController,
    required this.colorFields,
    required this.stylePresets,
    required this.onChanged,
    required this.onApplyStylePreset,
    required this.onRestoreSaved,
    required this.onResetToBuiltinCopy,
    required this.onBackgroundPick,
    required this.onBackgroundRemove,
    required this.scrollable,
  });

  final CustomTheme? draft;
  final bool canRestoreSaved;
  final TextEditingController nameController;
  final Map<String, String> colorFields;
  final List<_ThemeStylePreset> stylePresets;
  final ValueChanged<CustomTheme Function(CustomTheme)> onChanged;
  final ValueChanged<_ThemeStylePreset> onApplyStylePreset;
  final VoidCallback onRestoreSaved;
  final VoidCallback onResetToBuiltinCopy;
  final VoidCallback onBackgroundPick;
  final VoidCallback onBackgroundRemove;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final draftTheme = draft;
    if (draftTheme == null) {
      return _EmptyPane(label: '从右侧新建或复制一个主题，开始编辑。');
    }

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('编辑草稿', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('快速样式预设', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in stylePresets)
                OutlinedButton(
                  key: Key(preset.key),
                  onPressed: () => onApplyStylePreset(preset),
                  child: Text(preset.label),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canRestoreSaved)
                TextButton(
                  key: const Key('theme-studio-restore-saved-button'),
                  onPressed: onRestoreSaved,
                  child: const Text('恢复已保存版本'),
                ),
              TextButton(
                key: const Key('theme-studio-reset-builtin-button'),
                onPressed: onResetToBuiltinCopy,
                child: const Text('重置为当前内置主题副本'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('theme-name-field'),
            controller: nameController,
            maxLength: 32,
            decoration: const InputDecoration(labelText: '主题名称'),
            onChanged: (value) {
              if (value.trim().isNotEmpty) {
                onChanged((theme) => theme.copyWith(name: value));
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<ThemeLayout>(
            initialValue: draftTheme.layout,
            decoration: const InputDecoration(labelText: '布局'),
            items: const [
              DropdownMenuItem(
                value: ThemeLayout.dashboard,
                child: Text('仪表盘布局'),
              ),
              DropdownMenuItem(value: ThemeLayout.stage, child: Text('舞台布局')),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged((theme) => theme.copyWith(layout: value));
              }
            },
          ),
          const SizedBox(height: 12),
          Text('布局与密度', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<DashboardLayoutMode>(
            key: const Key('theme-dashboard-layout-mode'),
            initialValue: draftTheme.dashboardLayoutMode,
            decoration: const InputDecoration(labelText: '仪表盘模板'),
            items: const [
              DropdownMenuItem(
                value: DashboardLayoutMode.standard,
                child: Text('标准布局'),
              ),
              DropdownMenuItem(
                value: DashboardLayoutMode.focus,
                child: Text('聚焦数据'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(
                  (theme) => theme.copyWith(dashboardLayoutMode: value),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DashboardDensity>(
            key: const Key('theme-dashboard-density'),
            initialValue: draftTheme.dashboardDensity,
            decoration: const InputDecoration(labelText: '内容密度'),
            items: const [
              DropdownMenuItem(
                value: DashboardDensity.comfortable,
                child: Text('舒适'),
              ),
              DropdownMenuItem(
                value: DashboardDensity.compact,
                child: Text('紧凑'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged((theme) => theme.copyWith(dashboardDensity: value));
              }
            },
          ),
          const SizedBox(height: 20),
          Text('颜色组', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final entry in colorFields.entries)
            _ColorPickerCard(
              label: entry.value,
              fieldKey:
                  'theme-color-${switch (entry.key) {
                    'cardAlt' => 'card-alt',
                    'pageBackground' => 'page-background',
                    'dialogBackground' => 'dialog-background',
                    _ => entry.key,
                  }}',
              value: _colorFor(draftTheme.palette, entry.key),
              onChanged: (color) => onChanged(
                (theme) => theme.copyWith(
                  palette: _replaceColor(theme.palette, entry.key, color),
                ),
              ),
            ),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const Key('theme-advanced-gradients-section'),
            title: const Text('高级渐变'),
            subtitle: const Text('为舞台、内容和卡片添加第二颜色'),
            children: [
              _GradientEditor(
                label: '舞台',
                enabledKey: 'theme-stage-gradient-enabled',
                colorKey: 'theme-stage-gradient-secondary',
                directionKey: 'theme-stage-gradient-direction',
                secondary: draftTheme.stageGradientSecondary,
                direction: draftTheme.stageGradientDirection,
                onEnabledChanged: (enabled) => onChanged(
                  (theme) => enabled
                      ? theme.copyWith(
                          stageGradientSecondary: _gradientContrast(
                            theme.palette.stage,
                          ),
                        )
                      : theme.copyWith(clearStageGradientSecondary: true),
                ),
                onColorChanged: (color) => onChanged(
                  (theme) => theme.copyWith(stageGradientSecondary: color),
                ),
                onDirectionChanged: (direction) => onChanged(
                  (theme) => theme.copyWith(stageGradientDirection: direction),
                ),
              ),
              _GradientEditor(
                label: '内容',
                enabledKey: 'theme-content-gradient-enabled',
                colorKey: 'theme-content-gradient-secondary',
                directionKey: 'theme-content-gradient-direction',
                secondary: draftTheme.contentGradientSecondary,
                direction: draftTheme.contentGradientDirection,
                onEnabledChanged: (enabled) => onChanged(
                  (theme) => enabled
                      ? theme.copyWith(
                          contentGradientSecondary: _gradientContrast(
                            theme.palette.content,
                          ),
                        )
                      : theme.copyWith(clearContentGradientSecondary: true),
                ),
                onColorChanged: (color) => onChanged(
                  (theme) => theme.copyWith(contentGradientSecondary: color),
                ),
                onDirectionChanged: (direction) => onChanged(
                  (theme) =>
                      theme.copyWith(contentGradientDirection: direction),
                ),
              ),
              _GradientEditor(
                label: '卡片',
                enabledKey: 'theme-card-gradient-enabled',
                colorKey: 'theme-card-gradient-secondary',
                directionKey: 'theme-card-gradient-direction',
                secondary: draftTheme.cardGradientSecondary,
                direction: draftTheme.cardGradientDirection,
                onEnabledChanged: (enabled) => onChanged(
                  (theme) => enabled
                      ? theme.copyWith(
                          cardGradientSecondary: _gradientContrast(
                            theme.palette.card,
                          ),
                        )
                      : theme.copyWith(clearCardGradientSecondary: true),
                ),
                onColorChanged: (color) => onChanged(
                  (theme) => theme.copyWith(cardGradientSecondary: color),
                ),
                onDirectionChanged: (direction) => onChanged(
                  (theme) => theme.copyWith(cardGradientDirection: direction),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            key: const Key('theme-liquid-glass-section'),
            title: const Text('液态玻璃'),
            subtitle: Text(
              draftTheme.useLiquidGlassSurface
                  ? '已启用：折射高光、透明层与背景柔化'
                  : '关闭时完全使用你的卡片渐变',
            ),
            children: [
              SwitchListTile(
                key: const Key('theme-liquid-glass-enabled'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: const Text('启用液态玻璃'),
                subtitle: const Text('关闭时恢复自定义卡片渐变，不叠加玻璃材质'),
                value: draftTheme.useLiquidGlassSurface,
                onChanged: (enabled) => onChanged(
                  (theme) => theme.copyWith(
                    useGlassSurface: enabled,
                    useLiquidGlassSurface: enabled,
                  ),
                ),
              ),
              if (draftTheme.useLiquidGlassSurface) ...[
                _ValueSlider(
                  fieldKey: 'theme-glass-transparency-slider',
                  label: '玻璃通透度',
                  value: draftTheme.glassTransparency,
                  min: 0,
                  max: 1,
                  onChanged: (value) => onChanged(
                    (theme) => theme.copyWith(glassTransparency: value),
                  ),
                ),
                _ValueSlider(
                  fieldKey: 'theme-glass-highlight-slider',
                  label: '折射高光',
                  value: draftTheme.glassHighlight,
                  min: 0,
                  max: 1,
                  onChanged: (value) => onChanged(
                    (theme) => theme.copyWith(glassHighlight: value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<GlassBlur>(
                    key: const Key('theme-glass-blur'),
                    initialValue: draftTheme.glassBlur,
                    decoration: const InputDecoration(labelText: '背景柔化'),
                    items: const [
                      DropdownMenuItem(value: GlassBlur.none, child: Text('无')),
                      DropdownMenuItem(value: GlassBlur.light, child: Text('轻')),
                      DropdownMenuItem(value: GlassBlur.soft, child: Text('柔和')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onChanged((theme) => theme.copyWith(glassBlur: value));
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text('圆角与透明度', style: Theme.of(context).textTheme.titleMedium),
          _ValueSlider(
            fieldKey: 'theme-card-radius-slider',
            label: '卡片圆角',
            value: draftTheme.cardRadius,
            onChanged: (value) =>
                onChanged((theme) => theme.copyWith(cardRadius: value)),
          ),
          _ValueSlider(
            fieldKey: 'theme-control-radius-slider',
            label: '控件圆角',
            value: draftTheme.controlRadius,
            onChanged: (value) =>
                onChanged((theme) => theme.copyWith(controlRadius: value)),
          ),
          _ValueSlider(
            fieldKey: 'theme-content-radius-slider',
            label: '内容圆角',
            value: draftTheme.contentRadius,
            onChanged: (value) =>
                onChanged((theme) => theme.copyWith(contentRadius: value)),
          ),
          _ValueSlider(
            fieldKey: 'theme-shadow-opacity-slider',
            label: '阴影透明度',
            value: draftTheme.shadowOpacity,
            min: 0,
            max: 1,
            onChanged: (value) =>
                onChanged((theme) => theme.copyWith(shadowOpacity: value)),
          ),
          _ValueSlider(
            fieldKey: 'theme-stage-overlay-opacity-slider',
            label: '舞台叠层透明度',
            value: draftTheme.stageOverlayOpacity,
            min: 0,
            max: 1,
            onChanged: (value) => onChanged(
              (theme) => theme.copyWith(stageOverlayOpacity: value),
            ),
          ),
          const SizedBox(height: 12),
          Text('背景图片', style: Theme.of(context).textTheme.titleMedium),
          Text(
            draftTheme.backgroundImageFileName ?? '未选择背景图片',
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<BackgroundImageFit>(
            key: const Key('theme-background-fit-field'),
            initialValue: draftTheme.backgroundImageFit,
            decoration: const InputDecoration(labelText: '背景适配'),
            items: const [
              DropdownMenuItem(
                value: BackgroundImageFit.cover,
                child: Text('填充'),
              ),
              DropdownMenuItem(
                value: BackgroundImageFit.contain,
                child: Text('完整显示'),
              ),
              DropdownMenuItem(
                value: BackgroundImageFit.fill,
                child: Text('拉伸'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged((theme) => theme.copyWith(backgroundImageFit: value));
              }
            },
          ),
          _ValueSlider(
            fieldKey: 'theme-background-opacity-slider',
            label: '背景透明度',
            value: draftTheme.backgroundImageOpacity,
            min: 0,
            max: 1,
            onChanged: (value) => onChanged(
              (theme) => theme.copyWith(backgroundImageOpacity: value),
            ),
          ),
          DropdownButtonFormField<BackgroundImageAlignment>(
            key: const Key('theme-background-alignment-field'),
            initialValue: draftTheme.backgroundImageAlignment,
            decoration: const InputDecoration(labelText: '背景对齐'),
            items: const [
              DropdownMenuItem(
                value: BackgroundImageAlignment.center,
                child: Text('居中'),
              ),
              DropdownMenuItem(
                value: BackgroundImageAlignment.left,
                child: Text('靠左'),
              ),
              DropdownMenuItem(
                value: BackgroundImageAlignment.right,
                child: Text('靠右'),
              ),
              DropdownMenuItem(
                value: BackgroundImageAlignment.top,
                child: Text('靠上'),
              ),
              DropdownMenuItem(
                value: BackgroundImageAlignment.bottom,
                child: Text('靠下'),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(
                  (theme) => theme.copyWith(backgroundImageAlignment: value),
                );
              }
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onBackgroundPick,
                icon: const Icon(Icons.image_outlined),
                label: const Text('选择图片'),
              ),
              if (draftTheme.backgroundImageFileName != null)
                TextButton.icon(
                  onPressed: onBackgroundRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('移除'),
                ),
            ],
          ),
        ],
      ),
    );
    return Card(
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _PreviewPane extends StatefulWidget {
  const _PreviewPane({
    required this.draft,
    required this.previewBackground,
    required this.resolveSavedBackground,
    required this.narrow,
    required this.onNarrow,
    required this.onWide,
  });
  final CustomTheme? draft;
  final File? previewBackground;
  final Future<File?> Function(String themeId) resolveSavedBackground;
  final bool narrow;
  final VoidCallback onNarrow;
  final VoidCallback onWide;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane> {
  Future<File?>? _savedBackground;
  String? _themeId;

  @override
  void initState() {
    super.initState();
    _loadSavedBackground();
  }

  @override
  void didUpdateWidget(covariant _PreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft?.id != widget.draft?.id ||
        oldWidget.draft?.backgroundImageFileName !=
            widget.draft?.backgroundImageFileName) {
      _loadSavedBackground();
    }
  }

  void _loadSavedBackground() {
    _themeId = widget.draft?.id;
    _savedBackground = _themeId == null
        ? null
        : widget.resolveSavedBackground(_themeId!);
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final previewBackground = widget.previewBackground;
    final draftTheme = draft;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('实时预览', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      key: const Key('theme-studio-wide-preview-button'),
                      tooltip: '宽屏预览',
                      onPressed: widget.onWide,
                      icon: Icon(
                        Icons.desktop_windows_outlined,
                        color: !widget.narrow
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    IconButton(
                      key: const Key('theme-studio-narrow-preview-button'),
                      tooltip: '窄屏预览',
                      onPressed: widget.onNarrow,
                      icon: Icon(
                        Icons.phone_android_outlined,
                        color: widget.narrow
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  ],
                ),
                if (draftTheme != null) ...[
                  const SizedBox(height: 6),
                  _PreviewStatus(theme: draftTheme),
                ],
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (draftTheme == null) {
                  return const _EmptyPane(label: '新建主题后将在这里实时预览。');
                }
                final canvasSize = draftTheme.layout == ThemeLayout.stage
                    ? const Size(1320, 760)
                    : const Size(680, 800);
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: widget.narrow ? 360 : constraints.maxWidth,
                      maxHeight: constraints.maxHeight,
                    ),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        key: const Key('theme-preview-canvas'),
                        width: canvasSize.width,
                        height: canvasSize.height,
                        child: _PreviewBackgroundComposition(
                          theme: draftTheme,
                          pendingBackground: previewBackground,
                          savedBackground: _savedBackground,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStatus extends StatelessWidget {
  const _PreviewStatus({required this.theme});
  final CustomTheme theme;

  @override
  Widget build(BuildContext context) {
    final gradientCount = [
      theme.stageGradientSecondary,
      theme.contentGradientSecondary,
      theme.cardGradientSecondary,
    ].whereType<int>().length;
    final layoutLabel = theme.dashboardLayoutMode == DashboardLayoutMode.focus
        ? '聚焦数据'
        : '标准布局';
    final densityLabel = theme.dashboardDensity == DashboardDensity.compact
        ? '紧凑'
        : '舒适';
    return Container(
      key: Key('theme-preview-gradient-count-$gradientCount'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$layoutLabel · $densityLabel · $gradientCount 层渐变',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

BoxFit _previewBackgroundFit(BackgroundImageFit fit) => switch (fit) {
  BackgroundImageFit.contain => BoxFit.contain,
  BackgroundImageFit.fill => BoxFit.fill,
  BackgroundImageFit.cover => BoxFit.cover,
};

Alignment _previewBackgroundAlignment(BackgroundImageAlignment alignment) =>
    switch (alignment) {
      BackgroundImageAlignment.left => Alignment.centerLeft,
      BackgroundImageAlignment.right => Alignment.centerRight,
      BackgroundImageAlignment.top => Alignment.topCenter,
      BackgroundImageAlignment.bottom => Alignment.bottomCenter,
      BackgroundImageAlignment.center => Alignment.center,
    };

/// Isolated fixture dashboard: it uses the production ProviderCard widget but never
/// reads, refreshes, or persists controller state.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.theme, this.background});
  final CustomTheme theme;
  final File? background;

  @override
  Widget build(BuildContext context) {
    final resolved = ResolvedTheme.custom(theme);
    final tokens = resolved.tokens;
    final compact = theme.dashboardDensity == DashboardDensity.compact;
    final focus = theme.dashboardLayoutMode == DashboardLayoutMode.focus;
    final previewPadding = compact ? 8.0 : 14.0;
    final summaryGap = compact ? 6.0 : 12.0;
    return Theme(
      data: tokens.materialTheme(),
      child: Builder(
        builder: (context) => DecoratedBox(
          key: const Key('theme-preview-stage-gradient'),
          decoration: BoxDecoration(gradient: tokens.stageGradient),
          child: Stack(
            children: [
              if (theme.layout == ThemeLayout.dashboard)
                Positioned.fill(
                  child: DecoratedBox(
                    key: const Key('theme-preview-dashboard-page-background'),
                    decoration: BoxDecoration(color: tokens.pageBackground),
                  ),
                ),
              if (background != null)
                Positioned.fill(
                  child: Opacity(
                    key: const Key('theme-preview-background-opacity'),
                    opacity: theme.backgroundImageOpacity.clamp(0.0, 1.0),
                    child: Image.file(
                      background!,
                      key: const Key('theme-preview-background'),
                      fit: _previewBackgroundFit(theme.backgroundImageFit),
                      alignment: _previewBackgroundAlignment(
                        theme.backgroundImageAlignment,
                      ),
                      errorBuilder: (_, _, _) => const SizedBox.expand(),
                    ),
                  ),
                ),
              if (theme.layout == ThemeLayout.stage)
                Positioned.fill(
                  child: ColoredBox(
                    color: tokens.stageGradient.colors.first.withValues(
                      alpha: theme.stageOverlayOpacity,
                    ),
                  ),
                ),
              SafeArea(
                child: theme.layout == ThemeLayout.stage
                    ? KeyedSubtree(
                        key: const Key('theme-preview-stage-layout'),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            key: const Key(
                              'theme-preview-stage-content-column',
                            ),
                            widthFactor: .55,
                            child: _PreviewBody(
                              theme: theme,
                              tokens: tokens,
                              compact: compact,
                              focus: focus,
                              summaryGap: summaryGap,
                              previewPadding: previewPadding,
                            ),
                          ),
                        ),
                      )
                    : KeyedSubtree(
                        key: const Key('theme-preview-dashboard-layout'),
                        child: _PreviewBody(
                          theme: theme,
                          tokens: tokens,
                          compact: compact,
                          focus: focus,
                          summaryGap: summaryGap,
                          previewPadding: previewPadding,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.theme,
    required this.tokens,
    required this.compact,
    required this.focus,
    required this.summaryGap,
    required this.previewPadding,
  });

  final CustomTheme theme;
  final AppThemeTokens tokens;
  final bool compact;
  final bool focus;
  final double summaryGap;
  final double previewPadding;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          key: const Key('theme-preview-header-background'),
          decoration: BoxDecoration(
            color: tokens.pageBackground,
            border: Border(bottom: BorderSide(color: tokens.outline)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                DecoratedBox(
                  key: const Key('theme-preview-primary-swatch'),
                  decoration: BoxDecoration(
                    color: tokens.primary,
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                  ),
                  child: const SizedBox(width: 32, height: 32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    theme.name,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(Icons.refresh_rounded, color: tokens.text),
              ],
            ),
          ),
        ),
        Expanded(
          child: DecoratedBox(
            key: const Key('theme-preview-content-gradient'),
            decoration: BoxDecoration(
              gradient: tokens.contentGradient,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(tokens.contentRadius),
              ),
              boxShadow: [
                BoxShadow(
                  color: tokens.shadow.withValues(alpha: theme.shadowOpacity),
                  blurRadius: compact ? 6 : 14,
                  offset: Offset(0, compact ? 2 : 6),
                ),
              ],
            ),
            child: ListView(
              key: theme.dashboardDensity == DashboardDensity.compact
                  ? const Key('theme-preview-density-compact')
                  : const Key('theme-preview-density-comfortable'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    previewPadding,
                    previewPadding,
                    previewPadding,
                    10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DecoratedBox(
                          key: const Key('theme-preview-page-background'),
                          decoration: BoxDecoration(
                            color: tokens.pageBackground,
                            borderRadius: BorderRadius.circular(
                              tokens.controlRadius,
                            ),
                            border: Border.all(color: tokens.outline),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              '页面 / 顶栏',
                              style: TextStyle(color: tokens.text),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DecoratedBox(
                          key: const Key('theme-preview-dialog-background'),
                          decoration: BoxDecoration(
                            color: tokens.dialogBackground,
                            borderRadius: BorderRadius.circular(
                              tokens.cardRadius,
                            ),
                            border: Border.all(color: tokens.outline),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(
                              '对话框',
                              style: TextStyle(color: tokens.text),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final summaries = const [
                      _PreviewSummary('余额合计', '¥ 48.60'),
                      _PreviewSummary('今日消耗', '¥ 2.30'),
                      _PreviewSummary('本月消耗', '¥ 13.80'),
                    ];
                    if (focus) {
                      return Wrap(
                        key: const Key('theme-preview-focus-summary'),
                        spacing: summaryGap,
                        runSpacing: summaryGap,
                        children: summaries
                            .map(
                              (item) => SizedBox(
                                width: constraints.maxWidth < 460
                                    ? double.infinity
                                    : (constraints.maxWidth - summaryGap) / 2,
                                child: item,
                              ),
                            )
                            .toList(),
                      );
                    }
                    if (constraints.maxWidth < 460) {
                      return Column(
                        children: [
                          for (final item in summaries) ...[
                            item,
                            SizedBox(height: summaryGap),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        for (final item in summaries)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: summaryGap / 2,
                              ),
                              child: item,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                DecoratedBox(
                  key: const Key('theme-preview-card-gradient'),
                  decoration: BoxDecoration(gradient: tokens.cardGradient),
                  child: ProviderCard(
                    provider: const ProviderViewState(
                      id: 'preview-provider',
                      name: 'OpenAI 兼容服务',
                      status: ConnectionStatus.connected,
                      message: '已连接',
                      balance: 4.8,
                      dailyUsage: 1.2,
                      monthlyUsage: 8.6,
                    ),
                    accent: tokens.primary,
                    rechargeUrl: 'https://example.com/recharge',
                    lowBalanceThreshold: 5,
                    onRecharge: () {},
                    onEditDailyUsage: () {},
                    onEditMonthlyUsage: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return GlassSurface(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: tokens.mutedText, fontSize: 11)),
          Text(
            value,
            style: TextStyle(color: tokens.text, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _GradientEditor extends StatelessWidget {
  const _GradientEditor({
    required this.label,
    required this.enabledKey,
    required this.colorKey,
    required this.directionKey,
    required this.secondary,
    required this.direction,
    required this.onEnabledChanged,
    required this.onColorChanged,
    required this.onDirectionChanged,
  });

  final String label;
  final String enabledKey;
  final String colorKey;
  final String directionKey;
  final int? secondary;
  final GradientDirection direction;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<GradientDirection> onDirectionChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = secondary != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        children: [
          SwitchListTile(
            key: Key(enabledKey),
            contentPadding: EdgeInsets.zero,
            title: Text('$label 第二颜色'),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          if (enabled) ...[
            _ColorPickerCard(
              label: '$label 渐变终点颜色',
              fieldKey: colorKey,
              value: secondary!,
              onChanged: onColorChanged,
            ),
            DropdownButtonFormField<GradientDirection>(
              key: Key(directionKey),
              initialValue: direction,
              decoration: const InputDecoration(labelText: '渐变方向'),
              items: const [
                DropdownMenuItem(
                  value: GradientDirection.topBottom,
                  child: Text('从上到下'),
                ),
                DropdownMenuItem(
                  value: GradientDirection.leftRight,
                  child: Text('从左到右'),
                ),
                DropdownMenuItem(
                  value: GradientDirection.diagonal,
                  child: Text('左上到右下'),
                ),
              ],
              onChanged: (value) {
                if (value != null) onDirectionChanged(value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ColorPickerCard extends StatelessWidget {
  const _ColorPickerCard({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });
  final String label, fieldKey;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Color(value),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('theme-color-picker-$fieldKey'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _ColorPickerDialog(
            label: label,
            fieldKey: fieldKey,
            value: value,
            onChanged: onChanged,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(value),
                  border: Border.all(color: Colors.white),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color:
                        ThemeData.estimateBrightnessForColor(Color(value)) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                ),
              ),
              const Icon(Icons.colorize_outlined),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });
  final String label, fieldKey;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv;
  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.value));
  }

  void _set(HSVColor color) {
    setState(() => _hsv = color);
    widget.onChanged(color.toColor().toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      title: Text('选择${widget.label}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: double.infinity, height: 40, color: color),
            Text('RGB(${color.r}, ${color.g}, ${color.b})'),
            _colorSlider(
              '色相',
              'theme-color-hue-slider',
              _hsv.hue,
              0,
              360,
              (v) => _set(_hsv.withHue(v)),
            ),
            _colorSlider(
              '饱和度',
              'theme-color-saturation-slider',
              _hsv.saturation,
              0,
              1,
              (v) => _set(_hsv.withSaturation(v)),
            ),
            _colorSlider(
              '明度',
              'theme-color-value-slider',
              _hsv.value,
              0,
              1,
              (v) => _set(_hsv.withValue(v)),
            ),
            _colorSlider(
              '透明度',
              'theme-color-opacity-slider',
              _hsv.alpha,
              0,
              1,
              (v) => _set(_hsv.withAlpha(v)),
            ),
            ExpansionTile(
              title: const Text('高级输入（十六进制）'),
              children: [
                _HexField(
                  label: '十六进制',
                  fieldKey: '${widget.fieldKey}-hex',
                  value: color.toARGB32(),
                  onValidChanged: (v) => _set(HSVColor.fromColor(Color(v))),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _colorSlider(
    String label,
    String key,
    double value,
    double min,
    double max,
    ValueChanged<double> changed,
  ) => Row(
    children: [
      SizedBox(width: 64, child: Text(label)),
      Expanded(
        child: Slider(
          key: Key(key),
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: changed,
        ),
      ),
    ],
  );
}

class _HexField extends StatefulWidget {
  const _HexField({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.onValidChanged,
  });
  final String label, fieldKey;
  final int value;
  final ValueChanged<int> onValidChanged;
  @override
  State<_HexField> createState() => _HexFieldState();
}

class _HexFieldState extends State<_HexField> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: _hex(widget.value));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: Key(widget.fieldKey),
    controller: controller,
    decoration: InputDecoration(labelText: widget.label, prefixText: '#'),
    onChanged: (v) {
      final p = _parseHex(v);
      if (p != null) widget.onValidChanged(p);
    },
  );
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 80,
  });
  final String fieldKey, label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：${max <= 1 ? value.toStringAsFixed(2) : value.toStringAsFixed(0)}',
        ),
        Slider(
          key: Key(fieldKey),
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: max <= 1 ? 100 : (max - min).round(),
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _PreviewBackgroundComposition extends StatelessWidget {
  const _PreviewBackgroundComposition({
    required this.theme,
    required this.pendingBackground,
    required this.savedBackground,
  });
  final CustomTheme theme;
  final File? pendingBackground;
  final Future<File?>? savedBackground;
  @override
  Widget build(BuildContext context) {
    if (pendingBackground != null) {
      return ThemePreview(theme: theme, background: pendingBackground);
    }
    if (savedBackground == null) return ThemePreview(theme: theme);
    return FutureBuilder<File?>(
      future: savedBackground,
      builder: (_, snapshot) =>
          ThemePreview(theme: theme, background: snapshot.data),
    );
  }
}

class _ThemeManagerPane extends StatelessWidget {
  const _ThemeManagerPane({
    required this.controller,
    required this.selectedId,
    required this.onNew,
    required this.onImport,
    required this.onCopyBuiltin,
    required this.onEdit,
    required this.onRename,
    required this.onDelete,
    required this.onExport,
    required this.scrollable,
  });

  final BatteryController controller;
  final String? selectedId;
  final VoidCallback onNew;
  final VoidCallback onImport;
  final ValueChanged<AppTheme> onCopyBuiltin;
  final ValueChanged<CustomTheme> onEdit;
  final ValueChanged<CustomTheme> onRename;
  final ValueChanged<CustomTheme> onDelete;
  final ValueChanged<CustomTheme> onExport;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            key: const Key('theme-studio-new-button'),
            onPressed: onNew,
            icon: const Icon(Icons.add),
            label: const Text('新建主题'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('theme-studio-import-button'),
            onPressed: onImport,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入主题'),
          ),
          const SizedBox(height: 16),
          Text('内置主题', style: Theme.of(context).textTheme.titleMedium),
          for (final theme in AppTheme.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppThemeTokens.forTheme(theme).name),
              trailing: IconButton(
                key: theme == AppTheme.miku
                    ? const Key('theme-studio-copy-miku-button')
                    : null,
                tooltip: '复制 ${AppThemeTokens.forTheme(theme).name}',
                onPressed: () => onCopyBuiltin(theme),
                icon: const Icon(Icons.copy_outlined),
              ),
              onTap: () => controller.selectTheme(theme),
            ),
          const Divider(),
          Text('自定义主题', style: Theme.of(context).textTheme.titleMedium),
          if (controller.customThemes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('尚无自定义主题'),
            ),
          for (final theme in controller.customThemes)
            ListTile(
              contentPadding: EdgeInsets.zero,
              selected: selectedId == theme.id,
              title: Text(theme.name),
              onTap: () => onEdit(theme),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('theme-studio-rename-${theme.id}'),
                    tooltip: '重命名 ${theme.name}',
                    onPressed: () => onRename(theme),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    key: Key('theme-studio-export-${theme.id}'),
                    tooltip: '导出 ${theme.name}',
                    onPressed: () => onExport(theme),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  IconButton(
                    key: Key('theme-studio-delete-${theme.id}'),
                    tooltip: '删除 ${theme.name}',
                    onPressed: () => onDelete(theme),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    return Card(
      child: scrollable ? SingleChildScrollView(child: content) : content,
    );
  }
}

class _EmptyPane extends StatelessWidget {
  const _EmptyPane({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(label, textAlign: TextAlign.center),
    ),
  );
}

int _colorFor(ThemePalette palette, String key) => switch (key) {
  'primary' => palette.primary,
  'secondary' => palette.secondary,
  'stage' => palette.stage,
  'content' => palette.content,
  'pageBackground' => palette.pageBackground,
  'card' => palette.card,
  'dialogBackground' => palette.dialogBackground,
  'cardAlt' => palette.cardAlt,
  'text' => palette.text,
  'mutedText' => palette.mutedText,
  'onStage' => palette.onStage,
  'outline' => palette.outline,
  'success' => palette.success,
  'error' => palette.error,
  'statusIdle' => palette.statusIdle,
  _ => palette.shadow,
};
ThemePalette _replaceColor(ThemePalette palette, String key, int value) =>
    switch (key) {
      'primary' => palette.copyWith(primary: value),
      'secondary' => palette.copyWith(secondary: value),
      'stage' => palette.copyWith(stage: value),
      'content' => palette.copyWith(content: value),
      'pageBackground' => palette.copyWith(pageBackground: value),
      'card' => palette.copyWith(card: value),
      'dialogBackground' => palette.copyWith(dialogBackground: value),
      'cardAlt' => palette.copyWith(cardAlt: value),
      'text' => palette.copyWith(text: value),
      'mutedText' => palette.copyWith(mutedText: value),
      'onStage' => palette.copyWith(onStage: value),
      'outline' => palette.copyWith(outline: value),
      'success' => palette.copyWith(success: value),
      'error' => palette.copyWith(error: value),
      'statusIdle' => palette.copyWith(statusIdle: value),
      _ => palette.copyWith(shadow: value),
    };
int _gradientContrast(int value) {
  final hsl = HSLColor.fromColor(Color(value));
  final lightness = hsl.lightness > .55
      ? (hsl.lightness - .18).clamp(.0, 1.0)
      : (hsl.lightness + .18).clamp(.0, 1.0);
  return hsl.withLightness(lightness).toColor().toARGB32();
}

String _hex(int value) => value.toRadixString(16).padLeft(8, '0').toUpperCase();
int? _parseHex(String raw) {
  final cleaned = raw.trim().replaceFirst('#', '');
  final normalized = cleaned.length == 6 ? 'FF$cleaned' : cleaned;
  return RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(normalized)
      ? int.tryParse(normalized, radix: 16)
      : null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
