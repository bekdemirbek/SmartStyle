import 'package:flutter/material.dart';

class WardrobeAnalysis {
  final int score;
  final int totalItems;
  final String statusTitle;
  final String statusMessage;
  final Map<String, int> counts;
  final List<WardrobeMetric> metrics;
  final List<WardrobeInsight> insights;
  final List<PurchaseSuggestion> suggestions;
  final List<String> dominantColors;
  final Map<String, int> seasonCounts;
  final int topCount;
  final int bottomCount;
  final int shoeCount;

  const WardrobeAnalysis({
    required this.score,
    required this.totalItems,
    required this.statusTitle,
    required this.statusMessage,
    required this.counts,
    required this.metrics,
    required this.insights,
    required this.suggestions,
    this.dominantColors = const [],
    this.seasonCounts = const {
      'kis': 0,
      'yaz': 0,
      'ilkbahar': 0,
      'sonbahar': 0,
    },
    this.topCount = 0,
    this.bottomCount = 0,
    this.shoeCount = 0,
  });

  int get categoryBalance => _metricScore('Kategori dengesi');
  int get colorHarmony => _metricScore('Renk uyumu');
  int get seasonBalance => _metricScore('Mevsim dengesi');
  int get versatility => _metricScore('Çok yönlülük');

  int _metricScore(String label) {
    for (final metric in metrics) {
      if (metric.label == label) return metric.score;
    }
    return 0;
  }
}

class WardrobeMetric {
  final String label;
  final int score;
  final Color color;
  final String explanation;
  final String detail;

  const WardrobeMetric({
    required this.label,
    required this.score,
    required this.color,
    required this.explanation,
    required this.detail,
  });
}

class WardrobeInsight {
  final IconData icon;
  final String title;
  final String message;

  const WardrobeInsight({
    required this.icon,
    required this.title,
    required this.message,
  });
}

class PurchaseSuggestion {
  final IconData icon;
  final String title;
  final String message;
  final String impact;
  final Color color;

  const PurchaseSuggestion({
    required this.icon,
    required this.title,
    required this.message,
    required this.impact,
    required this.color,
  });
}
