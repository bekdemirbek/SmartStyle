import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/outfit_recommendation_models.dart';
import 'weather_service.dart';

class OutfitRecommendationService {
  static const Map<String, String> wardrobeCollections = {
    'Üst Giyim': 'ust_giyim',
    'Alt Giyim': 'alt_giyim',
    'Dış Giyim': 'dis_giyim',
    'Ayakkabı': 'ayakkabi',
    'Çorap': 'corap',
  };

  final FirebaseFirestore firestore;

  OutfitRecommendationService({FirebaseFirestore? firestore})
    : firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<ClothingItem>> fetchWardrobeItems(String userId) async {
    final items = <ClothingItem>[];

    for (final collection in wardrobeCollections.values) {
      final snapshot = await firestore
          .collection(collection)
          .where('user_id', isEqualTo: userId)
          .get();

      items.addAll(
        snapshot.docs.map(
          (doc) => ClothingItem.fromFirestore(doc: doc, collection: collection),
        ),
      );
    }

    return items;
  }

  Future<List<ClothingItem>> fetchWardrobeItemsByIds({
    required String userId,
    required Iterable<String> itemIds,
  }) async {
    final ids = itemIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];

    final allItems = await fetchWardrobeItems(userId);
    final idSet = ids.toSet();
    return allItems.where((item) => idSet.contains(item.id)).toList();
  }

  List<OutfitRecommendation> generateWeeklyRecommendations({
    required List<ClothingItem> wardrobe,
    String userGender = 'unspecified',
    required WeeklyStylePreference stylePreference,
    required Map<DateTime, WeatherProfile> weatherByDate,
    Map<DateTime, DayPlan> dayPlans = const {},
    DateTime? weekStart,
  }) {
    final start = _dateOnly(weekStart ?? DateTime.now());
    final allocation = stylePreference.allocationForWeek();
    final recommendations = <OutfitRecommendation>[];
    final usedCombinationKeys = <String>{};
    final usedItemCounts = <String, int>{};

    for (var dayIndex = 0; dayIndex < 7; dayIndex++) {
      final date = start.add(Duration(days: dayIndex));
      final plan = dayPlans[_dateOnly(date)];
      final planType = plan?.type ?? DayPlanType.normalDay;
      final baseStyle = allocation[dayIndex];
      final focusStyle = _styleForPlan(planType) ?? baseStyle;
      final weather =
          weatherByDate[_dateOnly(date)] ??
          WeatherProfile(
            date: date,
            temperatureC: 18,
            condition: WeatherCondition.unknown,
          );

      final recommendation = _buildBestOutfitForDay(
        date: date,
        wardrobe: wardrobe,
        userGender: userGender,
        focusStyle: focusStyle,
        planType: planType,
        weather: weather,
        usedCombinationKeys: usedCombinationKeys,
        usedItemCounts: usedItemCounts,
      );

      recommendations.add(recommendation);
      usedCombinationKeys.add(_combinationKey(recommendation.items));
      for (final item in recommendation.items) {
        usedItemCounts[item.id] = (usedItemCounts[item.id] ?? 0) + 1;
      }
    }

    return recommendations;
  }

  WeatherProfile weatherProfileFromWeatherData({
    required WeatherData weatherData,
    DateTime? date,
  }) {
    return WeatherProfile(
      date: _dateOnly(date ?? DateTime.now()),
      temperatureC: weatherData.temperature,
      humidity: weatherData.humidity,
      condition: _parseWeatherCondition(weatherData.mainCondition),
      description: weatherData.description,
    );
  }

  OutfitRecommendation _buildBestOutfitForDay({
    required DateTime date,
    required List<ClothingItem> wardrobe,
    required String userGender,
    required StylePreference focusStyle,
    required DayPlanType planType,
    required WeatherProfile weather,
    required Set<String> usedCombinationKeys,
    required Map<String, int> usedItemCounts,
  }) {
    final profileSafeWardrobe = _genderSafeWardrobe(wardrobe, userGender);
    final wardrobePool =
        profileSafeWardrobe.isNotEmpty ? profileSafeWardrobe : wardrobe;
    final tops = _validItems(wardrobePool, ClothingCategory.top, weather, planType);
    final bottoms = _validItems(
      wardrobePool,
      ClothingCategory.bottom,
      weather,
      planType,
    );
    final shoes = _validItems(
      wardrobePool,
      ClothingCategory.shoes,
      weather,
      planType,
    );
    final outerwear = _validItems(
      wardrobePool,
      ClothingCategory.outerwear,
      weather,
      planType,
    );
    final socks = _validItems(
      wardrobePool,
      ClothingCategory.socks,
      weather,
      planType,
    );

    if (wardrobe.isEmpty) {
      throw StateError('Wardrobe is empty.');
    }

    final needsOuterwear = weather.isCold || weather.isRainy || weather.isSnowy;
    final hasOnePiece =
        tops.any(_isOnePiece) ||
        wardrobePool
            .where((item) => item.category == ClothingCategory.top)
            .any(_isOnePiece);
    final missingRequiredCategories = <String>[
      if (tops.isEmpty) 'üst giyim',
      if (bottoms.isEmpty && !hasOnePiece) 'alt giyim',
      if (shoes.isEmpty) 'ayakkabı',
    ];

    if (missingRequiredCategories.isNotEmpty) {
      throw StateError(
        'A full outfit needs ${missingRequiredCategories.join(', ')}.',
      );
    }

    final outerwearOptions = weather.temperatureC >= 20
        ? <ClothingItem?>[null]
        : (needsOuterwear && outerwear.isNotEmpty
              ? outerwear
              : <ClothingItem?>[null, ...outerwear]);
    final candidates = <_OutfitCandidate>[];
    final femaleMode = _femaleSpecialMode(
      date: date,
      tops: tops,
      bottoms: bottoms,
      planType: planType,
      userGender: userGender,
      usedItemCounts: usedItemCounts,
    );
    final candidateTops = _topCandidatesForMode(tops, femaleMode, planType);

    for (final top in candidateTops) {
      final bottomOptions = _isOnePiece(top)
          ? [top]
          : _bottomCandidatesForMode(bottoms, femaleMode, planType, weather);
      for (final bottom in bottomOptions) {
        for (final shoe in _shoeCandidatesForPlan(shoes, planType)) {
          final outerwearBlocked = weather.temperatureC >= 20 || _isOnePiece(top);
          final dayOuterwearOptions = _isOnePiece(top)
              ? <ClothingItem?>[null]
              : outerwearOptions;
          for (final outer in dayOuterwearOptions) {
            if (!outerwearBlocked &&
                needsOuterwear &&
                outer == null &&
                outerwear.isNotEmpty) {
              continue;
            }
            final sockOptions = _sockOptionsForOutfit(
              socks: socks,
              top: top,
              bottom: bottom,
              planType: planType,
              weather: weather,
              userGender: userGender,
            );
            for (final sock in sockOptions) {
              final items = [
                top,
                if (bottom.id != top.id) bottom,
                shoe,
                if (outer != null) outer,
                if (sock != null) sock,
              ];
              final score = _scoreOutfit(
                items: items,
                focusStyle: focusStyle,
                planType: planType,
                weather: weather,
                userGender: userGender,
                usedCombinationKeys: usedCombinationKeys,
                usedItemCounts: usedItemCounts,
              );
              candidates.add(
                _OutfitCandidate(
                  top: top,
                  bottom: bottom,
                  shoes: shoe,
                  outerwear: outer,
                  socks: sock,
                  score: score,
                ),
              );
            }
          }
        }
      }
    }

    if (candidates.isEmpty) {
      throw StateError('No valid outfit could be generated for ${date.day}.');
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    final bestPool = candidates.take(min(5, candidates.length)).toList();
    // Seeded by date so the fallback stays deterministic for the same day.
    final selected =
        bestPool[Random(date.millisecondsSinceEpoch).nextInt(bestPool.length)];

    return OutfitRecommendation(
      date: _dateOnly(date),
      day: _dayName(date),
      style: _styleLabel(focusStyle),
      description: _descriptionForOutfit(selected, weather),
      focusStyle: focusStyle,
      planType: planType,
      weather: weather,
      top: selected.top,
      bottom: selected.bottom,
      shoes: selected.shoes,
      outerwear: selected.outerwear,
      socks: selected.socks,
      score: selected.score,
      notes: _notesForOutfit(selected, weather),
    );
  }

  List<ClothingItem> _validItems(
    List<ClothingItem> wardrobe,
    ClothingCategory category,
    WeatherProfile weather,
    DayPlanType planType,
  ) {
    final weatherSafeItems = wardrobe
        .where((item) => item.category == category)
        .where((item) => _passesWeatherHardFilter(item, weather))
        .toList();

    final planSafeItems = weatherSafeItems
        .where((item) => _passesPlanHardFilter(item, planType))
        .toList();

    if (planSafeItems.isNotEmpty) return planSafeItems;
    if (weatherSafeItems.isNotEmpty) return weatherSafeItems;

    return wardrobe.where((item) => item.category == category).toList();
  }

  bool _passesWeatherHardFilter(ClothingItem item, WeatherProfile weather) {
    final type = _normalize(item.subCategory);

    if (weather.isHot) {
      if (item.thickness == Thickness.heavy) return false;
      if (type.contains('kaban') ||
          type.contains('mont') ||
          type.contains('bot') ||
          type.contains('kazak') ||
          type.contains('hoodie')) {
        return false;
      }
    }

    if (weather.isFreezing) {
      if (type.contains('sort') ||
          type.contains('atlet') ||
          type.contains('sandalet') ||
          type.contains('terlik') ||
          type.contains('crop')) {
        return false;
      }
    }

    if (weather.isRainy || weather.isSnowy) {
      if (type.contains('sandalet') || type.contains('terlik')) return false;
    }

    return true;
  }

  bool _passesPlanHardFilter(ClothingItem item, DayPlanType planType) {
    final type = _normalize(item.subCategory);

    if (_isOnePiece(item)) return true;

    if (planType == DayPlanType.gym) {
      if (type.contains('klasik') ||
          type.contains('blazer') ||
          type.contains('kaban') ||
          type.contains('gomlek')) {
        return false;
      }
    }

    if (planType == DayPlanType.office) {
      if (type.contains('terlik') || type.contains('atlet')) return false;
    }

    return true;
  }

  List<ClothingItem> _genderSafeWardrobe(
    List<ClothingItem> wardrobe,
    String userGender,
  ) {
    return wardrobe
        .where((item) => !_isGenderIncompatible(item, userGender))
        .toList();
  }

  bool _isGenderIncompatible(ClothingItem item, String userGender) {
    if (_normalize(userGender) != 'male') return false;

    final text = _normalize(
      '${item.subCategory} ${item.category.name} ${item.rawData['tur'] ?? ''} '
      '${item.rawData['type'] ?? ''} ${item.rawData['styleTags'] ?? ''}',
    );

    return _containsAny(text, [
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
    ]);
  }

  bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  double _scoreOutfit({
    required List<ClothingItem> items,
    required StylePreference focusStyle,
    required DayPlanType planType,
    required WeatherProfile weather,
    required String userGender,
    required Set<String> usedCombinationKeys,
    required Map<String, int> usedItemCounts,
  }) {
    var score = 0.0;

    for (final item in items) {
      if (item.styles.contains(focusStyle)) score += 18;
      if (item.seasons.contains(weather.preferredSeason)) score += 10;
      if (item.seasons.contains(Season.all)) score += 6;
      if (item.favorite) score += 4;

      score += _weatherScore(item, weather);
      score += _planScore(item, planType, userGender);
      score += _sockScore(item, items, planType, weather, userGender);
      final repeatPenalty = _isOnePiece(item) && _isDressEvent(planType)
          ? 2
          : 7;
      score -= (usedItemCounts[item.id] ?? 0) * repeatPenalty;
    }

    score += _colorCompatibilityScore(items);

    if (usedCombinationKeys.contains(_combinationKey(items))) {
      score -= 50;
    }

    return score;
  }

  double _weatherScore(ClothingItem item, WeatherProfile weather) {
    if (item.category == ClothingCategory.outerwear &&
        !weather.isCold &&
        !weather.isRainy &&
        !weather.isSnowy) {
      return -8;
    }

    if (weather.isHot) {
      if (item.thickness == Thickness.light) return 8;
      if (item.thickness == Thickness.medium) return 2;
      return -12;
    }

    if (weather.isCold) {
      if (item.thickness == Thickness.heavy) return 9;
      if (item.thickness == Thickness.medium) return 5;
      return -4;
    }

    if (weather.isRainy) {
      final type = _normalize(item.subCategory);
      if (type.contains('yagmurluk') || type.contains('bot')) return 12;
      if (item.category == ClothingCategory.shoes && type.contains('sneaker')) {
        return -3;
      }
    }

    return 3;
  }

  double _planScore(
    ClothingItem item,
    DayPlanType planType,
    String userGender,
  ) {
    final type = _normalize(item.subCategory);
    final gender = _normalize(userGender);

    switch (planType) {
      case DayPlanType.normalDay:
        if (item.category == ClothingCategory.bottom &&
            _containsAny(type, ['pantolon', 'jean', 'chino'])) {
          return 18;
        }
        if (item.category == ClothingCategory.top &&
            _containsAny(type, ['gomlek', 'body', 'tisort', 't-shirt', 'basic'])) {
          return 14;
        }
        if (item.category == ClothingCategory.shoes &&
            _containsAny(type, ['sneaker', 'spor'])) {
          return 16;
        }
        if (_containsAny(type, ['etek', 'elbise'])) return -4;
        return item.styles.contains(StylePreference.casual) ? 5 : 0;
      case DayPlanType.office:
        if (type.contains('gomlek') ||
            type.contains('blazer') ||
            type.contains('klasik') ||
            type.contains('pantolon') ||
            type.contains('loafer')) {
          return 12;
        }
        return item.styles.contains(StylePreference.smart) ? 8 : 0;
      case DayPlanType.date:
      case DayPlanType.dinner:
      case DayPlanType.specialEvent:
        if (gender == 'female') {
          if (_isOnePiece(item)) return 50;
          if (_isDressEventHero(item)) return 45;
          if (_containsAny(type, [
            'topuklu',
            'stiletto',
            'ince bantli',
            'blok topuk',
          ])) {
            return 35;
          }
          if (_containsAny(type, ['bluz', 'body', 'saten', 'ipek'])) {
            return 25;
          }
          if (_containsAny(type, ['blazer', 'kumas'])) return 18;
          if (item.category == ClothingCategory.top &&
              _containsAny(type, [
                'tisort',
                't-shirt',
                'sweatshirt',
                'hoodie',
              ])) {
            return -20;
          }
        }

        if (gender == 'male') {
          if (_containsAny(type, ['gomlek', 'blazer', 'ceket'])) return 32;
          if (_containsAny(type, ['kumas pantolon', 'chino', 'klasik pantolon'])) {
            return 30;
          }
          if (_containsAny(type, ['klasik', 'derby', 'oxford', 'loafer'])) {
            return 28;
          }
          if (_containsAny(type, ['polo', 'kaban'])) return 14;
          if (_containsAny(type, ['sneaker', 'esofman', 'hoodie', 'sort'])) {
            return -15;
          }
        }

        if (item.styles.contains(StylePreference.special) ||
            item.styles.contains(StylePreference.smart)) {
          return 12;
        }
        return 0;
      case DayPlanType.gym:
        if (item.category == ClothingCategory.shoes &&
            _containsAny(type, ['sneaker', 'spor', 'training'])) {
          return 24;
        }
        if (item.category == ClothingCategory.bottom &&
            _containsAny(type, ['sort', 'esofman', 'jogger', 'pantolon'])) {
          return 20;
        }
        if (item.category == ClothingCategory.top &&
            _containsAny(type, ['tisort', 't-shirt', 'crop', 'body', 'spor'])) {
          return 20;
        }
        if (item.styles.contains(StylePreference.sport) ||
            type.contains('spor') ||
            type.contains('esofman') ||
            type.contains('tayt')) {
          return 14;
        }
        if (item.category == ClothingCategory.top &&
            (type.contains('tisort') ||
                type.contains('t-shirt') ||
                type.contains('sweat') ||
                type.contains('sweatshirt') ||
                type.contains('hoodie') ||
                type.contains('kazak') ||
                type.contains('triko') ||
                type.contains('atlet'))) {
          return 11;
        }
        return -5;
      case DayPlanType.travel:
        if (item.styles.contains(StylePreference.casual) ||
            item.styles.contains(StylePreference.street) ||
            type.contains('sneaker')) {
          return 10;
        }
        return 0;
    }
  }

  double _sockScore(
    ClothingItem item,
    List<ClothingItem> outfit,
    DayPlanType planType,
    WeatherProfile weather,
    String userGender,
  ) {
    if (item.category != ClothingCategory.socks) return 0;
    if (_normalize(userGender) != 'female') return -20;
    if (!_isTights(item)) return -12;
    if (weather.isHot) return -18;

    final hasDressOrSkirt =
        outfit.any((piece) => _isOnePiece(piece) || _isDressEventHero(piece));
    if (!hasDressOrSkirt) return -15;
    if (_isDressEvent(planType)) return 10;
    if (weather.isCold || weather.isMild) return 10;
    return 6;
  }

  double _colorCompatibilityScore(List<ClothingItem> items) {
    final colors = items
        .map((item) => _normalize(item.color))
        .where((color) => color.isNotEmpty && color != 'belirtilmedi')
        .toList();
    if (colors.isEmpty) return 0;

    final neutralCount = colors.where(_isNeutralColor).length;
    final uniqueCount = colors.toSet().length;

    var score = neutralCount * 3.0;
    if (uniqueCount <= 3) score += 6;
    if (uniqueCount >= 5) score -= 5;
    return score;
  }

  bool _isOnePiece(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('elbise') || type.contains('tulum');
  }

  _FemaleSpecialMode? _femaleSpecialMode({
    required DateTime date,
    required List<ClothingItem> tops,
    required List<ClothingItem> bottoms,
    required DayPlanType planType,
    required String userGender,
    required Map<String, int> usedItemCounts,
  }) {
    if (_normalize(userGender) != 'female') return null;
    if (!_isDressEvent(planType)) return null;

    final hasUnusedDress = tops.any(
      (item) => _isOnePiece(item) && (usedItemCounts[item.id] ?? 0) == 0,
    );
    final hasAnyDress = tops.any(_isOnePiece);
    final hasSkirt = bottoms.any(_isSkirt);
    final weighted = _weightedFemaleSpecialMode(date);

    if (weighted == _FemaleSpecialMode.dress && (hasUnusedDress || !hasSkirt)) {
      return hasAnyDress ? _FemaleSpecialMode.dress : _FemaleSpecialMode.skirtShirt;
    }
    if (weighted == _FemaleSpecialMode.skirtShirt && hasSkirt) {
      return _FemaleSpecialMode.skirtShirt;
    }
    if (weighted == _FemaleSpecialMode.skirtBodyKnit && hasSkirt) {
      return _FemaleSpecialMode.skirtBodyKnit;
    }
    if (weighted == _FemaleSpecialMode.other) return _FemaleSpecialMode.other;

    if (hasSkirt && !hasUnusedDress) return _FemaleSpecialMode.skirtShirt;
    if (hasAnyDress) return _FemaleSpecialMode.dress;
    return hasSkirt ? _FemaleSpecialMode.skirtShirt : _FemaleSpecialMode.other;
  }

  _FemaleSpecialMode _weightedFemaleSpecialMode(DateTime date) {
    final value = date.millisecondsSinceEpoch.abs() % 100;
    if (value < 55) return _FemaleSpecialMode.dress;
    if (value < 85) return _FemaleSpecialMode.skirtShirt;
    if (value < 95) return _FemaleSpecialMode.skirtBodyKnit;
    return _FemaleSpecialMode.other;
  }

  List<ClothingItem> _topCandidatesForMode(
    List<ClothingItem> tops,
    _FemaleSpecialMode? mode,
    DayPlanType planType,
  ) {
    if (mode == _FemaleSpecialMode.dress) {
      final dresses = tops.where(_isOnePiece).toList();
      if (dresses.isNotEmpty) return dresses;
    }
    if (mode == _FemaleSpecialMode.skirtShirt) {
      final smartTops = tops.where(_isSmartFemaleShirtTop).toList();
      if (smartTops.isNotEmpty) return smartTops;
    }
    if (mode == _FemaleSpecialMode.skirtBodyKnit) {
      final bodyKnit = tops.where(_isBodyOrKnit).toList();
      if (bodyKnit.isNotEmpty) return bodyKnit;
    }
    if (planType == DayPlanType.gym) {
      final sportTops = tops.where(_isSportFemaleTop).toList();
      if (sportTops.isNotEmpty) return sportTops;
    }
    return tops;
  }

  List<ClothingItem> _bottomCandidatesForMode(
    List<ClothingItem> bottoms,
    _FemaleSpecialMode? mode,
    DayPlanType planType,
    WeatherProfile weather,
  ) {
    if (mode == _FemaleSpecialMode.skirtShirt ||
        mode == _FemaleSpecialMode.skirtBodyKnit) {
      final skirts = bottoms.where(_isSkirt).toList();
      if (skirts.isNotEmpty) return skirts;
    }
    if (planType == DayPlanType.gym) {
      final preferred = weather.temperatureC >= 24
          ? bottoms.where(_isShorts).toList()
          : bottoms.where((item) => _isSweatpants(item) || _isPants(item)).toList();
      if (preferred.isNotEmpty) return preferred;
    }
    if (planType == DayPlanType.normalDay) {
      final pants = bottoms.where(_isPants).toList();
      if (pants.isNotEmpty) return pants;
    }
    return bottoms;
  }

  List<ClothingItem> _shoeCandidatesForPlan(
    List<ClothingItem> shoes,
    DayPlanType planType,
  ) {
    final sorted = [...shoes];
    sorted.sort((a, b) =>
        _shoePriority(a, planType).compareTo(_shoePriority(b, planType)));
    return sorted;
  }

  bool _isDressEventHero(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('etek') ||
        type.contains('palazzo') ||
        type.contains('cigarette');
  }

  bool _isSkirt(ClothingItem item) {
    return _normalize(item.subCategory).contains('etek');
  }

  bool _isShorts(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('sort') || type.contains('short');
  }

  bool _isSweatpants(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('esofman') ||
        type.contains('jogger') ||
        type.contains('sweatpant');
  }

  bool _isPants(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('pantolon') ||
        type.contains('jean') ||
        type.contains('chino') ||
        type.contains('trouser');
  }

  bool _isSmartFemaleShirtTop(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('gomlek') ||
        type.contains('bluz') ||
        type.contains('saten') ||
        type.contains('ipek') ||
        type.contains('shirt') ||
        type.contains('blouse');
  }

  bool _isBodyOrKnit(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('body') ||
        type.contains('kazak') ||
        type.contains('triko') ||
        type.contains('knit') ||
        type.contains('sweater');
  }

  bool _isSportFemaleTop(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('tisort') ||
        type.contains('t-shirt') ||
        type.contains('crop') ||
        type.contains('body') ||
        type.contains('spor') ||
        type.contains('training') ||
        type.contains('sweatshirt');
  }

  int _shoePriority(ClothingItem item, DayPlanType planType) {
    final type = _normalize(item.subCategory);
    if (_isDressEvent(planType)) {
      if (_containsAny(type, ['topuklu', 'stiletto', 'heel'])) return 0;
      if (_containsAny(type, ['cizme', 'bot', 'boot'])) return 1;
      if (_containsAny(type, ['loafer', 'klasik', 'oxford', 'derby'])) return 2;
      if (_containsAny(type, ['sneaker', 'spor'])) return 3;
      return 4;
    }
    if (planType == DayPlanType.gym || planType == DayPlanType.normalDay) {
      if (_containsAny(type, ['sneaker', 'spor', 'training'])) return 0;
      if (_containsAny(type, ['loafer', 'bot', 'boot'])) return 1;
      if (_containsAny(type, ['topuklu', 'stiletto', 'heel'])) return 4;
      return 2;
    }
    return 2;
  }

  List<ClothingItem?> _sockOptionsForOutfit({
    required List<ClothingItem> socks,
    required ClothingItem top,
    required ClothingItem bottom,
    required DayPlanType planType,
    required WeatherProfile weather,
    required String userGender,
  }) {
    if (_normalize(userGender) != 'female') return const [null];

    final shouldConsiderTights =
        _isOnePiece(top) || _isDressEventHero(bottom) || _isDressEvent(planType);
    if (!shouldConsiderTights || weather.isHot) return const [null];

    final tights = socks.where(_isTights).toList();
    if (tights.isEmpty) return const [null];

    return <ClothingItem?>[null, ...tights];
  }

  bool _isDressEvent(DayPlanType planType) {
    return planType == DayPlanType.date ||
        planType == DayPlanType.dinner ||
        planType == DayPlanType.specialEvent;
  }

  bool _isTights(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('kulotlu') ||
        type.contains('külotlu') ||
        type.contains('pantyhose') ||
        type.contains('tights');
  }

  List<String> _notesForOutfit(
    _OutfitCandidate outfit,
    WeatherProfile weather,
  ) {
    final notes = <String>[];
    if ((weather.isCold || weather.isRainy || weather.isSnowy) &&
        outfit.outerwear == null) {
      notes.add('Outerwear is recommended, but no suitable item was found.');
    }
    if (weather.isHot) {
      notes.add('Hot-weather filtering removed heavy winter items.');
    }
    if (weather.isRainy) {
      notes.add('Rain filtering avoided sandals and slippers.');
    }
    if (outfit.socks != null && _isTights(outfit.socks!)) {
      notes.add('Külotlu çorap bu kombin için isteğe bağlı tamamlayıcı olarak eklendi.');
    }
    return notes;
  }

  String _descriptionForOutfit(
    _OutfitCandidate outfit,
    WeatherProfile weather,
  ) {
    final pieces = [
      outfit.top.subCategory,
      if (outfit.bottom.id != outfit.top.id) outfit.bottom.subCategory,
      outfit.shoes.subCategory,
      if (outfit.outerwear != null) outfit.outerwear!.subCategory,
    ].where((name) => name.trim().isNotEmpty).join(' + ');

    if (weather.isCold || weather.isRainy || weather.isSnowy) {
      return pieces.isEmpty
          ? 'Hava durumuna göre tamamlanan kombin'
          : '$pieces, hava durumuna göre tamamlandı';
    }

    return pieces.isEmpty ? 'Tam günlük kombin' : pieces;
  }

  String _dayName(DateTime date) {
    const days = {
      DateTime.monday: 'Pazartesi',
      DateTime.tuesday: 'Salı',
      DateTime.wednesday: 'Çarşamba',
      DateTime.thursday: 'Perşembe',
      DateTime.friday: 'Cuma',
      DateTime.saturday: 'Cumartesi',
      DateTime.sunday: 'Pazar',
    };
    return days[date.weekday] ?? '';
  }

  String _styleLabel(StylePreference style) {
    switch (style) {
      case StylePreference.casual:
        return 'Casual';
      case StylePreference.street:
        return 'Street';
      case StylePreference.sport:
        return 'Sport';
      case StylePreference.smart:
        return 'Smart';
      case StylePreference.special:
        return 'Special';
    }
  }

  StylePreference? _styleForPlan(DayPlanType planType) {
    switch (planType) {
      case DayPlanType.normalDay:
        return null;
      case DayPlanType.office:
        return StylePreference.smart;
      case DayPlanType.date:
      case DayPlanType.dinner:
      case DayPlanType.specialEvent:
        return StylePreference.special;
      case DayPlanType.gym:
        return StylePreference.sport;
      case DayPlanType.travel:
        return StylePreference.casual;
    }
  }

  WeatherCondition _parseWeatherCondition(String value) {
    final text = _normalize(value);
    if (text.contains('clear')) return WeatherCondition.clear;
    if (text.contains('cloud')) return WeatherCondition.clouds;
    if (text.contains('rain') || text.contains('drizzle')) {
      return WeatherCondition.rain;
    }
    if (text.contains('snow')) return WeatherCondition.snow;
    if (text.contains('wind')) return WeatherCondition.wind;
    return WeatherCondition.unknown;
  }

  String _combinationKey(List<ClothingItem> items) {
    final ids = items.map((item) => item.id).toList()..sort();
    return ids.join('|');
  }

  bool _isNeutralColor(String color) {
    return color.contains('siyah') ||
        color.contains('beyaz') ||
        color.contains('gri') ||
        color.contains('bej') ||
        color.contains('lacivert') ||
        color.contains('black') ||
        color.contains('white') ||
        color.contains('gray') ||
        color.contains('navy') ||
        color.contains('beige');
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
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

enum _FemaleSpecialMode {
  dress,
  skirtShirt,
  skirtBodyKnit,
  other,
}

class _OutfitCandidate {
  final ClothingItem top;
  final ClothingItem bottom;
  final ClothingItem shoes;
  final ClothingItem? outerwear;
  final ClothingItem? socks;
  final double score;

  const _OutfitCandidate({
    required this.top,
    required this.bottom,
    required this.shoes,
    this.outerwear,
    this.socks,
    required this.score,
  });
}
