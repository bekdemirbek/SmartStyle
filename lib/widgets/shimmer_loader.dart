import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../app_theme.dart';

class ShimmerLoader extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const ShimmerLoader({
    super.key,
    required this.child,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: isDark ? AppTheme.surface2 : AppTheme.surface3Light,
      highlightColor: isDark ? AppTheme.surface3 : AppTheme.surface2Light,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}
