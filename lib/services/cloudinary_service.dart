import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryUploadException implements Exception {
  const CloudinaryUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CloudinaryService {
  static const String _cloudName = 'dxhai5ctq';
  static const String _uploadPreset = 'smartstyle_upload';
  static const String _transformation =
      'e_background_removal,c_pad,w_500,h_500';

  static final Uri _uploadUri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
  );

  Future<String> uploadClothingImage(XFile image) async {
    final bytes = await image.readAsBytes();

    if (bytes.isEmpty) {
      throw const CloudinaryUploadException('Seçilen görsel okunamadı.');
    }

    final fileName = image.name.trim().isNotEmpty
        ? image.name.trim()
        : 'smartstyle_clothing_${DateTime.now().millisecondsSinceEpoch}.jpg';

    final request = http.MultipartRequest('POST', _uploadUri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

    try {
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw CloudinaryUploadException(
          _extractCloudinaryError(response.body) ??
              'Cloudinary upload failed with status ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const CloudinaryUploadException(
          'Cloudinary beklenmeyen bir yanıt döndürdü.',
        );
      }

      final secureUrl = decoded['secure_url']?.toString();
      if (secureUrl == null || secureUrl.isEmpty) {
        throw const CloudinaryUploadException(
          'Cloudinary görsel URL bilgisini döndürmedi.',
        );
      }

      return _buildTransformedUrl(secureUrl);
    } on CloudinaryUploadException {
      rethrow;
    } catch (_) {
      throw const CloudinaryUploadException(
        'Görsel Cloudinary sunucusuna yüklenemedi.',
      );
    }
  }

  String _buildTransformedUrl(String secureUrl) {
    const uploadSegment = '/upload/';

    if (!secureUrl.contains(uploadSegment)) {
      throw const CloudinaryUploadException(
        'Cloudinary görsel URL formatı dönüştürülemedi.',
      );
    }

    return secureUrl.replaceFirst(
      uploadSegment,
      '$uploadSegment$_transformation/',
    );
  }

  String? _extractCloudinaryError(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message']?.toString();
          if (message != null && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
