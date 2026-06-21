import '../models/wardrobe_item_model.dart';

// UPDATED: Mantıklı kombin sayacı — ham çarpım yerine filtreli hesap

// ─── Varyant anahtar ───────────────────────────────────────────────
// Aynı kategori+tip+renk grubunu tek varyant say
String wardrobeVariantKey(WardrobeItem item) {
  final cat = item.category.toLowerCase().trim();
  final type = item.type.toLowerCase().trim();
  final color = _normalizeColor(item.color);
  return '$cat|$type|$color';
}

String _normalizeColor(String raw) {
  final c = _normalize(raw);
  const neutrals = [
    'siyah',
    'beyaz',
    'gri',
    'bej',
    'krem',
    'lacivert',
    'black',
    'white',
    'gray',
    'grey',
    'beige',
    'navy',
  ];
  if (neutrals.any((n) => c.contains(n))) return 'neutral';
  for (final col in [
    'kirmizi',
    'mavi',
    'yesil',
    'sari',
    'turuncu',
    'mor',
    'pembe',
    'red',
    'blue',
    'green',
    'yellow',
    'orange',
    'purple',
    'pink',
  ]) {
    if (c.contains(col)) return col;
  }
  return c.isEmpty || c == 'belirtilmedi' ? 'unknown' : c;
}

// ─── Mevsim etiketleri ─────────────────────────────────────────────
Set<String> seasonTagsForItem(WardrobeItem item) {
  final seasonField = item.season.map(_normalize).join(' ');
  if (seasonField.contains('tum') ||
      seasonField.contains('all') ||
      seasonField.contains('4')) {
    return {'summer', 'spring', 'autumn', 'winter'};
  }
  if (seasonField.contains('yaz') || seasonField.contains('summer')) {
    return {'summer'};
  }
  if (seasonField.contains('kis') || seasonField.contains('winter')) {
    return {'winter'};
  }
  if (seasonField.contains('ilk') || seasonField.contains('spring')) {
    return {'spring'};
  }
  if (seasonField.contains('son') ||
      seasonField.contains('autumn') ||
      seasonField.contains('fall')) {
    return {'autumn'};
  }

  final combined = _itemText(item);
  const summerKw = [
    'sort',
    'short',
    'sandalet',
    'mayo',
    'bikini',
    'kolsuz',
    'crop',
    'tisort',
    't-shirt',
  ];
  const winterKw = [
    'mont',
    'kaban',
    'palto',
    'trenckot',
    'anorak',
    'polar',
    'bot',
    'kazak',
  ];
  const allKw = [
    'sweatshirt',
    'hoodie',
    'jean',
    'pantolon',
    'gomlek',
    'sneaker',
    'loafer',
  ];

  if (summerKw.any(combined.contains)) return {'summer', 'spring'};
  if (winterKw.any(combined.contains)) return {'winter', 'autumn'};
  if (allKw.any(combined.contains)) {
    return {'summer', 'spring', 'autumn', 'winter'};
  }
  return {'summer', 'spring', 'autumn', 'winter'};
}

// ─── Stil etiketleri ───────────────────────────────────────────────
Set<String> styleTagsForItem(WardrobeItem item) {
  final combined = _itemText(item);
  final tags = <String>{};
  const casualKw = [
    'tisort',
    't-shirt',
    'jean',
    'sweatshirt',
    'hoodie',
    'sneaker',
    'converse',
  ];
  const smartKw = [
    'gomlek',
    'shirt',
    'blazer',
    'chino',
    'pantolon',
    'loafer',
    'oxford',
    'klasik',
    'kundura',
  ];
  const sportKw = [
    'esofman',
    'tayt',
    'atlet',
    'spor ayakkabi',
    'kosu',
    'antrenman',
    'forma',
  ];
  const summerKw = ['sort', 'sandalet', 'keten', 'crop', 'kolsuz'];
  const winterKw = ['kazak', 'mont', 'kaban', 'palto', 'bot', 'polar', 'hirka'];

  if (casualKw.any(combined.contains)) tags.add('casual');
  if (smartKw.any(combined.contains)) tags.add('smart');
  if (sportKw.any(combined.contains)) tags.add('sport');
  if (summerKw.any(combined.contains)) tags.add('summer');
  if (winterKw.any(combined.contains)) tags.add('winter');
  if (tags.isEmpty) tags.add('casual');
  return tags;
}

// ─── Renk uyumu ────────────────────────────────────────────────────
bool colorsCompatible(String c1, String c2, String c3) {
  final colors = [c1, c2, c3].map(_normalizeColor).toList();
  final neutralCount = colors.where((c) => c == 'neutral').length;
  if (neutralCount >= 2) return true;
  if (colors.toSet().length == 1 &&
      colors.first != 'neutral' &&
      colors.first != 'unknown') {
    return false;
  }
  final strongColors = colors.where((c) => c != 'neutral' && c != 'unknown');
  if (strongColors.toSet().length >= 3) return false;
  return true;
}

// ─── Tek kombin mantık kontrolü ────────────────────────────────────
bool isLogicalCombination(
  WardrobeItem top,
  WardrobeItem bottom,
  WardrobeItem shoes, {
  WardrobeItem? outer,
}) {
  final topS = seasonTagsForItem(top);
  final botS = seasonTagsForItem(bottom);
  final shoeS = seasonTagsForItem(shoes);
  final seasonIntersect = topS.intersection(botS).intersection(shoeS);
  if (seasonIntersect.isEmpty) return false;

  if (outer != null) {
    final outerS = seasonTagsForItem(outer);
    if (outerS.intersection(seasonIntersect).isEmpty) return false;

    final outerCombined = _itemText(outer);
    final bottomCombined = _itemText(bottom);
    final shoeCombined = _itemText(shoes);
    final heavyWinter =
        ['mont', 'kaban', 'palto', 'anorak'].any(outerCombined.contains);
    final lightBottom =
        ['sort', 'short'].any(bottomCombined.contains) ||
        ['sandalet'].any(shoeCombined.contains);
    if (heavyWinter && lightBottom) return false;
  }

  final topSt = styleTagsForItem(top);
  final shoeSt = styleTagsForItem(shoes);

  final isSportTop = topSt.contains('sport');
  final isSmartShoe = shoeSt.contains('smart') && !shoeSt.contains('casual');
  if (isSportTop && isSmartShoe) return false;

  final isSmartTop = topSt.contains('smart') && !topSt.contains('casual');
  final isSportShoe = shoeSt.contains('sport') && !shoeSt.contains('casual');
  if (isSmartTop && isSportShoe) return false;

  final topCombined = _itemText(top);
  final bottomCombined = _itemText(bottom);
  final shoeCombined = _itemText(shoes);
  final hasTrackPiece =
      topCombined.contains('esofman') || bottomCombined.contains('esofman');
  final hasClassicShoe =
      ['kundura', 'oxford', 'loafer', 'klasik'].any(shoeCombined.contains);
  if (hasTrackPiece && hasClassicShoe) return false;

  final hasShorts = ['sort', 'short'].any(bottomCombined.contains);
  if (hasShorts && hasClassicShoe) return false;

  if (!colorsCompatible(top.color, bottom.color, shoes.color)) {
    final knownColors = [top, bottom, shoes]
        .where((i) => _normalizeColor(i.color) != 'unknown')
        .length;
    if (knownColors >= 3) return false;
  }

  return true;
}

// ─── Ana sayaç ─────────────────────────────────────────────────────
int logicalCombinationCount(List<WardrobeItem> items) {
  bool isTop(WardrobeItem i) {
    final c = _itemText(i);
    return [
      'upper',
      'ust',
      'gomlek',
      'tisort',
      't-shirt',
      'kazak',
      'sweatshirt',
      'hoodie',
      'bluz',
      'crop',
      'atlet',
      'blazer',
      'ceket',
      'hirka',
      'top',
      'shirt',
      'sweater',
      'jacket',
    ].any(c.contains);
  }

  bool isBottom(WardrobeItem i) {
    final c = _itemText(i);
    return [
      'lower',
      'alt',
      'pantolon',
      'etek',
      'sort',
      'jean',
      'tayt',
      'chino',
      'bottom',
      'pants',
      'skirt',
      'shorts',
      'leggings',
    ].any(c.contains);
  }

  bool isShoe(WardrobeItem i) {
    final c = _itemText(i);
    return [
      'shoes',
      'ayakkabi',
      'bot',
      'sneaker',
      'loafer',
      'sandalet',
      'topuklu',
      'oxford',
      'kundura',
      'shoe',
      'boot',
      'heel',
      'flat',
    ].any(c.contains);
  }

  bool isOuter(WardrobeItem i) {
    final c = _itemText(i);
    return [
      'outerwear',
      'dis giyim',
      'mont',
      'kaban',
      'palto',
      'trenckot',
      'anorak',
      'outer',
      'coat',
      'jacket',
    ].any(c.contains);
  }

  Map<String, WardrobeItem> deduplicateByVariant(List<WardrobeItem> list) {
    final map = <String, WardrobeItem>{};
    for (final item in list) {
      final key = wardrobeVariantKey(item);
      map.putIfAbsent(key, () => item);
    }
    return map;
  }

  final tops = deduplicateByVariant(items.where(isTop).toList()).values.toList();
  final bottoms =
      deduplicateByVariant(items.where(isBottom).toList()).values.toList();
  final shoes =
      deduplicateByVariant(items.where(isShoe).toList()).values.toList();
  final outers =
      deduplicateByVariant(items.where(isOuter).toList()).values.toList();

  if (tops.isEmpty || bottoms.isEmpty || shoes.isEmpty) return 0;

  double count = 0;

  for (final top in tops) {
    for (final bottom in bottoms) {
      final compatibleShoes = shoes.where((shoe) {
        return isLogicalCombination(top, bottom, shoe);
      }).toList();
      if (compatibleShoes.isEmpty) continue;

      // Baz stil: üst + alt ikilisi. Ayakkabı kombini tamamlar ama her ek
      // ayakkabı aynı üst-alt için tamamen yeni bir kombin gibi sayılmaz.
      count += 1.0;
      if (compatibleShoes.length > 1) {
        count += (compatibleShoes.length - 1) * 0.28;
      }

      for (final shoe in shoes) {
        if (!compatibleShoes.contains(shoe)) continue;

        for (final outer in outers) {
          if (isLogicalCombination(top, bottom, shoe, outer: outer)) {
            count += 0.18;
          }
        }
      }
    }
  }

  return count.round();
}

// ─── Öneri etkisi ──────────────────────────────────────────────────
int potentialCombinationImpact(
  List<WardrobeItem> currentItems,
  WardrobeItem virtualItem,
) {
  final before = logicalCombinationCount(currentItems);
  final after = logicalCombinationCount([...currentItems, virtualItem]);
  return after - before;
}

String _itemText(WardrobeItem item) {
  return _normalize('${item.collection} ${item.category} ${item.type}');
}

String _normalize(String value) {
  return value
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}
