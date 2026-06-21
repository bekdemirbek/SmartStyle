import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/wardrobe_analysis_model.dart';

class GeminiInsightException implements Exception {
  final String message;

  const GeminiInsightException(this.message);

  @override
  String toString() => message;
}

class GeminiInsightService {
  static const String endpoint =
      'https://us-central1-smartstyle-app-63929.cloudfunctions.net/'
      'generateWardrobeInsight';
  static const Duration cacheTtl = Duration(minutes: 30);

  final http.Client _client;

  String? _cachedInsight;
  DateTime? _cacheTime;
  int? _lastItemCount;

  GeminiInsightService({http.Client? client}) : _client = client ?? http.Client();

  bool _isCacheValid(int currentItemCount) {
    final cachedInsight = _cachedInsight;
    final cacheTime = _cacheTime;
    final lastItemCount = _lastItemCount;

    if (cachedInsight == null || cachedInsight.trim().isEmpty) return false;
    if (cacheTime == null || lastItemCount == null) return false;
    if (DateTime.now().difference(cacheTime) > cacheTtl) return false;
    if ((currentItemCount - lastItemCount).abs() >= 3) return false;

    return true;
  }

  Future<String> getInsight(
    WardrobeAnalysis analysis, {
    Duration timeout = const Duration(seconds: 35),
  }) async {
    if (_isCacheValid(analysis.totalItems)) {
      return _cachedInsight!;
    }

    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(_analysisToJson(analysis)),
          )
          .timeout(timeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      final payload = Map<String, dynamic>.from(decoded);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GeminiInsightException(
          payload['error']?.toString() ?? 'Gemini önerisi alınamadı.',
        );
      }

      final data = payload['data'];
      if (data is! Map || data['insight'] is! String) {
        throw const GeminiInsightException(
          'Gemini cevabı beklenen formatta değil.',
        );
      }

      final insight = (data['insight'] as String).trim();
      if (insight.isEmpty) {
        throw const GeminiInsightException('Gemini boş öneri döndürdü.');
      }

      _cachedInsight = insight;
      _cacheTime = DateTime.now();
      _lastItemCount = analysis.totalItems;

      return insight;
    } on TimeoutException {
      throw const GeminiInsightException('Gemini önerisi zaman aşımına uğradı.');
    } on GeminiInsightException {
      rethrow;
    } catch (_) {
      throw const GeminiInsightException('Gemini önerisi hazırlanamadı.');
    }
  }

  Map<String, dynamic> _analysisToJson(WardrobeAnalysis analysis) {
    return {
      'totalItems': analysis.totalItems,
      'categoryDistribution': analysis.counts,
      'dominantColors': analysis.dominantColors,
      'seasonCounts': analysis.seasonCounts,
      'categoryBalance': analysis.categoryBalance,
      'colorHarmony': analysis.colorHarmony,
      'seasonBalance': analysis.seasonBalance,
      'versatility': analysis.versatility,
      'overallScore': analysis.score,
      'topCount': analysis.topCount,
      'bottomCount': analysis.bottomCount,
      'shoeCount': analysis.shoeCount,
    };
  }
}
