import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/outfit_recommendation_models.dart';
import '../models/saved_outfit_model.dart';

class SavedOutfitService {
  static const String collectionName = 'kombinler';

  final FirebaseFirestore firestore;

  SavedOutfitService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _collection {
    return firestore.collection(collectionName);
  }

  CollectionReference<Map<String, dynamic>> _favoritesCollection(
    String userId,
  ) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('favorite_outfits');
  }

  Future<String> saveOutfit(SavedOutfit outfit) async {
    final docRef = await _collection.add(outfit.toFirestore());
    await _markPiecesUsed(outfit.pieces);
    return docRef.id;
  }

  Future<String> saveRecommendation({
    required String userId,
    required WeeklyStylePreference stylePreference,
    required OutfitRecommendation recommendation,
    String? weekId,
    String creationType = 'weekly_recommendation',
    bool favorite = false,
  }) async {
    final savedOutfit = SavedOutfit.fromRecommendation(
      userId: userId,
      weekId: weekId ?? buildWeekId(recommendation.date),
      recommendation: recommendation,
      stylePreference: stylePreference,
      creationType: creationType,
    ).copyWith(
      favorite: favorite,
    );

    return saveOutfit(savedOutfit);
  }

  Future<String> saveFavoriteRecommendation({
    required String userId,
    required WeeklyStylePreference stylePreference,
    required OutfitRecommendation recommendation,
    String? weekId,
  }) async {
    final favoriteId = favoriteIdForRecommendation(recommendation);
    final savedOutfit = SavedOutfit.fromRecommendation(
      userId: userId,
      weekId: weekId ?? buildWeekId(recommendation.date),
      recommendation: recommendation,
      stylePreference: stylePreference,
      creationType: 'ai_recommendation',
    ).copyWith(
      id: favoriteId,
      favorite: true,
      source: 'ai_recommendation',
    );

    await _favoritesCollection(userId).doc(favoriteId).set({
      ...savedOutfit.toFirestore(),
      'favorite_id': favoriteId,
      'userId': userId,
      'day': savedOutfit.day,
      'title': savedOutfit.description.isEmpty
          ? '${savedOutfit.day} Kombini'
          : savedOutfit.description,
      'styleType': savedOutfit.primaryStyle,
      'outfit': {
        for (final piece in savedOutfit.pieces)
          piece.category: piece.toMap(),
      },
      'styleNote': savedOutfit.description,
      'whyThisWorks': recommendation.notes.join(' '),
      'vibe': savedOutfit.primaryStyle,
      'weather': savedOutfit.weather,
      'source': 'ai_recommendation',
      'recommendationDate': Timestamp.fromDate(recommendation.date),
    });
    await _markPiecesUsed(savedOutfit.pieces);

    return favoriteId;
  }

  Future<String> saveFavoriteOutfit({
    required String userId,
    required SavedOutfit outfit,
    String? favoriteId,
  }) async {
    final resolvedFavoriteId =
        favoriteId ?? (outfit.id.isNotEmpty ? outfit.id : _favoriteIdForOutfit(outfit));
    final savedOutfit = outfit.copyWith(
      id: resolvedFavoriteId,
      favorite: true,
      source: outfit.source.isEmpty ? 'saved_outfit' : outfit.source,
    );

    await _favoritesCollection(userId).doc(resolvedFavoriteId).set({
      ...savedOutfit.toFirestore(),
      'favorite_id': resolvedFavoriteId,
      'user_id': userId,
      'source': savedOutfit.source,
    });
    await _markPiecesUsed(savedOutfit.pieces);

    return resolvedFavoriteId;
  }

  String favoriteIdForRecommendation(OutfitRecommendation recommendation) {
    final itemIds = recommendation.items
        .map((item) => item.id)
        .where((id) => id.trim().isNotEmpty)
        .join('_');
    final dayKey = recommendation.day
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final base = '${buildWeekId(recommendation.date)}_${dayKey}_$itemIds';
    return base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }

  Future<SavedOutfit?> fetchFavoriteOutfitById({
    required String userId,
    required String favoriteId,
  }) async {
    final doc = await _favoritesCollection(userId).doc(favoriteId).get();
    if (!doc.exists) return null;
    return SavedOutfit.fromFirestore(doc);
  }

  Stream<List<SavedOutfit>> watchFavoriteOutfits({
    required String userId,
    int limit = 50,
  }) {
    return _favoritesCollection(userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(SavedOutfit.fromFirestore).toList());
  }

  Future<List<SavedOutfit>> fetchFavoriteOutfits({
    required String userId,
    int limit = 50,
  }) async {
    final snapshot = await _favoritesCollection(userId)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map(SavedOutfit.fromFirestore).toList();
  }

  Future<void> deleteFavoriteOutfit({
    required String userId,
    required String favoriteId,
  }) async {
    await _favoritesCollection(userId).doc(favoriteId).delete();
  }

  Future<List<String>> saveWeeklyOutfits({
    required String userId,
    required WeeklyStylePreference stylePreference,
    required List<OutfitRecommendation> recommendations,
    String? weekId,
    String creationType = 'weekly_recommendation',
  }) async {
    if (recommendations.isEmpty) return const [];

    final resolvedWeekId = weekId ?? buildWeekId(recommendations.first.date);
    final batch = firestore.batch();
    final ids = <String>[];

    for (final recommendation in recommendations) {
      final docRef = _collection.doc();
      final savedOutfit = SavedOutfit.fromRecommendation(
        userId: userId,
        weekId: resolvedWeekId,
        recommendation: recommendation,
        stylePreference: stylePreference,
        creationType: creationType,
      );

      batch.set(docRef, savedOutfit.toFirestore());
      for (final piece in savedOutfit.pieces.where(_isTrackablePiece)) {
        if (piece.collection.trim().isEmpty || piece.itemId.trim().isEmpty) {
          continue;
        }
        batch.set(
          firestore.collection(piece.collection).doc(piece.itemId),
          {
            'use_count': FieldValue.increment(1),
            'last_used': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      ids.add(docRef.id);
    }

    await batch.commit();
    return ids;
  }

  Future<SavedOutfit?> fetchOutfitById(String outfitId) async {
    final doc = await _collection.doc(outfitId).get();
    if (!doc.exists) return null;
    return SavedOutfit.fromFirestore(doc);
  }

  Future<List<SavedOutfit>> fetchUserOutfits({
    required String userId,
    String? weekId,
    bool favoritesOnly = false,
    int limit = 50,
  }) async {
    Query<Map<String, dynamic>> query =
        _collection.where('user_id', isEqualTo: userId);

    if (weekId != null && weekId.isNotEmpty) {
      query = query.where('hafta_id', isEqualTo: weekId);
    }

    if (favoritesOnly) {
      query = query.where('favori', isEqualTo: true);
    }

    if (!favoritesOnly) {
      query = query.orderBy('created_at', descending: true);
    }

    final snapshot = await query.limit(limit).get();
    final outfits = snapshot.docs.map(SavedOutfit.fromFirestore).toList();

    if (favoritesOnly) {
      outfits.sort(_compareCreatedAtDesc);
    }

    return outfits;
  }

  Stream<List<SavedOutfit>> watchUserOutfits({
    required String userId,
    String? weekId,
    bool favoritesOnly = false,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query =
        _collection.where('user_id', isEqualTo: userId);

    if (weekId != null && weekId.isNotEmpty) {
      query = query.where('hafta_id', isEqualTo: weekId);
    }

    if (favoritesOnly) {
      query = query.where('favori', isEqualTo: true);
    }

    if (!favoritesOnly) {
      query = query.orderBy('created_at', descending: true);
    }

    return query.limit(limit).snapshots().map((snapshot) {
      final outfits = snapshot.docs.map(SavedOutfit.fromFirestore).toList();
      if (favoritesOnly) {
        outfits.sort(_compareCreatedAtDesc);
      }
      return outfits;
    });
  }

  Future<void> toggleFavorite({
    required String outfitId,
    required bool isFavorite,
  }) async {
    await _collection.doc(outfitId).update({
      'favori': isFavorite,
    });
  }

  int _compareCreatedAtDesc(SavedOutfit a, SavedOutfit b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  Future<void> _markPiecesUsed(List<SavedOutfitPiece> pieces) async {
    if (pieces.isEmpty) return;

    final batch = firestore.batch();
    var hasWrites = false;
    for (final piece in pieces.where(_isTrackablePiece)) {
      if (piece.collection.trim().isEmpty || piece.itemId.trim().isEmpty) {
        continue;
      }
      batch.set(
        firestore.collection(piece.collection).doc(piece.itemId),
        {
          'use_count': FieldValue.increment(1),
          'last_used': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      hasWrites = true;
    }

    if (hasWrites) await batch.commit();
  }

  bool _isTrackablePiece(SavedOutfitPiece piece) {
    final text = '${piece.category} ${piece.collection}'.toLowerCase();
    return !text.contains('corap') &&
        !text.contains('çorap') &&
        !text.contains('sock');
  }

  String _favoriteIdForOutfit(SavedOutfit outfit) {
    final itemIds = outfit.pieces
        .map((piece) => piece.itemId)
        .where((id) => id.trim().isNotEmpty)
        .join('_');
    final normalizedDay = outfit.day
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final base = '${outfit.weekId}_${normalizedDay}_$itemIds';
    return base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
  }
}
