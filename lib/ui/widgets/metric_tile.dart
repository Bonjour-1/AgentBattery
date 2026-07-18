import 'package:flutter/material.dart';

import '../theme/app_theme_tokens.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.trailing,
  });
  final String label;
  final String value;
  final Color? accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: tokens.surface.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(tokens.controlRadius),
          border: Border.all(color: tokens.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: tokens.mutedText),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent ?? tokens.text,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
