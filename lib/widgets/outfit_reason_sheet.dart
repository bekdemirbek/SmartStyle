import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/outfit_reason_data.dart';

class OutfitReasonSheet extends StatelessWidget {
  final OutfitReasonData reasonData;
  final VoidCallback? onSuggestedAction;

  const OutfitReasonSheet({
    super.key,
    required this.reasonData,
    this.onSuggestedAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : AppTheme.lightText;
    final scoreColor = _scoreColor(reasonData.overallScore);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Neden bu kombin önerildi?',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '%${reasonData.overallScore.round()} uyum',
                    style: TextStyle(
                      color: scoreColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ReasonRow(
              icon: Icons.thermostat_rounded,
              title: 'Hava uyumu',
              text: reasonData.weatherNote,
              isDark: isDark,
            ),
            _ReasonRow(
              icon: Icons.palette_rounded,
              title: 'Renk uyumu',
              text: reasonData.colorNote,
              isDark: isDark,
              progress: reasonData.colorScore / 100,
              progressColor: _scoreColor(reasonData.colorScore.toDouble()),
            ),
            _ReasonRow(
              icon: Icons.bar_chart_rounded,
              title: 'Parça kullanımı',
              text: reasonData.usageNote,
              isDark: isDark,
            ),
            if (reasonData.warningNote != null)
              _ReasonRow(
                icon: Icons.warning_amber_rounded,
                title: 'Dikkat',
                text: reasonData.warningNote!,
                isDark: isDark,
                iconColor: const Color(0xFFF0A92E),
              ),
            if (reasonData.suggestedAction != null && onSuggestedAction != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSuggestedAction,
                    child: Text('${reasonData.suggestedAction!} ↗'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 75) return const Color(0xFF62C584);
    if (score >= 50) return const Color(0xFFF0A92E);
    return const Color(0xFFE95F62);
  }
}

class _ReasonRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool isDark;
  final double? progress;
  final Color? progressColor;
  final Color? iconColor;

  const _ReasonRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.isDark,
    this.progress,
    this.progressColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF20242A);
    final subTextColor = isDark ? const Color(0xFFE1E3E8) : const Color(0xFF5E6470);

    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppTheme.gold(isDark)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1),
                      minHeight: 5,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progressColor ?? AppTheme.gold(isDark),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
