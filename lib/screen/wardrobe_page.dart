import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../app_theme.dart';
import '../models/wardrobe_analysis_model.dart';
import '../models/wardrobe_item_model.dart';
import '../services/gemini_insight_service.dart';
import '../services/gap_analysis_service.dart';
import 'clothing_detail_page.dart';
import 'gap_analysis_screen.dart';

class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  String selectedCategory = "Tümü";
  String searchQuery = "";
  String? _deletingDocId;
  String? _editingDocId;

  final TextEditingController _searchController = TextEditingController();
  late final Stream<List<WardrobeItem>> _wardrobeStream;
  final GeminiInsightService _geminiInsightService = GeminiInsightService();

  final List<String> categories = const [
    "Tümü",
    "Dış Giyim",
    "Alt Giyim",
    "Üst Giyim",
    "Ayakkabı",
    "Çorap",
  ];

  final Map<String, String> _categoryToCollection = {
    "Üst Giyim": "ust_giyim",
    "Alt Giyim": "alt_giyim",
    "Dış Giyim": "dis_giyim",
    "Ayakkabı": "ayakkabi",
    "Çorap": "corap",
  };

  final Map<String, List<String>> _categoryTypes = const {
    "Üst Giyim": [
      "Tişört",
      "Gömlek",
      "Sweatshirt",
      "Kazak",
      "Bluz",
      "Atlet",
      "Polo",
      "Crop",
      "Hoodie",
    ],
    "Alt Giyim": [
      "Pantolon",
      "Kumaş Pantolon",
      "Chino",
      "Kargo Pantolon",
      "Keten Pantolon",
      "Jean",
      "Eşofman",
      "Şort",
      "Etek",
      "Tayt",
    ],
    "Dış Giyim": [
      "Ceket",
      "Mont",
      "Kaban",
      "Blazer",
      "Hırka",
      "Yağmurluk",
      "Yelek",
    ],
    "Ayakkabı": [
      "Sneaker",
      "Bot",
      "Klasik Ayakkabı",
      "Spor Ayakkabı",
      "Loafer",
      "Sandalet",
      "Terlik",
    ],
    "Çorap": ["Kısa Çorap", "Uzun Çorap", "Bilek Çorap", "Spor Çorap"],
  };

  final Map<String, List<String>> _femaleCategoryTypeAdditions = const {
    "Üst Giyim": [
      "Body",
      "Uzun Kollu Body",
      "Kısa Kollu Body",
      "Elbise",
      "Tulum",
    ],
    "Ayakkabı": ["Topuklu Ayakkabı"],
    "Çorap": ["Külotlu Çorap"],
  };

  final List<String> _colors = const [
    "Siyah",
    "Beyaz",
    "Gri",
    "Bej",
    "Krem",
    "Kahverengi",
    "Lacivert",
    "Mavi",
    "Yeşil",
    "Kırmızı",
    "Bordo",
    "Pembe",
    "Mor",
    "Sarı",
    "Turuncu",
    "Haki",
    "Mint",
    "Nude",
    "Vizon",
    "Füme",
    "Altın",
    "Gümüş",
    "Siyah-Beyaz",
    "Lacivert-Beyaz",
    "Mavi-Beyaz",
    "Gri-Siyah",
    "Bej-Kahverengi",
    "Kırmızı-Beyaz",
    "Yeşil-Beyaz",
    "Pembe-Beyaz",
    "Çok Renkli",
  ];

  final List<String> _fabricTypes = const [
    "Belirtilmedi",
    "Pamuk",
    "Keten",
    "Yün",
    "Denim",
    "Deri",
    "Süet",
    "Polyester",
    "Viskon",
    "Triko",
    "Kanvas",
  ];

  @override
  void initState() {
    super.initState();
    _wardrobeStream = _watchWardrobeItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<WardrobeItem>> _watchWardrobeItems() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(const []);

    final streams = _categoryToCollection.entries.map((entry) {
      return _watchWardrobeCollection(
        userId: user.uid,
        categoryName: entry.key,
        collectionName: entry.value,
      );
    }).toList();

    return _combineWardrobeStreams(streams);
  }

  Stream<List<WardrobeItem>> _watchWardrobeCollection({
    required String userId,
    required String categoryName,
    required String collectionName,
  }) {
    return FirebaseFirestore.instance
        .collection(collectionName)
        .where("user_id", isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return _wardrobeItemFromDoc(
              doc: doc,
              categoryName: categoryName,
              collectionName: collectionName,
            );
          }).toList();
        });
  }

  Stream<List<WardrobeItem>> _combineWardrobeStreams(
    List<Stream<List<WardrobeItem>>> streams,
  ) {
    late final StreamController<List<WardrobeItem>> controller;
    final latest = List<List<WardrobeItem>?>.filled(streams.length, null);
    final subscriptions = <StreamSubscription<List<WardrobeItem>>>[];
    var activeSubscriptions = streams.length;

    void emitIfReady() {
      if (latest.any((items) => items == null)) return;

      final allItems = latest
          .whereType<List<WardrobeItem>>()
          .expand((items) => items)
          .toList();
      allItems.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      if (!controller.isClosed) controller.add(allItems);
    }

    controller = StreamController<List<WardrobeItem>>(
      onListen: () {
        if (streams.isEmpty) {
          controller.add(const []);
          controller.close();
          return;
        }

        for (var i = 0; i < streams.length; i++) {
          final index = i;
          subscriptions.add(
            streams[index].listen(
              (items) {
                latest[index] = items;
                emitIfReady();
              },
              onError: controller.addError,
              onDone: () {
                activeSubscriptions--;
                if (activeSubscriptions == 0 && !controller.isClosed) {
                  controller.close();
                }
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  WardrobeItem _wardrobeItemFromDoc({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String categoryName,
    required String collectionName,
  }) {
    final data = doc.data();
    final type =
        (data["tur"] ?? data["type"] ?? data["ad"] ?? data["name"] ?? "Kıyafet")
            .toString();
    final color = (data["renk"] ?? data["color"] ?? "").toString();
    final rawData = {
      ...data,
      "doc_id": doc.id,
      "collection": collectionName,
      "title": type,
      "category": categoryName,
      "image_url": (data["image_url"] ?? data["imageUrl"] ?? "").toString(),
      "renk": color,
      "kumas_turu": (data["kumas_turu"] ?? data["fabricType"] ?? "Belirtilmedi")
          .toString(),
      "season": _parseNormalizedStringList(data["mevsim"] ?? data["season"]),
    };

    return WardrobeItem(
      id: doc.id,
      collection: collectionName,
      userId: (data["user_id"] ?? data["userId"] ?? "").toString(),
      imageUrl: rawData["image_url"].toString(),
      category: categoryName,
      type: type,
      color: color,
      fabricType: rawData["kumas_turu"].toString(),
      favorite: data["favori"] == true || data["favorite"] == true,
      buttoned: _parseNullableBool(data["dugmeli_mi"]),
      zippered: _parseNullableBool(data["fermuarli_mi"]),
      createdAt: _parseDate(data["created_at"] ?? data["createdAt"]),
      useCount: _parseInt(data["use_count"] ?? data["useCount"]),
      lastUsed: _parseDate(data["last_used"] ?? data["lastUsed"]),
      styleTags: _parseStringList(data["style_tags"] ?? data["styleTags"]),
      season: _parseNormalizedStringList(data["mevsim"] ?? data["season"]),
      rawData: rawData,
    );
  }

  List<WardrobeItem> _filterItems(List<WardrobeItem> items) {
    return items.where((item) {
      final matchesCategory =
          selectedCategory == "Tümü" || item.category == selectedCategory;

      final title = item.type.toLowerCase();
      final category = item.category.toLowerCase();
      final color = item.color.toLowerCase();
      final query = searchQuery.trim().toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          title.contains(query) ||
          category.contains(query) ||
          color.contains(query);

      return matchesCategory && matchesSearch;
    }).toList();
  }

  Future<void> _openGapAnalysis(List<WardrobeItem> wardrobe) async {
    final service = GapAnalysisService();
    final isMaleUser = await _fetchIsMaleUser();
    if (!mounted) return;

    final suggestions = service.analyze(wardrobe, isMaleUser: isMaleUser);
    final currentCombos = service.countPossibleCombos(wardrobe);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GapAnalysisScreen(
          wardrobe: wardrobe,
          suggestions: suggestions,
          currentCombos: currentCombos,
          isMaleUser: isMaleUser,
        ),
      ),
    );
  }

  Future<bool?> _fetchIsMaleUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final value = doc.data()?['cinsiyet'];
    if (value is bool) return value;

    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == 'erkek' || text == 'male') return true;
    if (text == 'false' ||
        text == 'kadın' ||
        text == 'kadin' ||
        text == 'female') {
      return false;
    }
    return null;
  }

  bool? _parseNullableBool(Object? value) {
    if (value is bool) return value;
    if (value == null) return null;

    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty || text == "belirtilmedi") return null;
    if (text == "true" || text == "evet" || text == "yes") return true;
    if (text == "false" || text == "hayir" || text == "hayır" || text == "no") {
      return false;
    }
    return null;
  }

  List<String> _parseNormalizedStringList(Object? value) {
    return _parseStringList(value)
        .map((item) => _normalizeText(item.trim()))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  DateTime? _parseDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<String> _parseStringList(Object? value) {
    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(",")
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  Future<void> _deleteClothingItem(WardrobeItem item) async {
    final docId = item.id;
    final collection = item.collection;
    final imageUrl = item.imageUrl;
    final title = item.displayName;

    if (docId.isEmpty || collection.isEmpty) {
      _showSnackBar("Silme işlemi yapılamadı.", isError: true);
      return;
    }

    setState(() {
      _deletingDocId = docId;
    });

    try {
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(docId)
          .delete();

      if (imageUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(imageUrl).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      _showSnackBar("$title dolabından silindi.", isError: false);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _showSnackBar("Silme sırasında bir hata oluştu.", isError: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _deletingDocId = null;
      });
    }
  }

  Future<void> _showDeleteBottomSheet(WardrobeItem item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = item.displayName;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return AppTheme.frosted(
          isDark: isDark,
          radius: 24,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.tertiaryText(isDark),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                Text("Kıyafeti Sil", style: AppTheme.heading2(isDark)),
                const SizedBox(height: 8),
                Text(
                  "\"$title\" parçasını dolabından silmek üzeresin.",
                  textAlign: TextAlign.center,
                  style: AppTheme.caption(isDark),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Vazgeç"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _deleteClothingItem(item);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE24B4A),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Sil"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateClothingItem({
    required WardrobeItem item,
    required String category,
    required String type,
    required String color,
    required String fabricType,
  }) async {
    final docId = item.id;
    final oldCollection = item.collection;
    final newCollection = _categoryToCollection[category] ?? oldCollection;

    if (docId.isEmpty || oldCollection.isEmpty || newCollection.isEmpty) {
      _showSnackBar("Düzenleme yapılamadı.", isError: true);
      return;
    }

    setState(() {
      _editingDocId = docId;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final updateData = <String, dynamic>{
        "kategori": category,
        "tur": type,
        "renk": color,
        "kumas_turu": fabricType,
        "updated_at": FieldValue.serverTimestamp(),
      };

      if (newCollection == oldCollection) {
        await firestore.collection(oldCollection).doc(docId).update(updateData);
      } else {
        final oldRef = firestore.collection(oldCollection).doc(docId);
        final snapshot = await oldRef.get();
        final currentData = snapshot.data() ?? <String, dynamic>{};
        await firestore.collection(newCollection).add({
          ...currentData,
          ...updateData,
        });
        await oldRef.delete();
      }

      if (!mounted) return;
      _showSnackBar("Kıyafet bilgileri güncellendi.", isError: false);
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _showSnackBar("Düzenleme sırasında bir hata oluştu.", isError: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _editingDocId = null;
      });
    }
  }

  Future<void> _showEditBottomSheet(WardrobeItem item) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMaleUser = await _fetchIsMaleUser();
    var category = item.category;
    if (!_categoryTypes.containsKey(category)) category = "Üst Giyim";

    var type = item.type;
    if (!_availableTypesForCategory(category, isMaleUser).contains(type)) {
      type = _availableTypesForCategory(category, isMaleUser).first;
    }

    var color = item.color;
    if (!_colors.contains(color)) color = "Belirtilmedi";

    var fabricType = item.fabricType;
    if (!_fabricTypes.contains(fabricType)) fabricType = "Belirtilmedi";

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final availableTypes = _availableTypesForCategory(
              category,
              isMaleUser,
            );

            return AppTheme.frosted(
              isDark: isDark,
              radius: 24,
              padding: EdgeInsets.fromLTRB(
                20,
                18,
                20,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.tertiaryText(isDark),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text("Kıyafeti Düzenle", style: AppTheme.heading2(isDark)),
                    const SizedBox(height: 16),
                    _buildEditDropdown(
                      isDark: isDark,
                      label: "Kategori",
                      value: category,
                      items: _categoryTypes.keys.toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() {
                          category = value;
                          type = _availableTypesForCategory(
                            value,
                            isMaleUser,
                          ).first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditDropdown(
                      isDark: isDark,
                      label: "Tür",
                      value: type,
                      items: availableTypes,
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => type = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditDropdown(
                      isDark: isDark,
                      label: "Renk",
                      value: color,
                      items: ["Belirtilmedi", ..._colors],
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => color = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildEditDropdown(
                      isDark: isDark,
                      label: "Kumaş",
                      value: fabricType,
                      items: _fabricTypes,
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => fabricType = value);
                      },
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Vazgeç"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _updateClothingItem(
                                item: item,
                                category: category,
                                type: type,
                                color: color,
                                fabricType: fabricType,
                              );
                            },
                            child: const Text("Kaydet"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> _availableTypesForCategory(String category, bool? isMaleUser) {
    final types = [...(_categoryTypes[category] ?? const <String>[])];
    if (isMaleUser == false) {
      types.addAll(_femaleCategoryTypeAdditions[category] ?? const <String>[]);
    }
    return types;
  }

  Widget _buildEditDropdown({
    required bool isDark,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label(isDark)),
        const SizedBox(height: 6),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
            border: Border.all(color: AppTheme.subtleBorder(isDark)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppTheme.card(isDark),
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          item,
                          style: AppTheme.body(
                            isDark,
                          ).copyWith(color: AppTheme.primaryText(isDark)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openClothingDetail(WardrobeItem item) async {
    final collection = item.collection;
    final docId = item.id;
    if (collection.isEmpty || docId.isEmpty) {
      _showSnackBar("Kıyafet detayı açılamadı.", isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ClothingDetailPage(collection: collection, documentId: docId),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : AppTheme.gold(true),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case "Tümü":
        return Icons.apps_rounded;
      case "Dış Giyim":
        return Icons.checkroom_rounded;
      case "Alt Giyim":
        return Icons.straighten_rounded;
      case "Üst Giyim":
        return Icons.iron_rounded;
      case "Ayakkabı":
        return Icons.hiking_rounded;
      case "Çorap":
        return Icons.spa_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  // UPDATED: Metrik açıklama helper fonksiyonları eklendi
  String _categoryMetricExplanation(Map<String, int> counts, int score) {
    if (score >= 80) return 'Kategori dağılımı dengeli.';
    final weakest = _weakestCategory(counts);
    final strongest = _strongestCategory(counts);
    if (weakest != null && weakest.value == 0) {
      return '${weakest.key} boş görünüyor.';
    }
    if (strongest != null &&
        weakest != null &&
        strongest.value > weakest.value * 2) {
      return '${strongest.key}, ${weakest.key} kategorisine göre baskın.';
    }
    return 'Kategori sayıları eşit dağılmıyor.';
  }

  String _categoryMetricDetail(Map<String, int> counts, int score) {
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) {
      return 'Dolapta analiz edilecek parça olmadığı için kategori dengesi hesaplanamıyor.';
    }
    final weakest = _weakestCategory(counts);
    final strongest = _strongestCategory(counts);
    final distribution = counts.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
    if (score >= 80) {
      return 'Kategori dağılımı genel olarak dengeli görünüyor. Mevcut dağılım: $distribution.';
    }
    if (weakest != null && weakest.value == 0) {
      return '${weakest.key} kategorisinde kayıtlı parça yok. Kategori skorunda boş kategoriler güçlü ceza aldığı için genel denge puanı düşüyor. Mevcut dağılım: $distribution.';
    }
    if (strongest != null &&
        weakest != null &&
        strongest.value > weakest.value * 2) {
      return '${strongest.key} ${strongest.value} parça, ${weakest.key} ${weakest.value} parça görünüyor. Bu fark kategori oranlarını ideal dağılımdan uzaklaştırdığı için puanı düşürüyor.';
    }
    return 'Kategori skorunda her kategorinin doluluk seviyesi ve toplam içindeki oranı birlikte değerlendiriliyor. Mevcut dağılım ideal orandan saptığı için puan sınırlanıyor: $distribution.';
  }

  String _colorMetricExplanation(List<String> colors, int score) {
    if (colors.isEmpty)
      return 'Renk bilgisi girilmemiş parçalar skoru etkiliyor.';
    final stats = _colorMetricStats(colors);
    if ((stats['dominantRatio'] ?? 0) > 0.60)
      return 'Bir renk belirgin baskın.';
    if ((stats['neutralRatio'] ?? 0) < 0.35) return 'Nötr renk oranı düşük.';
    if ((stats['neutralRatio'] ?? 0) > 0.75) return 'Nötr renkler baskın.';
    if ((stats['diversityRatio'] ?? 0) > 0.65)
      return 'Renk dağılımı fazla parçalı.';
    if ((stats['diversityRatio'] ?? 0) < 0.25) return 'Renk çeşitliliği düşük.';
    if (score >= 80) return 'Renk dengesi iyi durumda.';
    return 'Renk dağılımı dengeli değil.';
  }

  String _colorMetricDetail(List<String> colors, int score) {
    if (colors.isEmpty) {
      return 'Renk skoru için kullanılabilir renk bilgisi bulunamadı. Renk alanı boş veya belirtilmedi olan parçalar bu değerlendirmeye katılmıyor.';
    }
    final stats = _colorMetricStats(colors);
    final dominant = stats['dominantColorText'] ?? 'bir renk';
    final dominantRatio = ((stats['dominantRatio'] ?? 0) * 100).round();
    final neutralRatio = ((stats['neutralRatio'] ?? 0) * 100).round();
    final diversityRatio = ((stats['diversityRatio'] ?? 0) * 100).round();
    if ((stats['dominantRatio'] ?? 0) > 0.60) {
      return '$dominant rengi toplam renkli parçaların yaklaşık %$dominantRatio kadarını oluşturuyor. Tek rengin bu kadar baskın olması renk uyumu skorunu düşürüyor.';
    }
    if ((stats['neutralRatio'] ?? 0) < 0.35) {
      return 'Nötr renk oranı yaklaşık %$neutralRatio. Skor mantığı siyah, beyaz, gri, bej, krem ve lacivert gibi nötr renklerin belirli bir denge aralığında olmasını bekliyor.';
    }
    if ((stats['neutralRatio'] ?? 0) > 0.75) {
      return 'Nötr renk oranı yaklaşık %$neutralRatio. Bu oran ideal aralığın üstünde olduğu için skor artık daha sert sınırlanıyor; baskın renk ve çeşitlilik iyi olsa bile renk uyumu mükemmel sayılmıyor.';
    }
    if (score >= 80) {
      return 'Renk skoru dengeli görünüyor. Baskın renk oranı %$dominantRatio, nötr renk oranı %$neutralRatio ve çeşitlilik oranı %$diversityRatio seviyesinde.';
    }
    return 'Renk skorunda baskın renk, nötr renk oranı ve renk çeşitliliği birlikte hesaplanıyor. Bu dolapta baskın renk oranı %$dominantRatio, nötr oranı %$neutralRatio ve çeşitlilik oranı %$diversityRatio.';
  }

  String _seasonMetricExplanation(
    List<WardrobeItem> items,
    Map<String, int> seasonCounts,
    int score,
  ) {
    if (items.isEmpty)
      return 'Parça bilgisi yok, mevsim dengesi hesaplanamıyor.';
    final stats = _seasonMetricStats(items, seasonCounts);
    final missingRole = stats['missingRole']?.toString();
    final weakestRole = stats['weakestRole']?.toString();
    if (score >= 80) return 'Mevsim dağılımı dengeli.';
    if (missingRole != null && missingRole.isNotEmpty) {
      return '$missingRole eksik görünüyor.';
    }
    if (weakestRole != null && weakestRole.isNotEmpty) {
      return '$weakestRole tarafı daha sınırlı.';
    }
    final strongest = stats['strongest'] ?? 'bir mevsim';
    final weakest = stats['weakest'] ?? 'bir mevsim';
    if ((stats['coverage'] ?? 0) < 0.4)
      return 'Mevsim bilgisi eksik görünüyor.';
    return '$strongest ağırlığı, $weakest ağırlığına göre yüksek.';
  }

  String _seasonMetricDetail(
    List<WardrobeItem> items,
    Map<String, int> seasonCounts,
    int score,
  ) {
    if (items.isEmpty) {
      return 'Dolapta analiz edilecek parça olmadığı için mevsim dengesi hesaplanamıyor.';
    }
    final stats = _seasonMetricStats(items, seasonCounts);
    final strongest = stats['strongest'] ?? 'bir mevsim';
    final weakest = stats['weakest'] ?? 'bir mevsim';
    final strongestValue = stats['strongestValue'] ?? 0;
    final weakestValue = stats['weakestValue'] ?? 0;
    final coverage = ((stats['coverage'] ?? 0) * 100).round();
    final source = stats['source'] ?? 'mevsim ve tür bilgileri';
    final missingRole = stats['missingRole']?.toString();
    final weakestRole = stats['weakestRole']?.toString();
    if (score >= 80) {
      return 'Mevsim skoru dengeli görünüyor. Değerlendirme $source üzerinden yapıldı ve dört mevsim arasındaki dağılım birbirine yakın.';
    }
    if (missingRole != null && missingRole.isNotEmpty) {
      return '$missingRole grubunda kayıtlı parça görünmüyor. Mevsim skoru bu somut grupları da hesaba katıyor; bu gruptan bir parça eklenince eksik grup dolmuş sayılır ve denge puanı yükselir.';
    }
    if (weakestRole != null && weakestRole.isNotEmpty) {
      return '$weakestRole grubu diğer mevsim parçalarına göre daha sınırlı. Bu gruptaki parça sayısı arttığında aynı hesap içinde denge güçlenir ve mevsim puanı yükselir.';
    }
    if ((stats['coverage'] ?? 0) < 0.4) {
      return 'Mevsim alanı dolu olan parça oranı yaklaşık %$coverage. Mevsim bilgisi az olduğunda skor daha çok tür/kategori tahminine dayanıyor ve güven seviyesi düşüyor.';
    }
    return '$source içinde $strongest ağırlığı ${strongestValue.toStringAsFixed(1)}, $weakest ağırlığı ${weakestValue.toStringAsFixed(1)} görünüyor. Skor, mevsimler birbirine yakın dağılmadığında düşüyor.';
  }

  String _versatilityMetricExplanation(
    List<String> types,
    int topCount,
    int bottomCount,
    int shoesCount,
    int score,
  ) {
    final total = types.length;
    if (score >= 88) {
      return 'Kombin dengesi güçlü.';
    }
    if (shoesCount == 0) return 'Ayakkabı kategorisi boş.';
    if (bottomCount == 0) return 'Alt giyim kategorisi boş.';
    if (topCount == 0) return 'Üst giyim kategorisi boş.';
    if (shoesCount == 1) return 'Ayakkabı çeşitliliği sınırlı.';
    if (topCount > 0 && bottomCount > 0) {
      final tbRatio = topCount < bottomCount
          ? topCount / bottomCount
          : bottomCount / topCount;
      if (tbRatio < 0.4) {
        return 'Üst-alt dağılımı dengesiz.';
      }
    }
    final uniqueTypeCount = types.toSet().length;
    if (uniqueTypeCount < 4) return 'Kıyafet tür çeşitliliği düşük.';
    if (total < 8) return 'Toplam parça sayısı az.';
    return 'Kombin dağılımı sınırlı.';
  }

  String _versatilityMetricDetail(
    List<String> types,
    int topCount,
    int bottomCount,
    int shoesCount,
    int score,
  ) {
    final total = types.length;
    final uniqueTypeCount = types.map(_normalizeText).toSet().length;
    if (score >= 88) {
      return 'Çok yönlülük skoru güçlü. Üst giyim $topCount, alt giyim $bottomCount, ayakkabı $shoesCount ve tür çeşitliliği $uniqueTypeCount olarak görünüyor.';
    }
    if (shoesCount == 0) {
      return 'Kayıtlı ayakkabı olmadığı için üst ve alt parçalar kombin hesabında tamamlanamıyor. Bu eksiklik çok yönlülük skorunda doğrudan ceza oluşturuyor.';
    }
    if (bottomCount == 0) {
      return 'Alt giyim kaydı olmadığı için üst parçalarla tamamlanan kombin sayısı sınırlı kalıyor. Bu durum çok yönlülük skorunu düşürüyor.';
    }
    if (topCount == 0) {
      return 'Üst giyim kaydı olmadığı için alt ve ayakkabı parçalarıyla kombin çeşitliliği oluşmuyor. Bu durum çok yönlülük skorunu düşürüyor.';
    }
    if (shoesCount == 1) {
      return 'Ayakkabı sayısı 1 olduğu için skor tavanı sınırlanıyor. Mevcut dağılım: üst $topCount, alt $bottomCount, ayakkabı $shoesCount, tür çeşitliliği $uniqueTypeCount.';
    }
    if (topCount > 0 && bottomCount > 0) {
      final tbRatio = topCount < bottomCount
          ? topCount / bottomCount
          : bottomCount / topCount;
      if (tbRatio < 0.4) {
        return 'Üst-alt oranı dengesiz görünüyor. Üst giyim $topCount, alt giyim $bottomCount olduğu için kombin potansiyeli aynı oranda büyümüyor.';
      }
    }
    if (uniqueTypeCount < 4) {
      return 'Kıyafet tür çeşitliliği $uniqueTypeCount seviyesinde. Skor, farklı türler arttıkça daha geniş kombin potansiyeli kabul ediyor.';
    }
    if (total < 8) {
      return 'Toplam kayıtlı tür sayısı $total. Küçük dolaplarda skor ölçeklenerek sınırlandığı için çok yönlülük puanı daha kontrollü yükseliyor.';
    }
    return 'Çok yönlülük skoru üst, alt, ayakkabı dengesi, tür çeşitliliği ve toplam parça sayısını birlikte değerlendiriyor. Mevcut dağılım puanı sınırlıyor.';
  }

  MapEntry<String, int>? _weakestCategory(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value <= b.value ? a : b);
  }

  MapEntry<String, int>? _strongestCategory(Map<String, int> counts) {
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  }

  Map<String, dynamic> _colorMetricStats(List<String> colors) {
    const neutralKeywords = [
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
    final normalized = colors
        .map((color) => _normalizeText(color.trim()))
        .where((color) => color.isNotEmpty)
        .toList();
    final total = normalized.length;
    final freq = <String, int>{};
    for (final color in normalized) {
      freq[color] = (freq[color] ?? 0) + 1;
    }
    final dominant = freq.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final neutralCount = normalized.where((color) {
      return neutralKeywords.any((keyword) => color.contains(keyword));
    }).length;
    return {
      'dominantColorText': dominant.key,
      'dominantRatio': dominant.value / total,
      'neutralRatio': neutralCount / total,
      'diversityRatio': freq.length / total,
    };
  }

  Map<String, dynamic> _seasonMetricStats(
    List<WardrobeItem> items,
    Map<String, int> seasonCounts,
  ) {
    final explicitTotal = seasonCounts.values.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final useExplicit = explicitTotal >= items.length * 0.4;
    final counts = <String, double>{
      'Kış': 0,
      'Yaz': 0,
      'İlkbahar': 0,
      'Sonbahar': 0,
    };
    if (useExplicit) {
      counts['Kış'] = (seasonCounts['kis'] ?? 0).toDouble();
      counts['Yaz'] = (seasonCounts['yaz'] ?? 0).toDouble();
      counts['İlkbahar'] = (seasonCounts['ilkbahar'] ?? 0).toDouble();
      counts['Sonbahar'] = (seasonCounts['sonbahar'] ?? 0).toDouble();
    } else {
      for (final item in items) {
        final groups = _inferredSeasonGroupsForItem(item).toSet();
        if (groups.contains('all')) {
          for (final key in counts.keys) {
            counts[key] = (counts[key] ?? 0) + 0.25;
          }
        }
        if (groups.contains('winter')) counts['Kış'] = (counts['Kış'] ?? 0) + 1;
        if (groups.contains('summer')) counts['Yaz'] = (counts['Yaz'] ?? 0) + 1;
        if (groups.contains('spring')) {
          counts['İlkbahar'] = (counts['İlkbahar'] ?? 0) + 1;
        }
        if (groups.contains('fall')) {
          counts['Sonbahar'] = (counts['Sonbahar'] ?? 0) + 1;
        }
      }
    }
    final strongest = counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    final weakest = counts.entries.reduce((a, b) => a.value <= b.value ? a : b);
    final roleCounts = _seasonRoleCounts(items);
    String missingRole = '';
    for (final entry in roleCounts.entries) {
      if (entry.value == 0) {
        missingRole = entry.key;
        break;
      }
    }
    final weakestRoleEntry = roleCounts.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    return {
      'strongest': strongest.key,
      'weakest': weakest.key,
      'strongestValue': strongest.value,
      'weakestValue': weakest.value,
      'coverage': items.isEmpty ? 0.0 : explicitTotal / items.length,
      'source': useExplicit
          ? 'girilen mevsim bilgileri'
          : 'tür ve kategori tahmini',
      'missingRole': missingRole,
      'weakestRole': weakestRoleEntry.value <= 1 ? weakestRoleEntry.key : '',
    };
  }

  Map<String, int> _seasonRoleCounts(List<WardrobeItem> items) {
    final counts = {
      'Kısa kollu/yazlık üst': 0,
      'Uzun kollu/kalın üst': 0,
      'Şort/ince alt': 0,
      'Soğuk hava dış giyim': 0,
    };

    for (final item in items) {
      final text = _normalizeText('${item.category} ${item.type}');
      if (text.contains('tisort') ||
          text.contains('t-shirt') ||
          text.contains('atlet') ||
          text.contains('kolsuz') ||
          text.contains('kisa kol') ||
          text.contains('kisa kollu') ||
          text.contains('crop') ||
          text.contains('bluz')) {
        counts['Kısa kollu/yazlık üst'] =
            (counts['Kısa kollu/yazlık üst'] ?? 0) + 1;
      }
      if (text.contains('uzun kollu') ||
          text.contains('uzun kol') ||
          text.contains('sweat') ||
          text.contains('hoodie') ||
          text.contains('kazak') ||
          text.contains('triko') ||
          text.contains('hirka') ||
          text.contains('gomlek')) {
        counts['Uzun kollu/kalın üst'] =
            (counts['Uzun kollu/kalın üst'] ?? 0) + 1;
      }
      if (text.contains('sort') ||
          text.contains('etek') ||
          text.contains('keten') ||
          text.contains('sandalet')) {
        counts['Şort/ince alt'] = (counts['Şort/ince alt'] ?? 0) + 1;
      }
      if (text.contains('mont') ||
          text.contains('kaban') ||
          text.contains('parka') ||
          text.contains('palto') ||
          text.contains('trenckot') ||
          text.contains('bot')) {
        counts['Soğuk hava dış giyim'] =
            (counts['Soğuk hava dış giyim'] ?? 0) + 1;
      }
    }

    return counts;
  }

  WardrobeAnalysis _analyzeWardrobe(List<WardrobeItem> items) {
    final counts = {
      for (final category in _categoryToCollection.keys) category: 0,
    };
    final colors = <String>[];
    final types = <String>[];

    for (final item in items) {
      final category = item.category;
      if (counts.containsKey(category)) {
        counts[category] = (counts[category] ?? 0) + 1;
      }

      final color = item.color.trim();
      if (color.isNotEmpty && color != "Belirtilmedi") {
        colors.add(color);
      }

      final type = item.type.trim();
      if (type.isNotEmpty) types.add(type);
    }

    final topCount = counts["Üst Giyim"] ?? 0;
    final bottomCount = counts["Alt Giyim"] ?? 0;
    final shoesCount = counts["Ayakkabı"] ?? 0;
    final outerwearCount = counts["Dış Giyim"] ?? 0;
    final socksCount = counts["Çorap"] ?? 0;
    final dominantColors = _dominantColors(colors);
    final seasonCounts = _seasonDistribution(items);
    final categoryScore = _categoryBalanceScore(counts);
    // Verification guide:
    // Scenario A: deleting 5 of 25 pieces should move each metric by 3-8 points.
    // Scenario B: color variety dropping from 5 colors to 2 should lower color harmony.
    // Scenario C: losing summer/winter pieces should lower season balance by 10+.
    // Scenario D: losing shoes or bottoms should lower versatility with penalties.
    final colorScore = _colorScore(colors);
    final seasonScore = _seasonScore(items, counts, types);
    final versatilityScore = _versatilityScore(
      types,
      colors,
      topCount,
      bottomCount,
      shoesCount,
    );
    final score =
        (categoryScore * 0.25 +
                colorScore * 0.20 +
                seasonScore * 0.25 +
                versatilityScore * 0.30)
            .round()
            .clamp(0, 100)
            .toInt();
    final metrics = [
      WardrobeMetric(
        label: "Kategori dengesi",
        score: categoryScore,
        color: _scoreColor(categoryScore),
        explanation: _categoryMetricExplanation(counts, categoryScore),
        detail: _categoryMetricDetail(counts, categoryScore),
      ),
      WardrobeMetric(
        label: "Renk uyumu",
        score: colorScore,
        color: _scoreColor(colorScore),
        explanation: _colorMetricExplanation(colors, colorScore),
        detail: _colorMetricDetail(colors, colorScore),
      ),
      WardrobeMetric(
        label: "Mevsim dengesi",
        score: seasonScore,
        color: _scoreColor(seasonScore),
        explanation: _seasonMetricExplanation(items, seasonCounts, seasonScore),
        detail: _seasonMetricDetail(items, seasonCounts, seasonScore),
      ),
      WardrobeMetric(
        label: "Çok yönlülük",
        score: versatilityScore,
        color: _scoreColor(versatilityScore),
        explanation: _versatilityMetricExplanation(
          types,
          topCount,
          bottomCount,
          shoesCount,
          versatilityScore,
        ),
        detail: _versatilityMetricDetail(
          types,
          topCount,
          bottomCount,
          shoesCount,
          versatilityScore,
        ),
      ),
    ];

    final insights = <WardrobeInsight>[];
    final suggestions = <PurchaseSuggestion>[];
    if (items.isEmpty) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.add_photo_alternate_rounded,
          title: "Dolabını başlat",
          message: "Analiz için birkaç üst, alt ve ayakkabı eklemen yeterli.",
        ),
      );
      return WardrobeAnalysis(
        score: 0,
        totalItems: 0,
        statusTitle: "Dolabını başlat",
        statusMessage:
            "Birkaç temel parça ekleyince analiz anlamlı hale gelir.",
        counts: counts,
        metrics: metrics,
        insights: insights,
        suggestions: const [
          PurchaseSuggestion(
            icon: Icons.iron_rounded,
            title: "3 temel üst parça ekle",
            message:
                "Beyaz tişört, düz gömlek ve sweatshirt başlangıç için iyi temel oluşturur.",
            impact: "İlk 6-8 kombin buradan çıkar",
            color: Color(0xFFF0A92E),
          ),
        ],
        dominantColors: dominantColors,
        seasonCounts: seasonCounts,
        topCount: topCount,
        bottomCount: bottomCount,
        shoeCount: shoesCount,
      );
    }

    if (topCount < 3) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.iron_rounded,
          title: "Üst giyim az",
          message: "Günlük kombin çeşitliliği için birkaç tişört/gömlek ekle.",
        ),
      );
      suggestions.add(
        PurchaseSuggestion(
          icon: Icons.iron_rounded,
          title: "Düz beyaz tişört veya oxford gömlek",
          message:
              "Mevcut alt ve ayakkabılarınla hızlıca eşleşen güvenli temel parça olur.",
          impact:
              "${_comboImpact(1, bottomCount, shoesCount)} yeni kombin potansiyeli",
          color: const Color(0xFFF0A92E),
        ),
      );
    }
    if (bottomCount < 2) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.straighten_rounded,
          title: "Alt giyim sınırlı",
          message: "Pantolon, jean veya şort eklemek kombin tekrarını azaltır.",
        ),
      );
      suggestions.add(
        PurchaseSuggestion(
          icon: Icons.straighten_rounded,
          title: "Koyu jean veya bej chino",
          message:
              "Üst giyimdeki parçaları daha fazla güne yayar, smart-casual geçişi kolaylaştırır.",
          impact:
              "${_comboImpact(topCount, 1, shoesCount)} yeni kombin potansiyeli",
          color: const Color(0xFF4AA3FF),
        ),
      );
    }
    if (shoesCount < 2) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.hiking_rounded,
          title: "Ayakkabı desteği lazım",
          message: "En az bir sneaker veya loafer kombinleri daha esnek yapar.",
        ),
      );
      suggestions.add(
        PurchaseSuggestion(
          icon: Icons.hiking_rounded,
          title: "Beyaz sneaker veya loafer",
          message:
              "Ayakkabı çeşitliliği az olduğu için kombinler aynı hissedebilir.",
          impact:
              "${_comboImpact(topCount, bottomCount, 1)} yeni kombin potansiyeli",
          color: const Color(0xFFE95F62),
        ),
      );
    }
    if (outerwearCount == 0) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.checkroom_rounded,
          title: "Dış giyim eksik",
          message: "Soğuk ve yağışlı günlerde öneriler sınırlı kalabilir.",
        ),
      );
      suggestions.add(
        PurchaseSuggestion(
          icon: Icons.checkroom_rounded,
          title: "Mevsimlik ceket veya yağmurluk",
          message:
              "Hava soğuduğunda kombin önerileri dış giyimle daha gerçekçi olur.",
          impact: "Soğuk gün kombinlerini güçlendirir",
          color: const Color(0xFF62C584),
        ),
      );
    }
    if (socksCount == 0) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.spa_rounded,
          title: "Çorap/aksesuar boşluğu var",
          message:
              "Küçük tamamlayıcılar günlük kombinleri daha kullanışlı yapar.",
        ),
      );
    }
    if (_neutralColorRatio(colors) > 0.75 && colors.length >= 4) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.palette_rounded,
          title: "Renk çeşitliliği düşük",
          message:
              "Dolap nötr ağırlıklı olduğu için kombinler birbirine benzer görünebilir.",
        ),
      );
      suggestions.add(
        const PurchaseSuggestion(
          icon: Icons.palette_rounded,
          title: "1 vurgu renkli parça",
          message:
              "Bordo, koyu yeşil veya lacivert bir üst nötr parçalarla kolay eşleşir.",
          impact: "Benzer kombinleri daha farklı gösterir",
          color: Color(0xFFF0A92E),
        ),
      );
    }
    if (!_hasSmartBase(types)) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.work_outline_rounded,
          title: "Smart kombin tabanı zayıf",
          message:
              "Gömlek, blazer veya klasik ayakkabı eklemeyi düşünebilirsin.",
        ),
      );
      suggestions.add(
        PurchaseSuggestion(
          icon: Icons.work_outline_rounded,
          title: "Smart-casual tamamlayıcı",
          message: "Bir gömlek, blazer veya loafer ofis/akşam planlarını açar.",
          impact:
              "${_comboImpact(topCount < 1 ? 1 : topCount, bottomCount < 1 ? 1 : bottomCount, 1)} smart kombin potansiyeli",
          color: const Color(0xFF4AA3FF),
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const WardrobeInsight(
          icon: Icons.verified_rounded,
          title: "Dolap dengeli görünüyor",
          message: "Kategori, renk ve kullanım çeşitliliği iyi seviyede.",
        ),
      );
    }

    return WardrobeAnalysis(
      score: score,
      totalItems: items.length,
      statusTitle: _analysisStatusTitle(score),
      statusMessage: _analysisStatusMessage(metrics),
      counts: counts,
      metrics: metrics,
      insights: insights.take(4).toList(),
      suggestions: suggestions.take(3).toList(),
      dominantColors: dominantColors,
      seasonCounts: seasonCounts,
      topCount: topCount,
      bottomCount: bottomCount,
      shoeCount: shoesCount,
    );
  }

  int _comboImpact(int topCount, int bottomCount, int shoesCount) {
    final impact = topCount * bottomCount * shoesCount;
    if (impact <= 0) return 1;
    return impact.clamp(1, 12).toInt();
  }

  int _categoryBalanceScore(Map<String, int> counts) {
    if (counts.isEmpty) return 0;

    final totalItems = counts.values.fold<int>(0, (sum, count) => sum + count);
    if (totalItems == 0) return 0;

    const idealRatios = {
      "Üst Giyim": 0.35,
      "Alt Giyim": 0.25,
      "Dış Giyim": 0.15,
      "Ayakkabı": 0.15,
      "Çorap": 0.10,
    };

    var ratioPenalty = 0.0;
    var bandQualityTotal = 0.0;
    var missingPenalty = 0.0;
    var weakPenalty = 0.0;

    for (final entry in counts.entries) {
      final actualRatio = entry.value / totalItems;
      final idealRatio = idealRatios[entry.key] ?? (1 / counts.length);
      final bandScore = _categoryBand(entry.key, entry.value).score / 100;

      ratioPenalty += math.pow((actualRatio - idealRatio).abs(), 1.25) * 140;
      bandQualityTotal += bandScore * idealRatio;

      if (entry.value == 0) {
        missingPenalty += 34 + idealRatio * 60;
      } else if (bandScore <= 0.25) {
        weakPenalty += idealRatio * 35;
      } else if (bandScore <= 0.60) {
        weakPenalty += idealRatio * 16;
      }
    }

    final nonEmptyCount = counts.values.where((count) => count > 0).length;
    final coverageScore = math.pow(nonEmptyCount / counts.length, 1.6) * 100;
    final bandScore = bandQualityTotal * 100;
    final ratioScore = 100 - ratioPenalty;
    final lowBandCount = counts.entries
        .where((entry) => _categoryBand(entry.key, entry.value).score <= 25)
        .length;
    final lowBandPenalty = math.pow(lowBandCount, 1.35) * 7;

    final score =
        (ratioScore * 0.35) +
        (coverageScore * 0.25) +
        (bandScore * 0.40) -
        missingPenalty -
        weakPenalty -
        lowBandPenalty;

    return score.round().clamp(0, 100).toInt();
  }

  _CategoryBand _categoryBand(String category, int count) {
    switch (category) {
      case "Üst Giyim":
        return _bandForCount(
          count,
          lowMax: 2,
          midMax: 5,
          goodMax: 9,
          idealMax: 15,
        );
      case "Alt Giyim":
        return _bandForCount(
          count,
          lowMax: 1,
          midMax: 4,
          goodMax: 7,
          idealMax: 12,
        );
      case "Dış Giyim":
        return _bandForCount(
          count,
          lowMax: 0,
          midMax: 2,
          goodMax: 4,
          idealMax: 8,
        );
      case "Ayakkabı":
        return _bandForCount(
          count,
          lowMax: 1,
          midMax: 3,
          goodMax: 5,
          idealMax: 9,
        );
      case "Çorap":
        return _bandForCount(
          count,
          lowMax: 0,
          midMax: 2,
          goodMax: 4,
          idealMax: 8,
        );
      default:
        return _bandForCount(
          count,
          lowMax: 0,
          midMax: 2,
          goodMax: 4,
          idealMax: 8,
        );
    }
  }

  _CategoryBand _bandForCount(
    int count, {
    required int lowMax,
    required int midMax,
    required int goodMax,
    required int idealMax,
  }) {
    if (count <= lowMax) {
      return const _CategoryBand(
        label: "Çok az",
        score: 0,
        color: Color(0xFFE95F62),
      );
    }
    if (count <= midMax) {
      return const _CategoryBand(
        label: "Az",
        score: 25,
        color: Color(0xFFF0A92E),
      );
    }
    if (count <= goodMax) {
      return const _CategoryBand(
        label: "Orta",
        score: 60,
        color: Color(0xFF7FAE32),
      );
    }
    if (count <= idealMax) {
      return const _CategoryBand(
        label: "İdeal",
        score: 100,
        color: Color(0xFF22A579),
      );
    }
    return const _CategoryBand(
      label: "Fazla",
      score: 70,
      color: Color(0xFF2068A8),
    );
  }

  // UPDATED: Scores color harmony with dominance, neutral balance, diversity, and small-wardrobe scaling.
  int _colorScore(List<String> colors) {
    const neutralKeywords = [
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

    final allColors = colors
        .map((color) => _normalizeText(color.trim()))
        .where((color) => color.isNotEmpty)
        .toList();
    final total = allColors.length;
    if (total == 0) return 50;

    final freq = <String, int>{};
    for (final color in allColors) {
      freq[color] = (freq[color] ?? 0) + 1;
    }

    final uniqueCount = freq.length;
    final dominantCount = freq.values.reduce(math.max);
    final dominantRatio = dominantCount / total;
    final neutralCount = allColors.where((color) {
      return neutralKeywords.any((keyword) => color.contains(keyword));
    }).length;
    final neutralRatio = neutralCount / total;
    final diversityRatio = uniqueCount / total;

    final dominanceScore = dominantRatio <= 0.40
        ? 100.0
        : dominantRatio >= 0.90
        ? 0.0
        : 100.0 * (0.90 - dominantRatio) / 0.50;
    final neutralScore = neutralRatio >= 0.40 && neutralRatio <= 0.65
        ? 100.0
        : neutralRatio < 0.40
        ? (neutralRatio / 0.40) * 100.0
        : neutralRatio <= 0.75
        ? 100.0 - ((neutralRatio - 0.65) / 0.10 * 25.0)
        : math.max(35.0, 75.0 - ((neutralRatio - 0.75) / 0.25 * 40.0));
    final diversityScore = diversityRatio >= 0.30 && diversityRatio <= 0.60
        ? 100.0
        : diversityRatio < 0.30
        ? (diversityRatio / 0.30) * 100.0
        : math.max(0.0, 100.0 - (diversityRatio - 0.60) / 0.40 * 100.0);
    final sizeScale = total < 10 ? total / 10.0 : 1.0;
    final raw =
        (dominanceScore * 0.35) +
        (neutralScore * 0.40) +
        (diversityScore * 0.25);
    final cap = neutralRatio > 0.75 ? 88.0 : 100.0;
    final scaled = (50.0 + (raw - 50.0) * sizeScale).clamp(0.0, cap);

    return scaled.round().toInt();
  }

  // UPDATED: Scores explicit season data when available, otherwise uses low-confidence type inference.
  int _seasonScore(
    List<WardrobeItem> items,
    Map<String, int> counts,
    List<String> types,
  ) {
    if (items.isEmpty) return 0;

    final explicitScore = _computeSeasonScoreFromField(items);
    final explicitCount = items.where((item) {
      return item.season.expand(_seasonGroups).isNotEmpty;
    }).length;
    final explicitCoverage = explicitCount / items.length;

    final roleScore = _seasonRoleCoverageScore(items);

    if (explicitCoverage >= 0.5) {
      return ((explicitScore * 0.72) + (roleScore * 0.28))
          .round()
          .clamp(0, 100)
          .toInt();
    }

    final inferredScore = _computeSeasonScoreFromInferredTypes(items);
    final hasOuterwear = (counts["Dış Giyim"] ?? 0) > 0;
    final hasAnyType = types.any((type) => type.trim().isNotEmpty);
    final inferenceReliability = hasAnyType ? 0.90 : 0.45;
    final blendedScore =
        (explicitScore * explicitCoverage) +
        (inferredScore * (1 - explicitCoverage) * inferenceReliability);
    final outerwearBonus = hasOuterwear ? 4 : 0;
    final scoreWithRoles = (blendedScore * 0.82) + (roleScore * 0.18);

    return (scoreWithRoles + outerwearBonus).round().clamp(0, 100).toInt();
  }

  int _seasonRoleCoverageScore(List<WardrobeItem> items) {
    if (items.isEmpty) return 0;

    final counts = _seasonRoleCounts(items);
    final presentCount = counts.values.where((count) => count > 0).length;
    final coverageScore = presentCount / counts.length * 100.0;
    final values = counts.values.toList();
    final maxCount = values.reduce((a, b) => a > b ? a : b);
    final minPresent = values
        .where((count) => count > 0)
        .fold<int>(
          maxCount,
          (minValue, count) => count < minValue ? count : minValue,
        );
    final balanceScore = maxCount == 0
        ? 0.0
        : ((minPresent / maxCount).clamp(0.0, 1.0) * 100.0).toDouble();

    return ((coverageScore * 0.70) + (balanceScore * 0.30))
        .round()
        .clamp(0, 100)
        .toInt();
  }

  // UPDATED: Uses entropy, missing-season penalties, season coverage, and small-wardrobe scaling.
  int _computeSeasonScoreFromField(List<WardrobeItem> items) {
    if (items.isEmpty) return 0;

    final seasonCounts = <String, double>{
      "winter": 0,
      "summer": 0,
      "spring": 0,
      "fall": 0,
    };
    var itemsWithSeason = 0;

    for (final item in items) {
      final groups = item.season.expand(_seasonGroups).toSet();
      if (groups.isEmpty) continue;

      itemsWithSeason++;
      _addSeasonGroupsToCounts(seasonCounts, groups, weight: 1);
    }

    return _seasonBalanceFromCounts(
      seasonCounts,
      totalItems: items.length,
      coverage: itemsWithSeason / items.length,
    );
  }

  int _computeSeasonScoreFromInferredTypes(List<WardrobeItem> items) {
    final seasonCounts = <String, double>{
      "winter": 0,
      "summer": 0,
      "spring": 0,
      "fall": 0,
    };
    var inferredItems = 0;

    for (final item in items) {
      final groups = _inferredSeasonGroupsForItem(item).toSet();
      if (groups.isEmpty) continue;

      inferredItems++;
      _addSeasonGroupsToCounts(seasonCounts, groups, weight: 0.75);
    }

    return _seasonBalanceFromCounts(
      seasonCounts,
      totalItems: items.length,
      coverage: inferredItems / items.length,
    );
  }

  int _seasonBalanceFromCounts(
    Map<String, double> seasonCounts, {
    required int totalItems,
    required double coverage,
  }) {
    if (totalItems == 0 || coverage <= 0) return 0;

    final values = seasonCounts.values.toList();
    final totalSeasonWeight = values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    if (totalSeasonWeight <= 0) return 0;

    var entropy = 0.0;
    for (final value in values) {
      if (value <= 0) continue;
      final ratio = value / totalSeasonWeight;
      entropy -= ratio * math.log(ratio);
    }
    final entropyScore = entropy / math.log(4) * 100;
    final maxSeasonWeight = values.reduce((a, b) => a > b ? a : b);
    final minSeasonWeight = values.reduce((a, b) => a < b ? a : b);
    final balanceScore = maxSeasonWeight <= 0
        ? 0.0
        : math.pow(minSeasonWeight / maxSeasonWeight, 0.55) * 100;
    final missingSeasonPenalty =
        values.where((value) => value <= 0).length * 10;
    final smallWardrobeScale = totalItems < 8 ? 0.70 * (totalItems / 8) : 1.0;
    final sizeFactor = _wardrobeSizeFactor(totalItems);
    final rawScore =
        (entropyScore * 0.58) + (balanceScore * 0.42) - missingSeasonPenalty;
    final score = rawScore * coverage * sizeFactor * smallWardrobeScale;

    return score.round().clamp(0, 100).toInt();
  }

  void _addSeasonGroupsToCounts(
    Map<String, double> seasonCounts,
    Set<String> groups, {
    required double weight,
  }) {
    if (groups.contains("all")) {
      for (final key in seasonCounts.keys) {
        seasonCounts[key] = (seasonCounts[key] ?? 0) + (weight * 0.25);
      }
      return;
    }

    for (final group in groups) {
      if (!seasonCounts.containsKey(group)) continue;
      seasonCounts[group] = (seasonCounts[group] ?? 0) + weight;
    }
  }

  Iterable<String> _seasonGroups(String value) {
    final text = _normalizeText(value);
    final groups = <String>[];

    if (text.contains("4mevsim") ||
        text.contains("4 mevsim") ||
        text.contains("all season") ||
        text.contains("all-season") ||
        text == "all") {
      groups.add("all");
    }
    if (text.contains("kis") || text.contains("winter")) {
      groups.add("winter");
    }
    if (text.contains("yaz") || text.contains("summer")) {
      groups.add("summer");
    }
    if (text.contains("ilkbahar") ||
        text == "bahar" ||
        text.contains("spring")) {
      groups.add("spring");
    }
    if (text.contains("sonbahar") ||
        text.contains("autumn") ||
        text.contains("fall")) {
      groups.add("fall");
    }

    return groups;
  }

  // UPDATED: skor tavanları ve neutralBonus düzeltildi
  int _versatilityScore(
    List<String> types,
    List<String> colors,
    int topCount,
    int bottomCount,
    int shoesCount,
  ) {
    const neutralKeywords = [
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

    final total = math.max(types.length, topCount + bottomCount + shoesCount);
    if (total == 0) return 0;

    var penalty = 0.0;
    if (topCount == 0) penalty += 25.0;
    if (bottomCount == 0) penalty += 20.0;
    if (shoesCount == 0) penalty += 15.0;

    final tbRatio = topCount > 0 && bottomCount > 0
        ? math.min(topCount, bottomCount) /
              math.max(topCount, bottomCount).toDouble()
        : 0.0;
    final bsRatio = bottomCount > 0 && shoesCount > 0
        ? math.min(bottomCount, shoesCount) /
              math.max(bottomCount, shoesCount).toDouble()
        : 0.0;
    final comboScore = ((tbRatio + bsRatio) / 2.0) * 100.0;
    final uniqueTypes = types.map(_normalizeText).toSet().length;
    final typeScore = math.min(uniqueTypes / 8.0, 1.0) * 100.0;
    final sizeScore =
        (math.log(total + 1) / math.log(25)).clamp(0.0, 1.0) * 100.0;
    final normalizedColors = colors.map((color) => _normalizeText(color));
    final neutralCount = normalizedColors.where((color) {
      return neutralKeywords.any((keyword) => color.contains(keyword));
    }).length;
    final neutralTarget = math.max(total * 0.3, 1).toDouble();
    final neutralBonus = math.min(neutralCount / neutralTarget, 1.0) * 8.0;
    final sizeScale = total < 10 ? total / 10.0 : 1.0;
    var raw = (comboScore * 0.45) + (typeScore * 0.30) + (sizeScore * 0.25);
    raw += neutralBonus;

    // Soft cap: tam 100 sadece gerçekten geniş ve dengeli dolaplarda mümkün
    double cap = 100.0;

    // Tavan koşulları — hepsi sağlanmıyorsa max 94
    final bool fullScore =
        topCount >= 5 &&
        bottomCount >= 3 &&
        shoesCount >= 2 &&
        uniqueTypes >= 6 &&
        total >= 15;
    if (!fullScore) cap = math.min(cap, 94.0);

    // Ek kısıtlı durumlar (birden fazlası aynı anda geçerliyse en düşük cap kazanır)
    if (shoesCount == 1) cap = math.min(cap, 88.0);
    if (bottomCount <= 2) cap = math.min(cap, 86.0);
    if (topCount <= 3) cap = math.min(cap, 86.0);

    final scaled = (50.0 + (raw - 50.0) * sizeScale).clamp(0.0, cap);
    final finalScore = (scaled - penalty).clamp(0.0, 100.0);

    return finalScore.round().toInt();
  }

  Color _scoreColor(int score) {
    if (score >= 75) return const Color(0xFF62C584);
    if (score >= 50) return const Color(0xFFF0A92E);
    return const Color(0xFFE95F62);
  }

  String _analysisStatusTitle(int score) {
    if (score >= 80) return "Dengeli dolap";
    if (score >= 60) return "Gelişime açık dolap";
    return "Temel parçalar eksik";
  }

  String _analysisStatusMessage(List<WardrobeMetric> metrics) {
    final sorted = [...metrics]..sort((a, b) => a.score.compareTo(b.score));
    final weak = sorted.take(2).map((metric) => metric.label.toLowerCase());
    return "${weak.join(" ve ")} skoru genel dengeyi düşürüyor.";
  }

  bool _hasSmartBase(List<String> types) {
    final normalized = types.map(_normalizeText).join(" ");
    return normalized.contains("gomlek") ||
        normalized.contains("blazer") ||
        normalized.contains("loafer") ||
        normalized.contains("klasik") ||
        normalized.contains("ceket");
  }

  double _neutralColorRatio(List<String> colors) {
    if (colors.isEmpty) return 0;
    final neutralCount = colors.where((color) {
      final text = _normalizeText(color);
      return text.contains("siyah") ||
          text.contains("beyaz") ||
          text.contains("gri") ||
          text.contains("bej") ||
          text.contains("krem") ||
          text.contains("lacivert");
    }).length;
    return neutralCount / colors.length;
  }

  List<String> _dominantColors(List<String> colors) {
    final counts = <String, int>{};
    final displayValues = <String, String>{};

    for (final color in colors) {
      final trimmed = color.trim();
      final normalized = _normalizeText(trimmed);
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + 1;
      displayValues.putIfAbsent(normalized, () => trimmed);
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(3)
        .map((entry) => displayValues[entry.key] ?? entry.key)
        .toList();
  }

  // UPDATED: Uses explicit season values first and falls back to type inference for UI distribution.
  Map<String, int> _seasonDistribution(List<WardrobeItem> items) {
    final counts = {"kis": 0, "yaz": 0, "ilkbahar": 0, "sonbahar": 0};

    for (final item in items) {
      final explicitGroups = item.season.expand(_seasonGroups).toSet();
      final groups = explicitGroups.isNotEmpty
          ? explicitGroups
          : _inferredSeasonGroupsForItem(item).toSet();
      if (groups.contains("all")) {
        counts.update("kis", (value) => value + 1);
        counts.update("yaz", (value) => value + 1);
        counts.update("ilkbahar", (value) => value + 1);
        counts.update("sonbahar", (value) => value + 1);
        continue;
      }
      if (groups.contains("winter")) {
        counts.update("kis", (value) => value + 1);
      }
      if (groups.contains("summer")) {
        counts.update("yaz", (value) => value + 1);
      }
      if (groups.contains("spring")) {
        counts.update("ilkbahar", (value) => value + 1);
      }
      if (groups.contains("fall")) {
        counts.update("sonbahar", (value) => value + 1);
      }
    }

    return counts;
  }

  Iterable<String> _inferredSeasonGroupsForItem(WardrobeItem item) {
    final type = _normalizeText(item.type);
    final category = _normalizeText(item.category);
    final text = '$category $type';
    final groups = <String>[];

    if (text.contains("mont") ||
        text.contains("kaban") ||
        text.contains("parka") ||
        text.contains("palto") ||
        text.contains("bot") ||
        text.contains("kazak") ||
        text.contains("triko")) {
      groups.add("winter");
    }
    if (text.contains("tisort") ||
        text.contains("t-shirt") ||
        text.contains("sort") ||
        text.contains("atlet") ||
        text.contains("keten") ||
        text.contains("sandalet")) {
      groups.add("summer");
    }
    if (text.contains("gomlek") ||
        text.contains("sweat") ||
        text.contains("hoodie") ||
        text.contains("hirka") ||
        text.contains("ceket") ||
        text.contains("jean") ||
        text.contains("sneaker")) {
      groups.add("spring");
      groups.add("fall");
    }
    if (category.contains("corap") && groups.isEmpty) {
      groups.add("all");
    }

    return groups;
  }

  double _wardrobeSizeFactor(int totalItems) {
    if (totalItems <= 0) return 0;
    if (totalItems < 10) return (totalItems / 10).clamp(0.0, 1.0);
    if (totalItems <= 30) return 1;
    return (math.log(31) / math.log(totalItems + 1)).clamp(0.82, 1.0);
  }

  String _normalizeText(String value) {
    return value
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ş', 's')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c');
  }

  Widget _buildWardrobeAnalysisCard(List<WardrobeItem> items, bool isDark) {
    final analysis = _analyzeWardrobe(items);
    final scoreColor = _scoreColor(analysis.score);

    return GestureDetector(
      onTap: () => _showWardrobeAnalysisSheet(analysis),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.panelDecoration(isDark).copyWith(
          color: isDark ? const Color(0xFF16161B) : AppTheme.surface1Light,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: analysis.score / 100,
                    strokeWidth: 5,
                    backgroundColor: isDark
                        ? Colors.white12
                        : const Color(0xFFE7DFD2),
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                  ),
                  Text(
                    "${analysis.score}",
                    style: AppTheme.label(isDark).copyWith(
                      color: AppTheme.primaryText(isDark),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Gardırop analizi",
                    style: AppTheme.body(isDark).copyWith(
                      color: AppTheme.primaryText(isDark),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    analysis.statusTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(isDark).copyWith(
                      color: AppTheme.gold(isDark),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    analysis.statusMessage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(isDark).copyWith(
                      color: isDark
                          ? const Color(0xFFE3E4EA)
                          : AppTheme.secondaryText(isDark),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.secondaryText(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGapAnalysisButton(List<WardrobeItem> items, bool isDark) {
    return GestureDetector(
      onTap: () => _openGapAnalysis(items),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.panelDecoration(isDark).copyWith(
          color: isDark ? const Color(0xFF16161B) : AppTheme.surface1Light,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.gold(isDark).withOpacity(0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.gold(isDark).withOpacity(0.28),
                ),
              ),
              child: Icon(
                Icons.shopping_bag_outlined,
                color: AppTheme.gold(isDark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Ne alsam?",
                    style: AppTheme.body(isDark).copyWith(
                      color: AppTheme.primaryText(isDark),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    "En çok kombin çıkaracak eksik parçaları gör",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(isDark).copyWith(
                      color: isDark
                          ? const Color(0xFFE3E4EA)
                          : AppTheme.secondaryText(isDark),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.secondaryText(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showWardrobeAnalysisSheet(WardrobeAnalysis analysis) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? aiInsight;
    var isLoadingAiInsight = false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> loadAiInsight() async {
              setSheetState(() => isLoadingAiInsight = true);
              try {
                final insight = await _geminiInsightService.getInsight(
                  analysis,
                );
                if (!context.mounted) return;
                setSheetState(() => aiInsight = insight);
              } catch (_) {
                if (!context.mounted) return;
                setSheetState(
                  () => aiInsight = "Şu an öneri alınamadı, tekrar dene.",
                );
              } finally {
                if (!context.mounted) return;
                setSheetState(() => isLoadingAiInsight = false);
              }
            }

            return AppTheme.frosted(
              isDark: isDark,
              radius: 24,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.82,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: AppTheme.tertiaryText(isDark),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Gardırop analizi",
                          style: AppTheme.heading2(isDark),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${analysis.totalItems} parça · Son güncelleme: bugün",
                          style: AppTheme.body(isDark).copyWith(
                            color: isDark
                                ? const Color(0xFFE3E4EA)
                                : AppTheme.secondaryText(isDark),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          "GENEL SKOR",
                          style: AppTheme.label(isDark).copyWith(
                            color: AppTheme.secondaryText(isDark),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _AnalysisHeroCard(analysis: analysis, isDark: isDark),
                        const SizedBox(height: 14),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: analysis.metrics.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.35,
                              ),
                          itemBuilder: (context, index) {
                            return _AnalysisMetricCard(
                              metric: analysis.metrics[index],
                              isDark: isDark,
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.gold(isDark),
                              foregroundColor: AppTheme.textOnGold,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: isLoadingAiInsight
                                ? null
                                : loadAiInsight,
                            icon: isLoadingAiInsight
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              isLoadingAiInsight
                                  ? "Gemini düşünüyor..."
                                  : "AI Öneri Al",
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        if (aiInsight != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1F1F25)
                                  : AppTheme.layer2(false),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.gold(isDark).withOpacity(0.25),
                              ),
                            ),
                            child: Text(
                              aiInsight!,
                              style: AppTheme.body(isDark).copyWith(
                                color: AppTheme.primaryText(isDark),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Divider(color: AppTheme.subtleBorder(isDark)),
                        const SizedBox(height: 14),
                        Text(
                          "KATEGORİ DAĞILIMI",
                          style: AppTheme.label(isDark).copyWith(
                            color: AppTheme.secondaryText(isDark),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final entry in analysis.counts.entries)
                          _CategoryDistributionRow(
                            label: entry.key,
                            count: entry.value,
                            band: _categoryBand(entry.key, entry.value),
                            isDark: isDark,
                          ),
                        const SizedBox(height: 18),
                        Text(
                          "ANALİZ NOTLARI",
                          style: AppTheme.label(isDark).copyWith(
                            color: AppTheme.secondaryText(isDark),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final insight in analysis.insights)
                          _ActionInsightCard(insight: insight, isDark: isDark),
                        if (analysis.suggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            "EKLENECEK PARÇA ÖNERİSİ",
                            style: AppTheme.label(isDark).copyWith(
                              color: AppTheme.secondaryText(isDark),
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final suggestion in analysis.suggestions)
                            PurchaseSuggestionCard(
                              suggestion: suggestion,
                              isDark: isDark,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClothingCard(WardrobeItem item, bool isDark) {
    final docId = item.id;
    final imageUrl = item.imageUrl.trim();
    final title = item.displayName;
    final category = item.category;
    final color = item.color;
    final bool isBusy = _deletingDocId == docId || _editingDocId == docId;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isBusy ? 0.55 : 1,
      child: GestureDetector(
        onTap: isBusy ? null : () => _openClothingDetail(item),
        onLongPress: isBusy ? null : () => _showEditBottomSheet(item),
        child: Container(
          decoration: AppTheme.panelDecoration(isDark).copyWith(
            color: isDark ? const Color(0xFF16161B) : AppTheme.surface1Light,
            boxShadow: [
              ...AppTheme.cardShadow(isDark),
              if (isDark)
                BoxShadow(
                  color: Colors.white.withOpacity(0.03),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 154,
                  color: isDark
                      ? const Color(0xFF1B1B22)
                      : AppTheme.layer2(false),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.black.withOpacity(0.05),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: imageUrl.isEmpty
                                  ? Icon(
                                      _getCategoryIcon(category),
                                      size: 44,
                                      color: AppTheme.gold(isDark),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.contain,
                                      errorWidget: (_, __, ___) => Icon(
                                        _getCategoryIcon(category),
                                        size: 44,
                                        color: AppTheme.gold(isDark),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: PopupMenuButton<String>(
                          tooltip: '',
                          icon: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.black.withOpacity(0.38)
                                  : Colors.white.withOpacity(0.92),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: isDark
                                  ? Colors.white
                                  : AppTheme.textPrimaryLight,
                              size: 18,
                            ),
                          ),
                          color: AppTheme.card(isDark),
                          onSelected: (value) async {
                            if (value == "edit") {
                              await _showEditBottomSheet(item);
                            } else if (value == "delete") {
                              await _showDeleteBottomSheet(item);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem<String>(
                              value: "edit",
                              child: Text("Düzenle"),
                            ),
                            PopupMenuItem<String>(
                              value: "delete",
                              child: Text("Sil"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(isDark).copyWith(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.primaryText(isDark),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        category.toUpperCase(),
                        style: AppTheme.label(isDark).copyWith(
                          color: AppTheme.gold(isDark),
                          letterSpacing: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (color.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          "Renk: $color",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption(isDark).copyWith(
                            color: AppTheme.secondaryText(isDark),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      body: SafeArea(
        child: AppTheme.auroraBackground(
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.screenPadding,
              20,
              AppTheme.screenPadding,
              0,
            ),
            child: StreamBuilder<List<WardrobeItem>>(
              stream: _wardrobeStream,
              builder: (context, snapshot) {
                final allItems = snapshot.data ?? [];
                final filteredItems = _filterItems(allItems);

                return RefreshIndicator(
                  onRefresh: () async {},
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Dolabım", style: AppTheme.heading1(isDark)),
                            const SizedBox(height: 6),
                            Text(
                              "${allItems.length} parça",
                              style: AppTheme.bodyText(
                                isDark,
                              ).copyWith(color: AppTheme.secondaryText(isDark)),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1F1F25)
                                    : AppTheme.layer2(false),
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusInput,
                                ),
                                border: Border.all(
                                  color: AppTheme.subtleBorder(isDark),
                                ),
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() {
                                    searchQuery = value;
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: "Parça ara",
                                  hintStyle: AppTheme.caption(isDark).copyWith(
                                    color: AppTheme.secondaryText(isDark),
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: AppTheme.secondaryText(isDark),
                                  ),
                                  border: InputBorder.none,
                                  filled: false,
                                ),
                                style: AppTheme.body(
                                  isDark,
                                ).copyWith(color: AppTheme.primaryText(isDark)),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                physics: const BouncingScrollPhysics(),
                                itemCount: categories.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final category = categories[index];
                                  final isSelected =
                                      selectedCategory == category;

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        selectedCategory = category;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        gradient: isSelected
                                            ? AppTheme.themeGoldGradient(isDark)
                                                  as Gradient?
                                            : null,
                                        color: isSelected
                                            ? null
                                            : (isDark
                                                  ? const Color(0xFF191A20)
                                                  : AppTheme.surface1Light),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusPill,
                                        ),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.transparent
                                              : AppTheme.mediumBorder(isDark),
                                        ),
                                      ),
                                      child: Text(
                                        category,
                                        style: AppTheme.body(isDark).copyWith(
                                          color: isSelected
                                              ? AppTheme.textOnGold
                                              : AppTheme.primaryText(
                                                  isDark,
                                                ).withOpacity(0.92),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildWardrobeAnalysisCard(allItems, isDark),
                            const SizedBox(height: 10),
                            _buildGapAnalysisButton(allItems, isDark),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (filteredItems.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              "Bu kategoride kıyafet bulunamadı",
                              style: AppTheme.bodyText(
                                isDark,
                              ).copyWith(color: AppTheme.secondaryText(isDark)),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 120),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.60,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              return _buildClothingCard(
                                    filteredItems[index],
                                    isDark,
                                  )
                                  .animate(delay: (index * 60).ms)
                                  .fadeIn(
                                    duration: 280.ms,
                                    curve: Curves.easeOutCubic,
                                  )
                                  .slideY(begin: 0.1, end: 0);
                            }, childCount: filteredItems.length),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryBand {
  final String label;
  final int score;
  final Color color;

  const _CategoryBand({
    required this.label,
    required this.score,
    required this.color,
  });
}

class _AnalysisHeroCard extends StatelessWidget {
  final WardrobeAnalysis analysis;
  final bool isDark;

  const _AnalysisHeroCard({required this.analysis, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: analysis.score / 100,
                  strokeWidth: 6,
                  backgroundColor: isDark ? Colors.white10 : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    analysis.score >= 75
                        ? const Color(0xFF62C584)
                        : analysis.score >= 50
                        ? const Color(0xFFF0A92E)
                        : const Color(0xFFE95F62),
                  ),
                ),
                Text(
                  "${analysis.score}",
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  analysis.statusTitle,
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  analysis.statusMessage,
                  style: AppTheme.body(isDark).copyWith(
                    color: isDark
                        ? const Color(0xFFE3E4EA)
                        : AppTheme.secondaryText(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisMetricCard extends StatelessWidget {
  final WardrobeMetric metric;
  final bool isDark;

  const _AnalysisMetricCard({required this.metric, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showMetricExplanation(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption(isDark).copyWith(
                      color: isDark
                          ? const Color(0xFFE3E4EA)
                          : AppTheme.secondaryText(isDark),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  "${metric.score}",
                  style: AppTheme.caption(
                    isDark,
                  ).copyWith(color: metric.color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: metric.score / 100,
                minHeight: 4,
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(metric.color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              metric.explanation,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: isDark
                    ? Colors.white.withOpacity(0.45)
                    : Colors.black.withOpacity(0.45),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMetricExplanation(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.28),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
              decoration: AppTheme.panelDecoration(isDark).copyWith(
                color: isDark
                    ? const Color(0xFF1F1F25)
                    : AppTheme.surface1Light,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          metric.label,
                          style: AppTheme.body(isDark).copyWith(
                            color: AppTheme.primaryText(isDark),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        "${metric.score}",
                        style: AppTheme.body(isDark).copyWith(
                          color: metric.color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppTheme.secondaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    metric.detail,
                    style: AppTheme.body(isDark).copyWith(
                      color: isDark
                          ? const Color(0xFFE3E4EA)
                          : AppTheme.secondaryText(isDark),
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryDistributionRow extends StatelessWidget {
  final String label;
  final int count;
  final _CategoryBand band;
  final bool isDark;

  const _CategoryDistributionRow({
    required this.label,
    required this.count,
    required this.band,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = (band.score / 100).clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: AppTheme.caption(isDark).copyWith(
                color: AppTheme.primaryText(isDark),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                backgroundColor: isDark ? Colors.white10 : Colors.black12,
                valueColor: AlwaysStoppedAnimation<Color>(band.color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 24,
            child: Text(
              "$count",
              textAlign: TextAlign.right,
              style: AppTheme.caption(isDark).copyWith(
                color: AppTheme.primaryText(isDark),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              band.label,
              textAlign: TextAlign.right,
              style: AppTheme.caption(isDark).copyWith(
                color: band.color,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionInsightCard extends StatelessWidget {
  final WardrobeInsight insight;
  final bool isDark;

  const _ActionInsightCard({required this.insight, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(insight.icon, color: AppTheme.gold(isDark), size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  insight.message,
                  style: AppTheme.body(isDark).copyWith(
                    color: isDark
                        ? const Color(0xFFE3E4EA)
                        : AppTheme.secondaryText(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.42,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PurchaseSuggestionCard extends StatelessWidget {
  final PurchaseSuggestion suggestion;
  final bool isDark;

  const PurchaseSuggestionCard({
    required this.suggestion,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: suggestion.color.withValues(alpha: isDark ? 0.22 : 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: suggestion.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(suggestion.icon, color: suggestion.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  style: AppTheme.body(isDark).copyWith(
                    color: AppTheme.primaryText(isDark),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion.message,
                  style: AppTheme.body(isDark).copyWith(
                    color: isDark
                        ? const Color(0xFFE3E4EA)
                        : AppTheme.secondaryText(isDark),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.42,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: suggestion.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    suggestion.impact,
                    style: AppTheme.caption(isDark).copyWith(
                      color: suggestion.color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
