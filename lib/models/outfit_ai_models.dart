class OutfitSuggestionRequest {
  final String planType;
  final String userGender;
  final List<String> stylePriority;
  final List<RequestedDay> days;
  final List<AiWardrobeItem> wardrobe;
  final Map<String, WeatherInfo> weather;
  final String refreshType;
  final String? replaceItem;
  final String? replaceIntent;
  final Map<String, dynamic>? currentOutfit;

  const OutfitSuggestionRequest({
    required this.planType,
    this.userGender = 'unspecified',
    required this.stylePriority,
    required this.days,
    required this.wardrobe,
    required this.weather,
    this.refreshType = 'none',
    this.replaceItem,
    this.replaceIntent,
    this.currentOutfit,
  });

  Map<String, dynamic> toJson() {
    return {
      'planType': planType,
      'userProfile': {
        'gender': userGender,
      },
      'stylePriority': stylePriority,
      'days': days.map((day) => day.toJson()).toList(),
      'wardrobe': wardrobe.map((item) => item.toJson()).toList(),
      'weather': weather.map((day, info) => MapEntry(day, info.toJson())),
      'refreshType': refreshType,
      'replaceItem': replaceItem,
      'replaceIntent': replaceIntent,
      'currentOutfit': currentOutfit,
    };
  }
}

class RequestedDay {
  final String day;
  final String event;
  final bool requested;

  const RequestedDay({
    required this.day,
    required this.event,
    this.requested = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'event': event,
      'requested': requested,
    };
  }
}

class AiWardrobeItem {
  final String id;
  final String category;
  final String name;
  final String color;
  final List<String> season;
  final List<String> style;
  final String fabric;

  const AiWardrobeItem({
    required this.id,
    required this.category,
    required this.name,
    required this.color,
    required this.season,
    required this.style,
    required this.fabric,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'name': name,
      'color': color,
      'season': season,
      'style': style,
      'fabric': fabric,
    };
  }
}

class WeatherInfo {
  final double temp;
  final String condition;

  const WeatherInfo({
    required this.temp,
    required this.condition,
  });

  Map<String, dynamic> toJson() {
    return {
      'temp': temp,
      'condition': condition,
    };
  }
}

class OutfitSuggestionResponse {
  final String planType;
  final List<StyledDay> days;

  const OutfitSuggestionResponse({
    required this.planType,
    required this.days,
  });

  factory OutfitSuggestionResponse.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];

    return OutfitSuggestionResponse(
      planType: (json['plan_type'] ?? '').toString(),
      days: rawDays is Iterable
          ? rawDays
              .whereType<Map>()
              .map((day) => StyledDay.fromJson(Map<String, dynamic>.from(day)))
              .toList()
          : const [],
    );
  }
}

class StyledDay {
  final String day;
  final String status;
  final String? message;
  final String? title;
  final String? styleType;
  final OutfitData outfit;
  final String? styleNote;
  final String? whyThisWorks;
  final String? vibe;
  final bool canFavorite;

  const StyledDay({
    required this.day,
    required this.status,
    required this.outfit,
    this.message,
    this.title,
    this.styleType,
    this.styleNote,
    this.whyThisWorks,
    this.vibe,
    this.canFavorite = true,
  });

  bool get isStyled => status.toLowerCase() == 'styled';

  factory StyledDay.fromJson(Map<String, dynamic> json) {
    return StyledDay(
      day: (json['day'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      message: _nullableString(json['message']),
      title: _nullableString(json['title']),
      styleType: _nullableString(json['style_type']),
      outfit: OutfitData.fromJson(
        Map<String, dynamic>.from(json['outfit'] as Map? ?? {}),
      ),
      styleNote: _nullableString(json['style_note']),
      whyThisWorks: _nullableString(json['why_this_works']),
      vibe: _nullableString(json['vibe']),
      canFavorite: json['can_favorite'] != false,
    );
  }
}

class OutfitData {
  final OutfitPiece? top;
  final OutfitPiece? outerwear;
  final OutfitPiece? bottom;
  final OutfitPiece? shoes;
  final OutfitPiece? bag;
  final OutfitPiece? accessory;

  const OutfitData({
    this.top,
    this.outerwear,
    this.bottom,
    this.shoes,
    this.bag,
    this.accessory,
  });

  factory OutfitData.fromJson(Map<String, dynamic> json) {
    return OutfitData(
      top: OutfitPiece.fromNullableJson(json['top']),
      outerwear: OutfitPiece.fromNullableJson(json['outerwear']),
      bottom: OutfitPiece.fromNullableJson(json['bottom']),
      shoes: OutfitPiece.fromNullableJson(json['shoes']),
      bag: OutfitPiece.fromNullableJson(json['bag']),
      accessory: OutfitPiece.fromNullableJson(json['accessory']),
    );
  }
}

class OutfitPiece {
  final String id;
  final String name;

  const OutfitPiece({
    required this.id,
    required this.name,
  });

  factory OutfitPiece.fromJson(Map<String, dynamic> json) {
    return OutfitPiece(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
    );
  }

  static OutfitPiece? fromNullableJson(Object? value) {
    if (value == null) return null;
    if (value is! Map) return null;

    final piece = OutfitPiece.fromJson(Map<String, dynamic>.from(value));
    return piece.id.isEmpty ? null : piece;
  }
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}
