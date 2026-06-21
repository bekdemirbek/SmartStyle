import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ClothingColorAnalysisResult {
  final String color;
  final double confidence;
  final String note;

  const ClothingColorAnalysisResult({
    required this.color,
    required this.confidence,
    required this.note,
  });

  factory ClothingColorAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ClothingColorAnalysisResult(
      color: (json['color'] ?? 'Çok Renkli').toString(),
      confidence: json['confidence'] is num
          ? (json['confidence'] as num).toDouble()
          : 0.5,
      note: (json['note'] ?? '').toString(),
    );
  }
}

class ClothingColorAnalysisException implements Exception {
  final String message;

  const ClothingColorAnalysisException(this.message);

  @override
  String toString() => message;
}

class ClothingColorAnalysisService {
  static const String endpoint =
      'https://us-central1-smartstyle-app-63929.cloudfunctions.net/'
      'analyzeClothingColor';

  final http.Client _client;

  ClothingColorAnalysisService({http.Client? client})
      : _client = client ?? http.Client();

  Future<ClothingColorAnalysisResult> analyzeColor({
    required Uint8List imageBytes,
    required String mimeType,
    String? category,
    String? type,
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
            body: jsonEncode({
              'imageBase64': base64Encode(imageBytes),
              'mimeType': mimeType,
              'category': category,
              'type': type,
            }),
          )
          .timeout(timeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Response must be a JSON object.');
      }

      final payload = Map<String, dynamic>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'COLOR ANALYSIS ERROR ${response.statusCode}: ${response.body}',
        );
        throw ClothingColorAnalysisException(
          _extractError(payload) ?? 'Renk analizi yapılamadı.',
        );
      }

      final data = payload['data'];
      if (data is! Map) {
        throw const ClothingColorAnalysisException(
          'Renk analizi cevabı beklenen formatta değil.',
        );
      }

      return ClothingColorAnalysisResult.fromJson(
        Map<String, dynamic>.from(data),
      );
    } on TimeoutException {
      throw const ClothingColorAnalysisException(
        'Renk analizi zaman aşımına uğradı. Rengi manuel seçebilirsin.',
      );
    } on ClothingColorAnalysisException {
      rethrow;
    } catch (e) {
      debugPrint('COLOR ANALYSIS UNEXPECTED ERROR: $e');
      throw const ClothingColorAnalysisException(
        'Renk analizi yapılamadı. Rengi manuel seçebilirsin.',
      );
    }
  }

  String? _extractError(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error == null) return null;

    final message = error.toString().trim();
    return message.isEmpty ? null : message;
  }
}
