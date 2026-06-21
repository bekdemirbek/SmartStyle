import 'package:flutter/material.dart';

import '../app_theme.dart';

class GoldGradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool expanded;
  final double height;
  final EdgeInsetsGeometry padding;

  const GoldGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.leading,
    this.expanded = false,
    this.height = 54,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppTheme.backgroundPrimary : AppTheme.textPrimaryLight;

    final button = DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: Size(expanded ? double.infinity : 0, height),
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          foregroundColor: textColor,
        ),
        child: Row(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ],
            Text(
              label,
              style: AppTheme.body(isDark).copyWith(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );

    if (expanded) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
