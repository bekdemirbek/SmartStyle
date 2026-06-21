import 'package:cloud_firestore/cloud_firestore.dart';

import 'outfit_recommendation_models.dart';

class SavedOutfitPiece {
  final String collection;
  final String itemId;
  final String category;
  final String subCategory;
  final String color;
  final String imageUrl;

  const SavedOutfitPiece({
    required this.collection,
    required this.itemId,
    required this.category,
    required this.subCategory,
    required this.color,
    required this.imageUrl,
  });

  factory SavedOutfitPiece.fromClothingItem(ClothingItem item) {
    return SavedOutfitPiece(
      collection: item.collection,
      itemId: item.id,
      category: _categoryToFirestoreValue(item.category),
      subCategory: item.subCategory,
      color: item.color,
      imageUrl: item.imageUrl,
    );
  }

  factory SavedOutfitPiece.fromMap(Map<String, dynamic> map) {
    return SavedOutfitPiece(
      collection: (map['koleksiyon'] ?? '').toString(),
      itemId: (map['item_id'] ?? '').toString(),
      category: (map['kategori'] ?? '').toString(),
      subCategory: (map['tur'] ?? '').toString(),
      color: (map['renk'] ?? '').toString(),
      imageUrl: (map['image_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'koleksiyon': collection,
      'item_id': itemId,
      'kategori': category,
      'tur': subCategory,
      'renk': color,
      'image_url': imageUrl,
    };
  }
}

class SavedOutfit {
  final String id;
  final String userId;
  final DateTime? createdAt;
  final String weekId;
  final String day;
  final String primaryStyle;
  final String secondaryStyle;
  final String tertiaryStyle;
  final String dailyPlan;
  final Map<String, dynamic> weather;
  final double score;
  final String description;
  final bool favorite;
  final String creationType;
  final String source;
  final List<SavedOutfitPiece> pieces;

  const SavedOutfit({
    this.id = '',
    required this.userId,
    this.createdAt,
    required this.weekId,
    required this.day,
    required this.primaryStyle,
    required this.secondaryStyle,
    required this.tertiaryStyle,
    required this.dailyPlan,
    required this.weather,
    required this.score,
    required this.description,
    this.favorite = false,
    this.creationType = 'weekly_recommendation',
    this.source = 'weekly_recommendation',
    required this.pieces,
  });

  factory SavedOutfit.fromRecommendation({
    required String userId,
    required String weekId,
    required OutfitRecommendation recommendation,
    required WeeklyStylePreference stylePreference,
    String creationType = 'weekly_recommendation',
  }) {
    return SavedOutfit(
      userId: userId,
      weekId: weekId,
      day: _dayName(recommendation.date),
      primaryStyle: _styleToFirestoreValue(stylePreference.primary),
      secondaryStyle: _styleToFirestoreValue(stylePreference.secondary),
      tertiaryStyle: _styleToFirestoreValue(stylePreference.tertiary),
      dailyPlan: _planToFirestoreValue(recommendation.planType),
      weather: {
        'sicaklik': recommendation.weather.temperatureC,
        'nem': recommendation.weather.humidity,
        'durum': _weatherToFirestoreValue(recommendation.weather.condition),
        'aciklama': recommendation.weather.description,
      },
      score: recommendation.score,
      description: _buildDescription(recommendation),
      favorite: false,
      creationType: creationType,
      source: creationType,
      pieces: recommendation.items
          .map(SavedOutfitPiece.fromClothingItem)
          .toList(),
    );
  }

  factory SavedOutfit.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final rawPieces = data['parcalar'];

    return SavedOutfit(
      id: doc.id,
      userId: (data['user_id'] ?? '').toString(),
      createdAt: data['created_at'] is Timestamp
          ? (data['created_at'] as Timestamp).toDate()
          : null,
      weekId: (data['hafta_id'] ?? '').toString(),
      day: (data['gun'] ?? '').toString(),
      primaryStyle: (data['ana_stil'] ?? '').toString(),
      secondaryStyle: (data['ikinci_stil'] ?? '').toString(),
      tertiaryStyle: (data['ucuncu_stil'] ?? '').toString(),
      dailyPlan: (data['gunluk_plan'] ?? '').toString(),
      weather: Map<String, dynamic>.from(data['hava_durumu'] ?? {}),
      score: (data['puan'] is num) ? (data['puan'] as num).toDouble() : 0,
      description: (data['aciklama'] ?? '').toString(),
      favorite: data['favori'] == true,
      creationType: (data['olusturma_tipi'] ?? '').toString(),
      source: (data['source'] ?? data['olusturma_tipi'] ?? '').toString(),
      pieces: rawPieces is Iterable
          ? rawPieces
              .whereType<Map>()
              .map((piece) => SavedOutfitPiece.fromMap(
                    Map<String, dynamic>.from(piece),
                  ))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'user_id': userId,
      'created_at': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'hafta_id': weekId,
      'gun': day,
      'ana_stil': primaryStyle,
      'ikinci_stil': secondaryStyle,
      'ucuncu_stil': tertiaryStyle,
      'gunluk_plan': dailyPlan,
      'hava_durumu': weather,
      'puan': score,
      'aciklama': description,
      'favori': favorite,
      'olusturma_tipi': creationType,
      'source': source,
      'parcalar': pieces.map((piece) => piece.toMap()).toList(),
    };
  }

  SavedOutfit copyWith({
    String? id,
    String? userId,
    DateTime? createdAt,
    String? weekId,
    String? day,
    String? primaryStyle,
    String? secondaryStyle,
    String? tertiaryStyle,
    String? dailyPlan,
    Map<String, dynamic>? weather,
    double? score,
    String? description,
    bool? favorite,
    String? creationType,
    String? source,
    List<SavedOutfitPiece>? pieces,
  }) {
    return SavedOutfit(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      weekId: weekId ?? this.weekId,
      day: day ?? this.day,
      primaryStyle: primaryStyle ?? this.primaryStyle,
      secondaryStyle: secondaryStyle ?? this.secondaryStyle,
      tertiaryStyle: tertiaryStyle ?? this.tertiaryStyle,
      dailyPlan: dailyPlan ?? this.dailyPlan,
      weather: weather ?? this.weather,
      score: score ?? this.score,
      description: description ?? this.description,
      favorite: favorite ?? this.favorite,
      creationType: creationType ?? this.creationType,
      source: source ?? this.source,
      pieces: pieces ?? this.pieces,
    );
  }
}

String buildWeekId(DateTime date) {
  final monday = date.subtract(Duration(days: date.weekday - 1));
  return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
}

String _buildDescription(OutfitRecommendation recommendation) {
  if (recommendation.description.trim().isNotEmpty) {
    return recommendation.description;
  }

  final itemNames = recommendation.items
      .map((item) => item.subCategory)
      .where((name) => name.trim().isNotEmpty)
      .join(', ');

  return itemNames.isEmpty
      ? 'Haftalık kombin önerisi'
      : 'Önerilen parçalar: $itemNames';
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

String _categoryToFirestoreValue(ClothingCategory category) {
  switch (category) {
    case ClothingCategory.top:
      return 'Üst Giyim';
    case ClothingCategory.bottom:
      return 'Alt Giyim';
    case ClothingCategory.outerwear:
      return 'Dış Giyim';
    case ClothingCategory.shoes:
      return 'Ayakkabı';
    case ClothingCategory.socks:
      return 'Çorap';
    case ClothingCategory.unknown:
      return 'Bilinmeyen';
  }
}

String _styleToFirestoreValue(StylePreference style) {
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

String _planToFirestoreValue(DayPlanType plan) {
  switch (plan) {
    case DayPlanType.normalDay:
      return 'Normal Day';
    case DayPlanType.office:
      return 'Office';
    case DayPlanType.date:
      return 'Date';
    case DayPlanType.gym:
      return 'Gym';
    case DayPlanType.dinner:
      return 'Dinner';
    case DayPlanType.travel:
      return 'Travel';
    case DayPlanType.specialEvent:
      return 'Special Event';
  }
}

String _weatherToFirestoreValue(WeatherCondition condition) {
  switch (condition) {
    case WeatherCondition.clear:
      return 'Clear';
    case WeatherCondition.clouds:
      return 'Clouds';
    case WeatherCondition.rain:
      return 'Rain';
    case WeatherCondition.snow:
      return 'Snow';
    case WeatherCondition.wind:
      return 'Wind';
    case WeatherCondition.unknown:
      return 'Unknown';
  }
}
