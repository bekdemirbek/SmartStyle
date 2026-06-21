import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/wardrobe_item_model.dart';

class WardrobeItemService {
  final FirebaseFirestore firestore;

  WardrobeItemService({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  Future<WardrobeItem?> fetchItem({
    required String collection,
    required String documentId,
  }) async {
    if (collection.trim().isEmpty || documentId.trim().isEmpty) {
      return null;
    }

    final doc = await firestore.collection(collection).doc(documentId).get();
    if (!doc.exists) return null;

    return WardrobeItem.fromFirestore(
      doc: doc,
      collection: collection,
    );
  }

  Future<List<WardrobeItem>> fetchItemsByRefs(
    Iterable<({String collection, String documentId})> refs,
  ) async {
    final items = <WardrobeItem>[];

    for (final ref in refs) {
      final item = await fetchItem(
        collection: ref.collection,
        documentId: ref.documentId,
      );
      if (item != null) items.add(item);
    }

    return items;
  }

  Future<void> toggleFavorite({
    required String collection,
    required String documentId,
    required bool isFavorite,
  }) async {
    await firestore.collection(collection).doc(documentId).update({
      'favori': isFavorite,
    });
  }

  Future<void> markItemsUsed(
    Iterable<({String collection, String documentId})> refs,
  ) async {
    final batch = firestore.batch();

    for (final ref in refs) {
      if (ref.collection.trim().isEmpty || ref.documentId.trim().isEmpty) {
        continue;
      }

      batch.set(
        firestore.collection(ref.collection).doc(ref.documentId),
        {
          'use_count': FieldValue.increment(1),
          'last_used': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }
}
