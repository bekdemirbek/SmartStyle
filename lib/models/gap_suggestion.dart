import 'wardrobe_item_model.dart';

class GapSuggestion {
  final WardrobeItem candidateItem;
  final int currentCombos;
  final int projectedCombos;
  final int gain;
  final double tasteScore;
  final int preferencePenalty;
  final int preferenceBoost;
  final String style;
  final List<String> occasion;
  final String formality;
  final double confidence;
  final String? followUpQuestion;
  final List<WardrobeItem> compatibleItems;
  final String reason;
  final String badgeLabel;
  final String badgeType;

  const GapSuggestion({
    required this.candidateItem,
    required this.currentCombos,
    required this.projectedCombos,
    required this.gain,
    this.tasteScore = 0,
    this.preferencePenalty = 0,
    this.preferenceBoost = 0,
    this.style = 'Casual',
    this.occasion = const ['daily'],
    this.formality = 'casual',
    this.confidence = 0,
    this.followUpQuestion,
    required this.compatibleItems,
    required this.reason,
    this.badgeLabel = '',
    this.badgeType = 'impact',
  });
}
