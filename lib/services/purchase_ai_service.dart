import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/gap_suggestion.dart';
import '../models/wardrobe_item_model.dart';

class PurchaseAiException implements Exception {
  final String message;

  const PurchaseAiException(this.message);

  @override
  String toString() => message;
}

class PurchaseAiService {
  static const String endpoint =
      'https://us-central1-smartstyle-app-63929.cloudfunctions.net/'
      'generatePurchaseSuggestions';

  final http.Client _client;

  PurchaseAiService({http.Client? client}) : _client = client ?? http.Client();

  Future<List<GapSuggestion>> generateSuggestions({
    required List<WardrobeItem> wardrobe,
    required int currentCombos,
    required String contextText,
    required String userGender,
    required String? selectedOccasion,
    required String? selectedCategory,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'contextText': contextText,
              'userProfile': {
                'gender': userGender,
              },
              'selectedOccasion': selectedOccasion,
              'selectedCategory': selectedCategory,
              'currentCombinations': currentCombos,
              'wardrobe': wardrobe.map(_wardrobeToJson).toList(),
            }),
          )
          .timeout(timeout);

      final decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PurchaseAiException(
          decoded['error']?.toString() ??
              'Gemini alışveriş önerisi alınamadı.',
        );
      }

      final data = decoded['data'];
      if (data is! Map || data['recommendations'] is! List) {
        throw const PurchaseAiException('Gemini cevabı beklenen formatta değil.');
      }

      return (data['recommendations'] as List)
          .whereType<Map>()
          .map((item) => _suggestionFromJson(
                Map<String, dynamic>.from(item),
                currentCombos,
              ))
          .toList();
    } on TimeoutException {
      throw const PurchaseAiException('Gemini önerisi zaman aşımına uğradı.');
    } on FormatException {
      throw const PurchaseAiException('Gemini önerisi okunamadı.');
    } on PurchaseAiException {
      rethrow;
    } catch (_) {
      throw const PurchaseAiException('Gemini önerisi hazırlanamadı.');
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.trim().isEmpty) {
      throw const PurchaseAiException('Sunucudan boş cevap geldi.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException();
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _wardrobeToJson(WardrobeItem item) {
    return {
      'id': item.id,
      'category': item.category,
      'type': item.type,
      'color': item.color,
      'fabricType': item.fabricType,
      'styleTags': item.styleTags,
      'season': item.season,
      'favorite': item.favorite,
    };
  }

  GapSuggestion _suggestionFromJson(
    Map<String, dynamic> json,
    int currentCombos,
  ) {
    final unlocks = _intValue(json['unlocks_combinations']);
    final itemName = (json['item_name'] ?? 'Özel parça önerisi').toString();
    final color = (json['color'] ?? 'Belirtilmedi').toString();
    final category = (json['category'] ?? '').toString();

    final candidate = WardrobeItem(
      id: 'gemini_${itemName.hashCode}_${color.hashCode}',
      collection: 'gemini_purchase_candidate',
      userId: '',
      imageUrl: '',
      category: category,
      type: itemName,
      color: color,
      fabricType: 'Belirtilmedi',
      favorite: false,
      styleTags: _stringList(json['style_tags']),
      season: const ['all'],
      isVirtual: true,
      rawData: json,
    );

    return GapSuggestion(
      candidateItem: candidate,
      currentCombos: currentCombos,
      projectedCombos: currentCombos + unlocks,
      gain: unlocks,
      tasteScore: unlocks.toDouble(),
      style: _stringList(json['style_tags']).join(', '),
      occasion: _stringList(json['occasion_tags']),
      formality: (json['formality'] ?? 'smart casual').toString(),
      confidence: _doubleValue(json['confidence_score']).clamp(0, 1),
      compatibleItems: const [],
      reason: (json['why_this'] ?? '').toString(),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _doubleValue(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(RegExp(r'[,;/|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }
}
