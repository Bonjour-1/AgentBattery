import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme_tokens.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.gradient,
    this.radius,
    this.border,
    this.shadowAlpha = .10,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  final BorderRadius? radius;
  final Border? border;
  final double shadowAlpha;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final surfaceRadius = radius ?? BorderRadius.circular(tokens.cardRadius);
    final decoration = BoxDecoration(
      gradient: gradient ?? tokens.cardGradient,
      borderRadius: surfaceRadius,
      border: border ?? Border.all(color: tokens.outline),
      boxShadow: shadowAlpha <= 0
          ? null
          : [
              BoxShadow(
                color: tokens.shadow.withValues(alpha: shadowAlpha),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
    );
    final content = DecoratedBox(
      decoration: decoration,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (!tokens.isGlassTheme) return content;
    return ClipRRect(
      borderRadius: surfaceRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: content,
      ),
    );
  }
}
