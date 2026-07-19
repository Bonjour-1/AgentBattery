import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/custom_theme.dart';
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
    final liquid = tokens.useLiquidGlassSurface;
    final surfaceGradient = liquid
        ? _transparentGradient(
            gradient ?? tokens.cardGradient,
            tokens.glassTransparency,
          )
        : gradient ?? tokens.cardGradient;
    final highlight = tokens.glassHighlight;
    final opacity = 1 - .70 * tokens.glassTransparency;
    final blurSigma = switch (tokens.glassBlur) {
      GlassBlur.none => 0.0,
      GlassBlur.light => 10.0,
      GlassBlur.soft => 20.0,
    };
    final decoration = BoxDecoration(
      gradient: surfaceGradient,
      borderRadius: surfaceRadius,
      border: border ??
          Border.all(
            color: liquid
                ? Colors.white.withValues(alpha: (.22 + .50 * highlight) * opacity)
                : tokens.outline,
          ),
      boxShadow: shadowAlpha <= 0
          ? null
          : liquid
          ? [
              BoxShadow(
                color: tokens.shadow.withValues(
                  alpha: shadowAlpha * (0.60 + .95 * highlight),
                ),
                blurRadius: 34,
                spreadRadius: -2,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: .06 + .23 * highlight),
                blurRadius: 3,
                offset: const Offset(0, -1),
              ),
            ]
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
      child: liquid
          ? Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('liquid-glass-refraction'),
                      decoration: BoxDecoration(
                        borderRadius: surfaceRadius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(
                              alpha: .20 * opacity + .58 * highlight * opacity,
                            ),
                            Colors.white.withValues(
                              alpha: (.03 + .10 * highlight) * opacity,
                            ),
                            const Color(0xff7bdfff).withValues(
                              alpha: (.12 + .32 * highlight) * opacity,
                            ),
                          ],
                          stops: const [0, .35, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('liquid-glass-rim-light'),
                      decoration: BoxDecoration(
                        borderRadius: surfaceRadius,
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: (.24 + .62 * highlight) * opacity,
                          ),
                          width: 1.15,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x3378d9ff),
                            blurRadius: 12,
                            spreadRadius: -5,
                            offset: Offset(3, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                childContent,
              ],
            )
          : childContent,
    );
    if (!tokens.isGlassTheme || !blur || blurSigma == 0) return content;
    return ClipRRect(
      borderRadius: surfaceRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: content,
      ),
    );
  }

  static LinearGradient _transparentGradient(
    Gradient gradient,
    double transparency,
  ) {
    if (gradient is LinearGradient) {
      return LinearGradient(
        begin: gradient.begin,
        end: gradient.end,
        colors: [
          for (final color in gradient.colors)
            color.withValues(alpha: color.a * (1 - transparency)),
        ],
        stops: gradient.stops,
        tileMode: gradient.tileMode,
        transform: gradient.transform,
      );
    }
    return LinearGradient(
      colors: [Colors.white.withValues(alpha: 1 - transparency)],
    );
  }
}
