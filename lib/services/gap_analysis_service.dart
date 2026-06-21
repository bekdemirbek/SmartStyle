import '../models/gap_suggestion.dart';
import '../models/purchase_preference_profile.dart';
import '../models/wardrobe_item_model.dart';
import 'combination_logic.dart';

class GapAnalysisService {
  List<GapSuggestion> analyze(
    List<WardrobeItem> wardrobe, {
    PurchasePreferenceProfile preferenceProfile =
        const PurchasePreferenceProfile(),
    String contextText = '',
    String? selectedOccasion,
    String? selectedCategory,
    bool? isMaleUser,
  }) {
    final usableWardrobe = wardrobe.where((item) => !_isIgnored(item)).toList();
    final currentCombos = countPossibleCombos(usableWardrobe);
    final wardrobeProfile = _analyzeWardrobe(usableWardrobe);
    final context = _inferContext(
      contextText,
      selectedOccasion: selectedOccasion,
      selectedCategory: selectedCategory,
    );
    final suggestions = <GapSuggestion>[];
    final existingVariantKeys = usableWardrobe.map(wardrobeVariantKey).toSet();

    for (final candidate in _buildCandidates(
      usableWardrobe,
      context: context,
      isMaleUser: isMaleUser,
    )) {
      if (context.category != null && _categoryKey(candidate) != context.category) {
        continue;
      }
      if (!_matchesPurchaseContext(candidate, context)) {
        continue;
      }
      if (_isGenderIncompatible(candidate, isMaleUser: isMaleUser)) {
        continue;
      }
      if (existingVariantKeys.contains(wardrobeVariantKey(candidate))) {
        continue;
      }
      if (_hasSimilarItem(candidate, usableWardrobe)) {
        continue;
      }
      if (!context.hasSignal && _countSimilarType(usableWardrobe, candidate) >= 2) {
        continue;
      }

      final rawGain = potentialCombinationImpact(usableWardrobe, candidate);
      final gain = rawGain <= 0 && context.hasSignal ? 1 : rawGain;
      final newCombos = currentCombos + gain;

      if (gain <= 0) continue;

      final penalty = _preferencePenalty(candidate, preferenceProfile);
      final boost = _preferenceBoost(candidate, preferenceProfile);
      final contextBoost = _contextBoost(candidate, context, wardrobeProfile);
      final compatibleItems = _findCompatibleItems(usableWardrobe, candidate);
      final occasionList = _candidateOccasions(candidate);
      final badge = _resolveBadge(
        candidate: candidate,
        wardrobe: usableWardrobe,
        gain: gain,
        compatibleItems: compatibleItems,
        occasion: occasionList,
      );
      final confidence = _confidence(
        wardrobe: usableWardrobe,
        candidate: candidate,
        gain: gain,
        contextBoost: contextBoost,
        compatibleCount: compatibleItems.length,
        hasContext: context.hasSignal,
        hasPreference: preferenceProfile.hasSignals,
      );
      suggestions.add(
        GapSuggestion(
          candidateItem: candidate,
          currentCombos: currentCombos,
          projectedCombos: newCombos,
          gain: gain,
          tasteScore: (gain + boost + contextBoost - penalty).toDouble(),
          preferencePenalty: penalty,
          preferenceBoost: boost,
          style: _displayStyle(candidate),
          occasion: occasionList,
          formality: _candidateFormality(candidate),
          confidence: confidence,
          followUpQuestion: confidence < 0.62
              ? _mostImpactfulQuestion(wardrobeProfile, context)
              : null,
          compatibleItems: compatibleItems,
          reason: _buildReason(
            usableWardrobe,
            candidate,
            gain,
            context: context,
            confidence: confidence,
          ),
          badgeLabel: badge.label,
          badgeType: badge.type,
        ),
      );
    }

    if (suggestions.isEmpty && context.hasSignal) {
      for (final candidate in _contextCandidates(context)) {
        if (_isGenderIncompatible(candidate, isMaleUser: isMaleUser)) continue;

        final compatibleItems = _findCompatibleItems(usableWardrobe, candidate);
        final occasionList = _candidateOccasions(candidate);
        final badge = _resolveBadge(
          candidate: candidate,
          wardrobe: usableWardrobe,
          gain: 1,
          compatibleItems: compatibleItems,
          occasion: occasionList,
        );

        suggestions.add(
          GapSuggestion(
            candidateItem: candidate,
            currentCombos: currentCombos,
            projectedCombos: currentCombos + 1,
            gain: 1,
            tasteScore: 1,
            style: _displayStyle(candidate),
            occasion: occasionList,
            formality: _candidateFormality(candidate),
            confidence: 0.72,
            compatibleItems: compatibleItems,
            reason: _buildReason(
              usableWardrobe,
              candidate,
              1,
              context: context,
              confidence: 0.72,
            ),
            badgeLabel: badge.label,
            badgeType: badge.type,
          ),
        );
        if (suggestions.length >= 4) break;
      }
    }

    suggestions.sort((a, b) {
      final tasteCompare = b.tasteScore.compareTo(a.tasteScore);
      if (tasteCompare != 0) return tasteCompare;
      return b.gain.compareTo(a.gain);
    });
    return _diversifySuggestions(suggestions).take(8).toList();
  }

  int countPossibleCombos(List<WardrobeItem> wardrobe) {
    return logicalCombinationCount(wardrobe.where((item) => !_isIgnored(item)).toList());
  }

  List<GapSuggestion> missingCategorySuggestions(
    List<WardrobeItem> wardrobe, {
    bool? isMaleUser,
  }) {
    final usableWardrobe = wardrobe.where((item) => !_isIgnored(item)).toList();
    final missingCategories = _missingCategoryKeys(usableWardrobe);
    if (missingCategories.isEmpty) return const [];

    final currentCombos = countPossibleCombos(usableWardrobe);
    final suggestions = <GapSuggestion>[];
    final existingVariantKeys = usableWardrobe.map(wardrobeVariantKey).toSet();
    final seedContexts = const [
      _PurchaseContext(occasion: 'daily', style: 'casual', formality: 'casual'),
      _PurchaseContext(occasion: 'sport', style: 'sport', formality: 'casual'),
      _PurchaseContext(
        occasion: 'work',
        style: 'business',
        formality: 'smart casual',
      ),
      _PurchaseContext(
        occasion: 'wedding',
        style: 'business',
        formality: 'formal',
      ),
      _PurchaseContext(occasion: 'travel', style: 'casual', formality: 'casual'),
    ];

    for (final category in missingCategories) {
      final categoryContext = _PurchaseContext(category: category);
      final candidates = <WardrobeItem>[
        ..._contextCandidates(categoryContext),
        for (final context in seedContexts)
          ..._contextCandidates(context.copyWith(category: category)),
      ];

      for (final candidate in candidates) {
        if (_isGenderIncompatible(candidate, isMaleUser: isMaleUser)) continue;
        if (existingVariantKeys.contains(wardrobeVariantKey(candidate))) continue;

        final compatibleItems = _findCompatibleItems(usableWardrobe, candidate);
        final occasionList = _candidateOccasions(candidate);
        final badge = _resolveBadge(
          candidate: candidate,
          wardrobe: usableWardrobe,
          gain: 1,
          compatibleItems: compatibleItems,
          occasion: occasionList,
        );
        if (badge.type != 'missing') continue;

        suggestions.add(
          GapSuggestion(
            candidateItem: candidate,
            currentCombos: currentCombos,
            projectedCombos: currentCombos + 1,
            gain: 1,
            tasteScore: 1,
            style: _displayStyle(candidate),
            occasion: occasionList,
            formality: _candidateFormality(candidate),
            confidence: 0.74,
            compatibleItems: compatibleItems,
            reason: _buildReason(
              usableWardrobe,
              candidate,
              1,
              context: categoryContext,
              confidence: 0.74,
            ),
            badgeLabel: badge.label,
            badgeType: badge.type,
          ),
        );
        if (suggestions.where(
              (suggestion) =>
                  _categoryKey(suggestion.candidateItem) == category,
            ).length >=
            3) {
          break;
        }
      }
    }

    return _diversifySuggestions(suggestions).take(8).toList();
  }

  List<GapSuggestion> filterExistingSuggestions(
    List<GapSuggestion> suggestions,
    List<WardrobeItem> wardrobe, {
    String contextText = '',
    String? selectedOccasion,
    String? selectedCategory,
    bool? isMaleUser,
  }) {
    final usableWardrobe = wardrobe.where((item) => !_isIgnored(item)).toList();
    final context = _inferContext(
      contextText,
      selectedOccasion: selectedOccasion,
      selectedCategory: selectedCategory,
    );
    return suggestions
        .where(
          (suggestion) =>
              !_hasSimilarItem(suggestion.candidateItem, usableWardrobe) &&
              !_isAccessory(suggestion.candidateItem) &&
              _matchesPurchaseContext(suggestion.candidateItem, context) &&
              !_isGenderIncompatible(
                suggestion.candidateItem,
                isMaleUser: isMaleUser,
              ),
        )
        .map((suggestion) => _reclassifySuggestion(suggestion, usableWardrobe))
        .toList();
  }

  GapSuggestion _reclassifySuggestion(
    GapSuggestion suggestion,
    List<WardrobeItem> wardrobe,
  ) {
    final compatibleItems = suggestion.compatibleItems.isEmpty
        ? _findCompatibleItems(wardrobe, suggestion.candidateItem)
        : suggestion.compatibleItems;
    final badge = _resolveBadge(
      candidate: suggestion.candidateItem,
      wardrobe: wardrobe,
      gain: suggestion.gain,
      compatibleItems: compatibleItems,
      occasion: suggestion.occasion,
    );

    return GapSuggestion(
      candidateItem: suggestion.candidateItem,
      currentCombos: suggestion.currentCombos,
      projectedCombos: suggestion.projectedCombos,
      gain: suggestion.gain,
      tasteScore: suggestion.tasteScore,
      preferencePenalty: suggestion.preferencePenalty,
      preferenceBoost: suggestion.preferenceBoost,
      style: suggestion.style,
      occasion: suggestion.occasion,
      formality: suggestion.formality,
      confidence: suggestion.confidence,
      followUpQuestion: suggestion.followUpQuestion,
      compatibleItems: compatibleItems,
      reason: suggestion.reason,
      badgeLabel: badge.label,
      badgeType: badge.type,
    );
  }

  List<GapSuggestion> _diversifySuggestions(List<GapSuggestion> suggestions) {
    final selected = <GapSuggestion>[];
    final bucketCounts = <String, int>{};

    for (final suggestion in suggestions) {
      final category = _categoryKey(suggestion.candidateItem);
      final bucket = '${suggestion.badgeType}|$category';
      final count = bucketCounts[bucket] ?? 0;
      if (count >= 3) {
        continue;
      }
      selected.add(suggestion);
      bucketCounts[bucket] = count + 1;
    }

    for (final suggestion in suggestions) {
      if (selected.length >= 8) break;
      if (!selected.contains(suggestion)) selected.add(suggestion);
    }

    return selected;
  }

  // UPDATED: rozet etiketi belirleyici
  ({String label, String type}) _resolveBadge({
    required WardrobeItem candidate,
    required List<WardrobeItem> wardrobe,
    required int gain,
    required List<WardrobeItem> compatibleItems,
    required List<String> occasion,
  }) {
    bool isTop(WardrobeItem i) {
      final c = '${_normalize(i.category)} ${_normalize(i.type)}';
      return [
        'upper',
        'ust',
        'tisort',
        'gomlek',
        'sweatshirt',
        'kazak',
        'hoodie',
        'bluz',
        'ceket',
        'blazer',
      ].any(c.contains);
    }

    bool isBottom(WardrobeItem i) {
      final c = '${_normalize(i.category)} ${_normalize(i.type)}';
      return [
        'lower',
        'alt',
        'pantolon',
        'etek',
        'sort',
        'jean',
        'chino',
        'tayt',
      ].any(c.contains);
    }

    bool isShoe(WardrobeItem i) {
      final c = '${_normalize(i.category)} ${_normalize(i.type)}';
      return [
        'shoes',
        'ayakkabi',
        'sneaker',
        'bot',
        'loafer',
        'sandalet',
        'oxford',
        'kundura',
      ].any(c.contains);
    }

    bool isOuter(WardrobeItem i) {
      final c = '${_normalize(i.category)} ${_normalize(i.type)}';
      return [
        'outerwear',
        'mont',
        'kaban',
        'palto',
        'yagmurluk',
        'trenckot',
        'dis giyim',
      ].any(c.contains);
    }

    final topCount = wardrobe.where(isTop).length;
    final bottomCount = wardrobe.where(isBottom).length;
    final shoeCount = wardrobe.where(isShoe).length;
    final outerCount = wardrobe.where(isOuter).length;

    if (isShoe(candidate) && shoeCount <= 3) {
      return (label: 'Ayakkabı eksik', type: 'missing');
    }
    if (isBottom(candidate) && bottomCount <= 4) {
      return (label: 'Alt giyim eksik', type: 'missing');
    }
    if (isOuter(candidate) && outerCount <= 2) {
      return (label: 'Dış giyim eksik', type: 'missing');
    }
    if (isTop(candidate) && topCount <= 5) {
      return (label: 'Üst giyim eksik', type: 'missing');
    }

    if (compatibleItems.length >= 5) {
      return (
        label: 'Dolabınla uyumlu',
        type: 'match',
      );
    }

    if (gain >= 8) return (label: 'Yüksek etki', type: 'impact');

    return (label: 'Öneri', type: 'other');
  }

  bool _isCompatible(WardrobeItem a, WardrobeItem b) {
    final aStyles = _styleTags(a);
    final bStyles = _styleTags(b);
    final styleMatch = aStyles.any(bStyles.contains);
    if (!styleMatch) return false;

    final aIsNeutral = _isNeutralColor(a.color);
    final bIsNeutral = _isNeutralColor(b.color);
    return aIsNeutral || bIsNeutral;
  }

  _WardrobePurchaseProfile _analyzeWardrobe(List<WardrobeItem> wardrobe) {
    final styles = <String>[];
    final occasions = <String>[];
    final prices = <double>[];

    for (final item in wardrobe) {
      styles.addAll(_styleTags(item));
      occasions.addAll(_occasionTags(item));

      final price = item.rawData['price'] ?? item.rawData['fiyat'];
      if (price is num) prices.add(price.toDouble());
      if (price is String) {
        final parsed = double.tryParse(price.replaceAll(',', '.'));
        if (parsed != null) prices.add(parsed);
      }
    }

    final categoryCounts = {
      'upper': _countCategory(wardrobe, 'upper'),
      'lower': _countCategory(wardrobe, 'lower'),
      'shoes': _countCategory(wardrobe, 'shoes'),
      'outerwear': _countCategory(wardrobe, 'outerwear'),
    };

    final missingConnectors = categoryCounts.entries
        .where((entry) => entry.value < 2)
        .map((entry) => entry.key)
        .toSet();

    return _WardrobePurchaseProfile(
      dominantStyle: _mostCommon(styles) ?? 'casual',
      dominantOccasion: _mostCommon(occasions) ?? 'daily',
      missingConnectors: missingConnectors,
      hasPricePattern: prices.length >= 3,
    );
  }

  _PurchaseContext _inferContext(
    String value, {
    String? selectedOccasion,
    String? selectedCategory,
  }) {
    final text = _normalize(value);
    final category = _inferCategory(text) ?? selectedCategory;
    final normalizedOccasion = selectedOccasion == null
        ? null
        : _normalize(selectedOccasion);

    if (text.isEmpty) {
      return _PurchaseContext(
        occasion: normalizedOccasion,
        category: category,
        style: _styleForOccasion(normalizedOccasion),
        formality: _formalityForOccasion(normalizedOccasion),
      );
    }

    if (_containsAny(text, ['dugun', 'wedding', 'nikah', 'mezuniyet'])) {
      return _PurchaseContext(
        occasion: 'wedding',
        formality: 'formal',
        style: 'business',
        category: category,
      );
    }
    if (_containsAny(text, ['is', 'ofis', 'office', 'work', 'toplanti'])) {
      return _PurchaseContext(
        occasion: 'work',
        formality: 'smart casual',
        style: 'business',
        category: category,
      );
    }
    if (_containsAny(text, ['date', 'randevu', 'aksam yemegi', 'yemek'])) {
      return _PurchaseContext(
        occasion: 'date',
        formality: 'semi-formal',
        style: 'smart_casual',
        category: category,
      );
    }
    if (_containsAny(text, ['spor', 'gym', 'fitness', 'kosu'])) {
      return _PurchaseContext(
        occasion: 'sport',
        formality: 'casual',
        style: 'sport',
        category: category,
      );
    }
    if (_containsAny(text, ['gunluk', 'daily', 'okul', 'kampus'])) {
      return _PurchaseContext(
        occasion: 'daily',
        formality: 'casual',
        style: 'casual',
        category: category,
      );
    }

    return _PurchaseContext(
      occasion: normalizedOccasion,
      category: category,
      style: _styleForOccasion(normalizedOccasion),
      formality: _formalityForOccasion(normalizedOccasion),
      hasUnknownText: true,
    );
  }

  String? _inferCategory(String text) {
    if (text.isEmpty) return null;
    if (_containsAny(text, ['gomlek', 'tisort', 't-shirt', 'kazak', 'ust'])) {
      return 'upper';
    }
    if (_containsAny(text, ['pantolon', 'jean', 'chino', 'sort', 'alt'])) {
      return 'lower';
    }
    if (_containsAny(text, ['ayakkabi', 'sneaker', 'bot', 'loafer'])) {
      return 'shoes';
    }
    if (_containsAny(text, ['ceket', 'mont', 'kaban', 'blazer', 'dis'])) {
      return 'outerwear';
    }
    return null;
  }

  String? _styleForOccasion(String? occasion) {
    switch (occasion) {
      case 'wedding':
      case 'special':
      case 'formal':
      case 'work':
        return 'business';
      case 'sport':
        return 'sport';
      case 'daily':
      case 'travel':
        return 'casual';
    }
    return null;
  }

  String? _formalityForOccasion(String? occasion) {
    switch (occasion) {
      case 'wedding':
      case 'special':
      case 'formal':
        return 'formal';
      case 'work':
        return 'smart casual';
      case 'sport':
      case 'daily':
      case 'travel':
        return 'casual';
    }
    return null;
  }

  int _contextBoost(
    WardrobeItem candidate,
    _PurchaseContext context,
    _WardrobePurchaseProfile profile,
  ) {
    var boost = 0;
    final candidateStyles = _styleTags(candidate);
    final candidateOccasions = _candidateOccasions(candidate);
    final candidateFormality = _candidateFormality(candidate);
    final category = _categoryKey(candidate);

    if (profile.missingConnectors.contains(category)) boost += 6;
    if (candidateStyles.contains(profile.dominantStyle)) boost += 4;
    if (candidateOccasions.contains(profile.dominantOccasion)) boost += 3;
    if (profile.hasPricePattern) boost += 1;

    if (context.occasion != null &&
        candidateOccasions.contains(context.occasion)) {
      boost += 28;
    } else if (context.occasion != null) {
      boost -= 18;
    }
    if (context.style != null && candidateStyles.contains(context.style)) {
      boost += 10;
    }
    if (context.formality != null && candidateFormality == context.formality) {
      boost += 14;
    } else if (context.formality != null) {
      boost -= 8;
    }

    return boost;
  }

  List<WardrobeItem> _contextCandidates(_PurchaseContext context) {
    if (!context.hasSignal) return const [];

    final occasion = context.occasion ?? 'daily';
    final category = context.category;
    final items = <WardrobeItem>[];

    void add({
      required String id,
      required String itemCategory,
      required String type,
      required String color,
      required List<String> styles,
      required String formality,
      List<String>? occasions,
    }) {
      if (category != null && category != itemCategory) return;
      items.add(
        _virtualItem(
          id: 'context_${occasion}_$id',
          category: itemCategory,
          type: type,
          color: color,
          styleTags: styles,
          reasonKey: id,
          occasionTags: occasions ?? [occasion],
          formality: formality,
        ),
      );
    }

    switch (occasion) {
      case 'sport':
        add(
          id: 'sport_performance_tshirt',
          itemCategory: 'upper',
          type: 'Nefes Alan Performans Tişörtü',
          color: 'Siyah',
          styles: const ['sport'],
          formality: 'casual',
        );
        add(
          id: 'sport_zip_training_top',
          itemCategory: 'upper',
          type: 'Fermuarlı Antrenman Üstü',
          color: 'Lacivert',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        add(
          id: 'sport_technical_jogger',
          itemCategory: 'lower',
          type: 'Siyah Teknik Jogger',
          color: 'Siyah',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        add(
          id: 'sport_performance_jogger',
          itemCategory: 'lower',
          type: 'Lacivert Performans Jogger',
          color: 'Lacivert',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        add(
          id: 'sport_training_shorts',
          itemCategory: 'lower',
          type: 'Gri Antrenman Şortu',
          color: 'Gri',
          styles: const ['sport'],
          formality: 'casual',
        );
        add(
          id: 'sport_track_pants',
          itemCategory: 'lower',
          type: 'Siyah Eşofman Altı',
          color: 'Siyah',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        add(
          id: 'sport_training_sneaker',
          itemCategory: 'shoes',
          type: 'Beyaz Training Sneaker',
          color: 'Beyaz',
          styles: const ['sport'],
          formality: 'casual',
        );
        add(
          id: 'sport_running_sneaker',
          itemCategory: 'shoes',
          type: 'Siyah Hafif Koşu Ayakkabısı',
          color: 'Siyah',
          styles: const ['sport'],
          formality: 'casual',
        );
        add(
          id: 'sport_technical_rain_jacket',
          itemCategory: 'outerwear',
          type: 'Siyah Teknik Yağmurluk',
          color: 'Siyah',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        add(
          id: 'sport_light_zip_jacket',
          itemCategory: 'outerwear',
          type: 'Lacivert Hafif Spor Ceket',
          color: 'Lacivert',
          styles: const ['sport', 'casual'],
          formality: 'casual',
        );
        break;
      case 'wedding':
      case 'special':
      case 'formal':
        add(
          id: 'formal_oxford_shirt',
          itemCategory: 'upper',
          type: 'Beyaz Oxford Gömlek',
          color: 'Beyaz',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_satin_shirt',
          itemCategory: 'upper',
          type: 'Ekru Saten Gömlek',
          color: 'Ekru',
          styles: const ['business', 'smart_casual'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_black_trouser',
          itemCategory: 'lower',
          type: 'Siyah Kumaş Pantolon',
          color: 'Siyah',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_grey_trouser',
          itemCategory: 'lower',
          type: 'Gri Kumaş Pantolon',
          color: 'Gri',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_derby_shoes',
          itemCategory: 'shoes',
          type: 'Siyah Deri Derby Ayakkabı',
          color: 'Siyah',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_oxford_shoes',
          itemCategory: 'shoes',
          type: 'Siyah Oxford Ayakkabı',
          color: 'Siyah',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_navy_blazer',
          itemCategory: 'outerwear',
          type: 'Lacivert Blazer',
          color: 'Lacivert',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        add(
          id: 'formal_black_blazer',
          itemCategory: 'outerwear',
          type: 'Siyah Blazer',
          color: 'Siyah',
          styles: const ['business', 'classic'],
          formality: 'formal',
          occasions: const ['wedding', 'formal'],
        );
        break;
      case 'work':
        add(
          id: 'work_blue_shirt',
          itemCategory: 'upper',
          type: 'Açık Mavi Gömlek',
          color: 'Mavi',
          styles: const ['business', 'smart_casual'],
          formality: 'smart casual',
        );
        add(
          id: 'work_polo',
          itemCategory: 'upper',
          type: 'Lacivert Polo',
          color: 'Lacivert',
          styles: const ['smart_casual', 'business'],
          formality: 'smart casual',
        );
        add(
          id: 'work_chino',
          itemCategory: 'lower',
          type: 'Bej Chino Pantolon',
          color: 'Bej',
          styles: const ['smart_casual', 'business'],
          formality: 'smart casual',
        );
        add(
          id: 'work_grey_trouser',
          itemCategory: 'lower',
          type: 'Gri Kumaş Pantolon',
          color: 'Gri',
          styles: const ['business', 'smart_casual'],
          formality: 'smart casual',
        );
        add(
          id: 'work_loafer',
          itemCategory: 'shoes',
          type: 'Kahverengi Loafer',
          color: 'Kahverengi',
          styles: const ['business', 'smart_casual'],
          formality: 'smart casual',
        );
        add(
          id: 'work_derby',
          itemCategory: 'shoes',
          type: 'Siyah Derby Ayakkabı',
          color: 'Siyah',
          styles: const ['business'],
          formality: 'smart casual',
        );
        add(
          id: 'work_blazer',
          itemCategory: 'outerwear',
          type: 'Lacivert Blazer',
          color: 'Lacivert',
          styles: const ['business', 'smart_casual'],
          formality: 'smart casual',
        );
        add(
          id: 'work_overshirt',
          itemCategory: 'outerwear',
          type: 'Açık Gri Overshirt',
          color: 'Gri',
          styles: const ['smart_casual', 'casual'],
          formality: 'smart casual',
        );
        break;
      case 'travel':
        add(
          id: 'travel_linen_shirt',
          itemCategory: 'upper',
          type: 'Beyaz Keten Gömlek',
          color: 'Beyaz',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        add(
          id: 'travel_breathable_tshirt',
          itemCategory: 'upper',
          type: 'Nefes Alan Basic Tişört',
          color: 'Gri',
          styles: const ['casual', 'sport'],
          formality: 'casual',
        );
        add(
          id: 'travel_cargo',
          itemCategory: 'lower',
          type: 'Haki Relaxed Cargo Pantolon',
          color: 'Haki',
          styles: const ['casual', 'street'],
          formality: 'casual',
        );
        add(
          id: 'travel_relaxed_trouser',
          itemCategory: 'lower',
          type: 'Koyu Gri Relaxed Pantolon',
          color: 'Gri',
          styles: const ['casual'],
          formality: 'casual',
        );
        add(
          id: 'travel_sneaker',
          itemCategory: 'shoes',
          type: 'Beyaz Rahat Sneaker',
          color: 'Beyaz',
          styles: const ['casual', 'sport'],
          formality: 'casual',
        );
        add(
          id: 'travel_waterproof_sneaker',
          itemCategory: 'shoes',
          type: 'Siyah Su Geçirmez Sneaker',
          color: 'Siyah',
          styles: const ['casual', 'sport'],
          formality: 'casual',
        );
        add(
          id: 'travel_rain_jacket',
          itemCategory: 'outerwear',
          type: 'Siyah Teknik Yağmurluk',
          color: 'Siyah',
          styles: const ['casual', 'sport'],
          formality: 'casual',
        );
        add(
          id: 'travel_light_jacket',
          itemCategory: 'outerwear',
          type: 'İnce Mevsimlik Ceket',
          color: 'Gri',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        break;
      case 'daily':
      default:
        add(
          id: 'daily_tshirt',
          itemCategory: 'upper',
          type: 'Beyaz Basic Tişört',
          color: 'Beyaz',
          styles: const ['casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_knit',
          itemCategory: 'upper',
          type: 'Krem İnce Triko',
          color: 'Krem',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_black_jean',
          itemCategory: 'lower',
          type: 'Siyah Düz Jean',
          color: 'Siyah',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_chino',
          itemCategory: 'lower',
          type: 'Gri Chino Pantolon',
          color: 'Gri',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_white_sneaker',
          itemCategory: 'shoes',
          type: 'Minimal Beyaz Sneaker',
          color: 'Beyaz',
          styles: const ['casual', 'sport'],
          formality: 'casual',
        );
        add(
          id: 'daily_suede_sneaker',
          itemCategory: 'shoes',
          type: 'Kahverengi Süet Sneaker',
          color: 'Kahverengi',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_denim_jacket',
          itemCategory: 'outerwear',
          type: 'Koyu Mavi Denim Ceket',
          color: 'Mavi',
          styles: const ['casual'],
          formality: 'casual',
        );
        add(
          id: 'daily_overshirt',
          itemCategory: 'outerwear',
          type: 'Bej Overshirt',
          color: 'Bej',
          styles: const ['casual', 'smart_casual'],
          formality: 'casual',
        );
        break;
    }

    return items;
  }

  bool _matchesPurchaseContext(WardrobeItem candidate, _PurchaseContext context) {
    final candidateStyles = _styleTags(candidate);
    final candidateOccasions = _candidateOccasions(candidate);

    if (context.style != null &&
        !candidateStyles.contains(context.style) &&
        !candidateOccasions.contains(context.style)) {
      return false;
    }
    if (context.occasion != null &&
        !candidateOccasions.contains(context.occasion) &&
        !candidateStyles.contains(context.occasion)) {
      return false;
    }

    return true;
  }

  double _confidence({
    required List<WardrobeItem> wardrobe,
    required WardrobeItem candidate,
    required int gain,
    required int contextBoost,
    required int compatibleCount,
    required bool hasContext,
    required bool hasPreference,
  }) {
    var confidence = 0.36;
    confidence += (gain / 40).clamp(0, 0.22).toDouble();
    confidence += (compatibleCount / 16).clamp(0, 0.16).toDouble();
    confidence += (contextBoost / 40).clamp(0, 0.18).toDouble();
    if (hasContext) confidence += 0.12;
    if (hasPreference) confidence += 0.07;
    if (wardrobe.length >= 8) confidence += 0.06;
    if (_categoryKey(candidate).isNotEmpty) confidence += 0.03;

    return confidence.clamp(0.0, 0.97).toDouble();
  }

  int _preferencePenalty(
    WardrobeItem candidate,
    PurchasePreferenceProfile profile,
  ) {
    if (!profile.hasSignals) return 0;

    final color = _normalize(candidate.color);
    final category = _categoryKey(candidate);
    final item = candidate.id.trim().isEmpty
        ? _normalize(candidate.displayName)
        : candidate.id;
    final styles = _styleTags(candidate);

    var penalty = (profile.dislikedItems[item] ?? 0) * 8;
    penalty += (profile.dislikedColors[color] ?? 0) * 3;
    penalty += (profile.dislikedCategories[category] ?? 0) * 4;
    for (final style in styles) {
      penalty += (profile.dislikedStyles[style] ?? 0) * 3;
    }

    return penalty;
  }

  int _preferenceBoost(
    WardrobeItem candidate,
    PurchasePreferenceProfile profile,
  ) {
    if (!profile.hasSignals) return 0;

    final color = _normalize(candidate.color);
    final category = _categoryKey(candidate);
    final item = candidate.id.trim().isEmpty
        ? _normalize(candidate.displayName)
        : candidate.id;
    final styles = _styleTags(candidate);

    var boost = (profile.likedItems[item] ?? 0) * 6;
    boost += (profile.likedColors[color] ?? 0) * 2;
    boost += (profile.likedCategories[category] ?? 0) * 2;
    for (final style in styles) {
      boost += (profile.likedStyles[style] ?? 0) * 2;
    }

    return boost;
  }

  List<WardrobeItem> _buildCandidates(
    List<WardrobeItem> wardrobe, {
    _PurchaseContext context = const _PurchaseContext(),
    bool? isMaleUser,
  }) {
    final candidates = <WardrobeItem>[];
    final categories = <String, int>{};
    final typeTexts = wardrobe.map((item) => _normalize(item.type)).toSet();
    final colors = wardrobe.map((item) => _normalize(item.color)).toSet();

    for (final item in wardrobe) {
      categories.update(_categoryKey(item), (value) => value + 1,
          ifAbsent: () => 1);
    }

    final neutralRatio = wardrobe.isEmpty
        ? 1.0
        : wardrobe.where((item) => _isNeutralColor(item.color)).length /
            wardrobe.length;

    candidates.addAll(_contextCandidates(context));

    if (_countCategory(wardrobe, 'lower') < 3) {
      candidates.addAll([
        _virtualItem(
          id: 'candidate_grey_chino',
          category: 'lower',
          type: 'Gri Chino Pantolon',
          color: 'Gri',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'grey_chino',
          occasionTags: const ['daily', 'work'],
          formality: 'smart casual',
        ),
        _virtualItem(
          id: 'candidate_navy_performance_jogger_priority',
          category: 'lower',
          type: 'Lacivert Performans Jogger',
          color: 'Lacivert',
          styleTags: const ['sport', 'casual'],
          reasonKey: 'performance_jogger',
          occasionTags: const ['sport', 'daily'],
          formality: 'casual',
        ),
        _virtualItem(
          id: 'candidate_dark_relaxed_trouser',
          category: 'lower',
          type: 'Koyu Gri Relaxed Pantolon',
          color: 'Gri',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'relaxed_trouser',
          occasionTags: const ['daily', 'travel'],
          formality: 'casual',
        ),
      ]);
    }

    if (_countCategory(wardrobe, 'shoes') < 2) {
      candidates.addAll([
        _virtualItem(
          id: 'candidate_white_training_sneaker_priority',
          category: 'shoes',
          type: 'Beyaz Training Sneaker',
          color: 'Beyaz',
          styleTags: const ['sport'],
          reasonKey: 'white_training_sneaker',
          occasionTags: const ['sport', 'daily'],
          formality: 'casual',
        ),
        _virtualItem(
          id: 'candidate_brown_suede_sneaker',
          category: 'shoes',
          type: 'Kahverengi Süet Sneaker',
          color: 'Kahverengi',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'suede_sneaker',
          occasionTags: const ['daily', 'travel'],
          formality: 'casual',
        ),
      ]);
    }

    if (_countCategory(wardrobe, 'outerwear') < 2) {
      candidates.addAll([
        _virtualItem(
          id: 'candidate_navy_zip_jacket',
          category: 'outerwear',
          type: 'Lacivert Fermuarlı Ceket',
          color: 'Lacivert',
          styleTags: const ['casual', 'sport'],
          reasonKey: 'zip_jacket',
          occasionTags: const ['daily', 'sport', 'travel'],
          formality: 'casual',
        ),
        _virtualItem(
          id: 'candidate_light_overshirt',
          category: 'outerwear',
          type: 'Açık Gri Overshirt',
          color: 'Gri',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'light_overshirt',
          occasionTags: const ['daily', 'work'],
          formality: 'smart casual',
        ),
      ]);
    }

    if (neutralRatio > 0.70 &&
        !colors.contains('bordo') &&
        !colors.contains('koyu yesil')) {
      candidates.add(
        _virtualItem(
          id: 'candidate_accent_shirt',
          category: 'upper',
          type: 'Bordo / Koyu Yeşil Gömlek',
          color: 'Bordo',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'accent',
        ),
      );
    }

    if (_countStyle(wardrobe, 'shoes', 'smart_casual') < 1 &&
        !typeTexts.any((type) =>
            type.contains('loafer') || type.contains('klasik ayakkabi'))) {
      candidates.add(
        _virtualItem(
          id: 'candidate_loafer',
          category: 'shoes',
          type: 'Loafer / Klasik Ayakkabı',
          color: 'Kahverengi',
          styleTags: const ['smart_casual', 'business'],
          reasonKey: 'smart_shoes',
        ),
      );
    }

    if (!typeTexts.any((type) => type.contains('chino')) &&
        !colors.contains('bej') &&
        !colors.contains('haki')) {
      candidates.add(
        _virtualItem(
          id: 'candidate_chino',
          category: 'lower',
          type: 'Slim Fit Chino (Bej / Haki)',
          color: 'Bej',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'chino',
        ),
      );
    }

    if (!typeTexts.any((type) => type.contains('blazer'))) {
      candidates.add(
        _virtualItem(
          id: 'candidate_blazer',
          category: 'outerwear',
          type: 'Lacivert Blazer',
          color: 'Lacivert',
          styleTags: const ['smart_casual', 'business'],
          reasonKey: 'blazer',
        ),
      );
    }

    if (!colors.contains('beyaz') ||
        !typeTexts.any((type) =>
            type.contains('gomlek') || type.contains('oxford'))) {
      candidates.add(
        _virtualItem(
          id: 'candidate_white_shirt',
          category: 'upper',
          type: 'Beyaz Oxford Gömlek',
          color: 'Beyaz',
          styleTags: const ['smart_casual', 'business'],
          reasonKey: 'white_shirt',
        ),
      );
    }

    if (_countCategory(wardrobe, 'shoes') < 2 &&
        !typeTexts.any((type) => type.contains('beyaz sneaker'))) {
      candidates.add(
        _virtualItem(
          id: 'candidate_white_sneaker',
          category: 'shoes',
          type: 'Minimal Beyaz Sneaker',
          color: 'Beyaz',
          styleTags: const ['casual', 'sport', 'smart_casual'],
          reasonKey: 'white_sneaker',
        ),
      );
    }

    if (_countCategory(wardrobe, 'outerwear') < 2) {
      candidates.add(
        _virtualItem(
          id: 'candidate_light_jacket',
          category: 'outerwear',
          type: 'İnce Mevsimlik Ceket',
          color: 'Gri',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'light_jacket',
        ),
      );
    }

    if (_countCategory(wardrobe, 'upper') < 5) {
      candidates.add(
        _virtualItem(
          id: 'candidate_basic_polo',
          category: 'upper',
          type: 'Lacivert Polo',
          color: 'Lacivert',
          styleTags: const ['casual', 'smart_casual'],
          reasonKey: 'basic_polo',
        ),
      );
    }

    final fallbackCandidates = [
      _virtualItem(
        id: 'candidate_black_derby',
        category: 'shoes',
        type: 'Siyah Deri Derby Ayakkabı',
        color: 'Siyah',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'black_derby',
        occasionTags: const ['wedding', 'work', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_black_oxford_shoes',
        category: 'shoes',
        type: 'Siyah Rugan Oxford Ayakkabı',
        color: 'Siyah',
        styleTags: const ['business', 'classic'],
        reasonKey: 'black_oxford_shoes',
        occasionTags: const ['wedding', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_nude_block_heel',
        category: 'shoes',
        type: 'Nude Blok Topuklu Ayakkabı',
        color: 'Nude',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'nude_block_heel',
        occasionTags: const ['wedding', 'date', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_black_strappy_heel',
        category: 'shoes',
        type: 'Siyah İnce Bantlı Topuklu Ayakkabı',
        color: 'Siyah',
        styleTags: const ['business', 'classic'],
        reasonKey: 'black_strappy_heel',
        occasionTags: const ['wedding', 'date', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_satin_shirt',
        category: 'upper',
        type: 'Ekru Saten Gömlek',
        color: 'Ekru',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'satin_shirt',
        occasionTags: const ['wedding', 'date', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_black_satin_blouse',
        category: 'upper',
        type: 'Siyah Saten Bluz',
        color: 'Siyah',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'black_satin_blouse',
        occasionTags: const ['wedding', 'date', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_ivory_wrap_top',
        category: 'upper',
        type: 'Ekru Kruvaze Bluz',
        color: 'Ekru',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'ivory_wrap_top',
        occasionTags: const ['wedding', 'work', 'formal'],
        formality: 'semi-formal',
      ),
      _virtualItem(
        id: 'candidate_wide_leg_trouser',
        category: 'lower',
        type: 'Siyah Palazzo Kumaş Pantolon',
        color: 'Siyah',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'wide_leg_trouser',
        occasionTags: const ['wedding', 'work', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_tailored_black_trouser',
        category: 'lower',
        type: 'Siyah Cigarette Kumaş Pantolon',
        color: 'Siyah',
        styleTags: const ['business', 'classic'],
        reasonKey: 'tailored_black_trouser',
        occasionTags: const ['wedding', 'work', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_satin_midi_skirt',
        category: 'lower',
        type: 'Şampanya Saten Midi Etek',
        color: 'Şampanya',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'satin_midi_skirt',
        occasionTags: const ['wedding', 'date', 'formal'],
        formality: 'formal',
      ),
      _virtualItem(
        id: 'candidate_pleated_midi_skirt',
        category: 'lower',
        type: 'Siyah Pileli Midi Etek',
        color: 'Siyah',
        styleTags: const ['classic', 'smart_casual'],
        reasonKey: 'pleated_midi_skirt',
        occasionTags: const ['work', 'wedding', 'date'],
        formality: 'semi-formal',
      ),
      _virtualItem(
        id: 'candidate_trench',
        category: 'outerwear',
        type: 'Bej Trençkot',
        color: 'Bej',
        styleTags: const ['classic', 'smart_casual'],
        reasonKey: 'trench',
        occasionTags: const ['work', 'daily', 'travel'],
        formality: 'smart casual',
      ),
      _virtualItem(
        id: 'candidate_cropped_blazer',
        category: 'outerwear',
        type: 'Siyah Crop Blazer',
        color: 'Siyah',
        styleTags: const ['business', 'smart_casual'],
        reasonKey: 'cropped_blazer',
        occasionTags: const ['wedding', 'work', 'date'],
        formality: 'semi-formal',
      ),
      _virtualItem(
        id: 'candidate_linen_shirt',
        category: 'upper',
        type: 'Beyaz Keten Gömlek',
        color: 'Beyaz',
        styleTags: const ['casual', 'smart_casual'],
        reasonKey: 'linen_shirt',
        occasionTags: const ['daily', 'travel'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_oversize_white_tshirt',
        category: 'upper',
        type: 'Oversize Beyaz Tişört',
        color: 'Beyaz',
        styleTags: const ['casual', 'street'],
        reasonKey: 'oversize_white_tshirt',
        occasionTags: const ['daily', 'travel'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_boxy_polo',
        category: 'upper',
        type: 'Lacivert Boxy Polo',
        color: 'Lacivert',
        styleTags: const ['casual', 'smart_casual'],
        reasonKey: 'boxy_polo',
        occasionTags: const ['daily', 'work'],
        formality: 'smart casual',
      ),
      _virtualItem(
        id: 'candidate_running_sneaker',
        category: 'shoes',
        type: 'Siyah Hafif Koşu Ayakkabısı',
        color: 'Siyah',
        styleTags: const ['sport'],
        reasonKey: 'running_sneaker',
        occasionTags: const ['sport', 'daily'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_white_training_sneaker',
        category: 'shoes',
        type: 'Beyaz Training Sneaker',
        color: 'Beyaz',
        styleTags: const ['sport'],
        reasonKey: 'white_training_sneaker',
        occasionTags: const ['sport', 'daily'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_chunky_sneaker',
        category: 'shoes',
        type: 'Gri Chunky Sneaker',
        color: 'Gri',
        styleTags: const ['sport', 'street'],
        reasonKey: 'chunky_sneaker',
        occasionTags: const ['sport', 'daily', 'travel'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_technical_jacket',
        category: 'outerwear',
        type: 'Siyah Teknik Yağmurluk',
        color: 'Siyah',
        styleTags: const ['sport', 'casual'],
        reasonKey: 'technical_jacket',
        occasionTags: const ['sport', 'travel', 'daily'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_black_jogger',
        category: 'lower',
        type: 'Siyah Teknik Jogger',
        color: 'Siyah',
        styleTags: const ['sport', 'casual'],
        reasonKey: 'black_jogger',
        occasionTags: const ['sport', 'daily', 'travel'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_navy_performance_jogger',
        category: 'lower',
        type: 'Lacivert Performans Jogger',
        color: 'Lacivert',
        styleTags: const ['sport', 'casual'],
        reasonKey: 'performance_jogger',
        occasionTags: const ['sport', 'daily'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_grey_training_shorts',
        category: 'lower',
        type: 'Gri Antrenman Şortu',
        color: 'Gri',
        styleTags: const ['sport'],
        reasonKey: 'training_shorts',
        occasionTags: const ['sport'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_black_track_pants',
        category: 'lower',
        type: 'Siyah Eşofman Altı',
        color: 'Siyah',
        styleTags: const ['sport', 'casual'],
        reasonKey: 'track_pants',
        occasionTags: const ['sport', 'daily'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_grey_training_leggings',
        category: 'lower',
        type: 'Antrasit Training Tayt',
        color: 'Antrasit',
        styleTags: const ['sport'],
        reasonKey: 'grey_training_leggings',
        occasionTags: const ['sport'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_cargo_pant',
        category: 'lower',
        type: 'Haki Relaxed Cargo Pantolon',
        color: 'Haki',
        styleTags: const ['street', 'casual'],
        reasonKey: 'cargo_pant',
        occasionTags: const ['daily', 'travel'],
        formality: 'casual',
      ),
      _virtualItem(
        id: 'candidate_black_jean',
        category: 'lower',
        type: 'Siyah Düz Jean',
        color: 'Siyah',
        styleTags: const ['casual', 'smart_casual'],
        reasonKey: 'black_jean',
      ),
      _virtualItem(
        id: 'candidate_cream_knit',
        category: 'upper',
        type: 'Krem İnce Triko',
        color: 'Krem',
        styleTags: const ['casual', 'smart_casual'],
        reasonKey: 'cream_knit',
      ),
      _virtualItem(
        id: 'candidate_chelsea_boot',
        category: 'shoes',
        type: 'Kahverengi Chelsea Bot',
        color: 'Kahverengi',
        styleTags: const ['casual', 'smart_casual', 'business'],
        reasonKey: 'chelsea_boot',
      ),
      _virtualItem(
        id: 'candidate_overshirt',
        category: 'outerwear',
        type: 'Bej Overshirt',
        color: 'Bej',
        styleTags: const ['casual', 'smart_casual'],
        reasonKey: 'overshirt',
      ),
      _virtualItem(
        id: 'candidate_grey_trouser',
        category: 'lower',
        type: 'Gri Kumaş Pantolon',
        color: 'Gri',
        styleTags: const ['smart_casual', 'business'],
        reasonKey: 'grey_trouser',
      ),
      _virtualItem(
        id: 'candidate_denim_jacket',
        category: 'outerwear',
        type: 'Koyu Mavi Denim Ceket',
        color: 'Mavi',
        styleTags: const ['casual'],
        reasonKey: 'denim_jacket',
      ),
    ];

    final candidateIds = candidates.map((item) => item.id).toSet();
    for (final candidate in fallbackCandidates) {
      if (candidates.length >= 34) break;
      if (candidateIds.contains(candidate.id)) continue;
      if (_isGenderIncompatible(candidate, isMaleUser: isMaleUser)) continue;
      if (_hasSimilarItem(candidate, wardrobe)) continue;

      candidates.add(candidate);
      candidateIds.add(candidate.id);
    }

    return candidates;
  }

  String _buildReason(
    List<WardrobeItem> wardrobe,
    WardrobeItem candidate,
    int gain,
    {
    _PurchaseContext context = const _PurchaseContext(),
    double confidence = 0,
  }) {
    final compatible = _findCompatibleItems(wardrobe, candidate);
    final categoryCounts = <String, int>{};
    for (final item in compatible) {
      categoryCounts.update(_categoryKey(item), (value) => value + 1,
          ifAbsent: () => 1);
    }

    final contextLead = context.occasion == null
        ? ''
        : '${_occasionLabel(context.occasion!)} planı için iyi oturur. ';
    final confidenceText = confidence >= 0.78
        ? ' Güvenim yüksek; dolabındaki çizgiyle iyi örtüşüyor.'
        : confidence >= 0.62
            ? ' Güvenim orta-yüksek; yine de bağlamı iyi karşılıyor.'
            : '';

    final role = _reasonRole(candidate);
    final fit = _reasonWardrobeFit(candidate);
    final impact = _reasonImpact(candidate, gain);
    return '$contextLead$role $fit $impact$confidenceText';
  }

  String _reasonRole(WardrobeItem candidate) {
    final category = _categoryKey(candidate);
    final type = _normalize(candidate.type);
    final styles = _styleTags(candidate);
    final key = _normalize(candidate.rawData['reason_key']?.toString() ?? '');

    if (category == 'upper') {
      if (_containsAny(type, ['oxford', 'gomlek', 'saten'])) {
        return 'Üst tarafta daha temiz ve düzenli bir ifade kurar.';
      }
      if (_containsAny(type, ['performans', 'antrenman'])) {
        return 'Hareketli günlerde terletmeyen, pratik bir spor üst rolü üstlenir.';
      }
      if (_containsAny(type, ['tisort', 't-shirt', 'basic'])) {
        return 'Günlük kombinlerde hızlı kullanılan temel üst boşluğunu kapatır.';
      }
      if (_containsAny(type, ['triko', 'polo'])) {
        return 'Rahatlıkla düzenli görünüm arasında ara katman gibi çalışır.';
      }
      if (key.contains('accent')) {
        return 'Dolaptaki nötr ağırlığı kıran kontrollü bir renk vurgusu ekler.';
      }
    }

    if (category == 'lower') {
      if (_containsAny(type, ['jogger', 'esofman', 'performans'])) {
        return 'Jean yerine daha rahat ve hareketli bir alt seçenek açar.';
      }
      if (_containsAny(type, ['sort', 'antrenman'])) {
        return 'Spor ve sıcak hava kullanımında uzun pantolon ihtiyacını azaltır.';
      }
      if (_containsAny(type, ['chino'])) {
        return 'Günlük görünümü biraz daha toplu gösteren smart casual bir zemin sağlar.';
      }
      if (_containsAny(type, ['jean', 'denim'])) {
        return 'Dolabın günlük tarafında güvenli, kolay kombinlenen ana parça olur.';
      }
      if (_containsAny(type, ['kumas', 'palazzo', 'cigarette'])) {
        return 'Daha düzenli planlar için alt giyimi şık bir seviyeye taşır.';
      }
      if (styles.contains('street')) {
        return 'Rahat siluetiyle daha sokak ve seyahat odaklı kombinler açar.';
      }
    }

    if (category == 'shoes') {
      if (_containsAny(type, ['training', 'kosu', 'spor'])) {
        return 'Spor kullanımda tabanı daha rahat bir ayakkabı alternatifi verir.';
      }
      if (_containsAny(type, ['sneaker'])) {
        return 'Günlük kombinleri sertleştirmeden tamamlayan sade ayakkabı rolü görür.';
      }
      if (_containsAny(type, ['loafer', 'derby', 'oxford', 'klasik'])) {
        return 'Ayakkabı tarafında daha düzenli ve şık bir seçenek oluşturur.';
      }
      if (_containsAny(type, ['bot', 'chelsea'])) {
        return 'Serin havalarda alt giyimi daha güçlü gösteren sağlam bir bitiş sağlar.';
      }
    }

    if (category == 'outerwear') {
      if (_containsAny(type, ['yagmurluk', 'teknik'])) {
        return 'Yağışlı veya hareketli günlerde işlevsel dış katman ihtiyacını karşılar.';
      }
      if (_containsAny(type, ['blazer'])) {
        return 'Üstüne eklediğinde kombini tek hamlede daha şık hale getirir.';
      }
      if (_containsAny(type, ['overshirt'])) {
        return 'Mont kadar ağır olmayan, gömlekten daha güçlü bir ara katman sunar.';
      }
      if (_containsAny(type, ['denim', 'ceket'])) {
        return 'Günlük kombinlerde görüntüyü tamamlayan rahat bir dış katman olur.';
      }
    }

    return 'Dolaptaki mevcut çizgiye yeni bir kullanım rolü ekler.';
  }

  String _reasonWardrobeFit(WardrobeItem candidate) {
    final category = _categoryKey(candidate);
    final styles = _styleTags(candidate);
    final color = _normalize(candidate.color);

    if (category == 'upper') {
      if (styles.contains('business')) {
        return 'Kumaş pantolon, chino ve sade ayakkabılarla daha net eşleşir.';
      }
      if (styles.contains('sport')) {
        return 'Jogger, şort ve sneaker tarafıyla doğal bir spor bütünlüğü kurar.';
      }
      return 'Jean, chino ve sneaker gibi parçalarla zahmetsizce eşleşir.';
    }

    if (category == 'lower') {
      if (styles.contains('sport')) {
        return 'Tişört, sweatshirt ve spor ayakkabıyla hızlı bir set oluşturur.';
      }
      if (styles.contains('business')) {
        return 'Gömlek, polo ve loafer/derby çizgisiyle daha düzenli görünür.';
      }
      if (_isNeutralColor(color)) {
        return 'Nötr rengi sayesinde dolaptaki üstlerin çoğuyla kolayca denenir.';
      }
      return 'Üst giyimdeki sade parçalarla dolabın renk dengesini bozmadan çalışır.';
    }

    if (category == 'shoes') {
      if (styles.contains('sport')) {
        return 'Rahat altlar ve basic üstlerle gündelik-spor tarafı tamamlar.';
      }
      if (styles.contains('business')) {
        return 'Gömlek, blazer ve kumaş pantolon kombinlerini daha bitmiş gösterir.';
      }
      return 'Günlük altlarla çabuk uyum sağlar ve kombinleri daha temiz bitirir.';
    }

    if (category == 'outerwear') {
      if (styles.contains('sport')) {
        return 'Spor üstler ve rahat altlarla hafif, pratik bir katman verir.';
      }
      if (styles.contains('business')) {
        return 'Gömlek ve kumaş pantolon gibi düzenli parçaların üstüne yakışır.';
      }
      return 'Dolaptaki basic üstleri daha tamamlanmış günlük kombinlere çevirir.';
    }

    return 'Renk ve stil olarak mevcut parçalarınla uyumlu bir tamamlayıcıdır.';
  }

  String _reasonImpact(WardrobeItem candidate, int gain) {
    final category = _categoryKey(candidate);
    if (gain >= 8) {
      return 'Bu yüzden kombin ihtimalini belirgin şekilde artırır.';
    }
    if (category == 'outerwear') {
      return 'Özellikle katman eksik günlerde dolabın kullanım alanını genişletir.';
    }
    if (category == 'shoes') {
      return 'Ayakkabı çeşitliliği arttığı için aynı kıyafetleri farklı havada kullanmanı sağlar.';
    }
    if (category == 'lower') {
      return 'Alt giyim çeşitliliği arttıkça üstlerini daha farklı senaryolarda kullanabilirsin.';
    }
    if (category == 'upper') {
      return 'Üst giyim rotasyonunu genişlettiği için mevcut altları daha sık kullanılır hale getirir.';
    }
    return 'Bu yüzden küçük ama hissedilir bir dolap boşluğunu kapatır.';
  }

  List<WardrobeItem> _findCompatibleItems(
    List<WardrobeItem> wardrobe,
    WardrobeItem candidate,
  ) {
    return wardrobe.where((item) => _isCompatible(item, candidate)).toList();
  }

  WardrobeItem _virtualItem({
    required String id,
    required String category,
    required String type,
    required String color,
    required List<String> styleTags,
    required String reasonKey,
    List<String>? occasionTags,
    String? formality,
  }) {
    return WardrobeItem(
      id: id,
      collection: 'virtual_gap_candidate',
      userId: '',
      imageUrl: '',
      category: category,
      type: type,
      color: color,
      fabricType: 'Belirtilmedi',
      favorite: false,
      styleTags: styleTags,
      season: const ['ilkbahar', 'yaz', 'sonbahar', 'kış'],
      isVirtual: true,
      rawData: {
        'reason_key': reasonKey,
        'occasion_tags': occasionTags ?? _defaultOccasions(reasonKey, styleTags),
        'formality': formality ?? _defaultFormality(reasonKey, styleTags),
      },
    );
  }

  int _countCategory(List<WardrobeItem> wardrobe, String category) {
    return wardrobe.where((item) => _categoryKey(item) == category).length;
  }

  int _countStyle(List<WardrobeItem> wardrobe, String category, String style) {
    return wardrobe
        .where((item) => _categoryKey(item) == category)
        .where((item) => _styleTags(item).contains(style))
        .length;
  }

  Set<String> _missingCategoryKeys(List<WardrobeItem> wardrobe) {
    final counts = {
      'upper': 0,
      'lower': 0,
      'outerwear': 0,
      'shoes': 0,
    };
    for (final item in wardrobe) {
      final category = _categoryKey(item);
      if (counts.containsKey(category)) {
        counts[category] = counts[category]! + 1;
      }
    }

    final missing = <String>{};
    if ((counts['upper'] ?? 0) <= 5) missing.add('upper');
    if ((counts['lower'] ?? 0) <= 4) missing.add('lower');
    if ((counts['outerwear'] ?? 0) <= 2) missing.add('outerwear');
    if ((counts['shoes'] ?? 0) <= 3) missing.add('shoes');
    return missing;
  }

  // UPDATED: token overlap güçlendirildi, lokal ve Gemini için ortak filtre.
  bool _hasSimilarItem(WardrobeItem candidate, List<WardrobeItem> wardrobe) {
    final candName = _normalize(candidate.displayName);
    final candCategory = _categoryKey(candidate);
    final candColor = _normalize(candidate.color);
    final candType = _normalize(candidate.type);
    final candTokens = _keyTokens('$candName $candCategory $candType');

    for (final item in wardrobe) {
      final itemName = _normalize(item.displayName);
      final itemCategory = _categoryKey(item);
      final itemColor = _normalize(item.color);
      final itemType = _normalize(item.type);
      final itemTokens = _keyTokens('$itemName $itemCategory $itemType');

      if (candTokens.isNotEmpty && itemTokens.isNotEmpty) {
        final overlap = candTokens.intersection(itemTokens).length;
        final union = candTokens.union(itemTokens).length;
        final sameCategory =
            candCategory.isNotEmpty && candCategory == itemCategory;
        final minLen =
            candTokens.length < itemTokens.length ? candTokens.length : itemTokens.length;
        final sameColor =
            candColor.isNotEmpty && itemColor.isNotEmpty && itemColor == candColor;
        if (sameCategory && union > 0 && overlap / union >= 0.55) {
          return true;
        }
        if (sameColor && minLen > 0 && overlap / minLen >= 0.60) return true;
      }

      if (candType.isNotEmpty &&
          itemType == candType &&
          candColor.isNotEmpty &&
          itemColor == candColor) {
        return true;
      }
    }

    return false;
  }

  bool _isAccessory(WardrobeItem item) {
    final text = _normalize(
      '${item.displayName} ${item.type} ${item.category} '
      '${item.rawData['item_name'] ?? ''}',
    );

    return _containsAny(text, const [
      'kemer',
      'canta',
      'saat',
      'taki',
      'kolye',
      'bileklik',
      'kupe',
      'yuzuk',
      'sapka',
      'bere',
      'gozluk',
      'esarp',
      'atki',
      'eldiven',
      'cuzdan',
    ]);
  }

  int _countSimilarType(List<WardrobeItem> wardrobe, WardrobeItem candidate) {
    final candidateCategory = _categoryKey(candidate);
    final candidateType = _normalize(candidate.type);
    final candidateTokens = candidateType
        .split(RegExp(r'\s+|/|\(|\)'))
        .where((token) => token.length >= 4)
        .toSet();

    return wardrobe.where((item) {
      if (_categoryKey(item) != candidateCategory) return false;
      final itemType = _normalize(item.type);
      return candidateTokens.any(itemType.contains);
    }).length;
  }

  bool _isIgnored(WardrobeItem item) {
    final category = _categoryKey(item);
    return category.isEmpty || category == 'socks' || category == 'accessory';
  }

  bool _isGenderIncompatible(WardrobeItem item, {bool? isMaleUser}) {
    if (isMaleUser != true) return false;

    final text = _normalize(
      '${item.displayName} ${item.type} ${item.category} '
      '${item.rawData['reason_key'] ?? ''}',
    );

    return _containsAny(text, [
      'etek',
      'mini etek',
      'midi etek',
      'maxi etek',
      'elbise',
      'abiye',
      'body',
      'korset',
      'tulum',
      'tayt',
      'topuklu',
      'stiletto',
      'platform topuk',
      'kitten heel',
      'blok topuk',
      'ince bantli',
      'bluz',
      'crop',
      'crop top',
      'palazzo',
      'cigarette',
      'kadin kesimi',
      'kruvaze bluz',
      'wrap top',
      'saten midi',
      'pleated midi',
      'strappy heel',
      'block heel',
    ]);
  }

  String _categoryKey(WardrobeItem item) {
    final text = _normalize(item.category);
    final collection = _normalize(item.collection);
    if (text == 'upper' ||
        text.contains('ust') ||
        collection.contains('ust_giyim')) {
      return 'upper';
    }
    if (text == 'lower' ||
        text.contains('alt') ||
        collection.contains('alt_giyim')) {
      return 'lower';
    }
    if (text == 'outerwear' ||
        text.contains('dis') ||
        collection.contains('dis_giyim')) {
      return 'outerwear';
    }
    if (text == 'shoes' ||
        text.contains('ayakkabi') ||
        collection.contains('ayakkabi')) {
      return 'shoes';
    }
    if (text == 'accessory' || text.contains('aksesuar')) return 'accessory';
    if (text.contains('corap') || collection.contains('corap')) return 'socks';
    return text;
  }

  List<String> _styleTags(WardrobeItem item) {
    if (item.styleTags.isNotEmpty) {
      return item.styleTags.map(_normalize).toSet().toList();
    }

    final type = _normalize(item.type);
    final tags = <String>{'casual'};
    if (_containsAny(type, ['gomlek', 'polo', 'chino', 'blazer', 'loafer'])) {
      tags.add('smart_casual');
    }
    if (_containsAny(type, ['klasik', 'kumas', 'oxford', 'blazer'])) {
      tags.add('business');
    }
    if (_containsAny(type, [
      'spor',
      'sneaker',
      'esofman',
      'tayt',
      'jogger',
      'antrenman',
      'training',
      'performans',
    ])) {
      tags.add('sport');
    }
    return tags.toList();
  }

  List<String> _occasionTags(WardrobeItem item) {
    final raw = item.rawData['occasion'] ??
        item.rawData['occasions'] ??
        item.rawData['occasion_tags'] ??
        item.rawData['kullanim_alani'];
    final parsed = _parseStringList(raw).map(_normalize).toSet().toList();
    if (parsed.isNotEmpty) return parsed;

    final styles = _styleTags(item);
    return _defaultOccasions(
      item.rawData['reason_key']?.toString() ?? '',
      styles,
    );
  }

  List<String> _candidateOccasions(WardrobeItem item) {
    final raw = item.rawData['occasion_tags'] ?? item.rawData['occasion'];
    final parsed = _parseStringList(raw).map(_normalize).toSet().toList();
    if (parsed.isNotEmpty) return parsed;
    return _defaultOccasions(
      item.rawData['reason_key']?.toString() ?? '',
      _styleTags(item),
    );
  }

  String _candidateFormality(WardrobeItem item) {
    final raw = item.rawData['formality']?.toString().trim();
    if (raw != null && raw.isNotEmpty) return _normalize(raw);
    return _defaultFormality(
      item.rawData['reason_key']?.toString() ?? '',
      _styleTags(item),
    );
  }

  String _displayStyle(WardrobeItem item) {
    final styles = _styleTags(item);
    if (styles.contains('business')) return 'Classic';
    if (styles.contains('smart_casual')) return 'Smart casual';
    if (styles.contains('sport')) return 'Sport';
    if (styles.contains('street')) return 'Streetwear';
    return 'Casual';
  }

  List<String> _defaultOccasions(String reasonKey, List<String> styles) {
    final key = _normalize(reasonKey);
    if (_containsAny(key, ['blazer', 'white_shirt', 'smart_shoes'])) {
      return const ['work', 'semi-formal', 'wedding'];
    }
    if (_containsAny(key, ['grey_trouser', 'chelsea_boot'])) {
      return const ['work', 'date', 'semi-formal'];
    }
    if (_containsAny(key, ['white_sneaker', 'black_jean', 'denim_jacket'])) {
      return const ['daily', 'smart casual'];
    }
    if (styles.contains('business')) return const ['work', 'formal'];
    if (styles.contains('sport')) return const ['sport', 'daily'];
    if (styles.contains('smart_casual')) {
      return const ['daily', 'work', 'semi-formal'];
    }
    return const ['daily'];
  }

  String _defaultFormality(String reasonKey, List<String> styles) {
    final key = _normalize(reasonKey);
    if (_containsAny(key, ['blazer', 'white_shirt', 'smart_shoes'])) {
      return 'semi-formal';
    }
    if (_containsAny(key, ['grey_trouser', 'chelsea_boot'])) {
      return 'smart casual';
    }
    if (styles.contains('business')) return 'formal';
    if (styles.contains('smart_casual')) return 'smart casual';
    return 'casual';
  }

  String _mostImpactfulQuestion(
    _WardrobePurchaseProfile profile,
    _PurchaseContext context,
  ) {
    if (!context.hasSignal) return 'Bu parçayı hangi ortam için alıyorsun?';
    if (context.hasUnknownText) {
      return 'Daha resmi mi, daha günlük mü olsun?';
    }
    if (profile.dominantStyle.isEmpty) {
      return 'Tarz olarak minimal, klasik, casual veya streetwear mı seversin?';
    }
    return 'Bu öneri daha şık mı, daha rahat mı hissettirsin?';
  }

  String _occasionLabel(String occasion) {
    switch (_normalize(occasion)) {
      case 'wedding':
        return 'Düğün/nikah';
      case 'work':
        return 'İş/ofis';
      case 'date':
        return 'Akşam planı';
      case 'sport':
        return 'Spor';
      case 'daily':
        return 'Günlük kullanım';
      default:
        return occasion;
    }
  }

  List<String> _parseStringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String? _mostCommon(List<String> values) {
    if (values.isEmpty) return null;

    final counts = <String, int>{};
    for (final value in values.map(_normalize).where((value) => value.isNotEmpty)) {
      counts.update(value, (count) => count + 1, ifAbsent: () => 1);
    }
    if (counts.isEmpty) return null;

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  bool _isNeutralColor(String color) {
    final text = _normalize(color);
    return text.contains('siyah') ||
        text.contains('beyaz') ||
        text.contains('lacivert') ||
        text.contains('gri') ||
        text.contains('bej') ||
        text.contains('krem') ||
        text.contains('kahverengi') ||
        text.contains('haki');
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any(value.contains);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
  }

  Set<String> _keyTokens(String text) {
    const stopWords = {
      've',
      'ile',
      'bir',
      'bu',
      'su',
      'o',
      'de',
      'da',
      'mi',
      'mu',
      'fit',
      'slim',
      'regular',
      'oversize',
      'basic',
      'klasik',
      'the',
      'a',
      'an',
      'and',
      'with',
    };

    return _normalize(text)
        .split(RegExp(r'[\s\-_/]+'))
        .where((token) => token.length >= 3 && !stopWords.contains(token))
        .toSet();
  }
}

class _WardrobePurchaseProfile {
  final String dominantStyle;
  final String dominantOccasion;
  final Set<String> missingConnectors;
  final bool hasPricePattern;

  const _WardrobePurchaseProfile({
    required this.dominantStyle,
    required this.dominantOccasion,
    required this.missingConnectors,
    required this.hasPricePattern,
  });
}

class _PurchaseContext {
  final String? occasion;
  final String? category;
  final String? formality;
  final String? style;
  final bool hasUnknownText;

  const _PurchaseContext({
    this.occasion,
    this.category,
    this.formality,
    this.style,
    this.hasUnknownText = false,
  });

  bool get hasSignal =>
      occasion != null ||
      category != null ||
      formality != null ||
      style != null ||
      hasUnknownText;

  _PurchaseContext copyWith({
    String? occasion,
    String? category,
    String? formality,
    String? style,
    bool? hasUnknownText,
  }) {
    return _PurchaseContext(
      occasion: occasion ?? this.occasion,
      category: category ?? this.category,
      formality: formality ?? this.formality,
      style: style ?? this.style,
      hasUnknownText: hasUnknownText ?? this.hasUnknownText,
    );
  }
}
