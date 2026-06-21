import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app_theme.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppTheme.frosted(
      isDark: isDark,
      radius: 28,
      child: SizedBox(
        height: 94,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.other_houses_outlined,
                  activeIcon: Icons.home_rounded,
                  active: currentIndex == 0,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  icon: Icons.dry_cleaning_outlined,
                  activeIcon: Icons.dry_cleaning_rounded,
                  active: currentIndex == 1,
                  onTap: () => onTap(1),
                ),
                const SizedBox(width: 62),
                _NavItem(
                  icon: Icons.bookmark_border_rounded,
                  activeIcon: Icons.bookmark_rounded,
                  active: currentIndex == 3,
                  onTap: () => onTap(3),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  active: currentIndex == 4,
                  onTap: () => onTap(4),
                ),
              ],
            ),
            Positioned(
              top: -10,
              child: GestureDetector(
                onTap: () => onTap(2),
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.14)
                          : Colors.white.withOpacity(0.8),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.gold(isDark).withOpacity(0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add_a_photo_outlined,
                      color: isDark
                          ? AppTheme.textOnGold
                          : AppTheme.textPrimaryLight,
                      size: 26,
                    ),
                  ),
                ).animate(target: currentIndex == 2 ? 1 : 0).scale(
                      begin: const Offset(1, 1),
                      end: const Offset(1.08, 1.08),
                      duration: 280.ms,
                      curve: Curves.easeOutBack,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppTheme.gold(isDark);
    final inactiveColor = isDark
        ? AppTheme.secondaryText(true).withOpacity(0.78)
        : AppTheme.tertiaryText(false);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: active
                    ? activeColor.withOpacity(isDark ? 0.14 : 0.12)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                active ? activeIcon : icon,
                size: active ? 22 : 21,
                color: active ? activeColor : inactiveColor,
              ),
            ).animate(target: active ? 1 : 0).scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.15, 1.15),
                  duration: 280.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: active ? 5 : 4,
              height: active ? 5 : 4,
              decoration: BoxDecoration(
                color: active ? activeColor : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
