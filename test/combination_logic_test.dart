import 'package:flutter_test/flutter_test.dart';
import 'package:deneme_1/models/wardrobe_item_model.dart';
import 'package:deneme_1/services/combination_logic.dart';

/// Saf (framework'süz) gardırop kombin mantığının unit testleri.
/// Bu fonksiyonlar deterministik olduğu için Firebase/UI olmadan test edilir.
void main() {
  WardrobeItem item({
    String category = 'Üst Giyim',
    String type = 'Tişört',
    String color = 'Siyah',
    List<String> season = const [],
  }) {
    return WardrobeItem(
      id: '$category-$type-$color',
      collection: 'ust_giyim',
      userId: 'u1',
      imageUrl: '',
      category: category,
      type: type,
      color: color,
      fabricType: 'Belirtilmedi',
      favorite: false,
      season: season,
    );
  }

  group('colorsCompatible', () {
    test('iki nötr her zaman uyumludur', () {
      // siyah + beyaz nötr, kırmızı güçlü → 2 nötr → uyumlu
      expect(colorsCompatible('Siyah', 'Beyaz', 'Kırmızı'), isTrue);
    });

    test('üç farklı güçlü renk uyumsuzdur', () {
      expect(colorsCompatible('Kırmızı', 'Mavi', 'Yeşil'), isFalse);
    });

    test('aynı güçlü rengin üçlemesi uyumsuzdur', () {
      expect(colorsCompatible('Kırmızı', 'Kırmızı', 'Kırmızı'), isFalse);
    });

    test('bir nötr + iki güçlü renk uyumludur', () {
      expect(colorsCompatible('Siyah', 'Kırmızı', 'Mavi'), isTrue);
    });
  });

  group('wardrobeVariantKey', () {
    test('nötr renkler tek varyantta toplanır', () {
      final black = item(color: 'Siyah');
      final white = item(color: 'Beyaz');
      // aynı kategori+tip, iki nötr renk → aynı varyant anahtarı
      expect(wardrobeVariantKey(black), equals(wardrobeVariantKey(white)));
    });

    test('güçlü renk ayrı varyant üretir', () {
      final black = item(color: 'Siyah');
      final red = item(color: 'Kırmızı');
      expect(wardrobeVariantKey(black), isNot(equals(wardrobeVariantKey(red))));
    });

    test('farklı kategori ayrı varyanttır', () {
      final top = item(category: 'Üst Giyim', type: 'Tişört');
      final bottom = item(category: 'Alt Giyim', type: 'Pantolon');
      expect(
        wardrobeVariantKey(top),
        isNot(equals(wardrobeVariantKey(bottom))),
      );
    });
  });

  group('seasonTagsForItem', () {
    test('"Tüm Mevsim" tüm sezonları kapsar', () {
      final tags = seasonTagsForItem(item(season: const ['Tüm Mevsim']));
      expect(tags, containsAll(['summer', 'spring', 'autumn', 'winter']));
    });
  });

  group('styleTagsForItem', () {
    test('tişört casual etiketi alır', () {
      expect(styleTagsForItem(item(type: 'Tişört')), contains('casual'));
    });

    test('gömlek smart etiketi alır', () {
      final tags = styleTagsForItem(item(category: 'Üst Giyim', type: 'Gömlek'));
      expect(tags, contains('smart'));
    });
  });
}
