import 'dart:math';

import '../models/outfit_recommendation_models.dart';
import '../models/travel_mode_models.dart';

class TravelModeService {
  PackingResult createPackingPlan({
    required List<ClothingItem> wardrobe,
    required TripDetails trip,
    String userGender = 'unspecified',
    int variationSeed = 0,
    PackingFeedback? feedback,
  }) {
    final maxPieces = _hasComplaint(feedback, 'too_many_items')
        ? max(3, trip.maxPieces - 2)
        : trip.maxPieces;
    final excludedIds = feedback?.excludedItemIds.toSet() ?? const <String>{};
    final profileSafeWardrobe = wardrobe
        .where((item) => !_isGenderIncompatible(item, userGender))
        .toList();
    final sourceWardrobe =
        profileSafeWardrobe.isNotEmpty ? profileSafeWardrobe : wardrobe;
    final weatherSafe = sourceWardrobe
        .where((item) => !excludedIds.contains(item.id))
        .where((item) => _isWeatherCompatible(item, trip.weatherTemp))
        .toList();
    final pool = weatherSafe.isNotEmpty
        ? weatherSafe
        : sourceWardrobe
            .where((item) => !excludedIds.contains(item.id))
            .toList();
    final missingPieces = _missingPieces(pool, trip);
    final selected = _selectPackingItems(pool, trip, maxPieces, feedback);
    final outfits = _generateOutfits(selected, trip, feedback);
    final dayPlans = _buildDayPlans(
      outfits,
      trip,
      variationSeed: variationSeed,
      feedback: feedback,
    );
    final packingItems = _packingItemsFromDayPlans(
      dayPlans: dayPlans,
      fallbackItems: selected,
    );
    final reuseHighlights = _buildReuseHighlights(dayPlans);
    final coverageScore = _coverageScore(
      trip: trip,
      dayPlans: dayPlans,
      selectedItems: packingItems,
      missingPieces: missingPieces,
    );

    // TODO: Wire PackingResult into the future Travel Mode / Valiz Asistani UI.
    // TODO: Use dayPlans later for optional packing/reminder notifications.
    return PackingResult(
      selectedItems: packingItems,
      outfits: outfits,
      pieceCount: packingItems.length,
      outfitCount: dayPlans.where((plan) => plan.outfitItems.isNotEmpty).length,
      coverageScore: coverageScore,
      missingPieces: missingPieces,
      reuseHighlights: reuseHighlights,
      dayPlans: dayPlans,
    );
  }

  String buildGeminiPrompt({
    required TripDetails trip,
    required List<ClothingItem> wardrobe,
    String userGender = 'unspecified',
  }) {
    final maxPieces = trip.maxPieces;
    final wardrobeSummary = wardrobe.map(_wardrobePromptLine).join('\n');
    final tripOccasions = trip.occasions.join(', ');

    return '''
Sen bir seyahat stilisti asistanisin.
Kullanici ${trip.tripDays} gunluk ${trip.destination} seyahatine gidiyor.
Kullanici cinsiyeti: $userGender
Program: $tripOccasions
Hava: ${trip.weatherTemp}°C
Valiz tipi: ${trip.luggageType} maksimum $maxPieces parca.

Mevcut dolap:
$wardrobeSummary

Gorev:
1. Maksimum $maxPieces parcayla tum gunleri karsilayan kombin plani yap
2. Her gun icin ayri kombin oner
3. Parcalarin birden fazla gunde nasil kullanilacagini goster
4. Eksik parca varsa belirt
5. Cinsiyet erkekse etek, elbise, body, tulum, crop, bluz, topuklu, stiletto, palazzo ve tayt secme
6. Cinsiyet kadinsa bu parcalari uygun programlarda degerlendirebilirsin

Yaniti sadece JSON olarak ver:
{
  "selectedItemIds": [],
  "dayPlans": [
    {
      "day": 1,
      "occasion": "",
      "outfitItemIds": [],
      "note": ""
    }
  ],
  "reuseHighlights": [
    {
      "itemId": "",
      "usedOnDays": [],
      "reason": ""
    }
  ],
  "missingPieces": []
}''';
  }

  List<ClothingItem> _selectPackingItems(
    List<ClothingItem> pool,
    TripDetails trip,
    int maxPieces,
    PackingFeedback? feedback,
  ) {
    final sorted = [...pool]
      ..sort(
        (a, b) =>
            _scoreItem(b, trip, feedback).compareTo(_scoreItem(a, trip, feedback)),
      );
    final selected = <ClothingItem>[];
    final pinnedIds = feedback?.pinnedItemIds.toSet() ?? const <String>{};

    for (final item in sorted.where((item) => pinnedIds.contains(item.id))) {
      if (selected.length >= maxPieces) break;
      selected.add(item);
    }

    void addBest(ClothingCategory category) {
      if (selected.length >= maxPieces) return;
      final candidate = sorted
          .where((item) => item.category == category)
          .where((item) => !selected.any((picked) => picked.id == item.id))
          .firstOrNull;
      if (candidate != null) selected.add(candidate);
    }

    addBest(ClothingCategory.top);
    addBest(ClothingCategory.bottom);
    addBest(ClothingCategory.shoes);

    if (_hasFormalOccasion(trip) && !_hasComplaint(feedback, 'too_formal')) {
      for (final category in [
        ClothingCategory.top,
        ClothingCategory.bottom,
        ClothingCategory.shoes,
      ]) {
        if (selected.length >= maxPieces) break;
        final formal = sorted
            .where((item) => item.category == category)
            .where(_isFormal)
            .where((item) => !selected.any((picked) => picked.id == item.id))
            .firstOrNull;
        if (formal != null) selected.add(formal);
      }
    }

    // Greedy selection favors high-scoring connectors after the required outfit
    // categories are present. This keeps Phase 1 predictable and testable.
    for (final item in sorted) {
      if (selected.length >= maxPieces) break;
      if (selected.any((picked) => picked.id == item.id)) continue;
      selected.add(item);
    }

    return selected;
  }

  double _scoreItem(
    ClothingItem item,
    TripDetails trip,
    PackingFeedback? feedback,
  ) {
    final normalizedOccasions = trip.occasions.map(_normalize).toList();
    final occasionCoverage = normalizedOccasions
        .where((occasion) => _matchesOccasion(item, occasion))
        .length;
    final neutralBonus = _isNeutralColor(item.color) ? 16.0 : 3.0;
    final categoryBonus = item.category == ClothingCategory.top ? 6.0 : 3.0;
    final wantsLessFormal = _hasComplaint(feedback, 'too_formal');
    final formalityBonus = wantsLessFormal
        ? (_isFormal(item) ? -24.0 : 0.0)
        : (_hasFormalOccasion(trip) && _isFormal(item) ? 18.0 : 0);
    final seasonBonus = _seasonScore(item, trip.weatherTemp);
    final favoriteBonus = item.favorite ? 4.0 : 0.0;
    final rawOccasionBonus = _rawTags(item, [
      'occasion_tags',
      'occasionTags',
      'occasions',
    ]).length * 2.0;

    return (occasionCoverage * 22.0) +
        seasonBonus +
        formalityBonus +
        neutralBonus +
        categoryBonus +
        favoriteBonus +
        rawOccasionBonus;
  }

  List<List<ClothingItem>> _generateOutfits(
    List<ClothingItem> selected,
    TripDetails trip,
    PackingFeedback? feedback,
  ) {
    final tops = selected.where((item) => item.isTop).toList();
    final bottoms = selected.where((item) => item.isBottom).toList();
    final shoes = selected.where((item) => item.isShoes).toList();
    final outerwear = selected.where((item) => item.isOuterwear).toList();
    final needsOuterwear = trip.weatherTemp < 12;
    final outfits = <List<ClothingItem>>[];

    for (final top in tops) {
      for (final bottom in bottoms) {
        for (final shoe in shoes) {
          final base = [top, bottom, shoe];
          if (needsOuterwear && outerwear.isNotEmpty) {
            for (final outer in outerwear) {
              outfits.add([...base, outer]);
            }
          } else {
            outfits.add(base);
            for (final outer in outerwear.take(2)) {
              outfits.add([...base, outer]);
            }
          }
        }
      }
    }

    outfits.sort((a, b) {
      final scoreA = _outfitVersatilityScore(a, trip, feedback);
      final scoreB = _outfitVersatilityScore(b, trip, feedback);
      return scoreB.compareTo(scoreA);
    });
    return outfits;
  }

  List<TravelDayPlan> _buildDayPlans(
    List<List<ClothingItem>> outfits,
    TripDetails trip,
    {int variationSeed = 0, PackingFeedback? feedback}
  ) {
    final plans = <TravelDayPlan>[];
    final usedKeys = <String>{};
    final usedItemCounts = <String, int>{};
    String? previousTopId;

    for (var index = 0; index < trip.tripDays; index++) {
      final occasion = trip.occasions.isEmpty
          ? 'casual'
          : trip.occasions[index % trip.occasions.length];
      final normalizedOccasion = _normalize(occasion);
      final candidates = outfits.where((outfit) {
        final key = _outfitKey(outfit);
        return !usedKeys.contains(key) &&
            _outfitMatchesOccasion(outfit, normalizedOccasion, feedback);
      }).toList();
      final fallbackCandidates = outfits
          .where((outfit) => !usedKeys.contains(_outfitKey(outfit)))
          .toList();
      final searchPool = candidates.isNotEmpty ? candidates : fallbackCandidates;
      final selected = _chooseDayOutfit(
            candidates: searchPool,
            previousTopId: previousTopId,
            usedItemCounts: usedItemCounts,
            occasion: normalizedOccasion,
            variationSeed: variationSeed + index,
            feedback: feedback,
          ) ??
          _chooseDayOutfit(
            candidates: outfits,
            previousTopId: previousTopId,
            usedItemCounts: usedItemCounts,
            occasion: normalizedOccasion,
            variationSeed: variationSeed + index,
            feedback: feedback,
          ) ??
          const <ClothingItem>[];
      final top = selected.where((item) => item.isTop).firstOrNull;
      final key = _outfitKey(selected);

      if (key.isNotEmpty) usedKeys.add(key);
      for (final item in selected) {
        usedItemCounts[item.id] = (usedItemCounts[item.id] ?? 0) + 1;
      }
      previousTopId = top?.id ?? previousTopId;
      plans.add(
        TravelDayPlan(
          day: index + 1,
          occasion: occasion,
          outfitItems: selected,
          note: _dayPlanNote(selected, normalizedOccasion),
        ),
      );
    }

    return plans;
  }

  List<ClothingItem> _packingItemsFromDayPlans({
    required List<TravelDayPlan> dayPlans,
    required List<ClothingItem> fallbackItems,
  }) {
    final itemsById = <String, ClothingItem>{};
    for (final plan in dayPlans) {
      for (final item in plan.outfitItems) {
        itemsById.putIfAbsent(item.id, () => item);
      }
    }

    if (itemsById.isEmpty) return fallbackItems;
    return fallbackItems.where((item) => itemsById.containsKey(item.id)).toList();
  }

  List<ClothingItem>? _chooseDayOutfit(
      {required List<List<ClothingItem>> candidates,
      required String? previousTopId,
      required Map<String, int> usedItemCounts,
      required String occasion,
      int variationSeed = 0,
      PackingFeedback? feedback}) {
    if (candidates.isEmpty) return null;

    final ranked = candidates.map((outfit) {
      return _DayOutfitChoice(
        outfit: outfit,
        score: _dayDiversityScore(
          outfit: outfit,
          previousTopId: previousTopId,
          usedItemCounts: usedItemCounts,
          occasion: occasion,
          feedback: feedback,
        ),
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topPoolSize = min(3, ranked.length);
    final selectedIndex = variationSeed.abs() % topPoolSize;
    return ranked[selectedIndex].outfit;
  }

  double _dayDiversityScore({
    required List<ClothingItem> outfit,
    required String? previousTopId,
    required Map<String, int> usedItemCounts,
    required String occasion,
    PackingFeedback? feedback,
  }) {
    var score = 0.0;
    final top = outfit.where((item) => item.isTop).firstOrNull;
    final bottom = outfit.where((item) => item.isBottom).firstOrNull;
    final shoes = outfit.where((item) => item.isShoes).firstOrNull;

    // Travel mode should reuse pieces, but day plans should still feel varied.
    // Penalize repeated pieces by category, with tops receiving the strongest
    // penalty because users notice repeated tops first.
    for (final item in outfit) {
      final count = usedItemCounts[item.id] ?? 0;
      final categoryPenalty = item.isTop
          ? 32.0
          : item.isBottom
              ? 18.0
              : item.isShoes
                  ? 10.0
                  : 6.0;
      final repeatMultiplier = _hasComplaint(feedback, 'too_repetitive') ? 2.0 : 1.0;
      score -= count * categoryPenalty * repeatMultiplier;

      if (count == 0) score += item.isTop ? 24.0 : 10.0;
      if (_matchesOccasion(item, occasion)) score += 6.0;
    }

    if (top != null && top.id == previousTopId) score -= 80;
    if (top != null && (usedItemCounts[top.id] ?? 0) == 0) score += 18;
    if (bottom != null && (usedItemCounts[bottom.id] ?? 0) == 0) score += 8;
    if (shoes != null && (usedItemCounts[shoes.id] ?? 0) == 0) score += 4;

    final colorMultiplier = _hasComplaint(feedback, 'color_mismatch') ? 3.0 : 1.0;
    score += _colorCompatibilityScore(outfit) * colorMultiplier;
    return score;
  }

  List<String> _missingPieces(List<ClothingItem> pool, TripDetails trip) {
    final missing = <String>{};
    final hasTop = pool.any((item) => item.isTop);
    final hasBottom = pool.any((item) => item.isBottom);
    final hasShoes = pool.any((item) => item.isShoes);

    if (!hasTop) missing.add('ust giyim');
    if (!hasBottom) missing.add('alt giyim');
    if (!hasShoes) missing.add('ayakkabi');

    if (_hasFormalOccasion(trip)) {
      if (!pool.any((item) => item.isTop && _isFormal(item))) {
        missing.add('formal ust');
      }
      if (!pool.any((item) => item.isBottom && _isFormal(item))) {
        missing.add('formal alt');
      }
      if (!pool.any((item) => item.isShoes && _isFormal(item))) {
        missing.add('formal ayakkabi');
      }
    }

    if (trip.weatherTemp < 10 && !pool.any((item) => item.isOuterwear)) {
      missing.add('dis giyim');
    }

    return missing.toList();
  }

  List<TravelReuseHighlight> _buildReuseHighlights(List<TravelDayPlan> plans) {
    final daysByItemId = <String, List<int>>{};
    final itemById = <String, ClothingItem>{};

    for (final plan in plans) {
      for (final item in plan.outfitItems) {
        itemById[item.id] = item;
        daysByItemId.putIfAbsent(item.id, () => []).add(plan.day);
      }
    }

    return daysByItemId.entries
        .where((entry) => entry.value.length > 1)
        .map(
          (entry) => TravelReuseHighlight(
            item: itemById[entry.key]!,
            usedOnDays: entry.value,
            reason: 'Farkli kombinlerle tekrar kullanilabilen baglayici parca.',
          ),
        )
        .toList();
  }

  double _coverageScore({
    required TripDetails trip,
    required List<TravelDayPlan> dayPlans,
    required List<ClothingItem> selectedItems,
    required List<String> missingPieces,
  }) {
    if (trip.tripDays <= 0) return 0;
    final plannedDays = dayPlans
        .where((plan) => plan.outfitItems.where((item) => item.isTop).isNotEmpty)
        .length;
    final dayCoverage = plannedDays / trip.tripDays;
    final categoryCoverage = [
          selectedItems.any((item) => item.isTop),
          selectedItems.any((item) => item.isBottom),
          selectedItems.any((item) => item.isShoes),
        ].where((covered) => covered).length /
        3;
    final missingPenalty = min(0.35, missingPieces.length * 0.07);
    return max(0, min(1, (dayCoverage * 0.65) + (categoryCoverage * 0.35) - missingPenalty));
  }

  bool _isWeatherCompatible(ClothingItem item, int temperatureC) {
    final type = _normalize(item.subCategory);
    if (temperatureC >= 28) {
      if (item.thickness == Thickness.heavy) return false;
      if (type.contains('kaban') ||
          type.contains('mont') ||
          type.contains('bot') ||
          type.contains('kazak') ||
          type.contains('hoodie')) {
        return false;
      }
    }

    if (temperatureC <= 5) {
      if (type.contains('sort') ||
          type.contains('atlet') ||
          type.contains('sandalet') ||
          type.contains('terlik') ||
          type.contains('crop')) {
        return false;
      }
    }

    return true;
  }

  bool _matchesOccasion(ClothingItem item, String normalizedOccasion) {
    if (normalizedOccasion.contains('work') ||
        normalizedOccasion.contains('is') ||
        normalizedOccasion.contains('office') ||
        normalizedOccasion.contains('dinner') ||
        normalizedOccasion.contains('aksam')) {
      return _isFormal(item);
    }
    if (normalizedOccasion.contains('beach') ||
        normalizedOccasion.contains('deniz')) {
      return item.thickness == Thickness.light &&
          (item.styles.contains(StylePreference.casual) ||
              item.styles.contains(StylePreference.sport));
    }
    if (normalizedOccasion.contains('bayram') ||
        normalizedOccasion.contains('memleket')) {
      return item.styles.contains(StylePreference.casual) ||
          item.styles.contains(StylePreference.smart) ||
          item.styles.contains(StylePreference.special);
    }
    if (normalizedOccasion.contains('travel') ||
        normalizedOccasion.contains('seyahat') ||
        normalizedOccasion.contains('sightseeing') ||
        normalizedOccasion.contains('casual')) {
      return item.styles.contains(StylePreference.casual) ||
          item.styles.contains(StylePreference.street) ||
          item.styles.contains(StylePreference.sport);
    }
    return true;
  }

  bool _outfitMatchesOccasion(
    List<ClothingItem> outfit,
    String occasion,
    PackingFeedback? feedback,
  ) {
    if (_isFormalOccasionText(occasion) &&
        !_hasComplaint(feedback, 'too_formal')) {
      return outfit.any(_isFormal);
    }
    return outfit.any((item) => _matchesOccasion(item, occasion));
  }

  bool _hasFormalOccasion(TripDetails trip) {
    return trip.occasions.any((occasion) => _isFormalOccasionText(_normalize(occasion)));
  }

  bool _isFormalOccasionText(String occasion) {
    return occasion.contains('dinner') ||
        occasion.contains('aksam') ||
        occasion.contains('work') ||
        occasion.contains('is') ||
        occasion.contains('office') ||
        occasion.contains('business') ||
        occasion.contains('toplanti') ||
        occasion.contains('bayram');
  }

  bool _isFormal(ClothingItem item) {
    final type = _normalize(item.subCategory);
    final formality = _rawText(item, ['formality', 'formalite']);
    return item.styles.contains(StylePreference.smart) ||
        item.styles.contains(StylePreference.special) ||
        formality.contains('formal') ||
        formality.contains('smart') ||
        type.contains('gomlek') ||
        type.contains('blazer') ||
        type.contains('klasik') ||
        type.contains('loafer') ||
        type.contains('oxford');
  }

  double _seasonScore(ClothingItem item, int temperatureC) {
    final preferred = _preferredSeason(temperatureC);
    if (item.seasons.contains(Season.all)) return 12;
    if (item.seasons.contains(preferred)) return 16;
    return 0;
  }

  Season _preferredSeason(int temperatureC) {
    if (temperatureC >= 24) return Season.summer;
    if (temperatureC >= 14) return Season.spring;
    if (temperatureC >= 7) return Season.autumn;
    return Season.winter;
  }

  double _outfitVersatilityScore(
    List<ClothingItem> outfit,
    TripDetails trip,
    PackingFeedback? feedback,
  ) {
    final colorMultiplier =
        _hasComplaint(feedback, 'color_mismatch') ? 3.0 : 1.0;
    return outfit.fold<double>(
          0,
          (score, item) => score + _scoreItem(item, trip, feedback),
        ) +
        (_colorCompatibilityScore(outfit) * colorMultiplier);
  }

  double _colorCompatibilityScore(List<ClothingItem> items) {
    final neutralCount = items.where((item) => _isNeutralColor(item.color)).length;
    final uniqueCount = items.map((item) => _normalize(item.color)).toSet().length;
    return (neutralCount * 4.0) + (uniqueCount <= 3 ? 6.0 : -4.0);
  }

  String _dayPlanNote(List<ClothingItem> outfit, String occasion) {
    if (outfit.isEmpty) return 'Bu gun icin yeterli parca bulunamadi.';
    if (_isFormalOccasionText(occasion) && outfit.any(_isFormal)) {
      return 'Formal programa uygun parcalar one alindi.';
    }
    return 'Az parcayla tekrar kullanima uygun kombin.';
  }

  String _wardrobePromptLine(ClothingItem item) {
    return '- ${item.id}: ${item.subCategory}, ${item.category.name}, '
        '${item.color}, stiller=${item.styles.map((style) => style.name).join('/')}, '
        'mevsim=${item.seasons.map((season) => season.name).join('/')}';
  }

  List<String> _rawTags(ClothingItem item, List<String> keys) {
    for (final key in keys) {
      final value = item.rawData[key];
      if (value is Iterable) {
        return value.map((entry) => entry.toString()).toList();
      }
      if (value is String && value.trim().isNotEmpty) {
        return value.split(',').map((entry) => entry.trim()).toList();
      }
    }
    return const [];
  }

  String _rawText(ClothingItem item, List<String> keys) {
    for (final key in keys) {
      final value = item.rawData[key];
      if (value != null) return _normalize(value.toString());
    }
    return '';
  }

  bool _isNeutralColor(String color) {
    final text = _normalize(color);
    return text.contains('siyah') ||
        text.contains('beyaz') ||
        text.contains('gri') ||
        text.contains('bej') ||
        text.contains('lacivert') ||
        text.contains('black') ||
        text.contains('white') ||
        text.contains('gray') ||
        text.contains('navy') ||
        text.contains('beige');
  }

  String _outfitKey(List<ClothingItem> items) {
    final ids = items.map((item) => item.id).toList()..sort();
    return ids.join('|');
  }

  bool _hasComplaint(PackingFeedback? feedback, String complaint) {
    return feedback?.complaints.contains(complaint) ?? false;
  }

  bool _isGenderIncompatible(ClothingItem item, String userGender) {
    if (_normalize(userGender) != 'male') return false;

    final text = _normalize(
      '${item.subCategory} ${item.category.name} ${item.rawData['tur'] ?? ''} '
      '${item.rawData['type'] ?? ''} ${item.rawData['styleTags'] ?? ''}',
    );

    return [
      'etek',
      'elbise',
      'body',
      'tulum',
      'tayt',
      'topuklu',
      'stiletto',
      'blok topuk',
      'ince bantli',
      'bluz',
      'crop',
      'palazzo',
      'cigarette',
      'kruvaze bluz',
      'wrap top',
      'saten midi',
      'pleated midi',
      'strappy heel',
      'block heel',
    ].any(text.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
  }
}

class _DayOutfitChoice {
  final List<ClothingItem> outfit;
  final double score;

  const _DayOutfitChoice({
    required this.outfit,
    required this.score,
  });
}
