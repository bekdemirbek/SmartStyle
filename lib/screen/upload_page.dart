import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../services/clothing_color_analysis_service.dart';
import '../services/cloudinary_service.dart';
import '../widgets/gold_gradient_button.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage>
    with SingleTickerProviderStateMixin {
  XFile? _selectedImage;
  Uint8List? _webImageBytes;
  bool _isUploading = false;
  bool _isAnalyzing = false;
  bool _isAnalyzingColor = false;
  String _userGender = 'unspecified';

  String? _selectedCategory;
  String? _selectedType;
  String? _selectedColor;
  String? _colorAnalysisNote;

  final ImagePicker _picker = ImagePicker();
  final CloudinaryService _cloudinaryService = CloudinaryService();
  final ClothingColorAnalysisService _colorAnalysisService =
      ClothingColorAnalysisService();

  late final AnimationController _successController;
  late final Animation<double> _successScale;

  final List<String> _categories = const [
    "Üst Giyim",
    "Alt Giyim",
    "Dış Giyim",
    "Ayakkabı",
    "Çorap",
  ];

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

  final List<String> _clothingKeywords = const [
    "clothing",
    "apparel",
    "fashion",
    "garment",
    "shirt",
    "t-shirt",
    "top",
    "blouse",
    "sweater",
    "hoodie",
    "jacket",
    "coat",
    "pants",
    "trousers",
    "jeans",
    "shorts",
    "skirt",
    "dress",
    "bodysuit",
    "jumpsuit",
    "shoe",
    "shoes",
    "sneaker",
    "boot",
    "heel",
    "heels",
    "high heel",
    "high heels",
    "sock",
    "socks",
    "tights",
    "pantyhose",
  ];

  @override
  void initState() {
    super.initState();
    _loadUserGender();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _successScale = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );
  }

  Future<void> _loadUserGender() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted) return;
    setState(() {
      _userGender = _genderLabelFromValue(doc.data()?['cinsiyet']);
    });
  }

  String _genderLabelFromValue(Object? value) {
    if (value is bool) return value ? 'male' : 'female';

    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text == 'true' || text == 'erkek' || text == 'male') return 'male';
    if (text == 'false' ||
        text == 'kadın' ||
        text == 'kadin' ||
        text == 'female') {
      return 'female';
    }
    return 'unspecified';
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

  String _getCollectionName(String category) {
    switch (category) {
      case "Üst Giyim":
        return "ust_giyim";
      case "Alt Giyim":
        return "alt_giyim";
      case "Dış Giyim":
        return "dis_giyim";
      case "Ayakkabı":
        return "ayakkabi";
      case "Çorap":
        return "corap";
      default:
        return "kiyafetler";
    }
  }

  Map<String, dynamic> _buildClothingData({
    required User user,
    required String category,
    required String type,
    required String color,
    required String downloadUrl,
  }) {
    final baseData = <String, dynamic>{
      "user_id": user.uid,
      "kategori": category,
      "tur": type,
      "renk": color,
      "image_url": downloadUrl,
      "created_at": FieldValue.serverTimestamp(),
      "use_count": 0,
      "last_used": null,
      "favori": false,
    };

    switch (category) {
      case "Üst Giyim":
        return {
          ...baseData,
          "kumas_turu": "Belirtilmedi",
          "kol_tipi": "Belirtilmedi",
          "yaka_tipi": "Belirtilmedi",
        };
      case "Alt Giyim":
        return {
          ...baseData,
          "kesim_tipi": "Belirtilmedi",
          "bel_tipi": "Belirtilmedi",
          "kumas_turu": "Belirtilmedi",
        };
      case "Dış Giyim":
        return {
          ...baseData,
          "dugmeli_mi": false,
          "fermuarli_mi": false,
          "kumas_turu": "Belirtilmedi",
        };
      case "Ayakkabı":
        return {...baseData, "bagcikli_mi": false};
      case "Çorap":
        return {...baseData, "boy": "Belirtilmedi"};
      default:
        return baseData;
    }
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  List<String> get _availableTypes {
    final category = _selectedCategory;
    if (category == null) return [];

    final types = [...(_categoryTypes[category] ?? const <String>[])];
    if (_userGender == 'female') {
      types.addAll(_femaleCategoryTypeAdditions[category] ?? const <String>[]);
    }
    return types;
  }

  void _showCustomSnackBar({
    required String message,
    required IconData icon,
    required Color backgroundColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: backgroundColor,
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Future<void> _showSuccessDialog() async {
    _successController.reset();
    _successController.forward();

    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ScaleTransition(
            scale: _successScale,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: AppTheme.panelDecoration(_isDark, radius: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppTheme.themeGoldGradient(_isDark) as Gradient?,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      color: _isDark
                          ? AppTheme.backgroundPrimary
                          : AppTheme.textPrimaryLight,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text("Yükleme Başarılı", style: AppTheme.heading2(_isDark)),
                  const SizedBox(height: 8),
                  Text(
                    "Kıyafet gardırobuna başarıyla eklendi.",
                    textAlign: TextAlign.center,
                    style: AppTheme.caption(_isDark),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _selectImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        Uint8List? bytes;
        if (kIsWeb) {
          bytes = await pickedFile.readAsBytes();
        }
        setState(() {
          _selectedImage = pickedFile;
          _webImageBytes = bytes;
          _selectedColor = null;
          _colorAnalysisNote = null;
        });
      }
    } catch (_) {
      _showCustomSnackBar(
        message: "Fotoğraf seçilirken bir sorun oluştu.",
        icon: Icons.error_outline_rounded,
        backgroundColor: Colors.redAccent,
      );
    }
  }

  Future<bool> _isClothingImage() async {
    if (_selectedImage == null) return false;
    if (kIsWeb) return true;

    final inputImage = InputImage.fromFilePath(_selectedImage!.path);
    final imageLabeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.55),
    );

    try {
      final labels = await imageLabeler.processImage(inputImage);
      for (final label in labels) {
        final labelText = label.label.toLowerCase().trim();
        for (final keyword in _clothingKeywords) {
          if (labelText.contains(keyword)) return true;
        }
      }
      return false;
    } finally {
      imageLabeler.close();
    }
  }

  Future<void> _analyzeColorWithGemini() async {
    if (_selectedImage == null) {
      _showCustomSnackBar(
        message: "Renk analizi için önce görsel seçmelisin.",
        icon: Icons.photo_library_outlined,
        backgroundColor: Colors.orangeAccent.shade700,
      );
      return;
    }

    setState(() {
      _isAnalyzingColor = true;
      _colorAnalysisNote = null;
    });

    try {
      final bytes = kIsWeb && _webImageBytes != null
          ? _webImageBytes!
          : await _selectedImage!.readAsBytes();
      final result = await _colorAnalysisService.analyzeColor(
        imageBytes: bytes,
        mimeType:
            _selectedImage!.mimeType ?? _mimeTypeFromPath(_selectedImage!.path),
        category: _selectedCategory,
        type: _selectedType,
      );

      if (!mounted) return;
      setState(() {
        _selectedColor = _colors.contains(result.color)
            ? result.color
            : "Çok Renkli";
        _colorAnalysisNote = result.note.isEmpty
            ? "Gemini ana rengi $_selectedColor olarak tahmin etti."
            : result.note;
      });
    } on ClothingColorAnalysisException {
      if (!mounted) return;
      final bytes = kIsWeb && _webImageBytes != null
          ? _webImageBytes!
          : await _selectedImage!.readAsBytes();
      final fallbackColor = await _estimateColorLocally(bytes);
      if (!mounted) return;
      setState(() {
        _selectedColor = fallbackColor;
        _colorAnalysisNote =
            "Hızlı renk tahmini: $fallbackColor. İstersen manuel düzeltebilirsin.";
      });
      _showCustomSnackBar(
        message: "Hızlı renk tahmini yapıldı. İstersen manuel düzeltebilirsin.",
        icon: Icons.auto_awesome_rounded,
        backgroundColor: AppTheme.gold(_isDark),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isAnalyzingColor = false;
      });
    }
  }

  String _mimeTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<String> _estimateColorLocally(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 72);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return "Çok Renkli";

      final scores = <String, double>{
        for (final color in _colors) color: 0,
      };
      var colorfulPixels = 0;
      var sampledPixels = 0;

      for (var i = 0; i < data.lengthInBytes; i += 16) {
        final r = data.getUint8(i);
        final g = data.getUint8(i + 1);
        final b = data.getUint8(i + 2);
        final a = data.getUint8(i + 3);
        if (a < 180) continue;

        final maxChannel = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minChannel = [r, g, b].reduce((a, b) => a < b ? a : b);
        if (maxChannel > 245 && minChannel > 235) continue;

        sampledPixels++;
        if (maxChannel - minChannel > 55) colorfulPixels++;

        final nearest = _nearestPaletteColor(r, g, b);
        scores[nearest] = (scores[nearest] ?? 0) + 1;
      }

      image.dispose();
      if (sampledPixels == 0) return "Çok Renkli";

      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final best = sorted.first.key;
      final bestRatio = sorted.first.value / sampledPixels;

      if (colorfulPixels / sampledPixels > 0.42 && bestRatio < 0.45) {
        return "Çok Renkli";
      }

      return best;
    } catch (_) {
      return "Çok Renkli";
    }
  }

  String _nearestPaletteColor(int r, int g, int b) {
    final palette = <String, List<int>>{
      "Siyah": [20, 20, 20],
      "Beyaz": [242, 242, 238],
      "Gri": [128, 128, 128],
      "Bej": [216, 196, 162],
      "Krem": [241, 230, 200],
      "Kahverengi": [122, 75, 42],
      "Lacivert": [20, 33, 61],
      "Mavi": [47, 128, 237],
      "Yeşil": [46, 125, 50],
      "Kırmızı": [211, 47, 47],
      "Bordo": [123, 30, 43],
      "Pembe": [232, 138, 181],
      "Mor": [126, 87, 194],
      "Sarı": [242, 201, 76],
      "Turuncu": [242, 153, 74],
      "Haki": [93, 101, 64],
      "Mint": [152, 216, 190],
      "Nude": [224, 178, 150],
      "Vizon": [166, 143, 120],
      "Füme": [70, 74, 78],
      "Altın": [212, 175, 55],
      "Gümüş": [192, 192, 192],
    };

    var bestColor = "Çok Renkli";
    var bestDistance = double.infinity;
    for (final entry in palette.entries) {
      final pr = entry.value[0];
      final pg = entry.value[1];
      final pb = entry.value[2];
      final distance =
          ((r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb))
              .toDouble();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestColor = entry.key;
      }
    }

    return bestColor;
  }

  Future<void> _uploadClothing() async {
    if (_selectedImage == null) {
      _showCustomSnackBar(
        message: "Önce gardırobuna eklemek istediğin görseli seçmelisin.",
        icon: Icons.photo_library_outlined,
        backgroundColor: Colors.orangeAccent.shade700,
      );
      return;
    }
    if (_selectedCategory == null || _selectedType == null) {
      _showCustomSnackBar(
        message: "Kategori ve tür seçmelisin.",
        icon: Icons.category_rounded,
        backgroundColor: Colors.orangeAccent.shade700,
      );
      return;
    }
    if (_selectedColor == null) {
      _showCustomSnackBar(
        message: "Renk seçmelisin. İstersen Gemini ile tahmin ettirebilirsin.",
        icon: Icons.palette_outlined,
        backgroundColor: Colors.orangeAccent.shade700,
      );
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showCustomSnackBar(
        message: "Yükleme yapabilmek için önce giriş yapmalısın.",
        icon: Icons.lock_outline_rounded,
        backgroundColor: Colors.redAccent,
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _isAnalyzing = true;
    });

    try {
      final isClothing = await _isClothingImage();
      setState(() {
        _isAnalyzing = false;
      });
      if (!isClothing) {
        _showCustomSnackBar(
          message: "Bu görsel kıyafet olarak algılanmadı.",
          icon: Icons.search_off_rounded,
          backgroundColor: Colors.redAccent,
        );
        return;
      }

      final downloadUrl = await _cloudinaryService.uploadClothingImage(
        _selectedImage!,
      );
      final collectionName = _getCollectionName(_selectedCategory!);
      final clothingData = _buildClothingData(
        user: user,
        category: _selectedCategory!,
        type: _selectedType!,
        color: _selectedColor!,
        downloadUrl: downloadUrl,
      );
      await FirebaseFirestore.instance.collection(collectionName).add(clothingData);

      if (!mounted) return;
      setState(() {
        _selectedImage = null;
        _webImageBytes = null;
        _selectedCategory = null;
        _selectedType = null;
        _selectedColor = null;
        _colorAnalysisNote = null;
      });
      await _showSuccessDialog();
    } catch (_) {
      if (!mounted) return;
      _showCustomSnackBar(
        message: "Yükleme sırasında bir hata oluştu.",
        icon: Icons.error_outline_rounded,
        backgroundColor: Colors.redAccent,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _isAnalyzing = false;
      });
    }
  }

  Widget _buildImagePreview() {
    if (_selectedImage == null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.file_upload_outlined,
            size: 48,
            color: AppTheme.gold(_isDark),
          ),
          const SizedBox(height: 16),
          Text(
            "Fotoğraf seçilmedi",
            style: AppTheme.heading2(_isDark).copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: AppTheme.primaryText(_isDark),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Gardırobuna eklemek istediğin parçayı seç veya fotoğrafını çek",
            textAlign: TextAlign.center,
            style: AppTheme.body(_isDark).copyWith(
              color: AppTheme.primaryText(_isDark).withOpacity(0.92),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ).animate(onPlay: (c) => c.repeat()).fade(
            begin: 0.75,
            end: 1,
            duration: 2.seconds,
          );
    }

    if (kIsWeb) {
      if (_webImageBytes == null) {
        return Center(
          child: Text(
            "Görsel önizlemesi yüklenemedi",
            style: AppTheme.caption(_isDark),
          ),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusUpload),
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF2B2C35)
                  : const Color(0xFFF4EFE7),
              borderRadius: BorderRadius.circular(AppTheme.radiusUpload),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.memory(
                _webImageBytes!,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusUpload),
      child: SizedBox.expand(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _isDark ? const Color(0xFF2B2C35) : const Color(0xFFF4EFE7),
            borderRadius: BorderRadius.circular(AppTheme.radiusUpload),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Image.file(
              File(_selectedImage!.path),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: _isUploading
          ? null
          : () {
              setState(() {
                _selectedCategory = category;
                _selectedType = null;
                _colorAnalysisNote = null;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          gradient: isSelected ? AppTheme.themeGoldGradient(_isDark) as Gradient? : null,
          color: isSelected ? null : AppTheme.layer3(_isDark),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : AppTheme.subtleBorder(_isDark),
          ),
        ),
        child: Text(
          category,
          style: AppTheme.body(_isDark).copyWith(
            color: isSelected
                ? AppTheme.textOnGold
                : AppTheme.primaryText(_isDark).withOpacity(0.9),
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableActions = _isUploading || _isAnalyzing;
    final disableColorAnalysis = disableActions || _isAnalyzingColor;

    return Scaffold(
      backgroundColor: AppTheme.bg(_isDark),
      body: SafeArea(
        child: AppTheme.auroraBackground(
          isDark: _isDark,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.screenPadding,
              20,
              AppTheme.screenPadding,
              110,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Yeni Parça Ekle", style: AppTheme.heading1(_isDark)),
                const SizedBox(height: 6),
                Text(
                  "Gardırobuna yeni kıyafet yükle",
                  style: AppTheme.bodyText(_isDark).copyWith(
                    color: AppTheme.primaryText(_isDark).withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 26),
                Container(
                  width: double.infinity,
                  height: _selectedImage == null ? 236 : 214,
                  decoration: BoxDecoration(
                    color: _isDark ? const Color(0xFF1D1D23) : AppTheme.layer2(false),
                    borderRadius: BorderRadius.circular(AppTheme.radiusUpload),
                    border: Border.all(
                      color: AppTheme.gold(_isDark),
                      width: 1.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(child: _buildImagePreview()),
                      if (_selectedImage != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedImage = null;
                                _webImageBytes = null;
                                _selectedColor = null;
                                _colorAnalysisNote = null;
                              });
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.45),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _isDark
                        ? const Color(0xFF26262E)
                        : AppTheme.layer2(false),
                    borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                    border: Border.all(color: AppTheme.mediumBorder(_isDark)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.tips_and_updates_outlined,
                        color: AppTheme.gold(_isDark),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Kıyafeti düz zeminde, net ışıkta ve mümkünse tek parça olacak şekilde yükle.",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.captionText(_isDark).copyWith(
                            color: AppTheme.primaryText(_isDark).withOpacity(0.97),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  "Kategori",
                  style: AppTheme.sectionTitle(_isDark),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _categories.map(_buildCategoryChip).toList(),
                ),
                const SizedBox(height: 16),
                if (_selectedCategory != null)
                  Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: _isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
                      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                      border: Border.all(color: AppTheme.subtleBorder(_isDark)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedType,
                        isExpanded: true,
                        dropdownColor: AppTheme.card(_isDark),
                        hint: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            "Parça seç",
                            style: AppTheme.body(_isDark).copyWith(
                              color: AppTheme.secondaryText(_isDark),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        items: _availableTypes
                            .map((type) => DropdownMenuItem<String>(
                                  value: type,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    child: Text(
                                      type,
                                      style: AppTheme.body(_isDark).copyWith(
                                        color: AppTheme.primaryText(_isDark),
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                        onChanged: disableActions
                            ? null
                            : (value) {
                                setState(() {
                                  _selectedType = value;
                                  _colorAnalysisNote = null;
                                });
                              },
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  "Renk",
                  style: AppTheme.sectionTitle(_isDark),
                ),
                const SizedBox(height: 12),
                _buildColorPicker(disableActions),
                const SizedBox(height: 10),
                _buildGeminiColorButton(disableColorAnalysis),
                if (_colorAnalysisNote != null) ...[
                  const SizedBox(height: 10),
                  _buildColorAnalysisNote(),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: disableActions
                            ? null
                            : () => _selectImage(ImageSource.gallery),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(
                            color: AppTheme.gold(_isDark).withOpacity(_isDark ? 0.7 : 0.55),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                          ),
                          foregroundColor: AppTheme.primaryText(_isDark),
                          textStyle: AppTheme.body(_isDark).copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        icon: const Icon(Icons.photo_library_outlined, size: 18),
                        label: const Text("Galeriden Seç"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: disableActions
                            ? null
                            : () => _selectImage(ImageSource.camera),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(
                            color: AppTheme.gold(_isDark).withOpacity(_isDark ? 0.7 : 0.55),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                          ),
                          foregroundColor: AppTheme.primaryText(_isDark),
                          textStyle: AppTheme.body(_isDark).copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text("Fotoğraf Çek"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GoldGradientButton(
                  label: _isUploading ? "Yükleniyor..." : "Gardırobuma Yükle",
                  expanded: true,
                  leading: Icon(
                    Icons.upload_rounded,
                    color: AppTheme.backgroundPrimary,
                  ),
                  onTap: disableActions || _isAnalyzingColor
                      ? null
                      : _uploadClothing,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker(bool disabled) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1F1F25) : AppTheme.layer2(false),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        border: Border.all(color: AppTheme.subtleBorder(_isDark)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedColor,
          isExpanded: true,
          dropdownColor: AppTheme.card(_isDark),
          hint: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              "Renk seç",
              style: AppTheme.body(_isDark).copyWith(
                color: AppTheme.secondaryText(_isDark),
                fontSize: 14,
              ),
            ),
          ),
          items: _colors
              .map(
                (color) => DropdownMenuItem<String>(
                  value: color,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        _ColorSwatch(colorName: color),
                        const SizedBox(width: 10),
                        Text(
                          color,
                          style: AppTheme.body(_isDark).copyWith(
                            color: AppTheme.primaryText(_isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: disabled
              ? null
              : (value) {
                  setState(() {
                    _selectedColor = value;
                    _colorAnalysisNote = null;
                  });
                },
        ),
      ),
    );
  }

  Widget _buildGeminiColorButton(bool disabled) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: disabled ? null : _analyzeColorWithGemini,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(
            color: AppTheme.gold(_isDark).withOpacity(_isDark ? 0.7 : 0.55),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          ),
          foregroundColor: AppTheme.primaryText(_isDark),
        ),
        icon: _isAnalyzingColor
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.gold(_isDark),
                ),
              )
            : const Icon(Icons.auto_awesome_rounded, size: 18),
        label: Text(
          _isAnalyzingColor ? "Gemini analiz ediyor..." : "Gemini ile Renk Tahmin Et",
        ),
      ),
    );
  }

  Widget _buildColorAnalysisNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gold(_isDark).withOpacity(_isDark ? 0.12 : 0.16),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.gold(_isDark).withOpacity(0.28),
        ),
      ),
      child: Text(
        _colorAnalysisNote!,
        style: AppTheme.caption(_isDark).copyWith(
          color: AppTheme.primaryText(_isDark).withOpacity(0.9),
          height: 1.4,
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String colorName;

  const _ColorSwatch({required this.colorName});

  @override
  Widget build(BuildContext context) {
    if (colorName.contains("-")) {
      final parts = colorName.split("-");
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: parts.map(_colorForName).toList(),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.45)),
        ),
      );
    }

    if (colorName == "Çok Renkli") {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Colors.red,
              Colors.orange,
              Colors.yellow,
              Colors.green,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.45)),
        ),
      );
    }

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: _colorForName(colorName),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.45)),
      ),
    );
  }

  Color _colorForName(String name) {
    switch (name) {
      case "Siyah":
        return const Color(0xFF111111);
      case "Beyaz":
        return const Color(0xFFF8F8F8);
      case "Gri":
        return const Color(0xFF8A8A8A);
      case "Bej":
        return const Color(0xFFD8C4A2);
      case "Krem":
        return const Color(0xFFF1E6C8);
      case "Kahverengi":
        return const Color(0xFF7A4B2A);
      case "Lacivert":
        return const Color(0xFF14213D);
      case "Mavi":
        return const Color(0xFF2F80ED);
      case "Yeşil":
        return const Color(0xFF2E7D32);
      case "Kırmızı":
        return const Color(0xFFD32F2F);
      case "Bordo":
        return const Color(0xFF7B1E2B);
      case "Pembe":
        return const Color(0xFFE88AB5);
      case "Mor":
        return const Color(0xFF7E57C2);
      case "Sarı":
        return const Color(0xFFF2C94C);
      case "Turuncu":
        return const Color(0xFFF2994A);
      case "Haki":
        return const Color(0xFF5D6540);
      case "Mint":
        return const Color(0xFF98D8BE);
      case "Nude":
        return const Color(0xFFE0B296);
      case "Vizon":
        return const Color(0xFFA68F78);
      case "Füme":
        return const Color(0xFF464A4E);
      case "Altın":
        return const Color(0xFFD4AF37);
      case "Gümüş":
        return const Color(0xFFC0C0C0);
      default:
        return const Color(0xFFBDBDBD);
    }
  }
}
