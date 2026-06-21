import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/gap_suggestion.dart';
import '../models/purchase_preference_profile.dart';

class PurchasePreferenceService {
  final FirebaseFirestore firestore;

  PurchasePreferenceService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  Future<PurchasePreferenceProfile> fetchProfile(String userId) async {
    final snapshot = await firestore.collection('users').doc(userId).get();
    final data = snapshot.data();
    final rawProfile = data?['purchase_preferences'];

    return PurchasePreferenceProfile.fromJson(
      rawProfile is Map ? Map<String, dynamic>.from(rawProfile) : null,
    );
  }

  Future<void> recordFeedback({
    required String userId,
    required GapSuggestion suggestion,
    required PurchaseFeedbackReaction reaction,
    required PurchaseFeedbackReason reason,
  }) async {
    final item = suggestion.candidateItem;
    final colorKey = _normalize(item.color);
    final categoryKey = _categoryKey(item.category);
    final styleKeys = item.styleTags.map(_normalize).where((tag) => tag.isNotEmpty);
    final itemKey = item.id.trim().isEmpty ? _normalize(item.displayName) : item.id;
    final isLike = reaction == PurchaseFeedbackReaction.like;
    final prefix = isLike ? 'liked' : 'disliked';

    final update = <String, Object>{
      'purchase_preferences.updated_at': FieldValue.serverTimestamp(),
      'purchase_preferences.feedback_count': FieldValue.increment(1),
      'purchase_preferences.${prefix}_items.$itemKey': FieldValue.increment(1),
    };

    if ((reason == PurchaseFeedbackReason.color || isLike) &&
        colorKey.isNotEmpty) {
      update['purchase_preferences.${prefix}_colors.$colorKey'] =
          FieldValue.increment(1);
    }
    if ((reason == PurchaseFeedbackReason.category || isLike) &&
        categoryKey.isNotEmpty) {
      update['purchase_preferences.${prefix}_categories.$categoryKey'] =
          FieldValue.increment(1);
    }
    if (reason == PurchaseFeedbackReason.style || isLike) {
      for (final styleKey in styleKeys) {
        update['purchase_preferences.${prefix}_styles.$styleKey'] =
            FieldValue.increment(1);
      }
    }

    await firestore.collection('users').doc(userId).set(update, SetOptions(merge: true));
  }

  String _categoryKey(String value) {
    final text = _normalize(value);
    if (text == 'upper' || text.contains('ust')) return 'upper';
    if (text == 'lower' || text.contains('alt')) return 'lower';
    if (text == 'outerwear' || text.contains('dis')) return 'outerwear';
    if (text == 'shoes' || text.contains('ayakkabi')) return 'shoes';
    return text;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('.', ' ')
        .replaceAll('/', ' ')
        .trim();
  }
}

enum PurchaseFeedbackReaction { like, dislike }

enum PurchaseFeedbackReason { item, color, style, category }
