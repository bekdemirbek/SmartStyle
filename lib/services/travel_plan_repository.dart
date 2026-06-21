import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/travel_mode_models.dart';

class TravelPlanRepository {
  static const String collectionName = 'travel_plans';

  final FirebaseFirestore firestore;

  TravelPlanRepository({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _plans {
    return firestore.collection(collectionName);
  }

  CollectionReference<Map<String, dynamic>> _dayPlans(String planId) {
    return _plans.doc(planId).collection('day_plans');
  }

  Future<String> savePlan({
    required String userId,
    required TripDetails trip,
    required PackingResult result,
    PackingFeedback? feedback,
    String? parentPlanId,
    int generationCount = 1,
  }) async {
    final planRef = _plans.doc();
    final batch = firestore.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(planRef, {
      ...trip.toFirestore(),
      ...result.toFirestore(),
      'userId': userId,
      'status': 'active',
      'parentPlanId': parentPlanId,
      'generationCount': generationCount,
      if (feedback != null && !feedback.isEmpty)
        'feedback': feedback.toFirestore(),
      'createdAt': now,
      'updatedAt': now,
    });

    for (final dayPlan in result.dayPlans) {
      final dayPlanRef = planRef.collection('day_plans').doc();
      batch.set(dayPlanRef, {
        ...dayPlan.toFirestore(),
        'createdAt': now,
      });
    }

    await batch.commit();
    return planRef.id;
  }

  Future<List<TravelPlanSummary>> fetchActivePlans({
    required String userId,
    int limit = 20,
  }) async {
    final snapshot = await _plans.where('userId', isEqualTo: userId).get();

    final plans = snapshot.docs.map(TravelPlanSummary.fromFirestore).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    return plans.take(limit).toList();
  }

  Future<TravelPlanDetail?> fetchPlanDetail({
    required String planId,
  }) async {
    final planRef = _plans.doc(planId);
    final futures = await Future.wait([
      planRef.get(),
      planRef.collection('day_plans').orderBy('day').get(),
    ]);
    final planDoc = futures[0] as DocumentSnapshot<Map<String, dynamic>>;
    final dayPlans =
        futures[1] as QuerySnapshot<Map<String, dynamic>>;

    if (!planDoc.exists) return null;

    return TravelPlanDetail.fromFirestore(
      planDoc: planDoc,
      dayPlansSnapshot: dayPlans,
    );
  }

  Future<void> updateDayCheckedItems({
    required String planId,
    required String dayPlanId,
    required List<String> checkedItems,
  }) async {
    await _dayPlans(planId).doc(dayPlanId).update({
      'checkedItems': checkedItems,
    });
  }

  Future<void> archivePlan({
    required String planId,
  }) async {
    await _plans.doc(planId).update({
      'status': 'archived',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
