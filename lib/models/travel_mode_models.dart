import 'package:cloud_firestore/cloud_firestore.dart';

import 'outfit_recommendation_models.dart';

class TripDetails {
  final String destination;
  final int tripDays;
  final List<String> occasions;
  final int weatherTemp;
  final String luggageType;
  final DateTime departureDate;

  const TripDetails({
    required this.destination,
    required this.tripDays,
    required this.occasions,
    required this.weatherTemp,
    required this.luggageType,
    required this.departureDate,
  });

  int get maxPieces => luggageType == 'checked' ? 12 : 7;

  Map<String, dynamic> toFirestore() {
    return {
      'destination': destination,
      'tripDays': tripDays,
      'occasions': occasions,
      'weatherTemp': weatherTemp,
      'luggageType': luggageType,
      'departureDate': Timestamp.fromDate(departureDate),
    };
  }
}

class PackingFeedback {
  final List<String> complaints;
  final List<String> pinnedItemIds;
  final List<String> excludedItemIds;
  final DateTime? givenAt;

  const PackingFeedback({
    this.complaints = const [],
    this.pinnedItemIds = const [],
    this.excludedItemIds = const [],
    this.givenAt,
  });

  bool get isEmpty =>
      complaints.isEmpty && pinnedItemIds.isEmpty && excludedItemIds.isEmpty;

  Map<String, dynamic> toFirestore() {
    return {
      'complaints': complaints,
      'pinnedItemIds': pinnedItemIds,
      'excludedItemIds': excludedItemIds,
      'givenAt': Timestamp.fromDate(givenAt ?? DateTime.now()),
    };
  }
}

class PackingResult {
  final List<ClothingItem> selectedItems;
  final List<List<ClothingItem>> outfits;
  final int pieceCount;
  final int outfitCount;
  final double coverageScore;
  final List<String> missingPieces;
  final List<TravelReuseHighlight> reuseHighlights;
  final List<TravelDayPlan> dayPlans;

  const PackingResult({
    required this.selectedItems,
    required this.outfits,
    required this.pieceCount,
    required this.outfitCount,
    required this.coverageScore,
    required this.missingPieces,
    required this.reuseHighlights,
    required this.dayPlans,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'pieceCount': pieceCount,
      'outfitCount': outfitCount,
      'coverageScore': coverageScore,
      'missingPieces': missingPieces,
      'selectedItemIds': selectedItems.map((item) => item.id).toList(),
      'reuseHighlights': reuseHighlights.map((highlight) {
        return {
          'itemId': highlight.itemId,
          'usedOnDays': highlight.usedOnDays,
          'reason': highlight.reason,
        };
      }).toList(),
    };
  }
}

class TravelDayPlan {
  final int day;
  final String occasion;
  final List<ClothingItem> outfitItems;
  final String note;

  const TravelDayPlan({
    required this.day,
    required this.occasion,
    required this.outfitItems,
    this.note = '',
  });

  List<String> get outfitItemIds => outfitItems.map((item) => item.id).toList();

  Map<String, dynamic> toFirestore() {
    return {
      'day': day,
      'occasion': occasion,
      'note': note,
      'outfitItemIds': outfitItemIds,
      'checkedItems': <String>[],
    };
  }
}

class TravelReuseHighlight {
  final ClothingItem item;
  final List<int> usedOnDays;
  final String reason;

  const TravelReuseHighlight({
    required this.item,
    required this.usedOnDays,
    required this.reason,
  });

  String get itemId => item.id;
}

class TravelPlanSummary {
  final String planId;
  final String userId;
  final String destination;
  final int tripDays;
  final int pieceCount;
  final int outfitCount;
  final double coverageScore;
  final String status;
  final String? parentPlanId;
  final int generationCount;
  final DateTime? createdAt;

  const TravelPlanSummary({
    required this.planId,
    required this.userId,
    required this.destination,
    required this.tripDays,
    required this.pieceCount,
    required this.outfitCount,
    required this.coverageScore,
    required this.status,
    required this.parentPlanId,
    required this.generationCount,
    required this.createdAt,
  });

  factory TravelPlanSummary.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return TravelPlanSummary(
      planId: doc.id,
      userId: (data['userId'] ?? '').toString(),
      destination: (data['destination'] ?? '').toString(),
      tripDays: (data['tripDays'] as num?)?.toInt() ?? 0,
      pieceCount: (data['pieceCount'] as num?)?.toInt() ?? 0,
      outfitCount: (data['outfitCount'] as num?)?.toInt() ?? 0,
      coverageScore: (data['coverageScore'] as num?)?.toDouble() ?? 0,
      status: (data['status'] ?? '').toString(),
      parentPlanId: _nullableText(data['parentPlanId']),
      generationCount: (data['generationCount'] as num?)?.toInt() ?? 1,
      createdAt: _timestampToDate(data['createdAt']),
    );
  }
}

class TravelPlanDetail {
  final TravelPlanSummary summary;
  final List<String> selectedItemIds;
  final List<Map<String, dynamic>> reuseHighlights;
  final List<SavedDayPlan> dayPlans;

  const TravelPlanDetail({
    required this.summary,
    required this.selectedItemIds,
    required this.reuseHighlights,
    required this.dayPlans,
  });

  factory TravelPlanDetail.fromFirestore({
    required DocumentSnapshot<Map<String, dynamic>> planDoc,
    required QuerySnapshot<Map<String, dynamic>> dayPlansSnapshot,
  }) {
    final data = planDoc.data() ?? const <String, dynamic>{};
    final dayPlans = dayPlansSnapshot.docs
        .map(SavedDayPlan.fromFirestore)
        .toList()
      ..sort((a, b) => a.day.compareTo(b.day));

    return TravelPlanDetail(
      summary: TravelPlanSummary.fromFirestore(planDoc),
      selectedItemIds: _stringList(data['selectedItemIds']),
      reuseHighlights: _mapList(data['reuseHighlights']),
      dayPlans: dayPlans,
    );
  }
}

class SavedDayPlan {
  final String dayPlanId;
  final int day;
  final String occasion;
  final String note;
  final List<String> outfitItemIds;
  final List<String> checkedItems;

  const SavedDayPlan({
    required this.dayPlanId,
    required this.day,
    required this.occasion,
    required this.note,
    required this.outfitItemIds,
    required this.checkedItems,
  });

  factory SavedDayPlan.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return SavedDayPlan(
      dayPlanId: doc.id,
      day: (data['day'] as num?)?.toInt() ?? 0,
      occasion: (data['occasion'] ?? '').toString(),
      note: (data['note'] ?? '').toString(),
      outfitItemIds: _stringList(data['outfitItemIds']),
      checkedItems: _stringList(data['checkedItems']),
    );
  }
}

DateTime? _timestampToDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

List<String> _stringList(Object? value) {
  if (value is Iterable) {
    return value.map((entry) => entry.toString()).toList();
  }
  return const [];
}

String? _nullableText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is Iterable) {
    return value
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }
  return const [];
}
