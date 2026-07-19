enum AppTheme { miku, glass, cute, mita, nailong }

enum ThemeLayout { dashboard, stage }

enum DashboardDensity { comfortable, compact }

enum DashboardLayoutMode { standard, focus }

enum BackgroundImageFit { cover, contain, fill }

enum BackgroundImageAlignment { center, left, right, top, bottom }

enum GradientDirection { topBottom, leftRight, diagonal }

class ThemePalette {
  const ThemePalette({
    required this.primary,
    required this.secondary,
    required this.stage,
    required this.content,
    required this.pageBackground,
    required this.card,
    required this.dialogBackground,
    required this.cardAlt,
    required this.text,
    required this.mutedText,
    required this.onStage,
    required this.outline,
    required this.success,
    required this.error,
    required this.statusIdle,
    required this.shadow,
  }) : assert(primary >= 0 && primary <= 0xffffffff),
       assert(secondary >= 0 && secondary <= 0xffffffff),
       assert(stage >= 0 && stage <= 0xffffffff),
       assert(content >= 0 && content <= 0xffffffff),
       assert(pageBackground >= 0 && pageBackground <= 0xffffffff),
       assert(card >= 0 && card <= 0xffffffff),
       assert(dialogBackground >= 0 && dialogBackground <= 0xffffffff),
       assert(cardAlt >= 0 && cardAlt <= 0xffffffff),
       assert(text >= 0 && text <= 0xffffffff),
       assert(mutedText >= 0 && mutedText <= 0xffffffff),
       assert(onStage >= 0 && onStage <= 0xffffffff),
       assert(outline >= 0 && outline <= 0xffffffff),
       assert(success >= 0 && success <= 0xffffffff),
       assert(error >= 0 && error <= 0xffffffff),
       assert(statusIdle >= 0 && statusIdle <= 0xffffffff),
       assert(shadow >= 0 && shadow <= 0xffffffff);

  final int primary;
  final int secondary;
  final int stage;
  final int content;
  final int pageBackground;
  final int card;
  final int dialogBackground;
  final int cardAlt;
  final int text;
  final int mutedText;
  final int onStage;
  final int outline;
  final int success;
  final int error;
  final int statusIdle;
  final int shadow;

  ThemePalette copyWith({
    int? primary,
    int? secondary,
    int? stage,
    int? content,
    int? pageBackground,
    int? card,
    int? dialogBackground,
    int? cardAlt,
    int? text,
    int? mutedText,
    int? onStage,
    int? outline,
    int? success,
    int? error,
    int? statusIdle,
    int? shadow,
  }) {
    final result = ThemePalette._unchecked(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      stage: stage ?? this.stage,
      content: content ?? this.content,
      pageBackground: pageBackground ?? this.pageBackground,
      card: card ?? this.card,
      dialogBackground: dialogBackground ?? this.dialogBackground,
      cardAlt: cardAlt ?? this.cardAlt,
      text: text ?? this.text,
      mutedText: mutedText ?? this.mutedText,
      onStage: onStage ?? this.onStage,
      outline: outline ?? this.outline,
      success: success ?? this.success,
      error: error ?? this.error,
      statusIdle: statusIdle ?? this.statusIdle,
      shadow: shadow ?? this.shadow,
    );
    result._validate();
    return result;
  }

  const ThemePalette._unchecked({
    required this.primary,
    required this.secondary,
    required this.stage,
    required this.content,
    required this.pageBackground,
    required this.card,
    required this.dialogBackground,
    required this.cardAlt,
    required this.text,
    required this.mutedText,
    required this.onStage,
    required this.outline,
    required this.success,
    required this.error,
    required this.statusIdle,
    required this.shadow,
  });

  Map<String, Object> toJson() => {
    'primary': primary,
    'secondary': secondary,
    'stage': stage,
    'content': content,
    'page_background': pageBackground,
    'card': card,
    'dialog_background': dialogBackground,
    'card_alt': cardAlt,
    'text': text,
    'muted_text': mutedText,
    'on_stage': onStage,
    'outline': outline,
    'success': success,
    'error': error,
    'status_idle': statusIdle,
    'shadow': shadow,
  };

  factory ThemePalette.fromJson(Map<String, Object?> json) {
    int read(String key) {
      final value = json[key];
      if (value is! int || value < 0 || value > 0xffffffff) {
        throw ArgumentError.value(value, key, 'must be an ARGB 32-bit value');
      }
      return value;
    }

    final hasPageBackground = json.containsKey('page_background');
    final hasDialogBackground = json.containsKey('dialog_background');
    if (hasPageBackground != hasDialogBackground) {
      throw ArgumentError(
        'page_background and dialog_background must be provided together',
      );
    }
    final content = read('content');
    final card = read('card');
    final result = ThemePalette._unchecked(
      primary: read('primary'),
      secondary: read('secondary'),
      stage: read('stage'),
      content: content,
      pageBackground: hasPageBackground ? read('page_background') : content,
      card: card,
      dialogBackground: hasDialogBackground ? read('dialog_background') : card,
      cardAlt: read('card_alt'),
      text: read('text'),
      mutedText: read('muted_text'),
      onStage: read('on_stage'),
      outline: read('outline'),
      success: read('success'),
      error: read('error'),
      statusIdle: read('status_idle'),
      shadow: read('shadow'),
    );
    result._validate();
    return result;
  }

  void _validate() {
    if (!_areValidColors([
      primary,
      secondary,
      stage,
      content,
      pageBackground,
      card,
      dialogBackground,
      cardAlt,
      text,
      mutedText,
      onStage,
      outline,
      success,
      error,
      statusIdle,
      shadow,
    ])) {
      throw ArgumentError('Palette colors must be ARGB 32-bit values');
    }
  }

  static bool _areValidColors(List<int> values) =>
      values.every((value) => value >= 0 && value <= 0xffffffff);

  @override
  bool operator ==(Object other) =>
      other is ThemePalette &&
      primary == other.primary &&
      secondary == other.secondary &&
      stage == other.stage &&
      content == other.content &&
      pageBackground == other.pageBackground &&
      card == other.card &&
      dialogBackground == other.dialogBackground &&
      cardAlt == other.cardAlt &&
      text == other.text &&
      mutedText == other.mutedText &&
      onStage == other.onStage &&
      outline == other.outline &&
      success == other.success &&
      error == other.error &&
      statusIdle == other.statusIdle &&
      shadow == other.shadow;

  @override
  int get hashCode => Object.hashAll(toJson().values);
}

class CustomTheme {
  CustomTheme({
    required this.id,
    required String name,
    required this.layout,
    required this.palette,
    required this.cardRadius,
    required this.controlRadius,
    required this.contentRadius,
    required this.shadowOpacity,
    required this.stageOverlayOpacity,
    this.stageGradientSecondary,
    this.stageGradientDirection = GradientDirection.topBottom,
    this.contentGradientSecondary,
    this.contentGradientDirection = GradientDirection.topBottom,
    this.cardGradientSecondary,
    this.cardGradientDirection = GradientDirection.topBottom,
    this.backgroundImageFileName,
    this.backgroundImageFit = BackgroundImageFit.cover,
    this.backgroundImageAlignment = BackgroundImageAlignment.center,
    this.backgroundImageOpacity = 1,
    this.dashboardLayoutMode = DashboardLayoutMode.standard,
    this.dashboardDensity = DashboardDensity.comfortable,
    this.useGlassSurface = false,
    this.useLiquidGlassSurface = false,
  }) : name = name.trim() {
    _validate();
  }

  final String id;
  final String name;
  final ThemeLayout layout;
  final ThemePalette palette;
  final double cardRadius;
  final double controlRadius;
  final double contentRadius;
  final double shadowOpacity;
  final double stageOverlayOpacity;
  final int? stageGradientSecondary;
  final GradientDirection stageGradientDirection;
  final int? contentGradientSecondary;
  final GradientDirection contentGradientDirection;
  final int? cardGradientSecondary;
  final GradientDirection cardGradientDirection;
  final String? backgroundImageFileName;
  final BackgroundImageFit backgroundImageFit;
  final BackgroundImageAlignment backgroundImageAlignment;
  final double backgroundImageOpacity;
  final DashboardLayoutMode dashboardLayoutMode;
  final DashboardDensity dashboardDensity;
  final bool useGlassSurface;
  final bool useLiquidGlassSurface;

  CustomTheme copyWith({
    String? id,
    String? name,
    ThemeLayout? layout,
    ThemePalette? palette,
    double? cardRadius,
    double? controlRadius,
    double? contentRadius,
    double? shadowOpacity,
    double? stageOverlayOpacity,
    int? stageGradientSecondary,
    GradientDirection? stageGradientDirection,
    int? contentGradientSecondary,
    GradientDirection? contentGradientDirection,
    int? cardGradientSecondary,
    GradientDirection? cardGradientDirection,
    bool clearStageGradientSecondary = false,
    bool clearContentGradientSecondary = false,
    bool clearCardGradientSecondary = false,
    String? backgroundImageFileName,
    BackgroundImageFit? backgroundImageFit,
    BackgroundImageAlignment? backgroundImageAlignment,
    double? backgroundImageOpacity,
    DashboardLayoutMode? dashboardLayoutMode,
    DashboardDensity? dashboardDensity,
    bool? useGlassSurface,
    bool? useLiquidGlassSurface,
    bool clearBackgroundImage = false,
  }) => CustomTheme(
    id: id ?? this.id,
    name: name ?? this.name,
    layout: layout ?? this.layout,
    palette: palette ?? this.palette,
    cardRadius: cardRadius ?? this.cardRadius,
    controlRadius: controlRadius ?? this.controlRadius,
    contentRadius: contentRadius ?? this.contentRadius,
    shadowOpacity: shadowOpacity ?? this.shadowOpacity,
    stageOverlayOpacity: stageOverlayOpacity ?? this.stageOverlayOpacity,
    stageGradientSecondary: clearStageGradientSecondary
        ? null
        : stageGradientSecondary ?? this.stageGradientSecondary,
    stageGradientDirection:
        stageGradientDirection ?? this.stageGradientDirection,
    contentGradientSecondary: clearContentGradientSecondary
        ? null
        : contentGradientSecondary ?? this.contentGradientSecondary,
    contentGradientDirection:
        contentGradientDirection ?? this.contentGradientDirection,
    cardGradientSecondary: clearCardGradientSecondary
        ? null
        : cardGradientSecondary ?? this.cardGradientSecondary,
    cardGradientDirection: cardGradientDirection ?? this.cardGradientDirection,
    backgroundImageFileName: clearBackgroundImage
        ? null
        : backgroundImageFileName ?? this.backgroundImageFileName,
    backgroundImageFit: backgroundImageFit ?? this.backgroundImageFit,
    backgroundImageAlignment:
        backgroundImageAlignment ?? this.backgroundImageAlignment,
    backgroundImageOpacity:
        backgroundImageOpacity ?? this.backgroundImageOpacity,
    dashboardLayoutMode: dashboardLayoutMode ?? this.dashboardLayoutMode,
    dashboardDensity: dashboardDensity ?? this.dashboardDensity,
    useGlassSurface: useGlassSurface ?? this.useGlassSurface,
    useLiquidGlassSurface:
        useLiquidGlassSurface ?? this.useLiquidGlassSurface,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'layout': layout.name,
    'palette': palette.toJson(),
    'card_radius': cardRadius,
    'control_radius': controlRadius,
    'content_radius': contentRadius,
    'shadow_opacity': shadowOpacity,
    'stage_overlay_opacity': stageOverlayOpacity,
    if (stageGradientSecondary != null)
      'stage_gradient_secondary': stageGradientSecondary,
    'stage_gradient_direction': stageGradientDirection.name,
    if (contentGradientSecondary != null)
      'content_gradient_secondary': contentGradientSecondary,
    'content_gradient_direction': contentGradientDirection.name,
    if (cardGradientSecondary != null)
      'card_gradient_secondary': cardGradientSecondary,
    'card_gradient_direction': cardGradientDirection.name,
    if (backgroundImageFileName != null)
      'background_image_file_name': backgroundImageFileName,
    'background_image_fit': backgroundImageFit.name,
    'background_image_alignment': backgroundImageAlignment.name,
    'background_image_opacity': backgroundImageOpacity,
    'dashboard_layout_mode': dashboardLayoutMode.name,
    'dashboard_density': dashboardDensity.name,
    'use_glass_surface': useGlassSurface,
    'use_liquid_glass_surface': useLiquidGlassSurface,
  };

  factory CustomTheme.fromJson(Map<String, Object?> json) {
    final rawPalette = json['palette'];
    if (rawPalette is! Map) throw ArgumentError.value(rawPalette, 'palette');
    double readFinite(String key) {
      final value = json[key];
      if (value is! num || !value.isFinite) {
        throw ArgumentError.value(value, key, 'must be a finite number');
      }
      return value.toDouble();
    }

    int? readOptionalColor(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! int || value < 0 || value > 0xffffffff) {
        throw ArgumentError.value(value, key, 'must be an ARGB 32-bit value');
      }
      return value;
    }

    GradientDirection readDirection(String key) => switch (json[key]) {
      null || 'topBottom' => GradientDirection.topBottom,
      'leftRight' => GradientDirection.leftRight,
      'diagonal' => GradientDirection.diagonal,
      final value => throw ArgumentError.value(value, key),
    };

    final rawLayout = json['layout'];
    final layout = switch (rawLayout) {
      'dashboard' => ThemeLayout.dashboard,
      'stage' => ThemeLayout.stage,
      _ => throw ArgumentError.value(rawLayout, 'layout'),
    };
    final rawName = json['name'];
    final rawId = json['id'];
    final rawBackground = json['background_image_file_name'];
    final rawFit = json['background_image_fit'];
    final rawAlignment = json['background_image_alignment'];
    if (rawName is! String ||
        rawId is! String ||
        (rawBackground != null && rawBackground is! String) ||
        (rawFit != null && rawFit is! String) ||
        (rawAlignment != null && rawAlignment is! String)) {
      throw ArgumentError('Invalid custom theme JSON');
    }
    return CustomTheme(
      id: rawId,
      name: rawName,
      layout: layout,
      palette: ThemePalette.fromJson(Map<String, Object?>.from(rawPalette)),
      cardRadius: readFinite('card_radius'),
      controlRadius: readFinite('control_radius'),
      contentRadius: readFinite('content_radius'),
      shadowOpacity: readFinite('shadow_opacity'),
      stageOverlayOpacity: readFinite('stage_overlay_opacity'),
      stageGradientSecondary: readOptionalColor('stage_gradient_secondary'),
      stageGradientDirection: readDirection('stage_gradient_direction'),
      contentGradientSecondary: readOptionalColor('content_gradient_secondary'),
      contentGradientDirection: readDirection('content_gradient_direction'),
      cardGradientSecondary: readOptionalColor('card_gradient_secondary'),
      cardGradientDirection: readDirection('card_gradient_direction'),
      backgroundImageFileName: rawBackground as String?,
      backgroundImageFit: switch (rawFit) {
        null || 'cover' => BackgroundImageFit.cover,
        'contain' => BackgroundImageFit.contain,
        'fill' => BackgroundImageFit.fill,
        _ => throw ArgumentError.value(rawFit, 'background_image_fit'),
      },
      backgroundImageAlignment: switch (rawAlignment) {
        null || 'center' => BackgroundImageAlignment.center,
        'left' => BackgroundImageAlignment.left,
        'right' => BackgroundImageAlignment.right,
        'top' => BackgroundImageAlignment.top,
        'bottom' => BackgroundImageAlignment.bottom,
        _ => throw ArgumentError.value(
          rawAlignment,
          'background_image_alignment',
        ),
      },
      backgroundImageOpacity: json.containsKey('background_image_opacity')
          ? readFinite('background_image_opacity')
          : 1,
      dashboardLayoutMode: switch (json['dashboard_layout_mode']) {
        null || 'standard' => DashboardLayoutMode.standard,
        'focus' => DashboardLayoutMode.focus,
        final value => throw ArgumentError.value(
          value,
          'dashboard_layout_mode',
        ),
      },
      dashboardDensity: switch (json['dashboard_density']) {
        null || 'comfortable' => DashboardDensity.comfortable,
        'compact' => DashboardDensity.compact,
        final value => throw ArgumentError.value(value, 'dashboard_density'),
      },
      useGlassSurface: switch (json['use_glass_surface']) {
        null || false => false,
        true => true,
        final value => throw ArgumentError.value(value, 'use_glass_surface'),
      },
      useLiquidGlassSurface: switch (json['use_liquid_glass_surface']) {
        null || false => false,
        true => true,
        final value => throw ArgumentError.value(
          value,
          'use_liquid_glass_surface',
        ),
      },
    );
  }

  void _validate() {
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'must be a UUID');
    }
    if (name.isEmpty || name.length > 32) {
      throw ArgumentError.value(
        name,
        'name',
        'must contain 1 to 32 characters',
      );
    }
    if (cardRadius < 0 ||
        controlRadius < 0 ||
        contentRadius < 0 ||
        !cardRadius.isFinite ||
        !controlRadius.isFinite ||
        !contentRadius.isFinite) {
      throw ArgumentError('Theme radii must be finite and non-negative');
    }
    if (shadowOpacity < 0 ||
        shadowOpacity > 1 ||
        stageOverlayOpacity < 0 ||
        stageOverlayOpacity > 1 ||
        backgroundImageOpacity < 0 ||
        backgroundImageOpacity > 1 ||
        !shadowOpacity.isFinite ||
        !stageOverlayOpacity.isFinite ||
        !backgroundImageOpacity.isFinite) {
      throw ArgumentError('Theme opacities must be between zero and one');
    }
    final gradientColors = [
      stageGradientSecondary,
      contentGradientSecondary,
      cardGradientSecondary,
    ];
    if (gradientColors.any(
      (color) => color != null && (color < 0 || color > 0xffffffff),
    )) {
      throw ArgumentError('Gradient colors must be ARGB 32-bit values');
    }
    final fileName = backgroundImageFileName;
    if (fileName != null &&
        (fileName.isEmpty || fileName != _basename(fileName))) {
      throw ArgumentError.value(
        fileName,
        'backgroundImageFileName',
        'must be a managed basename',
      );
    }
  }

  static String _basename(String value) => value.split(RegExp(r'[\\/]')).last;

  @override
  bool operator ==(Object other) =>
      other is CustomTheme &&
      id == other.id &&
      name == other.name &&
      layout == other.layout &&
      palette == other.palette &&
      cardRadius == other.cardRadius &&
      controlRadius == other.controlRadius &&
      contentRadius == other.contentRadius &&
      shadowOpacity == other.shadowOpacity &&
      stageOverlayOpacity == other.stageOverlayOpacity &&
      stageGradientSecondary == other.stageGradientSecondary &&
      stageGradientDirection == other.stageGradientDirection &&
      contentGradientSecondary == other.contentGradientSecondary &&
      contentGradientDirection == other.contentGradientDirection &&
      cardGradientSecondary == other.cardGradientSecondary &&
      cardGradientDirection == other.cardGradientDirection &&
      backgroundImageFileName == other.backgroundImageFileName &&
      backgroundImageFit == other.backgroundImageFit &&
      backgroundImageAlignment == other.backgroundImageAlignment &&
      backgroundImageOpacity == other.backgroundImageOpacity &&
      dashboardLayoutMode == other.dashboardLayoutMode &&
      dashboardDensity == other.dashboardDensity &&
      useGlassSurface == other.useGlassSurface &&
      useLiquidGlassSurface == other.useLiquidGlassSurface;

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    layout,
    palette,
    cardRadius,
    controlRadius,
    contentRadius,
    shadowOpacity,
    stageOverlayOpacity,
    stageGradientSecondary,
    stageGradientDirection,
    contentGradientSecondary,
    contentGradientDirection,
    cardGradientSecondary,
    cardGradientDirection,
    backgroundImageFileName,
    backgroundImageFit,
    backgroundImageAlignment,
    backgroundImageOpacity,
    dashboardLayoutMode,
    dashboardDensity,
    useGlassSurface,
    useLiquidGlassSurface,
  ]);
}

class ThemeReference {
  const ThemeReference.builtin(this.builtinTheme) : customThemeId = null;
  const ThemeReference.custom(this.customThemeId) : builtinTheme = null;

  final AppTheme? builtinTheme;
  final String? customThemeId;
  bool get isBuiltin => builtinTheme != null;

  Map<String, String> toJson() => isBuiltin
      ? {'kind': 'builtin', 'theme': builtinTheme!.name}
      : {'kind': 'custom', 'custom_theme_id': customThemeId!};

  factory ThemeReference.fromJson(Object? value) {
    if (value is! Map) return const ThemeReference.builtin(AppTheme.miku);
    final kind = value['kind'];
    if (kind == 'builtin') {
      return ThemeReference.builtin(_parseBuiltin(value['theme']));
    }
    final id = value['custom_theme_id'];
    if (kind == 'custom' && id is String && _isUuid(id)) {
      return ThemeReference.custom(id);
    }
    return const ThemeReference.builtin(AppTheme.miku);
  }

  static AppTheme _parseBuiltin(Object? value) => switch (value) {
    'glass' || 'other' => AppTheme.glass,
    'cute' => AppTheme.cute,
    'mita' => AppTheme.mita,
    'nailong' => AppTheme.nailong,
    _ => AppTheme.miku,
  };

  static bool _isUuid(String value) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value);

  @override
  bool operator ==(Object other) =>
      other is ThemeReference &&
      builtinTheme == other.builtinTheme &&
      customThemeId == other.customThemeId;

  @override
  int get hashCode => Object.hash(builtinTheme, customThemeId);
}
