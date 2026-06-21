import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app_theme.dart';
import '../services/weather_service.dart';
import 'shimmer_loader.dart';

class WeatherPill extends StatelessWidget {
  final bool isDark;
  final bool isLoading;
  final String? error;
  final WeatherData? weather;
  final VoidCallback? onRetry;

  const WeatherPill({
    super.key,
    required this.isDark,
    required this.isLoading,
    required this.error,
    required this.weather,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ShimmerLoader(
        isDark: isDark,
        child: Container(
          width: 134,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.layer2(isDark),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          ),
        ),
      );
    }

    final weatherEmoji = _weatherEmoji(weather);
    final text = error != null
        ? "📍 Konum alınamadı · --°C"
        : "📍 ${weather?.cityName ?? ''} · ${weather?.temperature.round() ?? '--'}°C $weatherEmoji";

    final dotColor = _dotColor(weather?.temperature);
    final foreground = error != null
        ? AppTheme.tertiaryText(isDark)
        : AppTheme.primaryText(isDark);

    return GestureDetector(
      onTap: error != null ? onRetry : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF26262F)
              : Colors.white.withOpacity(0.92),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppTheme.mediumBorder(isDark), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ).animate().fadeIn(duration: 280.ms),
            const SizedBox(width: 8),
            Text(
              text,
              style: AppTheme.captionText(isDark).copyWith(
                color: foreground,
                fontWeight: FontWeight.w500,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _weatherEmoji(WeatherData? value) {
    if (value == null) return '';

    final main = value.mainCondition.toLowerCase();
    if (main.contains('clear')) return '☀️';
    if (main.contains('cloud')) return '☁️';
    if (main.contains('rain') || main.contains('drizzle')) return '🌧️';
    if (main.contains('snow')) return '❄️';
    if (main.contains('thunder')) return '⛈️';
    if (main.contains('mist') || main.contains('fog')) return '🌫️';
    if (main.contains('wind')) return '💨';
    return '🌤️';
  }

  Color _dotColor(double? temp) {
    if (temp == null) return AppTheme.textTertiary;
    if (temp < 10) return const Color(0xFF60A5FA);
    if (temp <= 20) return const Color(0xFFFBBF24);
    if (temp <= 28) return const Color(0xFF34D399);
    return const Color(0xFFF87171);
  }
}
