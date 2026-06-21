class PurchasePreferenceProfile {
  final Map<String, int> dislikedColors;
  final Map<String, int> dislikedCategories;
  final Map<String, int> dislikedStyles;
  final Map<String, int> dislikedItems;
  final Map<String, int> likedColors;
  final Map<String, int> likedCategories;
  final Map<String, int> likedStyles;
  final Map<String, int> likedItems;

  const PurchasePreferenceProfile({
    this.dislikedColors = const {},
    this.dislikedCategories = const {},
    this.dislikedStyles = const {},
    this.dislikedItems = const {},
    this.likedColors = const {},
    this.likedCategories = const {},
    this.likedStyles = const {},
    this.likedItems = const {},
  });

  factory PurchasePreferenceProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PurchasePreferenceProfile();

    return PurchasePreferenceProfile(
      dislikedColors: _intMap(json['disliked_colors']),
      dislikedCategories: _intMap(json['disliked_categories']),
      dislikedStyles: _intMap(json['disliked_styles']),
      dislikedItems: _intMap(json['disliked_items']),
      likedColors: _intMap(json['liked_colors']),
      likedCategories: _intMap(json['liked_categories']),
      likedStyles: _intMap(json['liked_styles']),
      likedItems: _intMap(json['liked_items']),
    );
  }

  bool get hasSignals =>
      dislikedColors.isNotEmpty ||
      dislikedCategories.isNotEmpty ||
      dislikedStyles.isNotEmpty ||
      dislikedItems.isNotEmpty ||
      likedColors.isNotEmpty ||
      likedCategories.isNotEmpty ||
      likedStyles.isNotEmpty ||
      likedItems.isNotEmpty;

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) return const {};

    return value.map((key, rawValue) {
      final parsed = rawValue is num
          ? rawValue.round()
          : int.tryParse(rawValue.toString()) ?? 0;
      return MapEntry(key.toString(), parsed);
    });
  }
}
