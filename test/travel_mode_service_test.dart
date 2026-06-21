import 'package:deneme_1/models/outfit_recommendation_models.dart';
import 'package:deneme_1/models/travel_mode_models.dart';
import 'package:deneme_1/services/travel_mode_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TravelModeService service;

  setUp(() {
    service = TravelModeService();
  });

  test('dinner trip without formal items reports formal missing pieces', () {
    final result = service.createPackingPlan(
      wardrobe: [
        item('casual_top', ClothingCategory.top, 'Tisort'),
        item('jeans', ClothingCategory.bottom, 'Jean'),
        item('sneaker', ClothingCategory.shoes, 'Sneaker'),
      ],
      trip: trip(occasions: ['dinner']),
    );

    expect(result.missingPieces, contains('formal ust'));
    expect(result.missingPieces, contains('formal alt'));
    expect(result.missingPieces, contains('formal ayakkabi'));
  });

  test('carry-on limit prefers versatile connector pieces', () {
    final result = service.createPackingPlan(
      wardrobe: [
        item('black_tee', ClothingCategory.top, 'Tisort', color: 'Siyah'),
        item('white_shirt', ClothingCategory.top, 'Gomlek', color: 'Beyaz'),
        item('red_party_top', ClothingCategory.top, 'Crop', color: 'Kirmizi'),
        item('navy_trouser', ClothingCategory.bottom, 'Pantolon', color: 'Lacivert'),
        item('black_jeans', ClothingCategory.bottom, 'Jean', color: 'Siyah'),
        item('yellow_shorts', ClothingCategory.bottom, 'Sort', color: 'Sari'),
        item('white_sneaker', ClothingCategory.shoes, 'Sneaker', color: 'Beyaz'),
        item('black_loafer', ClothingCategory.shoes, 'Loafer', color: 'Siyah'),
        item('green_boot', ClothingCategory.shoes, 'Bot', color: 'Yesil'),
      ],
      trip: trip(tripDays: 4, occasions: ['travel', 'work', 'casual']),
    );

    expect(result.selectedItems, hasLength(lessThanOrEqualTo(7)));
    expect(result.selectedItems.map((item) => item.id), contains('black_tee'));
    expect(result.selectedItems.map((item) => item.id), contains('navy_trouser'));
    expect(result.selectedItems.map((item) => item.id), contains('white_sneaker'));
  });

  test('7-day trip with only 8 wardrobe items still returns a result', () {
    final result = service.createPackingPlan(
      wardrobe: [
        item('top_1', ClothingCategory.top, 'Tisort'),
        item('top_2', ClothingCategory.top, 'Gomlek', styles: {StylePreference.smart}),
        item('bottom_1', ClothingCategory.bottom, 'Jean'),
        item('bottom_2', ClothingCategory.bottom, 'Pantolon'),
        item('shoe_1', ClothingCategory.shoes, 'Sneaker'),
        item('shoe_2', ClothingCategory.shoes, 'Loafer', styles: {StylePreference.smart}),
        item('outer_1', ClothingCategory.outerwear, 'Ceket'),
        item('sock_1', ClothingCategory.socks, 'Corap'),
      ],
      trip: trip(tripDays: 7, occasions: ['travel', 'work', 'dinner']),
    );

    expect(result.selectedItems.length, lessThanOrEqualTo(8));
    expect(result.dayPlans, hasLength(7));
    expect(result.coverageScore, greaterThanOrEqualTo(0));
  });

  test('same top is not assigned two days in a row when alternatives exist', () {
    final result = service.createPackingPlan(
      wardrobe: [
        item('top_1', ClothingCategory.top, 'Tisort', color: 'Siyah'),
        item('top_2', ClothingCategory.top, 'Tisort', color: 'Beyaz'),
        item('bottom_1', ClothingCategory.bottom, 'Jean'),
        item('shoe_1', ClothingCategory.shoes, 'Sneaker'),
      ],
      trip: trip(tripDays: 3, occasions: ['casual']),
    );

    final firstTop = topIdForDay(result, 1);
    final secondTop = topIdForDay(result, 2);

    expect(firstTop, isNotEmpty);
    expect(secondTop, isNotEmpty);
    expect(secondTop, isNot(firstTop));
  });

  test('weather filtering excludes clearly incompatible seasonal items', () {
    final result = service.createPackingPlan(
      wardrobe: [
        item(
          'winter_coat',
          ClothingCategory.outerwear,
          'Kaban',
          thickness: Thickness.heavy,
          seasons: {Season.winter},
        ),
        item('summer_top', ClothingCategory.top, 'Tisort', seasons: {Season.summer}),
        item('summer_bottom', ClothingCategory.bottom, 'Sort', seasons: {Season.summer}),
        item('summer_shoes', ClothingCategory.shoes, 'Sneaker', seasons: {Season.summer}),
      ],
      trip: trip(weatherTemp: 32, occasions: ['sightseeing']),
    );

    expect(result.selectedItems.map((item) => item.id), isNot(contains('winter_coat')));
  });
}

TripDetails trip({
  int tripDays = 3,
  List<String> occasions = const ['casual'],
  int weatherTemp = 22,
}) {
  return TripDetails(
    destination: 'Istanbul',
    tripDays: tripDays,
    occasions: occasions,
    weatherTemp: weatherTemp,
    luggageType: 'carry_on',
    departureDate: DateTime(2026, 5, 1),
  );
}

ClothingItem item(
  String id,
  ClothingCategory category,
  String subCategory, {
  String color = 'Siyah',
  Set<StylePreference>? styles,
  Set<Season>? seasons,
  Thickness thickness = Thickness.light,
}) {
  return ClothingItem(
    id: id,
    collection: 'test',
    userId: 'user',
    imageUrl: '',
    category: category,
    subCategory: subCategory,
    color: color,
    styles: styles ?? {StylePreference.casual},
    seasons: seasons ?? {Season.all},
    thickness: thickness,
    favorite: false,
  );
}

String topIdForDay(PackingResult result, int day) {
  return result.dayPlans
          .firstWhere((plan) => plan.day == day)
          .outfitItems
          .where((item) => item.isTop)
          .firstOrNull
          ?.id ??
      '';
}
