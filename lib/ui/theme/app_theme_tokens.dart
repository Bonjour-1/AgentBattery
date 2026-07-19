import 'package:flutter/material.dart';

import '../../models/custom_theme.dart';

LinearGradient _customGradient(
  int primary,
  int? secondary,
  GradientDirection direction,
) {
  final (begin, end) = switch (direction) {
    GradientDirection.topBottom => (
      Alignment.topCenter,
      Alignment.bottomCenter,
    ),
    GradientDirection.leftRight => (
      Alignment.centerLeft,
      Alignment.centerRight,
    ),
    GradientDirection.diagonal => (Alignment.topLeft, Alignment.bottomRight),
  };
  final primaryColor = Color(primary);
  return LinearGradient(
    begin: begin,
    end: end,
    colors: [primaryColor, Color(secondary ?? primary)],
  );
}

class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.kind,
    required this.name,
    required this.stageGradient,
    required this.contentGradient,
    required this.cardGradient,
    required this.pageBackground,
    required this.surface,
    required this.dialogBackground,
    required this.surfaceAlt,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.mutedText,
    required this.onStage,
    required this.outline,
    required this.success,
    required this.error,
    required this.statusIdle,
    required this.shadow,
    required this.cardRadius,
    required this.controlRadius,
    required this.contentRadius,
  });

  final AppTheme kind;
  final String name;
  final LinearGradient stageGradient;
  final LinearGradient contentGradient;
  final LinearGradient cardGradient;
  final Color pageBackground;
  Color get scaffold => pageBackground;
  final Color surface;
  final Color dialogBackground;
  final Color surfaceAlt;
  final Color primary;
  final Color secondary;
  final Color text;
  final Color mutedText;
  final Color onStage;
  final Color outline;
  final Color success;
  final Color error;
  final Color statusIdle;
  final Color shadow;
  final double cardRadius;
  final double controlRadius;
  final double contentRadius;

  static AppThemeTokens of(BuildContext context) =>
      Theme.of(context).extension<AppThemeTokens>() ?? forTheme(AppTheme.miku);

  static AppThemeTokens forTheme(AppTheme theme) => switch (theme) {
    AppTheme.miku => const AppThemeTokens(
      kind: AppTheme.miku,
      name: 'MIKU',
      stageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff0d5753), Color(0xff39c5bb), Color(0xffe9fffd)],
        stops: [0, .34, 1],
      ),
      contentGradient: LinearGradient(
        colors: [Color(0xeef3fffe), Color(0xffe9fffd)],
      ),
      cardGradient: LinearGradient(
        colors: [Color(0xd9f8fffe), Color(0xcce0f8f5)],
      ),
      pageBackground: Color(0xffe9fffd),
      surface: Color(0xfff3fffe),
      dialogBackground: Color(0xfff3fffe),
      surfaceAlt: Color(0xffddf8f5),
      primary: Color(0xff15968e),
      secondary: Color(0xffff8fab),
      text: Color(0xff123f3d),
      mutedText: Color(0xff557a77),
      onStage: Colors.white,
      outline: Color(0xffb6e4df),
      success: Color(0xff13867f),
      error: Color(0xffc34c70),
      statusIdle: Color(0xff687b79),
      shadow: Color(0xff0d5c57),
      cardRadius: 24,
      controlRadius: 16,
      contentRadius: 34,
    ),
    AppTheme.mita => const AppThemeTokens(
      kind: AppTheme.mita,
      name: 'MITA',
      stageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff1e1648), Color(0xff4a397d), Color(0xff7b5a8f)],
      ),
      contentGradient: LinearGradient(
        colors: [Color(0xfafffbf3), Color(0xf5eee7f4)],
      ),
      cardGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xeafffbf2), Color(0xddebe3f2)],
      ),
      pageBackground: Color(0xfff4edf5),
      surface: Color(0xfffffbf3),
      dialogBackground: Color(0xfffffbf3),
      surfaceAlt: Color(0xffeee5f1),
      primary: Color(0xff51409a),
      secondary: Color(0xffb33f5b),
      text: Color(0xff332955),
      mutedText: Color(0xff736587),
      onStage: Color(0xfffffaf6),
      outline: Color(0xffd0c0da),
      success: Color(0xff367b70),
      error: Color(0xffb33f5b),
      statusIdle: Color(0xff82768f),
      shadow: Color(0xff45336f),
      cardRadius: 20,
      controlRadius: 14,
      contentRadius: 28,
    ),
    AppTheme.nailong => const AppThemeTokens(
      kind: AppTheme.nailong,
      name: '奶龙',
      stageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xfffff7d9), Color(0xffffe886), Color(0xffffca55)],
      ),
      contentGradient: LinearGradient(
        colors: [Color(0xfafffdf3), Color(0xfafff3cf)],
      ),
      cardGradient: LinearGradient(
        colors: [Color(0xfffffff8), Color(0xfffff2c4)],
      ),
      pageBackground: Color(0xfffff8df),
      surface: Color(0xfffffcf1),
      dialogBackground: Color(0xfffffcf1),
      surfaceAlt: Color(0xfffff0bf),
      primary: Color(0xffe8891f),
      secondary: Color(0xffffb531),
      text: Color(0xff603b13),
      mutedText: Color(0xff9b6d34),
      onStage: Color(0xff603b13),
      outline: Color(0xffffd473),
      success: Color(0xff4a9b6e),
      error: Color(0xffc5573d),
      statusIdle: Color(0xff9b7f55),
      shadow: Color(0xffd98724),
      cardRadius: 23,
      controlRadius: 17,
      contentRadius: 32,
    ),
    AppTheme.glass => const AppThemeTokens(
      kind: AppTheme.glass,
      name: '玻璃',
      stageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffeaf3ff), Color(0xfff8f9ff), Color(0xffe6ecff)],
      ),
      contentGradient: LinearGradient(
        colors: [Color(0xeefeffff), Color(0xfff5f7ff)],
      ),
      cardGradient: LinearGradient(
        colors: [Color(0xfffdfdff), Color(0xffedf1ff)],
      ),
      pageBackground: Color(0xfff5f7ff),
      surface: Color(0xfffbfcff),
      dialogBackground: Color(0xfffbfcff),
      surfaceAlt: Color(0xffedf1ff),
      primary: Color(0xff6d7cff),
      secondary: Color(0xff4bc9ae),
      text: Color(0xff28335b),
      mutedText: Color(0xff69739a),
      onStage: Color(0xff33416d),
      outline: Color(0xffd2daf5),
      success: Color(0xff248f79),
      error: Color(0xffb95775),
      statusIdle: Color(0xff77809c),
      shadow: Color(0xff6d7cff),
      cardRadius: 26,
      controlRadius: 18,
      contentRadius: 38,
    ),
    AppTheme.cute => const AppThemeTokens(
      kind: AppTheme.cute,
      name: '可爱风',
      stageGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xffffd2df), Color(0xffff8fab), Color(0xffffe2ec)],
      ),
      contentGradient: LinearGradient(
        colors: [Color(0xfffffbfc), Color(0xffffeaf1)],
      ),
      cardGradient: LinearGradient(
        colors: [Color(0xfffffeff), Color(0xffffe2ec)],
      ),
      pageBackground: Color(0xfffff8fa),
      surface: Color(0xfffffbfc),
      dialogBackground: Color(0xfffffbfc),
      surfaceAlt: Color(0xffffe2ec),
      primary: Color(0xffff6f91),
      secondary: Color(0xffff8fab),
      text: Color(0xff633447),
      mutedText: Color(0xff936779),
      onStage: Color(0xff713449),
      outline: Color(0xffffc6d6),
      success: Color(0xff378a74),
      error: Color(0xffbd456b),
      statusIdle: Color(0xff937080),
      shadow: Color(0xffff8fab),
      cardRadius: 32,
      controlRadius: 24,
      contentRadius: 42,
    ),
  };

  factory AppThemeTokens.custom(CustomTheme theme) {
    final palette = theme.palette;
    return AppThemeTokens(
      // Custom themes do not have an AppTheme enum value. This marker is only
      // required by the existing non-nullable token API.
      kind: AppTheme.glass,
      name: theme.name,
      stageGradient: _customGradient(
        palette.stage,
        theme.stageGradientSecondary,
        theme.stageGradientDirection,
      ),
      contentGradient: _customGradient(
        palette.content,
        theme.contentGradientSecondary,
        theme.contentGradientDirection,
      ),
      cardGradient: _customGradient(
        palette.card,
        theme.cardGradientSecondary,
        theme.cardGradientDirection,
      ),
      pageBackground: Color(palette.pageBackground),
      surface: Color(palette.card),
      dialogBackground: Color(palette.dialogBackground),
      surfaceAlt: Color(palette.cardAlt),
      primary: Color(palette.primary),
      secondary: Color(palette.secondary),
      text: Color(palette.text),
      mutedText: Color(palette.mutedText),
      onStage: Color(palette.onStage),
      outline: Color(palette.outline),
      success: Color(palette.success),
      error: Color(palette.error),
      statusIdle: Color(palette.statusIdle),
      shadow: Color(palette.shadow),
      cardRadius: theme.cardRadius,
      controlRadius: theme.controlRadius,
      contentRadius: theme.contentRadius,
    );
  }

  @override
  AppThemeTokens copyWith() => this;

  @override
  AppThemeTokens lerp(
    covariant ThemeExtension<AppThemeTokens>? other,
    double t,
  ) => this;

  ThemeData materialTheme() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: primary,
          secondary: secondary,
          surface: surface,
          error: error,
          onSurface: text,
          outline: outline,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBackground,
      fontFamily: 'Microsoft YaHei UI',
      extensions: [this],
      appBarTheme: AppBarTheme(
        backgroundColor: pageBackground,
        foregroundColor: text,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: shape,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: shape,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: outline),
        shape: shape,
      ),
    );
  }
}
