import 'package:cloud_firestore/cloud_firestore.dart';

class WardrobeItem {
  final String id;
  final String collection;
  final String userId;
  final String imageUrl;
  final String category;
  final String type;
  final String color;
  final String fabricType;
  final bool favorite;
  final bool? buttoned;
  final bool? zippered;
  final DateTime? createdAt;
  final int useCount;
  final DateTime? lastUsed;
  final List<String> styleTags;
  final List<String> season;
  final bool isVirtual;
  final Map<String, dynamic> rawData;

  const WardrobeItem({
    required this.id,
    required this.collection,
    required this.userId,
    required this.imageUrl,
    required this.category,
    required this.type,
    required this.color,
    required this.fabricType,
    required this.favorite,
    this.buttoned,
    this.zippered,
    this.createdAt,
    this.useCount = 0,
    this.lastUsed,
    this.styleTags = const [],
    this.season = const [],
    this.isVirtual = false,
    this.rawData = const {},
  });

  factory WardrobeItem.fromFirestore({
    required DocumentSnapshot<Map<String, dynamic>> doc,
    required String collection,
  }) {
    final data = doc.data() ?? {};

    return WardrobeItem(
      id: doc.id,
      collection: collection,
      userId: (data['user_id'] ?? data['userId'] ?? '').toString(),
      imageUrl: (data['image_url'] ?? data['imageUrl'] ?? '').toString(),
      category: (data['kategori'] ?? data['category'] ?? '').toString(),
      type: (data['tur'] ?? data['type'] ?? 'Kıyafet').toString(),
      color: (data['renk'] ?? data['color'] ?? 'Belirtilmedi').toString(),
      fabricType: (data['kumas_turu'] ?? data['fabricType'] ?? 'Belirtilmedi')
          .toString(),
      favorite: data['favori'] == true || data['favorite'] == true,
      buttoned: _parseNullableBool(data['dugmeli_mi']),
      zippered: _parseNullableBool(data['fermuarli_mi']),
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
      useCount: _parseInt(data['use_count'] ?? data['useCount']),
      lastUsed: _parseDate(data['last_used'] ?? data['lastUsed']),
      styleTags: _parseStringList(data['style_tags'] ?? data['styleTags']),
      season: _parseStringList(data['season'] ?? data['mevsim']),
      isVirtual: data['is_virtual'] == true || data['isVirtual'] == true,
      rawData: data,
    );
  }

  WardrobeItem copyWith({
    bool? favorite,
    List<String>? styleTags,
    List<String>? season,
    bool? isVirtual,
  }) {
    return WardrobeItem(
      id: id,
      collection: collection,
      userId: userId,
      imageUrl: imageUrl,
      category: category,
      type: type,
      color: color,
      fabricType: fabricType,
      favorite: favorite ?? this.favorite,
      buttoned: buttoned,
      zippered: zippered,
      createdAt: createdAt,
      useCount: useCount,
      lastUsed: lastUsed,
      styleTags: styleTags ?? this.styleTags,
      season: season ?? this.season,
      isVirtual: isVirtual ?? this.isVirtual,
      rawData: rawData,
    );
  }

  String get displayName => type.trim().isEmpty ? category : type;

  static bool? _parseNullableBool(Object? value) {
    if (value is bool) return value;
    if (value == null) return null;

    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == 'belirtilmedi') return null;
    if (text == 'true' || text == 'evet' || text == 'yes') return true;
    if (text == 'false' || text == 'hayir' || text == 'hayır' || text == 'no') {
      return false;
    }
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static List<String> _parseStringList(Object? value) {
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
}
