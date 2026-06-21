import 'package:cloud_firestore/cloud_firestore.dart';

enum ClothingCategory {
  top,
  bottom,
  outerwear,
  shoes,
  socks,
  unknown,
}

enum StylePreference {
  casual,
  street,
  sport,
  smart,
  special,
}

enum DayPlanType {
  normalDay,
  office,
  date,
  gym,
  dinner,
  travel,
  specialEvent,
}

enum Season {
  all,
  spring,
  summer,
  autumn,
  winter,
}

enum Thickness {
  light,
  medium,
  heavy,
}

enum WeatherCondition {
  clear,
  clouds,
  rain,
  snow,
  wind,
  unknown,
}

class ClothingItem {
  final String id;
  final String collection;
  final String userId;
  final String imageUrl;
  final ClothingCategory category;
  final String subCategory;
  final String color;
  final Set<StylePreference> styles;
  final Set<Season> seasons;
  final Thickness thickness;
  final bool favorite;
  final Map<String, dynamic> rawData;

  const ClothingItem({
    required this.id,
    required this.collection,
    required this.userId,
    required this.imageUrl,
    required this.category,
    required this.subCategory,
    required this.color,
    required this.styles,
    required this.seasons,
    required this.thickness,
    required this.favorite,
    this.rawData = const {},
  });

  factory ClothingItem.fromFirestore({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String collection,
  }) {
    final data = doc.data();
    final categoryText = (data['kategori'] ?? data['category'] ?? '')
        .toString();
    final subCategory = (data['tur'] ?? data['subCategory'] ?? '').toString();
    final category = parseClothingCategory(categoryText);

    return ClothingItem(
      id: doc.id,
      collection: collection,
      userId: (data['user_id'] ?? data['userId'] ?? '').toString(),
      imageUrl: (data['image_url'] ?? data['imageUrl'] ?? '').toString(),
      category: category,
      subCategory: subCategory,
      color: (data['renk'] ?? data['color'] ?? 'Belirtilmedi').toString(),
      styles: parseStyles(data['style'] ?? data['styles'], subCategory),
      seasons: parseSeasons(data['season'] ?? data['seasons'], subCategory),
      thickness: parseThickness(data['thickness'], subCategory),
      favorite: data['favori'] == true || data['favorite'] == true,
      rawData: data,
    );
  }

  bool get isTop => category == ClothingCategory.top;
  bool get isBottom => category == ClothingCategory.bottom;
  bool get isOuterwear => category == ClothingCategory.outerwear;
  bool get isShoes => category == ClothingCategory.shoes;
  bool get isSocks => category == ClothingCategory.socks;

  static ClothingCategory parseClothingCategory(String value) {
    final text = _normalize(value);
    if (text.contains('ust') || text.contains('top')) {
      return ClothingCategory.top;
    }
    if (text.contains('alt') || text.contains('bottom')) {
      return ClothingCategory.bottom;
    }
    if (text.contains('dis') || text.contains('outer')) {
      return ClothingCategory.outerwear;
    }
    if (text.contains('ayakkabi') || text.contains('shoe')) {
      return ClothingCategory.shoes;
    }
    if (text.contains('corap') || text.contains('sock')) {
      return ClothingCategory.socks;
    }
    return ClothingCategory.unknown;
  }

  static Set<StylePreference> parseStyles(Object? value, String subCategory) {
    final explicit = _parseList(value)
        .map(_parseStyle)
        .whereType<StylePreference>()
        .toSet();
    if (explicit.isNotEmpty) return explicit;

    final type = _normalize(subCategory);
    if (type.contains('esofman') ||
        type.contains('tayt') ||
        type.contains('spor')) {
      return {StylePreference.sport, StylePreference.casual};
    }
    if (type.contains('blazer') ||
        type.contains('gomlek') ||
        type.contains('klasik') ||
        type.contains('kumas') ||
        type.contains('chino') ||
        type.contains('loafer')) {
      return {StylePreference.smart};
    }
    if (type.contains('bot') ||
        type.contains('hoodie') ||
        type.contains('jean') ||
        type.contains('sneaker')) {
      return {StylePreference.street, StylePreference.casual};
    }
    if (type.contains('etek') ||
        type.contains('elbise') ||
        type.contains('bluz') ||
        type.contains('body') ||
        type.contains('tulum') ||
        type.contains('crop')) {
      return {StylePreference.special, StylePreference.casual};
    }
    return {StylePreference.casual};
  }

  static Set<Season> parseSeasons(Object? value, String subCategory) {
    final explicit = _parseList(value)
        .map(_parseSeason)
        .whereType<Season>()
        .toSet();
    if (explicit.isNotEmpty) return explicit;

    final type = _normalize(subCategory);
    if (type.contains('sort') ||
        type.contains('atlet') ||
        type.contains('sandalet') ||
        type.contains('terlik') ||
        type.contains('kisa kollu body') ||
        type.contains('crop')) {
      return {Season.summer, Season.spring};
    }
    if (type.contains('mont') ||
        type.contains('kaban') ||
        type.contains('kazak') ||
        type.contains('bot') ||
        type.contains('hoodie')) {
      return {Season.winter, Season.autumn};
    }
    if (type.contains('yagmurluk')) {
      return {Season.spring, Season.autumn, Season.winter};
    }
    return {Season.all};
  }

  static Thickness parseThickness(Object? value, String subCategory) {
    final explicit = _parseThickness(value?.toString());
    if (explicit != null) return explicit;

    final type = _normalize(subCategory);
    if (type.contains('mont') ||
        type.contains('kaban') ||
        type.contains('kazak') ||
        type.contains('bot') ||
        type.contains('hoodie')) {
      return Thickness.heavy;
    }
    if (type.contains('ceket') ||
        type.contains('hirka') ||
        type.contains('sweatshirt') ||
        type.contains('uzun kollu body') ||
        type.contains('kumas') ||
        type.contains('jean')) {
      return Thickness.medium;
    }
    return Thickness.light;
  }
}

class WeeklyStylePreference {
  final StylePreference primary;
  final StylePreference secondary;
  final StylePreference tertiary;

  const WeeklyStylePreference({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  Map<StylePreference, int> get weights => {
        primary: 4,
        secondary: 2,
        tertiary: 1,
      };

  List<StylePreference> allocationForWeek() {
    return [
      primary,
      secondary,
      primary,
      tertiary,
      primary,
      secondary,
      primary,
    ];
  }
}

class DayPlan {
  final DateTime date;
  final DayPlanType type;

  const DayPlan({
    required this.date,
    required this.type,
  });
}

class WeatherProfile {
  final DateTime date;
  final double temperatureC;
  final int humidity;
  final WeatherCondition condition;
  final String description;

  const WeatherProfile({
    required this.date,
    required this.temperatureC,
    required this.condition,
    this.humidity = 0,
    this.description = '',
  });

  bool get isHot => temperatureC >= 28;
  bool get isWarm => temperatureC >= 20 && temperatureC < 28;
  bool get isMild => temperatureC >= 12 && temperatureC < 20;
  bool get isCold => temperatureC < 12;
  bool get isFreezing => temperatureC <= 5;
  bool get isRainy => condition == WeatherCondition.rain;
  bool get isSnowy => condition == WeatherCondition.snow;

  Season get preferredSeason {
    if (temperatureC >= 24) return Season.summer;
    if (temperatureC >= 14) return Season.spring;
    if (temperatureC >= 7) return Season.autumn;
    return Season.winter;
  }
}

class OutfitRecommendation {
  final DateTime date;
  final String day;
  final String style;
  final String description;
  final StylePreference focusStyle;
  final DayPlanType planType;
  final WeatherProfile weather;
  final ClothingItem top;
  final ClothingItem bottom;
  final ClothingItem shoes;
  final ClothingItem? outerwear;
  final ClothingItem? socks;
  final double score;
  final List<String> notes;

  const OutfitRecommendation({
    required this.date,
    required this.day,
    required this.style,
    required this.description,
    required this.focusStyle,
    required this.planType,
    required this.weather,
    required this.top,
    required this.bottom,
    required this.shoes,
    this.outerwear,
    this.socks,
    required this.score,
    this.notes = const [],
  });

  List<ClothingItem> get items => [
        top,
        if (bottom.id != top.id) bottom,
        shoes,
        if (outerwear != null) outerwear!,
        if (socks != null) socks!,
      ];

  List<ClothingItem> get visibleOutfitItems => [
        top,
        if (bottom.id != top.id) bottom,
        shoes,
        if (outerwear != null) outerwear!,
      ];
}

StylePreference? _parseStyle(String value) {
  final text = _normalize(value);
  if (text.contains('casual')) return StylePreference.casual;
  if (text.contains('street')) return StylePreference.street;
  if (text.contains('sport')) return StylePreference.sport;
  if (text.contains('smart')) return StylePreference.smart;
  if (text.contains('special') || text.contains('ozel')) {
    return StylePreference.special;
  }
  return null;
}

Season? _parseSeason(String value) {
  final text = _normalize(value);
  if (text.contains('all') || text.contains('tum')) return Season.all;
  if (text.contains('spring') || text.contains('ilkbahar')) {
    return Season.spring;
  }
  if (text.contains('summer') || text.contains('yaz')) return Season.summer;
  if (text.contains('autumn') || text.contains('fall') || text.contains('son')) {
    return Season.autumn;
  }
  if (text.contains('winter') || text.contains('kis')) return Season.winter;
  return null;
}

Thickness? _parseThickness(String? value) {
  final text = _normalize(value ?? '');
  if (text.contains('light') || text.contains('ince')) return Thickness.light;
  if (text.contains('medium') || text.contains('orta')) return Thickness.medium;
  if (text.contains('heavy') || text.contains('kalin')) return Thickness.heavy;
  return null;
}

List<String> _parseList(Object? value) {
  if (value == null) return const [];
  if (value is Iterable) {
    return value.map((item) => item.toString()).toList();
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'Belirtilmedi') return const [];
  return text.split(',').map((item) => item.trim()).toList();
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
