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
    this.blur = true,
    this.shadowAlpha = .10,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Gradient? gradient;
  final BorderRadius? radius;
  final Border? border;
  final bool blur;
  final double shadowAlpha;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final surfaceRadius = radius ?? BorderRadius.circular(tokens.cardRadius);
    final surfaceGradient = gradient ?? tokens.cardGradient;
    final decoration = BoxDecoration(
      gradient: surfaceGradient,
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
    final childContent = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    final content = DecoratedBox(
      decoration: decoration,
      child: tokens.useLiquidGlassSurface
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: surfaceRadius,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xaaffffff),
                            Color(0x33ffffff),
                            Color(0x55c7eaff),
                          ],
                          stops: [0, .38, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                childContent,
              ],
            )
          : childContent,
    );
    if (!tokens.isGlassTheme || !blur) return content;
    return ClipRRect(
      borderRadius: surfaceRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: content,
      ),
    );
  }
}
