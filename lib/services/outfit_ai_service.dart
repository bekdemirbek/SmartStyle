import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/outfit_ai_models.dart';
import 'local_outfit_fallback.dart';

class OutfitAiException implements Exception {
  final String message;

  const OutfitAiException(this.message);

  @override
  String toString() => message;
}

class OutfitAiService {
  static const String endpoint =
      'https://us-central1-smartstyle-app-63929.cloudfunctions.net/'
      'generateOutfitSuggestions';

  final http.Client _client;

  OutfitAiService({http.Client? client}) : _client = client ?? http.Client();

  Future<OutfitSuggestionResponse> generateSuggestions(
    OutfitSuggestionRequest request, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);

      final decoded = _decodeResponse(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OutfitAiException(
          _extractError(decoded) ??
              'Kombin önerisi alınamadı. Kod: ${response.statusCode}',
        );
      }

      final payload = _extractPayload(decoded);
      final suggestions = OutfitSuggestionResponse.fromJson(payload);

      if (suggestions.days.isEmpty) {
        throw const OutfitAiException('AI kombin cevabı boş geldi.');
      }

      return suggestions;
    } catch (_) {
      // AI servisi (Cloud Function) erişilemediğinde uygulamanın yerel yedek
      // öneri mantığı devreye girer; kullanıcı yine geçerli bir plan görür.
      return buildLocalOutfitResponse(request);
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    if (body.trim().isEmpty) {
      throw const OutfitAiException('Sunucudan boş cevap geldi.');
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Response must be a JSON object.');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _extractPayload(Map<String, dynamic> decoded) {
    if (decoded['success'] == false) {
      throw OutfitAiException(
        _extractError(decoded) ?? 'Kombin önerisi hazırlanamadı.',
      );
    }

    final data = decoded['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    if (decoded.containsKey('plan_type') && decoded.containsKey('days')) {
      return decoded;
    }

    throw const OutfitAiException(
      'Sunucu cevabı beklenen kombin formatında değil.',
    );
  }

  String? _extractError(Map<String, dynamic> decoded) {
    final error = decoded['error'];
    if (error == null) return null;

    final message = error.toString().trim();
    return message.isEmpty ? null : message;
  }
}
