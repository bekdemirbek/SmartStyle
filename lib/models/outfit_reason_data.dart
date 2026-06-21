class OutfitReasonData {
  final String weatherNote;
  final int colorScore;
  final String colorNote;
  final String usageNote;
  final String? warningNote;
  final String? suggestedAction;
  final double overallScore;

  const OutfitReasonData({
    required this.weatherNote,
    required this.colorScore,
    required this.colorNote,
    required this.usageNote,
    this.warningNote,
    this.suggestedAction,
    required this.overallScore,
  });
}
