import '../models/outfit_reason_data.dart';
import '../models/wardrobe_item_model.dart';

class OutfitReasonService {
  OutfitReasonData buildReasonData({
    required List<WardrobeItem> items,
    required String planType,
    required double? weatherTemp,
    List<WardrobeItem> wardrobe = const [],
  }) {
    final weather = _weatherAnalysis(items, weatherTemp);
    final color = _colorAnalysis(items, wardrobe);
    final visibleItems = items.where((item) => !_isCategory(item, 'socks')).toList();
    final usage = _usageAnalysis(visibleItems.isEmpty ? items : visibleItems);
    final warning = _warningAnalysis(items, planType);
    final overall = color.score * 0.4 + weather.score * 0.3 + usage.score * 0.3;

    return OutfitReasonData(
      weatherNote: weather.note,
      colorScore: color.score,
      colorNote: color.note,
      usageNote: usage.note,
      warningNote: warning.note,
      suggestedAction: warning.suggestedAction,
      overallScore: overall.clamp(0, 100).toDouble(),
    );
  }

  _ReasonScore _weatherAnalysis(List<WardrobeItem> items, double? temp) {
    if (temp == null) {
      return const _ReasonScore(
        score: 70,
        note: 'Hava bilgisi yok; kombin parça uyumuna göre değerlendirildi.',
      );
    }

    final hasOuterwear = items.any((item) => _isCategory(item, 'outerwear'));
    final hasWarmPiece = items.any((item) {
      final type = _normalize(item.type);
      return type.contains('kazak') ||
          type.contains('sweat') ||
          type.contains('hoodie') ||
          type.contains('mont') ||
          type.contains('kaban') ||
          type.contains('ceket');
    });
    final top = _firstByCategory(items, 'upper');
    final outer = _firstByCategory(items, 'outerwear');

    if (temp < 5) {
      return _ReasonScore(
        score: hasOuterwear && hasWarmPiece ? 88 : 46,
        note: hasOuterwear
            ? '${temp.round()}°C için ${outer?.displayName ?? 'dış giyim'} iyi bir koruma katmanı.'
            : '${temp.round()}°C çok soğuk; mont veya kaban eklemek daha güvenli olur.',
      );
    }
    if (temp <= 12) {
      return _ReasonScore(
        score: hasOuterwear ? 86 : 64,
        note: hasOuterwear
            ? '${temp.round()}°C için ${top?.displayName ?? 'üst parça'} + dış giyim katmanı dengeli.'
            : '${temp.round()}°C serin; hafif bir ceket katmanı iyi olurdu.',
      );
    }
    if (temp <= 20) {
      return _ReasonScore(
        score: hasOuterwear ? 76 : 84,
        note: hasOuterwear
            ? '${temp.round()}°C için dış giyim gerekebilir ama çok kalın olmamalı.'
            : '${temp.round()}°C için hafif üst seçimi yeterli görünüyor.',
      );
    }

    return _ReasonScore(
      score: hasOuterwear ? 58 : 86,
      note: hasOuterwear
          ? '${temp.round()}°C sıcak; dış giyim gerekmeyebilir.'
          : '${temp.round()}°C için ince ve hafif parçalar daha uygun.',
    );
  }

  _ReasonScore _colorAnalysis(
    List<WardrobeItem> items,
    List<WardrobeItem> wardrobe,
  ) {
    final colors = items
        .map((item) => item.color.trim())
        .where((color) => color.isNotEmpty && color != 'Belirtilmedi')
        .toList();
    if (colors.isEmpty) {
      return const _ReasonScore(
        score: 45,
        note: 'Bu kombindeki parçalarda renk bilgisi eksik.',
      );
    }

    final neutralCount = colors.where(_isNeutralColor).length;
    final accentColors = colors.where((color) => !_isNeutralColor(color)).toSet();
    final score = ((neutralCount / colors.length) * 78 +
            (accentColors.isNotEmpty ? 14 : 0) +
            (colors.toSet().length <= 3 ? 8 : 0))
        .round()
        .clamp(0, 100)
        .toInt();
    final colorText = colors.toSet().join(' + ');
    final matchingWardrobeCount = wardrobe.where((item) {
      return colors.any((color) => _normalize(item.color) == _normalize(color));
    }).length;
    final accentText = accentColors.isEmpty
        ? 'Nötr renkler güvenli bir uyum veriyor.'
        : '${accentColors.join(', ')} kontrast katar.';

    return _ReasonScore(
      score: score,
      note: '$colorText, dolabındaki $matchingWardrobeCount parçayla eşleşiyor. $accentText',
    );
  }

  _ReasonScore _usageAnalysis(List<WardrobeItem> items) {
    if (items.isEmpty) {
      return const _ReasonScore(score: 50, note: 'Parça kullanım bilgisi bulunamadı.');
    }

    final sorted = [...items]..sort((a, b) => a.useCount.compareTo(b.useCount));
    final least = sorted.first;
    final most = [...items]..sort((a, b) => b.useCount.compareTo(a.useCount));
    final mostUsed = most.first;
    final usageScore = (100 - (mostUsed.useCount * 6)).clamp(45, 92).toInt();

    return _ReasonScore(
      score: usageScore,
      note:
          '${least.displayName} ${_lastUsedText(least)}. ${mostUsed.displayName} toplam ${mostUsed.useCount} öneride yer aldı.',
    );
  }

  _WarningResult _warningAnalysis(List<WardrobeItem> items, String planType) {
    final normalizedPlan = _normalize(planType);
    final shoes = _firstByCategory(items, 'shoes');
    final upper = _firstByCategory(items, 'upper');
    final shoeType = _normalize(shoes?.type ?? '');
    final upperType = _normalize(upper?.type ?? '');

    if (normalizedPlan.contains('smart') && shoeType.contains('sneaker')) {
      return const _WarningResult(
        note: 'Sneaker smart casual için fazla rahat kalabilir.',
        suggestedAction: 'Loafer ile yeniden öner',
      );
    }
    if (normalizedPlan.contains('sport') && shoeType.contains('loafer')) {
      return const _WarningResult(
        note: 'Loafer spor plan için fazla resmi kalabilir.',
        suggestedAction: 'Spor ayakkabı ile yeniden öner',
      );
    }
    if ((normalizedPlan.contains('business') || normalizedPlan.contains('office')) &&
        (upperType.contains('tisort') || upperType.contains('t-shirt'))) {
      return const _WarningResult(
        note: 'Tişört iş/ofis planı için fazla günlük kalabilir.',
        suggestedAction: 'Gömlek ile yeniden öner',
      );
    }

    return const _WarningResult();
  }

  WardrobeItem? _firstByCategory(List<WardrobeItem> items, String category) {
    for (final item in items) {
      if (_isCategory(item, category)) return item;
    }
    return null;
  }

  bool _isCategory(WardrobeItem item, String category) {
    final text = _normalize('${item.category} ${item.collection}');
    switch (category) {
      case 'upper':
        return text.contains('ust') || text.contains('upper') || text.contains('top');
      case 'lower':
        return text.contains('alt') || text.contains('lower') || text.contains('bottom');
      case 'outerwear':
        return text.contains('dis') || text.contains('outer');
      case 'shoes':
        return text.contains('ayakkabi') || text.contains('shoe');
      case 'socks':
        return text.contains('corap') || text.contains('sock');
      default:
        return false;
    }
  }

  bool _isNeutralColor(String color) {
    final text = _normalize(color);
    return text.contains('siyah') ||
        text.contains('beyaz') ||
        text.contains('lacivert') ||
        text.contains('gri') ||
        text.contains('bej') ||
        text.contains('krem');
  }

  String _lastUsedText(WardrobeItem item) {
    if (item.useCount == 0 || item.lastUsed == null) {
      return 'henüz önerilerde kullanılmadı';
    }

    final days = DateTime.now().difference(item.lastUsed!).inDays;
    if (days <= 30) return 'bu ay ${item.useCount} kez önerilerde kullanıldı';
    return '30+ gün önce önerilerde kullanıldı';
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

class _ReasonScore {
  final int score;
  final String note;

  const _ReasonScore({
    required this.score,
    required this.note,
  });
}

class _WarningResult {
  final String? note;
  final String? suggestedAction;

  const _WarningResult({
    this.note,
    this.suggestedAction,
  });
}
