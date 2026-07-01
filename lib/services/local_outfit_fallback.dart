import '../models/outfit_ai_models.dart';

/// İstemci tarafı yerel yedek kombin üretici.
///
/// Cloud Function (Gemini) erişilemediğinde uygulamanın yine geçerli bir
/// kombin planı gösterebilmesi için kural tabanlı bir üretici. Sunucudaki
/// `buildLocalOutfitSuggestions` mantığının hafif Dart portudur: gardıroptan
/// gerçek parçaları hava durumu, etkinlik ve tekrar dengesine göre seçer.
OutfitSuggestionResponse buildLocalOutfitResponse(
  OutfitSuggestionRequest request,
) {
  final requestedDays = request.days.where((d) => d.requested).toList();
  final days = (requestedDays.isEmpty ? request.days : requestedDays);

  final wardrobe = request.wardrobe
      .where((item) => !_isGenderIncompatible(item, request.userGender))
      .toList();

  final usage = <String, int>{};
  final styledDays = <StyledDay>[];

  for (final day in days) {
    final temp = request.weather[day.day]?.temp;
    styledDays.add(_buildDay(day, wardrobe, temp, usage));
  }

  return OutfitSuggestionResponse(
    planType: request.planType,
    days: styledDays,
  );
}

StyledDay _buildDay(
  RequestedDay day,
  List<AiWardrobeItem> wardrobe,
  double? temp,
  Map<String, int> usage,
) {
  final special = _isSpecial(day.event);
  final sport = _isSport(day.event);
  final hot = temp != null && temp >= 24;

  final tops = wardrobe.where(_isTop).toList();
  final bottoms = wardrobe.where(_isBottom).toList();
  final shoesList = wardrobe.where(_isShoes).toList();

  // Üst / tek parça seçimi
  AiWardrobeItem? top;
  if (special) {
    top = _pick(tops, _isShirt, usage) ?? _pick(tops, _isOnePiece, usage);
  } else if (sport) {
    top = _pick(tops, _isTshirt, usage) ?? _pick(tops, (_) => true, usage);
  } else {
    top =
        _pick(tops, _isShirt, usage) ??
        _pick(tops, _isTshirt, usage) ??
        _pick(tops, (_) => true, usage);
  }

  final onePiece = top != null && _isOnePiece(top);

  // Alt seçimi (tek parça değilse)
  AiWardrobeItem? bottom;
  if (!onePiece) {
    if (sport && hot) {
      bottom = _pick(bottoms, _isShorts, usage) ?? _pick(bottoms, (_) => true, usage);
    } else if (special) {
      bottom = _pick(bottoms, _isSmartPants, usage) ??
          _pick(bottoms, _isPants, usage) ??
          _pick(bottoms, (_) => true, usage);
    } else {
      bottom = _pick(bottoms, _isPants, usage) ?? _pick(bottoms, (_) => true, usage);
    }
  }

  final shoes = special
      ? (_pick(shoesList, _isElegantShoe, usage) ?? _pick(shoesList, (_) => true, usage))
      : (_pick(shoesList, (_) => true, usage));

  // Zorunlu parçalar eksikse skipped
  if (top == null || shoes == null || (!onePiece && bottom == null)) {
    return StyledDay(
      day: day.day,
      status: 'skipped',
      message: 'Bu gün için uygun üst/alt/ayakkabı bulunamadı.',
      outfit: const OutfitData(),
      canFavorite: false,
    );
  }

  // Dış giyim yalnızca serinse ve tek parça değilse
  AiWardrobeItem? outer;
  if (!onePiece && temp != null && temp < 18) {
    outer = _pick(wardrobe.where(_isOuter).toList(), (_) => true, usage);
  }

  final bag = _pick(wardrobe.where(_isBag).toList(), (_) => true, usage);
  final accessory = _pick(wardrobe.where(_isAccessory).toList(), (_) => true, usage);

  _use(top, usage);
  if (bottom != null && !onePiece) _use(bottom, usage);
  _use(shoes, usage);
  if (outer != null) _use(outer, usage);

  return StyledDay(
    day: day.day,
    status: 'styled',
    title: _title(day.event),
    styleType: _styleType(day.event),
    outfit: OutfitData(
      top: _piece(top),
      outerwear: _piece(outer),
      bottom: onePiece ? null : _piece(bottom),
      shoes: _piece(shoes),
      bag: _piece(bag),
      accessory: _piece(accessory),
    ),
    styleNote: _styleNote(day.event, temp),
    whyThisWorks: _whyThisWorks(day.event),
    vibe: _vibe(day.event),
  );
}

// ─── Seçim yardımcıları ───────────────────────────────────────────────────

AiWardrobeItem? _pick(
  List<AiWardrobeItem> items,
  bool Function(AiWardrobeItem) predicate,
  Map<String, int> usage,
) {
  final matches = items.where(predicate).toList()
    ..sort((a, b) => (usage[a.id] ?? 0).compareTo(usage[b.id] ?? 0));
  return matches.isEmpty ? null : matches.first;
}

void _use(AiWardrobeItem item, Map<String, int> usage) {
  usage[item.id] = (usage[item.id] ?? 0) + 1;
}

OutfitPiece? _piece(AiWardrobeItem? item) =>
    item == null ? null : OutfitPiece(id: item.id, name: item.name);

// ─── Kategori/anahtar eşleştirme ──────────────────────────────────────────

String _text(AiWardrobeItem i) => _normalize(
      '${i.name} ${i.category} ${i.color} ${i.style.join(' ')} ${i.fabric}',
    );

bool _has(AiWardrobeItem i, List<String> tokens) {
  final t = _text(i);
  return tokens.any((tok) => t.contains(_normalize(tok)));
}

bool _isTop(AiWardrobeItem i) => _has(i, [
      'ust', 'tisort', 't-shirt', 'gomlek', 'shirt', 'polo', 'bluz', 'body',
      'crop', 'elbise', 'dress', 'tulum', 'sweatshirt', 'hoodie', 'kazak', 'triko',
    ]);
bool _isBottom(AiWardrobeItem i) => _has(i, [
      'alt', 'pantolon', 'pants', 'jean', 'denim', 'chino', 'sort', 'short',
      'etek', 'skirt', 'esofman', 'jogger',
    ]);
bool _isShoes(AiWardrobeItem i) => _has(i, [
      'ayakkabi', 'shoes', 'sneaker', 'loafer', 'bot', 'boot', 'topuklu', 'stiletto',
    ]);
bool _isOuter(AiWardrobeItem i) => _has(i, [
      'ceket', 'jacket', 'mont', 'kaban', 'coat', 'blazer', 'puffer', 'hirka', 'parka',
    ]);
bool _isBag(AiWardrobeItem i) => _has(i, ['canta', 'bag']);
bool _isAccessory(AiWardrobeItem i) =>
    _has(i, ['aksesuar', 'kemer', 'belt', 'saat', 'watch', 'kolye', 'sapka']);
bool _isOnePiece(AiWardrobeItem i) => _has(i, ['elbise', 'dress', 'tulum']);
bool _isShirt(AiWardrobeItem i) => _has(i, ['gomlek', 'shirt', 'bluz', 'polo']);
bool _isTshirt(AiWardrobeItem i) => _has(i, ['tisort', 't-shirt', 'tshirt']);
bool _isShorts(AiWardrobeItem i) => _has(i, ['sort', 'short']);
bool _isPants(AiWardrobeItem i) =>
    _has(i, ['pantolon', 'pants', 'jean', 'denim', 'chino']);
bool _isSmartPants(AiWardrobeItem i) =>
    _has(i, ['kumas', 'chino', 'klasik', 'pantolon']);
bool _isElegantShoe(AiWardrobeItem i) =>
    _has(i, ['loafer', 'topuklu', 'stiletto', 'klasik', 'bot', 'oxford']);

bool _isGenderIncompatible(AiWardrobeItem i, String gender) {
  if (gender != 'male') return false;
  return _has(i, [
    'elbise', 'dress', 'etek', 'skirt', 'crop', 'bluz', 'topuklu', 'stiletto',
    'tulum', 'body', 'tayt',
  ]);
}

// ─── Etkinlik metinleri ───────────────────────────────────────────────────

bool _isSpecial(String e) => _hasText(e, [
      'date', 'dinner', 'special', 'ozel', 'aksam', 'davet', 'gece',
    ]);
bool _isSport(String e) =>
    _hasText(e, ['spor', 'sport', 'gym', 'fitness', 'kosu', 'antrenman']);

bool _hasText(String text, List<String> tokens) {
  final t = _normalize(text);
  return tokens.any((tok) => t.contains(_normalize(tok)));
}

String _title(String e) {
  if (_isSpecial(e)) return 'Net Date Şıklığı';
  if (_isSport(e)) return 'Rahat Spor Kombin';
  return 'Gündelik Dengeli Kombin';
}

String _styleType(String e) {
  if (_isSpecial(e)) return 'Smart Casual';
  if (_isSport(e)) return 'Sport';
  return 'Casual';
}

String _styleNote(String e, double? temp) {
  final w = temp == null
      ? 'hava verisine göre dengeli parçalarla'
      : '${temp.round()}°C hava için kumaş ve katman dengesini koruyarak';
  if (_isSpecial(e)) return '$w daha özenli ve temiz çizgide bir kombin kuruldu.';
  if (_isSport(e)) return '$w hareket rahatlığı öne alınarak spor parça seçildi.';
  return '$w gündelik ve giyilebilir bir denge kuruldu.';
}

String _whyThisWorks(String e) {
  if (_isSpecial(e)) return 'Sade ama daha özenli görünürsün.';
  if (_isSport(e)) return 'Rahat hareket ederken kombinin yine düzenli görünür.';
  return 'Gün içinde düşünmeden giyebileceğin temiz bir kombin olur.';
}

String _vibe(String e) {
  if (_isSpecial(e)) return 'Smart date';
  if (_isSport(e)) return 'Sport casual';
  return 'Everyday clean';
}

String _normalize(String text) => text
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');
