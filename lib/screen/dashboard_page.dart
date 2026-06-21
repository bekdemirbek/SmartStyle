import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import '../models/outfit_ai_models.dart';
import '../models/saved_outfit_model.dart';
import '../models/wardrobe_item_model.dart';
import '../services/weather_service.dart';
import '../models/outfit_recommendation_models.dart';
import '../services/outfit_ai_service.dart';
import '../services/outfit_reason_service.dart';
import '../services/outfit_recommendation_service.dart';
import '../services/saved_outfit_service.dart';
import '../services/wardrobe_item_service.dart';
import '../widgets/gold_gradient_button.dart';
import '../widgets/outfit_collage_card.dart';
import '../widgets/outfit_reason_sheet.dart';
import '../widgets/replace_piece_sheet.dart';
import '../widgets/weather_pill.dart';
import '../app_theme.dart';
import 'outfit_detail_page.dart';
import 'travel_mode_page.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  static const String _logoAsset = 'assets/images/smartstyle_logo.png';

  WeatherData? _weatherData;
  List<WeatherForecastDay> _dailyForecast = const [];
  bool _isLoadingWeather = true;
  bool _isGeneratingRecommendations = false;
  String? _weatherError;
  List<_RecommendationDaySlot> _recommendationSlots = [];
  WeeklyStylePreference? _activeStylePreference;
  Map<DateTime, DayPlan> _activeDayPlans = {};
  Map<DateTime, WeatherProfile> _activeWeatherByDate = {};
  bool _isOpeningRecommendationDetail = false;
  bool _lastRecommendationUsedLocalFallback = false;

  final OutfitRecommendationService _recommendationService =
      OutfitRecommendationService();
  final OutfitAiService _outfitAiService = OutfitAiService();
  final OutfitReasonService _outfitReasonService = OutfitReasonService();
  final SavedOutfitService _savedOutfitService = SavedOutfitService();
  final WardrobeItemService _wardrobeItemService = WardrobeItemService();

  static const double _fallbackLat = 41.0082;
  static const double _fallbackLon = 28.9784;

  static const List<Map<String, String>> _maleWeeklyOutfits = [
    {
      "day": "Pazartesi",
      "image":
          "https://images.unsplash.com/photo-1516826957135-700dedea698c?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Salı",
      "image":
          "https://images.unsplash.com/photo-1520975661595-6453be3f7070?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Çarşamba",
      "image":
          "https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Perşembe",
      "image":
          "https://images.unsplash.com/photo-1516257984-b1b4d707412e?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Cuma",
      "image":
          "https://images.pexels.com/photos/1043474/pexels-photo-1043474.jpeg",
    },
    {
      "day": "Cumartesi",
      "image":
          "https://images.unsplash.com/photo-1520975916090-3105956dac38?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Pazar",
      "image":
          "https://images.unsplash.com/photo-1487222477894-8943e31ef7b2?auto=format&fit=crop&w=800&q=80",
    },
  ];

  static const List<Map<String, String>> _femaleWeeklyOutfits = [
    {
      "day": "Pazartesi",
      "image":
          "https://images.unsplash.com/photo-1487412720507-e7ab37603c6f?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Salı",
      "image":
          "https://images.unsplash.com/photo-1496747611176-843222e1e57c?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Çarşamba",
      "image":
          "https://images.unsplash.com/photo-1485968579580-b6d095142e6e?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Perşembe",
      "image":
          "https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Cuma",
      "image":
          "https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Cumartesi",
      "image":
          "https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80",
    },
    {
      "day": "Pazar",
      "image":
          "https://images.unsplash.com/photo-1529626455594-4ff0802cfb7e?auto=format&fit=crop&w=800&q=80",
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadWeather();
    _loadSavedRecommendationSlots();
  }

  Future<void> _loadSavedRecommendationSlots() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final savedOutfits = await _savedOutfitService.fetchUserOutfits(
        userId: user.uid,
        weekId: buildWeekId(DateTime.now()),
        limit: 20,
      );
      final aiOutfits = savedOutfits
          .where((outfit) =>
              outfit.creationType == 'ai_recommendation' ||
              outfit.creationType == 'weekly_recommendation')
          .toList();
      if (aiOutfits.isEmpty) return;

      final slots = _slotsFromSavedOutfits(aiOutfits);
      if (!mounted || slots.every((slot) => !slot.hasRecommendation)) return;
      final favoriteOutfits = await _savedOutfitService.fetchFavoriteOutfits(
        userId: user.uid,
      );
      final favoriteIds = favoriteOutfits.map((outfit) => outfit.id).toSet();
      final slotsWithFavorites = _slotsWithFavoriteState(slots, favoriteIds);

      setState(() {
        _recommendationSlots = slotsWithFavorites;
        _activeStylePreference = _stylePreferenceFromSavedOutfits(aiOutfits);
        _activeDayPlans = {
          for (final slot in slotsWithFavorites)
            slot.date: DayPlan(date: slot.date, type: slot.planType),
        };
        _activeWeatherByDate = {
          for (final slot in slotsWithFavorites) slot.date: slot.weather,
        };
      });
    } catch (e) {
      debugPrint("LOAD SAVED RECOMMENDATIONS ERROR: $e");
    }
  }

  Future<void> _loadWeather() async {
    try {
      setState(() {
        _isLoadingWeather = true;
        _weatherError = null;
      });

      final position = await _getUserPositionOrFallback();

      debugPrint("FINAL LAT: ${position.latitude}");
      debugPrint("FINAL LON: ${position.longitude}");

      final weather = await WeatherService.getWeather(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      final dailyForecast = await WeatherService.getDailyForecast(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _weatherData = weather;
        _dailyForecast = dailyForecast;
        _isLoadingWeather = false;
      });
    } catch (e) {
      debugPrint("LOAD WEATHER ERROR: $e");

      if (!mounted) return;

      setState(() {
        _weatherError = e.toString();
        _isLoadingWeather = false;
      });
    }
  }

  Future<Position> _getUserPositionOrFallback() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return _fallbackPosition();
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallbackPosition();
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return position;
    } catch (e) {
      return _fallbackPosition();
    }
  }

  Position _fallbackPosition() {
    return Position(
      longitude: _fallbackLon,
      latitude: _fallbackLat,
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email ?? "Kullanıcı";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = AppTheme.bg(isDark);
    final titleColor = AppTheme.primaryText(isDark);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: AppTheme.auroraBackground(
          isDark: isDark,
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 145),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(name, isDark),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.screenPadding,
                      ),
                      child: Text(
                        "HAFTALIK KOMBİNLER",
                        style: AppTheme.screenTitle(isDark).copyWith(
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.screenPadding,
                      ),
                      child: Text(
                        "Senin stiline uygun günlük kombin önerileri",
                        style: AppTheme.caption(isDark).copyWith(
                          color: AppTheme.primaryText(isDark).withOpacity(0.82),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: user == null
                          ? null
                          : FirebaseFirestore.instance
                              .collection("users")
                              .doc(user.uid)
                              .snapshots(),
                      builder: (context, snapshot) {
                        final userGender = _genderLabelFromValue(
                          snapshot.data?.data()?['cinsiyet'],
                        );
                        final placeholderOutfits =
                            _placeholderWeeklyOutfits(userGender);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _recommendationSlots.isEmpty
                                ? placeholderOutfits.length
                                : _recommendationSlots.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 0.72,
                                ),
                            itemBuilder: (context, index) {
                              if (_recommendationSlots.isNotEmpty) {
                                final slot = _recommendationSlots[index];
                                return _buildRecommendationSlotCard(
                                  slot: slot,
                                  isDark: isDark,
                                  isHighlighted: index == 0,
                                  onTap: slot.hasRecommendation
                                      ? () => _openRecommendationDetail(index)
                                      : null,
                                ).animate(delay: (index * 60).ms).fadeIn(
                                      duration: 280.ms,
                                      curve: Curves.easeOutCubic,
                                    ).slideY(begin: 0.1, end: 0);
                              }

                              final item = placeholderOutfits[index];
                              return _buildOutfitCard(
                                day: item["day"]!,
                                image: item["image"]!,
                                isDark: isDark,
                                isHighlighted: index == 0,
                              ).animate(delay: (index * 60).ms).fadeIn(
                                    duration: 280.ms,
                                    curve: Curves.easeOutCubic,
                                  ).slideY(begin: 0.1, end: 0);
                            },
                          ),
                        );
                      },
                      ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: AppTheme.frosted(
                  isDark: isDark,
                  radius: 16,
                  padding: const EdgeInsets.all(10),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            gradient:
                                AppTheme.themeGoldGradient(isDark) as Gradient?,
                            shape: BoxShape.circle,
                          ),
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                _logoAsset,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "Özel kombin oluştur",
                            style: AppTheme.body(isDark).copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GoldGradientButton(
                          label: "Öneri Al",
                          height: 40,
                          onTap: _isGeneratingRecommendations
                              ? null
                              : _startRecommendationFlow,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTravelModePage() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TravelModePage()),
    );
  }

  Future<void> _startRecommendationFlow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar("Öneri almak için giriş yapmalısın.", isError: true);
      return;
    }

    final input = await _showRecommendationFlowSheet();
    if (input == null) return;

    setState(() {
      _isGeneratingRecommendations = true;
      _recommendationSlots = [];
      _activeStylePreference = input.stylePreference;
      _activeDayPlans = input.dayPlans;
    });

    try {
      final wardrobe = await _recommendationService.fetchWardrobeItems(
        user.uid,
      );
      final userGender = await _fetchUserGender(user.uid);

      if (wardrobe.isEmpty) {
        _showSnackBar(
          "Dolabında henüz kıyafet yok. Bir parça eklediğinde öneri hazırlayabilirim.",
          isError: true,
        );
        return;
      }

      final weatherByDate = _weatherProfilesForWeek();
      _activeWeatherByDate = weatherByDate;
      final aiRequest = _buildAiSuggestionRequest(
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: input.stylePreference,
        dayPlans: input.dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: input.requestedDayIndexes,
      );
      final slots = await _resolveRecommendationSlots(
        aiRequest: aiRequest,
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: input.stylePreference,
        dayPlans: input.dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: input.requestedDayIndexes,
        debugContext: 'AI RESPONSE FALLBACK',
      );
      final recommendations = slots
          .map((slot) => slot.recommendation)
          .whereType<OutfitRecommendation>()
          .toList();

      if (recommendations.isEmpty) {
        _showSnackBar(
          input.requestedDayIndexes.isEmpty
              ? "En az bir gün seçmelisin."
              : "AI uygun bir kombin oluşturamadı. Dolabına üst, alt ve ayakkabı eklemeyi dene.",
          isError: true,
        );
        setState(() => _recommendationSlots = slots);
        return;
      }

      try {
        final outfitIds = await _savedOutfitService.saveWeeklyOutfits(
          userId: user.uid,
          stylePreference: input.stylePreference,
          recommendations: recommendations,
        );

        if (!mounted) return;

        setState(() {
          _recommendationSlots = _slotsWithSavedIds(slots, outfitIds);
        });

        _showSnackBar(
          _lastRecommendationUsedLocalFallback
              ? "AI limiti dolduğu için yerel kombin önerileri hazırlandı ve kaydedildi."
              : "Haftalık kombin önerilerin hazır ve kaydedildi.",
          isError: false,
        );
      } on FirebaseException catch (e) {
        if (!mounted) return;
        setState(() {
          _recommendationSlots = slots;
        });
        final message = e.code == 'permission-denied'
            ? "Kombin hazır, ama Firestore izni yok: kombinler rules kontrol edilmeli."
            : "Kombin hazır, ama kayıt hatası: ${e.code}";
        _showSnackBar(message, isError: true);
        debugPrint("SAVE RECOMMENDATIONS FIREBASE ERROR: ${e.code} ${e.message}");
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _recommendationSlots = slots;
        });
        _showSnackBar(
          "Kombinlerin hazır, ama Firestore'a kaydedilemedi.",
          isError: true,
        );
        debugPrint("SAVE RECOMMENDATIONS ERROR: $e");
      }
    } catch (e) {
      if (!mounted) return;
      final message = e is OutfitAiException
          ? e.message
          : "Öneri hazırlanamadı. Lütfen dolabındaki kıyafetleri tekrar kontrol et.";
      _showSnackBar(message, isError: true);
      debugPrint("RECOMMENDATION ERROR: $e");
    } finally {
      if (!mounted) return;
      setState(() {
        _isGeneratingRecommendations = false;
      });
    }
  }

  Future<_RecommendationFlowInput?> _showRecommendationFlowSheet() {
    var primary = StylePreference.casual;
    var secondary = StylePreference.street;
    var tertiary = StylePreference.special;
    final planSelections = <int, DayPlanType>{
      for (var i = 0; i < 7; i++) i: DayPlanType.normalDay,
    };
    final requestedDayIndexes = <int>{for (var i = 0; i < 7; i++) i};

    return showModalBottomSheet<_RecommendationFlowInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.88,
              minChildSize: 0.55,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFF111111),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    children: [
                      const Text(
                        "HAFTALIK PLAN",
                        style: TextStyle(
                          color: Color(0xFFC8A84B),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Hangi günler için kombin\noluşturalım?",
                        style: AppTheme.screenTitle(true).copyWith(
                          color: Colors.white,
                          fontSize: 24,
                          height: 1.08,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Seçmediğin günler haftalık ekranda boş kalır.",
                        style: TextStyle(
                          color: Color(0xFF747474),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 26),
                      for (var i = 0; i < 7; i++) ...[
                        _buildWeeklyPlanDayCard(
                          index: i,
                          planType: planSelections[i] ?? DayPlanType.normalDay,
                          isSelected: requestedDayIndexes.contains(i),
                          onSelectedChanged: (value) {
                            setSheetState(() {
                              if (value) {
                                requestedDayIndexes.add(i);
                              } else {
                                requestedDayIndexes.remove(i);
                              }
                            });
                          },
                          onPlanChanged: (value) {
                            setSheetState(() => planSelections[i] = value);
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          final dayPlans = <DateTime, DayPlan>{};

                          for (final entry in planSelections.entries) {
                            final date = _dateForRecommendationIndex(entry.key);
                            dayPlans[date] = DayPlan(
                              date: date,
                              type: entry.value,
                            );
                          }

                          Navigator.pop(
                            context,
                            _RecommendationFlowInput(
                              stylePreference: WeeklyStylePreference(
                                primary: primary,
                                secondary: secondary,
                                tertiary: tertiary,
                              ),
                              dayPlans: dayPlans,
                              requestedDayIndexes: requestedDayIndexes,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC8A84B),
                          foregroundColor: const Color(0xFF111111),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          "Önerileri Oluştur",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWeeklyPlanDayCard({
    required int index,
    required DayPlanType planType,
    required bool isSelected,
    required ValueChanged<bool> onSelectedChanged,
    required ValueChanged<DayPlanType> onPlanChanged,
  }) {
    const gold = Color(0xFFC8A84B);
    final planOptions = const [
      DayPlanType.normalDay,
      DayPlanType.office,
      DayPlanType.date,
      DayPlanType.gym,
      DayPlanType.dinner,
      DayPlanType.travel,
      DayPlanType.specialEvent,
    ];
    final cardColor = isSelected ? const Color(0xFF15120D) : const Color(0xFF1A1A1A);
    final borderColor = isSelected ? gold.withOpacity(0.32) : const Color(0xFF252525);
    final primaryText = isSelected ? Colors.white : const Color(0xFF555555);
    final secondaryText = isSelected ? const Color(0xFF9E7D23) : const Color(0xFF454545);
    final badgeColor = isSelected ? gold : const Color(0xFF242424);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: isSelected ? 1 : 0.58,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _dayShortLabel(index),
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF111111) : const Color(0xFF555555),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dayLabel(index),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSelected ? _planLabel(planType) : "Seçilmedi",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.82,
                  child: Switch(
                    value: isSelected,
                    activeColor: const Color(0xFF111111),
                    activeTrackColor: gold,
                    inactiveThumbColor: const Color(0xFF6C6C6C),
                    inactiveTrackColor: const Color(0xFF2C2C2C),
                    onChanged: onSelectedChanged,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final option in planOptions) ...[
                  _WeeklyPlanChip(
                    label: _planLabel(option),
                    isEnabled: isSelected,
                    isSelected: planType == option,
                    onTap: () => onPlanChanged(option),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dayShortLabel(int index) {
    switch (index) {
      case 0:
        return "Pzt";
      case 1:
        return "Sal";
      case 2:
        return "Çar";
      case 3:
        return "Per";
      case 4:
        return "Cum";
      case 5:
        return "Cmt";
      case 6:
        return "Paz";
      default:
        return "";
    }
  }

  OutfitSuggestionRequest _buildAiSuggestionRequest({
    required List<ClothingItem> wardrobe,
    required String userGender,
    required WeeklyStylePreference stylePreference,
    required Map<DateTime, DayPlan> dayPlans,
    required Map<DateTime, WeatherProfile> weatherByDate,
    required Set<int> requestedDayIndexes,
    String planType = 'weekly',
    String refreshType = 'none',
    String? replaceItem,
    String? replaceIntent,
    Map<String, dynamic>? currentOutfit,
  }) {
    return OutfitSuggestionRequest(
      planType: planType,
      userGender: userGender,
      stylePriority: [
        _styleLabel(stylePreference.primary),
        _styleLabel(stylePreference.secondary),
        _styleLabel(stylePreference.tertiary),
      ],
      days: [
        for (var i = 0; i < 7; i++)
          RequestedDay(
            day: _englishDayName(_dateForRecommendationIndex(i)),
            event: _planEventLabel(
              dayPlans[_dateForRecommendationIndex(i)]?.type ??
                  DayPlanType.normalDay,
            ),
            requested: requestedDayIndexes.contains(i),
          ),
      ],
      wardrobe: wardrobe.map(_aiWardrobeItemFromClothingItem).toList(),
      weather: {
        for (final entry in weatherByDate.entries)
          _englishDayName(entry.key): WeatherInfo(
            temp: entry.value.temperatureC,
            condition: _weatherConditionLabel(entry.value.condition),
          ),
      },
      refreshType: refreshType,
      replaceItem: replaceItem,
      replaceIntent: replaceIntent,
      currentOutfit: currentOutfit,
    );
  }

  AiWardrobeItem _aiWardrobeItemFromClothingItem(ClothingItem item) {
    return AiWardrobeItem(
      id: item.id,
      category: _aiCategoryLabel(item.category),
      name: item.subCategory.trim().isEmpty ? item.id : item.subCategory,
      color: item.color,
      season: item.seasons.map(_seasonLabel).toList(),
      style: item.styles.map(_styleLabel).toList(),
      // Most existing uploads do not have fabric metadata yet. Sending a safe
      // fallback keeps the backend prompt useful without blocking AI styling.
      fabric: (item.rawData['kumas'] ?? item.rawData['fabric'] ?? 'unknown')
          .toString(),
    );
  }

  List<_RecommendationDaySlot> _slotsFromAiResponse({
    required OutfitSuggestionResponse aiResponse,
    required List<ClothingItem> wardrobe,
    required WeeklyStylePreference stylePreference,
    required Map<DateTime, DayPlan> dayPlans,
    required Map<DateTime, WeatherProfile> weatherByDate,
    required Set<int> requestedDayIndexes,
  }) {
    final byDay = {
      for (final day in aiResponse.days) day.day.toLowerCase(): day,
    };
    final slots = <_RecommendationDaySlot>[];
    for (var i = 0; i < 7; i++) {
      final date = _dateForRecommendationIndex(i);
      final dateOnly = date;
      final planType = dayPlans[dateOnly]?.type ?? DayPlanType.normalDay;
      final weather = weatherByDate[dateOnly] ??
          WeatherProfile(
            date: date,
            temperatureC: 18,
            condition: WeatherCondition.unknown,
          );
      final isRequested = requestedDayIndexes.contains(i);

      if (!isRequested) {
        slots.add(
          _RecommendationDaySlot(
            index: i,
            date: dateOnly,
            requested: false,
            planType: planType,
            weather: weather,
            message: "Bugün için kombin önerisi yazılmadı.",
          ),
        );
        continue;
      }

      final styledDay = byDay[_englishDayName(date).toLowerCase()];
      if (styledDay == null || !styledDay.isStyled) {
        slots.add(
          _RecommendationDaySlot(
            index: i,
            date: dateOnly,
            requested: true,
            planType: planType,
            weather: weather,
            message: styledDay?.message ??
                "Bu gün için uygun bir kombin hazırlanamadı.",
          ),
        );
        continue;
      }

      final recommendation = _recommendationFromStyledDay(
        styledDay: styledDay,
        date: date,
        wardrobe: wardrobe,
        stylePreference: stylePreference,
        planType: planType,
        weather: weather,
      );

      slots.add(
        _RecommendationDaySlot(
          index: i,
          date: dateOnly,
          requested: true,
          planType: planType,
          weather: weather,
          recommendation: recommendation,
          canFavorite: styledDay.canFavorite,
          message: recommendation == null
              ? "Bu gün için uygun bir kombin hazırlanamadı."
              : styledDay.message,
        ),
      );
    }

    return slots;
  }

  List<_RecommendationDaySlot> _slotsFromLocalRecommendations({
    required List<ClothingItem> wardrobe,
    required String userGender,
    required WeeklyStylePreference stylePreference,
    required Map<DateTime, DayPlan> dayPlans,
    required Map<DateTime, WeatherProfile> weatherByDate,
    required Set<int> requestedDayIndexes,
    String refreshType = 'none',
    String? replaceItem,
    String? replaceIntent,
    OutfitRecommendation? currentRecommendation,
  }) {
    final recommendations = _recommendationService.generateWeeklyRecommendations(
      wardrobe: wardrobe,
      userGender: userGender,
      stylePreference: stylePreference,
      dayPlans: dayPlans,
      weatherByDate: weatherByDate,
      weekStart: _dateForRecommendationIndex(0),
    );
    final localRecommendations = [...recommendations];
    if (refreshType == 'replace_item' &&
        replaceItem != null &&
        currentRecommendation != null &&
        requestedDayIndexes.isNotEmpty) {
      final index = requestedDayIndexes.first;
      if (index >= 0 && index < localRecommendations.length) {
        localRecommendations[index] = _replacePieceLocally(
          currentRecommendation,
          wardrobe,
          replaceItem,
          replaceIntent,
          userGender,
        );
      }
    }

    return [
      for (var i = 0; i < 7; i++)
        if (!requestedDayIndexes.contains(i))
          _RecommendationDaySlot(
            index: i,
            date: _dateForRecommendationIndex(i),
            requested: false,
            planType: dayPlans[_dateForRecommendationIndex(i)]?.type ??
                DayPlanType.normalDay,
            weather: weatherByDate[_dateForRecommendationIndex(i)] ??
                WeatherProfile(
                  date: _dateForRecommendationIndex(i),
                  temperatureC: 18,
                  condition: WeatherCondition.unknown,
                ),
            message: "Bugün için kombin önerisi yazılmadı.",
          )
        else
          _RecommendationDaySlot(
            index: i,
            date: _dateForRecommendationIndex(i),
            requested: true,
            planType: localRecommendations[i].planType,
            weather: localRecommendations[i].weather,
            recommendation: localRecommendations[i],
            canFavorite: true,
            message:
                "AI cevabında eksik parça vardı; dolabından güvenli bir kombin hazırlandı.",
          ),
    ];
  }

  List<_RecommendationDaySlot> _slotsWithSavedIds(
    List<_RecommendationDaySlot> slots,
    List<String> outfitIds,
  ) {
    var generatedIndex = 0;

    return [
      for (final slot in slots)
        if (!slot.hasRecommendation)
          slot
        else
          slot.copyWith(
            outfitId: generatedIndex < outfitIds.length
                ? outfitIds[generatedIndex++]
                : '',
          ),
    ];
  }

  List<_RecommendationDaySlot> _slotsWithFavoriteState(
    List<_RecommendationDaySlot> slots,
    Set<String> favoriteIds,
  ) {
    return [
      for (final slot in slots)
        if (slot.recommendation == null)
          slot
        else
          slot.copyWith(
            favoriteId: _savedOutfitService.favoriteIdForRecommendation(
              slot.recommendation!,
            ),
            isFavorite: favoriteIds.contains(
              _savedOutfitService.favoriteIdForRecommendation(
                slot.recommendation!,
              ),
            ),
          ),
    ];
  }

  List<_RecommendationDaySlot> _slotsFromSavedOutfits(
    List<SavedOutfit> savedOutfits,
  ) {
    final byDay = {
      for (final outfit in savedOutfits)
        _normalize(outfit.day): outfit,
    };

    return [
      for (var i = 0; i < 7; i++)
        _slotFromSavedOutfit(
          index: i,
          date: _dateForRecommendationIndex(i),
          outfit: byDay[_normalize(_dayName(_dateForRecommendationIndex(i)))],
        ),
    ];
  }

  _RecommendationDaySlot _slotFromSavedOutfit({
    required int index,
    required DateTime date,
    required SavedOutfit? outfit,
  }) {
    final weather = _weatherProfileFromSavedOutfit(date, outfit);
    final planType = _dayPlanFromLabel(outfit?.dailyPlan ?? '');

    if (outfit == null) {
      return _RecommendationDaySlot(
        index: index,
        date: _dateOnly(date),
        requested: false,
        planType: planType,
        weather: weather,
        message: "Bugün için kombin önerisi yazılmadı.",
      );
    }

    return _RecommendationDaySlot(
      index: index,
      date: _dateOnly(date),
      requested: true,
      planType: planType,
      weather: weather,
      recommendation: _recommendationFromSavedOutfit(outfit, date),
      outfitId: outfit.id,
      canFavorite: true,
      isFavorite: outfit.favorite,
    );
  }

  OutfitRecommendation? _recommendationFromSavedOutfit(
    SavedOutfit outfit,
    DateTime date,
  ) {
    final top = _clothingItemFromSavedPiece(outfit.pieces, ClothingCategory.top);
    var bottom =
        _clothingItemFromSavedPiece(outfit.pieces, ClothingCategory.bottom);
    final shoes =
        _clothingItemFromSavedPiece(outfit.pieces, ClothingCategory.shoes);

    if (top != null && bottom == null && _isOnePiece(top)) {
      bottom = top;
    }

    if (top == null || bottom == null || shoes == null) return null;

    final outerwear =
        _clothingItemFromSavedPiece(outfit.pieces, ClothingCategory.outerwear);
    final socks = _clothingItemFromSavedPiece(outfit.pieces, ClothingCategory.socks);
    final planType = _dayPlanFromLabel(outfit.dailyPlan);
    final focusStyle = _styleFromAiLabel(outfit.primaryStyle) ??
        _styleFromAiLabel(outfit.secondaryStyle) ??
        StylePreference.casual;

    return OutfitRecommendation(
      date: _dateOnly(date),
      day: _dayName(date),
      style: outfit.primaryStyle.isEmpty ? _styleLabel(focusStyle) : outfit.primaryStyle,
      description: outfit.description,
      focusStyle: focusStyle,
      planType: planType,
      weather: _weatherProfileFromSavedOutfit(date, outfit),
      top: top,
      bottom: bottom,
      shoes: shoes,
      outerwear: outerwear,
      socks: socks,
      score: outfit.score,
      notes: const [],
    );
  }

  ClothingItem? _clothingItemFromSavedPiece(
    List<SavedOutfitPiece> pieces,
    ClothingCategory category,
  ) {
    for (final piece in pieces) {
      if (_categoryFromSavedPiece(piece) == category &&
          _savedPieceLooksLikeCategory(piece, category)) {
        return ClothingItem(
          id: piece.itemId,
          collection: piece.collection,
          userId: '',
          imageUrl: piece.imageUrl,
          category: category,
          subCategory: piece.subCategory,
          color: piece.color,
          styles: {StylePreference.casual},
          seasons: {Season.all},
          thickness: Thickness.light,
          favorite: false,
        );
      }
    }

    return null;
  }

  bool _savedPieceLooksLikeCategory(
    SavedOutfitPiece piece,
    ClothingCategory category,
  ) {
    final text = _normalize('${piece.category} ${piece.collection}');
    final type = _normalize(piece.subCategory);

    switch (category) {
      case ClothingCategory.top:
        return !_hasAny(type, [
          'pantolon',
          'jean',
          'sort',
          'etek',
          'ayakkabi',
          'sneaker',
          'bot',
        ]);
      case ClothingCategory.bottom:
        return !_hasAny(type, [
          'gomlek',
          'tisort',
          't-shirt',
          'sweatshirt',
          'hoodie',
          'ayakkabi',
          'sneaker',
          'bot',
        ]);
      case ClothingCategory.shoes:
        if (_hasAny(type, [
          'pantolon',
          'jean',
          'sort',
          'etek',
          'gomlek',
          'tisort',
          't-shirt',
          'sweatshirt',
          'hoodie',
        ])) {
          return false;
        }
        return _hasAny(text, ['ayakkabi', 'shoe']) ||
            _hasAny(type, ['ayakkabi', 'sneaker', 'loafer', 'bot', 'topuklu']);
      case ClothingCategory.outerwear:
        return !_hasAny(type, ['pantolon', 'jean', 'sort', 'ayakkabi']);
      case ClothingCategory.socks:
        return _hasAny(text, ['corap', 'sock']) ||
            _hasAny(type, ['corap', 'sock', 'tights']);
      case ClothingCategory.unknown:
        return true;
    }
  }

  ClothingCategory _categoryFromSavedPiece(SavedOutfitPiece piece) {
    return ClothingItem.parseClothingCategory(
      '${piece.category} ${piece.collection}',
    );
  }

  WeatherProfile _weatherProfileFromSavedOutfit(DateTime date, SavedOutfit? outfit) {
    final weather = outfit?.weather ?? const {};
    return WeatherProfile(
      date: _dateOnly(date),
      temperatureC: (weather['sicaklik'] is num)
          ? (weather['sicaklik'] as num).toDouble()
          : 18,
      humidity: weather['nem'] is int ? weather['nem'] as int : 0,
      condition: _weatherConditionFromLabel((weather['durum'] ?? '').toString()),
      description: (weather['aciklama'] ?? '').toString(),
    );
  }

  WeeklyStylePreference _stylePreferenceFromSavedOutfits(
    List<SavedOutfit> outfits,
  ) {
    final first = outfits.first;
    return WeeklyStylePreference(
      primary: _styleFromAiLabel(first.primaryStyle) ?? StylePreference.casual,
      secondary: _styleFromAiLabel(first.secondaryStyle) ?? StylePreference.street,
      tertiary: _styleFromAiLabel(first.tertiaryStyle) ?? StylePreference.special,
    );
  }

  OutfitRecommendation? _recommendationFromStyledDay({
    required StyledDay styledDay,
    required DateTime date,
    required List<ClothingItem> wardrobe,
    required WeeklyStylePreference stylePreference,
    required DayPlanType planType,
    required WeatherProfile weather,
  }) {
    final top = _findWardrobeItem(
      wardrobe,
      styledDay.outfit.top?.id,
      expectedCategory: ClothingCategory.top,
    );
    var bottom = _findWardrobeItem(
      wardrobe,
      styledDay.outfit.bottom?.id,
      expectedCategory: ClothingCategory.bottom,
    );
    final shoes = _findWardrobeItem(
      wardrobe,
      styledDay.outfit.shoes?.id,
      expectedCategory: ClothingCategory.shoes,
    );
    final accessory = _findWardrobeItem(
      wardrobe,
      styledDay.outfit.accessory?.id,
    );

    if (top != null && bottom == null && _isOnePiece(top)) {
      bottom = top;
    }

    if (top == null || bottom == null || shoes == null) {
      debugPrint("AI skipped invalid outfit for ${styledDay.day}");
      return null;
    }

    final outerwear = _findWardrobeItem(
      wardrobe,
      styledDay.outfit.outerwear?.id,
      expectedCategory: ClothingCategory.outerwear,
    );
    final socks = accessory?.category == ClothingCategory.socks ? accessory : null;
    final style = _styleFromAiLabel(styledDay.styleType) ??
        stylePreference.allocationForWeek()[
            (date.difference(_dateOnly(DateTime.now())).inDays).clamp(0, 6)];

    return OutfitRecommendation(
      date: _dateOnly(date),
      day: _dayName(date),
      style: styledDay.styleType ?? _styleLabel(style),
      description: styledDay.title ??
          styledDay.styleNote ??
          '${top.subCategory} + ${bottom.subCategory} + ${shoes.subCategory}',
      focusStyle: style,
      planType: planType,
      weather: weather,
      top: top,
      bottom: bottom,
      shoes: shoes,
      outerwear: outerwear,
      socks: socks,
      score: 100,
      notes: _aiNotes(styledDay),
    );
  }

  ClothingItem? _findWardrobeItem(
    List<ClothingItem> wardrobe,
    String? id, {
    ClothingCategory? expectedCategory,
  }) {
    if (id == null || id.isEmpty) return null;

    for (final item in wardrobe) {
      if (item.id != id) continue;
      if (expectedCategory != null && item.category != expectedCategory) {
        debugPrint(
          'Rejected item ${item.id} for $expectedCategory; '
          'actual category is ${item.category}.',
        );
        return null;
      }
      return item;
    }

    return null;
  }

  List<String> _aiNotes(StyledDay day) {
    return [
      if (day.styleNote != null) day.styleNote!,
      if (day.whyThisWorks != null) day.whyThisWorks!,
      if (day.vibe != null) day.vibe!,
      if (day.message != null) day.message!,
    ];
  }

  Map<DateTime, WeatherProfile> _weatherProfilesForWeek() {
    final start = _dateOnly(DateTime.now());
    final currentWeather = _weatherData;
    final forecastByDate = {
      for (final forecast in _dailyForecast)
        _dateOnly(forecast.date): WeatherProfile(
          date: _dateOnly(forecast.date),
          temperatureC: forecast.temperature,
          humidity: forecast.humidity,
          condition: _weatherConditionFromLabel(forecast.mainCondition),
          description: forecast.description,
        ),
    };
    final profile = currentWeather == null
        ? WeatherProfile(
            date: start,
            temperatureC: 18,
            condition: WeatherCondition.unknown,
          )
        : _recommendationService.weatherProfileFromWeatherData(
            weatherData: currentWeather,
            date: start,
          );

    final weekWeather = <DateTime, WeatherProfile>{};
    for (var i = 0; i < 7; i++) {
      final entry = _weatherProfileForDay(start, i, profile, forecastByDate);
      weekWeather[entry.key] = entry.value;
    }

    return weekWeather;
  }

  MapEntry<DateTime, WeatherProfile> _weatherProfileForDay(
    DateTime start,
    int dayOffset,
    WeatherProfile fallback,
    Map<DateTime, WeatherProfile> forecastByDate,
  ) {
    final date = start.add(Duration(days: dayOffset));
    final dateOnly = _dateOnly(date);
    final forecast = forecastByDate[dateOnly];
    if (forecast != null) return MapEntry(dateOnly, forecast);

    WeatherProfile? latestForecast;
    for (final entry in forecastByDate.entries) {
      if (!entry.key.isAfter(dateOnly)) {
        latestForecast = entry.value;
      }
    }

    final source = latestForecast ?? fallback;
    return MapEntry(
      dateOnly,
      WeatherProfile(
        date: dateOnly,
        temperatureC: source.temperatureC,
        humidity: source.humidity,
        condition: source.condition,
        description: source.description,
      ),
    );
  }

  Widget _buildRecommendationSlotCard({
    required _RecommendationDaySlot slot,
    required bool isDark,
    bool isHighlighted = false,
    VoidCallback? onTap,
  }) {
    final recommendation = slot.recommendation;

    if (recommendation == null) {
      return _buildNotRequestedCard(
        slot: slot,
        isDark: isDark,
        isHighlighted: isHighlighted,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: OutfitCollageCard(
            recommendation: recommendation,
            isDark: isDark,
            isHighlighted: isHighlighted,
            onTap: onTap,
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: _buildWhyRecommendationButton(slot, isDark),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _buildRecommendationMenu(slot, isDark),
        ),
        if (slot.isRefreshing || slot.isSavingFavorite)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: _RecommendationBusyIndicator(
                  message: slot.isSavingFavorite
                      ? "Favoriler güncelleniyor..."
                      : slot.isReplacingPiece
                          ? "Parça değiştiriliyor..."
                          : "Kombin yenileniyor...",
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWhyRecommendationButton(
    _RecommendationDaySlot slot,
    bool isDark,
  ) {
    final iconColor = isDark ? const Color(0xFF17212B) : const Color(0xFF2F2F2F);

    return Material(
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: () => _showWhyRecommendationSheet(slot),
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.question_mark_rounded, color: iconColor, size: 18),
        ),
      ),
    );
  }

  Future<void> _showWhyRecommendationSheet(_RecommendationDaySlot slot) async {
    final recommendation = slot.recommendation;
    if (recommendation == null) return;

    var items = await _wardrobeItemService.fetchItemsByRefs(
      recommendation.items.map(
        (item) => (collection: item.collection, documentId: item.id),
      ),
    );
    if (!mounted) return;

    if (items.isEmpty) {
      items = recommendation.items.map(_wardrobeItemFromClothingItem).toList();
    }

    final user = FirebaseAuth.instance.currentUser;
    final wardrobe = user == null
        ? recommendation.items
        : await _recommendationService.fetchWardrobeItems(user.uid);
    final reasonData = _outfitReasonService.buildReasonData(
      items: items,
      wardrobe: wardrobe.map(_wardrobeItemFromClothingItem).toList(),
      planType: _planEventLabel(recommendation.planType),
      weatherTemp: recommendation.weather.temperatureC,
    );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return OutfitReasonSheet(
          reasonData: reasonData,
          onSuggestedAction: reasonData.suggestedAction == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  _refreshRecommendationSlot(
                    slot.index,
                    refreshType: 'replace_item',
                    replaceItem: 'shoes',
                    replaceIntent: 'smarter',
                  );
                },
        );
      },
    );
  }

  WardrobeItem _wardrobeItemFromClothingItem(ClothingItem item) {
    return WardrobeItem(
      id: item.id,
      collection: item.collection,
      userId: item.userId,
      imageUrl: item.imageUrl,
      category: _categoryLabel(item.category),
      type: item.subCategory,
      color: item.color,
      fabricType: '',
      favorite: item.favorite,
      rawData: item.rawData,
    );
  }

  String _categoryLabel(ClothingCategory category) {
    switch (category) {
      case ClothingCategory.top:
        return 'Üst Giyim';
      case ClothingCategory.bottom:
        return 'Alt Giyim';
      case ClothingCategory.outerwear:
        return 'Dış Giyim';
      case ClothingCategory.shoes:
        return 'Ayakkabı';
      case ClothingCategory.socks:
        return 'Çorap';
      case ClothingCategory.unknown:
        return 'Bilinmeyen';
    }
  }

  String _pieceName(ClothingItem item) {
    final name = item.subCategory.trim();
    if (name.isNotEmpty) return name;

    switch (item.category) {
      case ClothingCategory.top:
        return 'üst parça';
      case ClothingCategory.bottom:
        return 'alt parça';
      case ClothingCategory.outerwear:
        return 'dış giyim';
      case ClothingCategory.shoes:
        return 'ayakkabı';
      case ClothingCategory.socks:
        return 'çorap';
      case ClothingCategory.unknown:
        return 'parça';
    }
  }

  Widget _buildRecommendationMenu(_RecommendationDaySlot slot, bool isDark) {
    final iconColor = isDark ? const Color(0xFF17212B) : const Color(0xFF2F2F2F);
    final menuBackground = isDark ? const Color(0xFF161B24) : Colors.white;
    final menuTextColor = isDark ? Colors.white : const Color(0xFF111827);
    final disabledTextColor = isDark
        ? Colors.white.withOpacity(0.45)
        : const Color(0xFF9CA3AF);

    return Material(
      color: Colors.white.withOpacity(0.96),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: PopupMenuButton<String>(
        enabled: !slot.isRefreshing && !slot.isSavingFavorite,
        color: menuBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        icon: Icon(Icons.more_horiz, color: iconColor, size: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onSelected: (value) {
          if (value == 'favorite') {
            _favoriteRecommendationSlot(slot.index);
          } else if (value == 'refresh') {
            _refreshRecommendationSlot(slot.index);
          } else if (value == 'replace') {
            _showReplaceItemSheet(slot.index);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'favorite',
            enabled: slot.canFavorite,
            child: Text(
              slot.isFavorite ? 'Favorilerden Kaldır' : 'Favorilere Ekle',
              style: TextStyle(
                color: slot.canFavorite ? menuTextColor : disabledTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'refresh',
            child: Text(
              'Kombini Yenile',
              style: TextStyle(
                color: menuTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          PopupMenuItem(
            value: 'replace',
            child: Text(
              'Parça Değiştir',
              style: TextStyle(
                color: menuTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotRequestedCard({
    required _RecommendationDaySlot slot,
    required bool isDark,
    bool isHighlighted = false,
  }) {
    final titleColor = isDark ? const Color(0xFF17212B) : const Color(0xFF2F2F2F);
    final metaColor = isDark ? const Color(0xFF344252) : const Color(0xFF4B5563);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFD7DEE4) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHighlighted
              ? (isDark ? const Color(0xFFD8C38A) : AppTheme.lightPrimary)
              : (isDark ? Colors.transparent : const Color(0xFFE8DFCF)),
          width: isHighlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.16 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFFE9EEF2)
                    : const Color(0xFFF7F2EA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  slot.requested
                      ? Icons.info_outline_rounded
                      : Icons.event_busy_rounded,
                  color: metaColor,
                  size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${_dayName(slot.date)}\n${slot.requested ? "Hazırlanamadı" : "Seçilmedi"}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            slot.message ?? "Bugün için kombin önerisi yazılmadı.",
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: metaColor,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _favoriteRecommendationSlot(int index) async {
    final user = FirebaseAuth.instance.currentUser;
    final stylePreference = _activeStylePreference;

    if (user == null || stylePreference == null) {
      _showSnackBar("Favorilere eklemek için giriş yapmalısın.", isError: true);
      return;
    }
    if (index < 0 || index >= _recommendationSlots.length) return;

    final slot = _recommendationSlots[index];
    final recommendation = slot.recommendation;
    if (recommendation == null || !slot.canFavorite) {
      _showSnackBar("Bu gün favorilere eklenemez.", isError: true);
      return;
    }

    setState(() {
      _recommendationSlots[index] = slot.copyWith(isSavingFavorite: true);
    });

    try {
      var outfitId = slot.outfitId;
      var favoriteId = slot.favoriteId;
      final nextFavorite = !slot.isFavorite;

      if (nextFavorite) {
        favoriteId = await _savedOutfitService.saveFavoriteRecommendation(
          userId: user.uid,
          stylePreference: stylePreference,
          recommendation: recommendation,
        );
      } else {
        favoriteId = favoriteId.isNotEmpty
            ? favoriteId
            : _savedOutfitService.favoriteIdForRecommendation(recommendation);
        await _savedOutfitService.deleteFavoriteOutfit(
          userId: user.uid,
          favoriteId: favoriteId,
        );
        favoriteId = '';
      }

      if (outfitId.isEmpty) {
        outfitId = slot.outfitId;
      } else {
        await _savedOutfitService.toggleFavorite(
          outfitId: outfitId,
          isFavorite: nextFavorite,
        );
      }

      if (!mounted) return;
      setState(() {
        _recommendationSlots[index] = _recommendationSlots[index].copyWith(
          outfitId: outfitId,
          favoriteId: favoriteId,
          isFavorite: nextFavorite,
          isSavingFavorite: false,
        );
      });
      _showSnackBar(
        nextFavorite ? "Favorilere eklendi." : "Favorilerden kaldırıldı.",
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendationSlots[index] =
            _recommendationSlots[index].copyWith(isSavingFavorite: false);
      });
      _showSnackBar("Favori durumu güncellenemedi.", isError: true);
      debugPrint("SAVE FAVORITE RECOMMENDATION ERROR: $e");
    }
  }

  Future<void> _refreshRecommendationSlot(
    int index, {
    String refreshType = 'full_refresh',
    String? replaceItem,
    String? replaceIntent,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final stylePreference = _activeStylePreference;

    if (user == null || stylePreference == null) {
      _showSnackBar("Kombin yenilemek için giriş yapmalısın.", isError: true);
      return;
    }
    if (index < 0 || index >= _recommendationSlots.length) return;

    final oldSlot = _recommendationSlots[index];
    if (!oldSlot.hasRecommendation) {
      _showSnackBar("Bu gün için önce kombin oluşturmalısın.", isError: true);
      return;
    }

    setState(() {
      _recommendationSlots[index] = oldSlot.copyWith(
        isRefreshing: true,
        isReplacingPiece: replaceItem != null,
      );
    });

    try {
      final wardrobe = await _recommendationService.fetchWardrobeItems(user.uid);
      final userGender = await _fetchUserGender(user.uid);
      final weatherByDate = _activeWeatherByDate.isEmpty
          ? _weatherProfilesForWeek()
          : _activeWeatherByDate;
      final dayPlans = _activeDayPlans.isEmpty
          ? {oldSlot.date: DayPlan(date: oldSlot.date, type: oldSlot.planType)}
          : _activeDayPlans;
      final aiRequest = _buildAiSuggestionRequest(
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: stylePreference,
        dayPlans: dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: {index},
        planType: 'single_day',
        refreshType: refreshType,
        replaceItem: replaceItem,
        replaceIntent: replaceIntent,
        currentOutfit: _currentOutfitJson(oldSlot.recommendation),
      );
      final slots = await _resolveRecommendationSlots(
        aiRequest: aiRequest,
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: stylePreference,
        dayPlans: dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: {index},
        debugContext: 'AI REFRESH FALLBACK',
        currentRecommendation: oldSlot.recommendation,
      );
      var newSlot = slots[index];

      if (!newSlot.hasRecommendation) {
        throw OutfitAiException(
          newSlot.message ?? "Yeni kombin oluşturulamadı.",
        );
      }

      if (refreshType == 'replace_item' &&
          replaceItem != null &&
          replaceIntent != null &&
          newSlot.recommendation != null &&
          !_pieceMatchesReplaceIntent(
            _currentPieceForReplaceItem(newSlot.recommendation!, replaceItem),
            replaceIntent,
            newSlot.weather,
          )) {
        newSlot = newSlot.copyWith(
          recommendation: _replacePieceLocally(
            newSlot.recommendation!,
            wardrobe,
            replaceItem,
            replaceIntent,
            userGender,
          ),
        );
      }

      var outfitId = '';
      try {
        outfitId = await _savedOutfitService.saveRecommendation(
          userId: user.uid,
          stylePreference: stylePreference,
          recommendation: newSlot.recommendation!,
          creationType: 'ai_recommendation',
        );
      } catch (e) {
        debugPrint("SAVE REFRESHED RECOMMENDATION ERROR: $e");
      }

      if (!mounted) return;
      setState(() {
        _recommendationSlots[index] = newSlot.copyWith(
          outfitId: outfitId,
          isReplacingPiece: false,
          isRefreshing: false,
        );
      });
      _showSnackBar(
        _lastRecommendationUsedLocalFallback
            ? "AI limiti dolduğu için kombin yerel öneriyle yenilendi."
            : "Kombin yenilendi.",
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendationSlots[index] =
            _recommendationSlots[index].copyWith(
          isRefreshing: false,
          isReplacingPiece: false,
        );
      });
      final message = e is OutfitAiException
          ? e.message
          : "Kombin yenilenemedi. Lütfen tekrar dene.";
      _showSnackBar(message, isError: true);
      debugPrint("REFRESH RECOMMENDATION ERROR: $e");
    }
  }

  Future<void> _showReplaceItemSheet(int index) async {
    final slot = _recommendationSlots[index];
    final recommendation = slot.recommendation;
    if (recommendation == null) {
      _showSnackBar("Değiştirilecek kombin bulunamadı.", isError: true);
      return;
    }

    final selection = await showModalBottomSheet<ReplacePieceRequest>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ReplacePieceSheet(
          recommendation: recommendation,
        );
      },
    );

    if (selection == null) return;

    await _refreshRecommendationSlot(
      index,
      refreshType: 'replace_item',
      replaceItem: selection.replaceItem,
      replaceIntent: selection.intent,
    );
  }

  OutfitRecommendation _replacePieceLocally(
    OutfitRecommendation current,
    List<ClothingItem> wardrobe,
    String replaceItem,
    String? replaceIntent,
    String userGender,
  ) {
    final category = _categoryForReplaceItem(replaceItem);
    if (category == null) return current;

    final currentPiece = _currentPieceForReplaceItem(current, replaceItem);
    final candidates = wardrobe
        .where((item) => item.category == category)
        .where((item) => !_isGenderIncompatible(item, userGender))
        .where((item) => currentPiece == null || item.id != currentPiece.id)
        .toList();
    if (candidates.isEmpty) return current;

    final intentCandidates = candidates
        .where((item) => _pieceMatchesReplaceIntent(item, replaceIntent, current.weather))
        .toList();
    final rankedCandidates =
        intentCandidates.isNotEmpty ? intentCandidates : candidates;

    rankedCandidates.sort((a, b) {
      final bScore = _replaceIntentScore(b, currentPiece, replaceIntent, current.weather);
      final aScore = _replaceIntentScore(a, currentPiece, replaceIntent, current.weather);
      return bScore.compareTo(aScore);
    });

    final selected = rankedCandidates.first;
    return OutfitRecommendation(
      date: current.date,
      day: current.day,
      style: current.style,
      description: "${_pieceName(selected)} ile güncellenmiş kombin",
      focusStyle: current.focusStyle,
      planType: current.planType,
      weather: current.weather,
      top: replaceItem == 'top' ? selected : current.top,
      bottom: replaceItem == 'bottom' ? selected : current.bottom,
      shoes: replaceItem == 'shoes' ? selected : current.shoes,
      outerwear: replaceItem == 'outerwear' ? selected : current.outerwear,
      socks: current.socks,
      score: current.score,
      notes: [
        ...current.notes,
        "Yerel yenileme: ${_replaceIntentLabel(replaceIntent)} isteğine göre ${_pieceName(selected)} seçildi.",
      ],
    );
  }

  ClothingCategory? _categoryForReplaceItem(String replaceItem) {
    switch (replaceItem) {
      case 'top':
        return ClothingCategory.top;
      case 'bottom':
        return ClothingCategory.bottom;
      case 'outerwear':
        return ClothingCategory.outerwear;
      case 'shoes':
        return ClothingCategory.shoes;
      default:
        return null;
    }
  }

  ClothingItem? _currentPieceForReplaceItem(
    OutfitRecommendation current,
    String replaceItem,
  ) {
    switch (replaceItem) {
      case 'top':
        return current.top;
      case 'bottom':
        return current.bottom;
      case 'outerwear':
        return current.outerwear;
      case 'shoes':
        return current.shoes;
      default:
        return null;
    }
  }

  int _replaceIntentScore(
    ClothingItem item,
    ClothingItem? currentPiece,
    String? intent,
    WeatherProfile weather,
  ) {
    var score = 0;
    final type = _normalize(item.subCategory);

    switch (intent) {
      case 'lighter':
        if (item.thickness == Thickness.light) score += 30;
        if (_hasAny(type, ['tisort', 't-shirt', 'gomlek', 'polo', 'atlet', 'sort', 'etek', 'hirka', 'yelek'])) score += 18;
        if (_hasAny(type, ['sweat', 'sweatshirt', 'hoodie', 'kazak', 'triko'])) score -= 35;
        if (item.thickness == Thickness.heavy) score -= 30;
        break;
      case 'warmer':
        if (item.thickness == Thickness.heavy) score += 30;
        if (item.thickness == Thickness.medium) score += 18;
        if (_hasAny(type, ['kazak', 'sweat', 'sweatshirt', 'hoodie', 'triko', 'mont', 'kaban', 'bot', 'jean'])) score += 18;
        if (item.thickness == Thickness.light) score -= 16;
        break;
      case 'smarter':
        if (item.styles.contains(StylePreference.smart) ||
            item.styles.contains(StylePreference.special)) score += 28;
        if (_hasAny(type, ['gomlek', 'polo', 'blazer', 'ceket', 'chino', 'kumas', 'klasik', 'loafer', 'kaban'])) score += 20;
        if (_hasAny(type, ['spor', 'sneaker', 'esofman', 'hoodie'])) score -= 18;
        break;
      case 'comfortable':
      case 'casual':
        if (item.styles.contains(StylePreference.casual) ||
            item.styles.contains(StylePreference.sport)) score += 22;
        if (_hasAny(type, ['tisort', 'sweat', 'hoodie', 'jean', 'esofman', 'sneaker', 'spor', 'denim', 'bomber', 'hirka'])) score += 18;
        break;
      case 'sport':
        if (item.styles.contains(StylePreference.sport)) score += 34;
        if (_hasAny(type, ['spor', 'performans', 'dry', 'fit', 'jogger', 'esofman', 'kosu', 'antrenman', 'sneaker'])) score += 24;
        if (_hasAny(type, ['gomlek', 'blazer', 'kumas', 'loafer', 'oxford', 'derby'])) score -= 22;
        break;
      case 'weather':
        if ((weather.isRainy || weather.isSnowy) &&
            _hasAny(type, ['bot', 'yagmurluk', 'kapuson', 'mont'])) score += 34;
        if (weather.isCold && _hasAny(type, ['bot', 'mont', 'kaban', 'ceket'])) score += 22;
        if (weather.isHot && item.thickness == Thickness.light) score += 18;
        break;
      case 'color':
        if (currentPiece != null &&
            _normalize(item.color) != _normalize(currentPiece.color)) {
          score += 34;
        }
        break;
      case 'auto':
      default:
        if (item.seasons.contains(weather.preferredSeason)) score += 12;
        if (item.seasons.contains(Season.all)) score += 8;
        break;
    }

    if (item.styles.contains(StylePreference.smart) ||
        item.styles.contains(StylePreference.casual)) {
      score += 3;
    }
    if (item.favorite) score += 4;
    return score;
  }

  bool _pieceMatchesReplaceIntent(
    ClothingItem? item,
    String? intent,
    WeatherProfile weather,
  ) {
    if (item == null || intent == null || intent == 'auto') return true;

    final type = _normalize(item.subCategory);
    switch (intent) {
      case 'lighter':
        return item.thickness == Thickness.light ||
            _hasAny(type, ['tisort', 't-shirt', 'gomlek', 'polo', 'atlet', 'sort', 'etek', 'ince']);
      case 'warmer':
        return item.thickness == Thickness.heavy ||
            item.thickness == Thickness.medium ||
            _hasAny(type, ['kazak', 'sweat', 'sweatshirt', 'hoodie', 'triko', 'mont', 'kaban', 'bot', 'jean']);
      case 'smarter':
        return item.styles.contains(StylePreference.smart) ||
            item.styles.contains(StylePreference.special) ||
            _hasAny(type, ['gomlek', 'polo', 'blazer', 'ceket', 'chino', 'kumas', 'klasik', 'loafer', 'kaban']);
      case 'comfortable':
      case 'casual':
        return item.styles.contains(StylePreference.casual) ||
            item.styles.contains(StylePreference.sport) ||
            _hasAny(type, ['tisort', 'sweat', 'hoodie', 'jean', 'esofman', 'sneaker', 'spor', 'denim', 'bomber', 'hirka']);
      case 'sport':
        return item.styles.contains(StylePreference.sport) ||
            _hasAny(type, ['spor', 'performans', 'dry', 'fit', 'jogger', 'esofman', 'kosu', 'antrenman', 'sneaker']);
      case 'weather':
        if (weather.isRainy || weather.isSnowy) {
          return _hasAny(type, ['bot', 'yagmurluk', 'kapuson', 'mont']);
        }
        if (weather.isCold) {
          return _hasAny(type, ['bot', 'mont', 'kaban', 'ceket']) ||
              item.thickness != Thickness.light;
        }
        if (weather.isHot) return item.thickness == Thickness.light;
        return true;
      case 'color':
        return true;
      default:
        return true;
    }
  }

  bool _hasAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }

  String _replaceIntentLabel(String? intent) {
    switch (intent) {
      case 'lighter':
        return 'daha ince';
      case 'warmer':
        return 'daha sıcak';
      case 'smarter':
        return 'daha şık';
      case 'comfortable':
        return 'daha rahat';
      case 'weather':
        return 'havaya uygun';
      case 'casual':
        return 'daha günlük';
      case 'sport':
        return 'daha spor';
      case 'color':
        return 'rengi değiştir';
      default:
        return 'uygulamaya bırak';
    }
  }

  Map<String, dynamic>? _currentOutfitJson(OutfitRecommendation? recommendation) {
    if (recommendation == null) return null;

    Map<String, dynamic> piece(ClothingItem item) {
      return {
        'id': item.id,
        'name': item.subCategory.trim().isEmpty ? item.id : item.subCategory,
      };
    }

    return {
      'top': piece(recommendation.top),
      'outerwear': recommendation.outerwear == null
          ? null
          : piece(recommendation.outerwear!),
      'bottom': piece(recommendation.bottom),
      'shoes': piece(recommendation.shoes),
      'bag': null,
      'accessory': null,
    };
  }

  Future<void> _openRecommendationDetail(int index) async {
    if (index < 0 || index >= _recommendationSlots.length) {
      _showSnackBar(
        "Bu kombin bulunamadı.",
        isError: true,
      );
      return;
    }

    final slot = _recommendationSlots[index];
    if (!slot.hasRecommendation) {
      _showSnackBar(
        "Bu gün için kaydedilebilir kombin yok.",
        isError: true,
      );
      return;
    }

    var outfitId = slot.outfitId;

    if (outfitId.isEmpty) {
      outfitId = await _saveMissingRecommendationForDetail(index);
    }

    if (!mounted || outfitId.isEmpty) {
      _showSnackBar(
        "Bu kombin Firestore'a kaydedilemedi.",
        isError: true,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OutfitDetailPage(outfitId: outfitId),
      ),
    );
  }

  Future<String> _saveMissingRecommendationForDetail(int index) async {
    if (_isOpeningRecommendationDetail) return '';

    final user = FirebaseAuth.instance.currentUser;
    final stylePreference = _activeStylePreference;
    if (user == null || stylePreference == null) return '';
    if (index < 0 || index >= _recommendationSlots.length) return '';

    final recommendation = _recommendationSlots[index].recommendation;
    if (recommendation == null) return '';

    setState(() {
      _isOpeningRecommendationDetail = true;
    });

    try {
      final outfitId = await _savedOutfitService.saveRecommendation(
        userId: user.uid,
        stylePreference: stylePreference,
        recommendation: recommendation,
        creationType: 'ai_recommendation',
      );

      if (!mounted) return outfitId;

      setState(() {
        _recommendationSlots[index] =
            _recommendationSlots[index].copyWith(outfitId: outfitId);
      });

      return outfitId;
    } catch (e) {
      debugPrint("SAVE SINGLE RECOMMENDATION ERROR: $e");
      return '';
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningRecommendationDetail = false;
        });
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _dateForRecommendationIndex(int index) {
    final safeIndex = index.clamp(0, 6);
    return _dateOnly(DateTime.now().add(Duration(days: safeIndex)));
  }

  String _dayLabel(int index) {
    return _dayName(_dateForRecommendationIndex(index));
  }

  String _dayName(DateTime date) {
    const days = {
      DateTime.monday: "Pazartesi",
      DateTime.tuesday: "Salı",
      DateTime.wednesday: "Çarşamba",
      DateTime.thursday: "Perşembe",
      DateTime.friday: "Cuma",
      DateTime.saturday: "Cumartesi",
      DateTime.sunday: "Pazar",
    };
    return days[date.weekday] ?? "";
  }

  String _englishDayName(DateTime date) {
    const days = {
      DateTime.monday: "Monday",
      DateTime.tuesday: "Tuesday",
      DateTime.wednesday: "Wednesday",
      DateTime.thursday: "Thursday",
      DateTime.friday: "Friday",
      DateTime.saturday: "Saturday",
      DateTime.sunday: "Sunday",
    };
    return days[date.weekday] ?? "";
  }

  String _styleLabel(StylePreference style) {
    switch (style) {
      case StylePreference.casual:
        return "Casual";
      case StylePreference.street:
        return "Street";
      case StylePreference.sport:
        return "Sport";
      case StylePreference.smart:
        return "Smart";
      case StylePreference.special:
        return "Special";
    }
  }

  String _planLabel(DayPlanType plan) {
    switch (plan) {
      case DayPlanType.normalDay:
        return "Normal Gün";
      case DayPlanType.office:
        return "Ofis";
      case DayPlanType.date:
        return "Date";
      case DayPlanType.gym:
        return "Spor";
      case DayPlanType.dinner:
        return "Akşam Yemeği";
      case DayPlanType.travel:
        return "Seyahat";
      case DayPlanType.specialEvent:
        return "Özel Etkinlik";
    }
  }

  String _planEventLabel(DayPlanType plan) {
    switch (plan) {
      case DayPlanType.normalDay:
        return "Normal Day";
      case DayPlanType.office:
        return "Office";
      case DayPlanType.date:
        return "Date";
      case DayPlanType.gym:
        return "Gym";
      case DayPlanType.dinner:
        return "Dinner";
      case DayPlanType.travel:
        return "Travel";
      case DayPlanType.specialEvent:
        return "Special Event";
    }
  }

  String _aiCategoryLabel(ClothingCategory category) {
    switch (category) {
      case ClothingCategory.top:
        return "top";
      case ClothingCategory.bottom:
        return "bottom";
      case ClothingCategory.outerwear:
        return "outerwear";
      case ClothingCategory.shoes:
        return "shoes";
      case ClothingCategory.socks:
        return "socks";
      case ClothingCategory.unknown:
        return "unknown";
    }
  }

  String _seasonLabel(Season season) {
    switch (season) {
      case Season.all:
        return "all";
      case Season.spring:
        return "spring";
      case Season.summer:
        return "summer";
      case Season.autumn:
        return "autumn";
      case Season.winter:
        return "winter";
    }
  }

  String _weatherConditionLabel(WeatherCondition condition) {
    switch (condition) {
      case WeatherCondition.clear:
        return "sunny";
      case WeatherCondition.clouds:
        return "cloudy";
      case WeatherCondition.rain:
        return "rainy";
      case WeatherCondition.snow:
        return "snowy";
      case WeatherCondition.wind:
        return "windy";
      case WeatherCondition.unknown:
        return "unknown";
    }
  }

  WeatherCondition _weatherConditionFromLabel(String value) {
    final text = _normalize(value);
    if (text.contains("clear") || text.contains("sun")) {
      return WeatherCondition.clear;
    }
    if (text.contains("cloud")) return WeatherCondition.clouds;
    if (text.contains("rain")) return WeatherCondition.rain;
    if (text.contains("snow")) return WeatherCondition.snow;
    if (text.contains("wind")) return WeatherCondition.wind;
    return WeatherCondition.unknown;
  }

  DayPlanType _dayPlanFromLabel(String value) {
    final text = _normalize(value);
    if (text.contains("office") || text.contains("ofis")) {
      return DayPlanType.office;
    }
    if (text.contains("date")) return DayPlanType.date;
    if (text.contains("gym") || text.contains("spor")) {
      return DayPlanType.gym;
    }
    if (text.contains("dinner") || text.contains("yemek")) {
      return DayPlanType.dinner;
    }
    if (text.contains("travel") || text.contains("seyahat")) {
      return DayPlanType.travel;
    }
    if (text.contains("special") || text.contains("ozel")) {
      return DayPlanType.specialEvent;
    }
    return DayPlanType.normalDay;
  }

  StylePreference? _styleFromAiLabel(String? value) {
    final text = _normalize(value ?? "");
    if (text.contains("casual") || text.contains("minimal")) {
      return StylePreference.casual;
    }
    if (text.contains("street")) return StylePreference.street;
    if (text.contains("sport")) return StylePreference.sport;
    if (text.contains("smart")) return StylePreference.smart;
    if (text.contains("special") || text.contains("date")) {
      return StylePreference.special;
    }
    return null;
  }

  Future<String> _fetchUserGender(String userId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return _genderLabelFromValue(doc.data()?['cinsiyet']);
  }

  String _genderLabelFromValue(Object? value) {
    if (value is bool) return value ? 'male' : 'female';

    final text = _normalize(value?.toString() ?? '');
    if (text == 'true' || text == 'erkek' || text == 'male') return 'male';
    if (text == 'false' ||
        text == 'kadin' ||
        text == 'kadın' ||
        text == 'female') {
      return 'female';
    }
    return 'unspecified';
  }

  List<Map<String, String>> _placeholderWeeklyOutfits(String userGender) {
    return userGender == 'female' ? _femaleWeeklyOutfits : _maleWeeklyOutfits;
  }

  bool _isGenderIncompatible(ClothingItem item, String userGender) {
    if (_normalize(userGender) != 'male') return false;

    final text = _normalize(
      '${item.subCategory} ${item.category.name} ${item.rawData['tur'] ?? ''} '
      '${item.rawData['type'] ?? ''} ${item.rawData['styleTags'] ?? ''}',
    );

    return _hasAny(text, [
      'etek',
      'elbise',
      'body',
      'tulum',
      'tayt',
      'topuklu',
      'stiletto',
      'blok topuk',
      'ince bantli',
      'bluz',
      'crop',
      'palazzo',
      'cigarette',
      'kruvaze bluz',
      'wrap top',
      'saten midi',
      'pleated midi',
      'strappy heel',
      'block heel',
    ]);
  }

  bool _isOnePiece(ClothingItem item) {
    final type = _normalize(item.subCategory);
    return type.contains('elbise') || type.contains('tulum');
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll("ı", "i")
        .replaceAll("ğ", "g")
        .replaceAll("ü", "u")
        .replaceAll("ş", "s")
        .replaceAll("ö", "o")
        .replaceAll("ç", "c");
  }

  bool _canUseLocalRecommendationFallback(String message) {
    final text = _normalize(message);
    final missingOutfit = text.contains("missing outfit") ||
        (text.contains("outfit") && text.contains("missing"));
    final quotaIssue = text.contains("kota") ||
        text.contains("quota") ||
        text.contains("billing") ||
        text.contains("ucretsiz kota") ||
        text.contains("limit");
    final profileGuard = text.contains("gender incompatible");

    return missingOutfit || quotaIssue || profileGuard;
  }

  Future<List<_RecommendationDaySlot>> _resolveRecommendationSlots({
    required OutfitSuggestionRequest aiRequest,
    required List<ClothingItem> wardrobe,
    required String userGender,
    required WeeklyStylePreference stylePreference,
    required Map<DateTime, DayPlan> dayPlans,
    required Map<DateTime, WeatherProfile> weatherByDate,
    required Set<int> requestedDayIndexes,
    required String debugContext,
    OutfitRecommendation? currentRecommendation,
  }) async {
    try {
      final aiResponse = await _outfitAiService.generateSuggestions(aiRequest);
      final aiSlots = _slotsFromAiResponse(
        aiResponse: aiResponse,
        wardrobe: wardrobe,
        stylePreference: stylePreference,
        dayPlans: dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: requestedDayIndexes,
      );
      final hasInvalidRequestedSlot = aiSlots.any(
        (slot) => slot.requested && slot.recommendation == null,
      );
      if (!hasInvalidRequestedSlot) {
        _lastRecommendationUsedLocalFallback = false;
        return aiSlots;
      }

      _lastRecommendationUsedLocalFallback = true;
      debugPrint('$debugContext: invalid AI outfit slots, using local fallback');
      return _slotsFromLocalRecommendations(
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: stylePreference,
        dayPlans: dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: requestedDayIndexes,
        refreshType: aiRequest.refreshType,
        replaceItem: aiRequest.replaceItem,
        replaceIntent: aiRequest.replaceIntent,
        currentRecommendation: currentRecommendation,
      );
    } on OutfitAiException catch (e) {
      if (!_canUseLocalRecommendationFallback(e.message)) rethrow;

      _lastRecommendationUsedLocalFallback = true;
      debugPrint('$debugContext: ${e.message}');
      return _slotsFromLocalRecommendations(
        wardrobe: wardrobe,
        userGender: userGender,
        stylePreference: stylePreference,
        dayPlans: dayPlans,
        weatherByDate: weatherByDate,
        requestedDayIndexes: requestedDayIndexes,
        refreshType: aiRequest.refreshType,
        replaceItem: aiRequest.replaceItem,
        replaceIntent: aiRequest.replaceIntent,
        currentRecommendation: currentRecommendation,
      );
    }
  }

  Widget _buildProfileCircle({
    required bool isDark,
    required String? profileImageUrl,
    required String? selectedAvatarAsset,
  }) {
    ImageProvider? imageProvider;

    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      imageProvider = NetworkImage(profileImageUrl);
    } else if (selectedAvatarAsset != null && selectedAvatarAsset.isNotEmpty) {
      imageProvider = AssetImage(selectedAvatarAsset);
    }

    final accentColor = isDark ? AppTheme.darkAccent : AppTheme.lightPrimary;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.25), blurRadius: 14),
        ],
      ),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: isDark
            ? const Color(0xFFD8C38A)
            : const Color(0xFFF7E8C6),
        backgroundImage: imageProvider,
        child: imageProvider == null
            ? Icon(
                Icons.person,
                color: isDark
                    ? const Color(0xFF071723)
                    : const Color(0xFF6E5221),
                size: 28,
              )
            : null,
      ),
    );
  }

  Widget _buildHeader(String name, bool isDark) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.panelDecoration(isDark, radius: 24).copyWith(
        gradient: LinearGradient(
          colors: isDark
              ? [AppTheme.surface1, AppTheme.surface2]
              : [AppTheme.surface1Light, AppTheme.surface2Light],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Merhaba,",
                      style: AppTheme.body(isDark).copyWith(
                        color: AppTheme.primaryText(isDark).withOpacity(0.78),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading1(isDark),
                    ),
                    const SizedBox(height: 10),
                    WeatherPill(
                      isDark: isDark,
                      isLoading: _isLoadingWeather,
                      error: _weatherError,
                      weather: _weatherData,
                      onRetry: _loadWeather,
                    ),
                  ],
                ),
              ),
              if (user == null)
                _buildProfileCircle(
                  isDark: isDark,
                  profileImageUrl: null,
                  selectedAvatarAsset: null,
                )
              else
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection("users")
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final userData = snapshot.data?.data() ?? {};
                    final profileImageUrl =
                        (userData["profile_image_url"] ?? "").toString().trim();
                    final selectedAvatarAsset =
                        (userData["selected_avatar_asset"] ?? "")
                            .toString()
                            .trim();

                    return _buildProfileCircle(
                      isDark: isDark,
                      profileImageUrl: profileImageUrl.isEmpty
                          ? null
                          : profileImageUrl,
                      selectedAvatarAsset: selectedAvatarAsset.isEmpty
                          ? null
                          : selectedAvatarAsset,
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _startRecommendationFlow,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.layer2(isDark),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.subtleBorder(isDark)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: isDark
                                ? AppTheme.backgroundPrimary
                                : AppTheme.textPrimaryLight,
                            size: 20,
                          ),
                        ).animate(onPlay: (c) => c.repeat()).rotate(
                              duration: 12.seconds,
                            ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Bu haftanın kombinleri hazır",
                                style: AppTheme.heading2(isDark).copyWith(
                                  color: AppTheme.primaryText(isDark),
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _dashboardWeatherSummary(),
                                style: AppTheme.caption(isDark).copyWith(
                                  color: AppTheme.primaryText(isDark).withOpacity(0.72),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _openTravelModePage,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.layer2(isDark),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.subtleBorder(isDark)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.luggage_rounded,
                      color: isDark
                          ? AppTheme.backgroundPrimary
                          : AppTheme.textPrimaryLight,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Valiz Asistanı",
                          style: AppTheme.heading2(isDark).copyWith(
                            color: AppTheme.primaryText(isDark),
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Az parçayla daha çok seyahat kombini planla",
                          style: AppTheme.caption(isDark).copyWith(
                            color:
                                AppTheme.primaryText(isDark).withOpacity(0.72),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.tertiaryText(isDark),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutfitCard({
    required String day,
    required String image,
    required bool isDark,
    bool isHighlighted = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isHighlighted
              ? AppTheme.gold(isDark)
              : AppTheme.subtleBorder(isDark),
          width: isHighlighted ? 1.2 : 0.6,
        ),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CachedNetworkImage(
                    imageUrl: image,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: AppTheme.layer2(isDark),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: AppTheme.layer2(isDark),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppTheme.tertiaryText(isDark),
                        size: 36,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                if (isHighlighted)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: Text(
                        "Öne Çıkan",
                        style: AppTheme.label(isDark).copyWith(
                          color: isDark
                              ? AppTheme.backgroundPrimary
                              : AppTheme.textPrimaryLight,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ).animate(onPlay: (c) => c.repeat()).fade(
                          begin: 0.7,
                          end: 1,
                          duration: 2.seconds,
                        ),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppTheme.themeGoldGradient(isDark) as Gradient?,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    ),
                    child: Text(
                      day.toUpperCase(),
                      style: AppTheme.label(isDark).copyWith(
                        color: isDark
                            ? AppTheme.backgroundPrimary
                            : AppTheme.textPrimaryLight,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                if (image.isEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Icon(
                        Icons.add_circle_outline_rounded,
                        color: AppTheme.tertiaryText(isDark),
                        size: 30,
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

  String _capitalizeFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _dashboardWeatherSummary() {
    final weather = _weatherData;
    if (weather == null) {
      return "--°C · Hava durumuna göre seçildi";
    }

    return '${weather.temperature.round()}°C · ${_weatherSummaryLabel(weather)}';
  }

  String _weatherSummaryLabel(WeatherData weather) {
    final condition = _normalize(weather.mainCondition);
    if (condition.contains('clear')) {
      return 'Açık hava için seçildi';
    }
    if (condition.contains('cloud')) {
      return 'Bulutlu hava için seçildi';
    }
    if (condition.contains('rain') || condition.contains('drizzle')) {
      return 'Yağışlı hava için seçildi';
    }
    if (condition.contains('snow')) {
      return 'Karlı hava için seçildi';
    }
    if (condition.contains('wind')) {
      return 'Rüzgarlı hava için seçildi';
    }

    final description = weather.description.trim();
    if (description.isEmpty) {
      return 'Hava durumuna göre seçildi';
    }

    return '${_capitalizeFirst(description)} hava için seçildi';
  }
}

class _RecommendationFlowInput {
  final WeeklyStylePreference stylePreference;
  final Map<DateTime, DayPlan> dayPlans;
  final Set<int> requestedDayIndexes;

  const _RecommendationFlowInput({
    required this.stylePreference,
    required this.dayPlans,
    required this.requestedDayIndexes,
  });
}

class _RecommendationBusyIndicator extends StatelessWidget {
  final String message;

  const _RecommendationBusyIndicator({required this.message});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2F2F2F),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendationDaySlot {
  final int index;
  final DateTime date;
  final bool requested;
  final DayPlanType planType;
  final WeatherProfile weather;
  final OutfitRecommendation? recommendation;
  final String outfitId;
  final String favoriteId;
  final String? message;
  final bool canFavorite;
  final bool isFavorite;
  final bool isRefreshing;
  final bool isReplacingPiece;
  final bool isSavingFavorite;

  const _RecommendationDaySlot({
    required this.index,
    required this.date,
    required this.requested,
    required this.planType,
    required this.weather,
    this.recommendation,
    this.outfitId = '',
    this.favoriteId = '',
    this.message,
    this.canFavorite = false,
    this.isFavorite = false,
    this.isRefreshing = false,
    this.isReplacingPiece = false,
    this.isSavingFavorite = false,
  });

  bool get hasRecommendation => recommendation != null;

  _RecommendationDaySlot copyWith({
    bool? requested,
    DayPlanType? planType,
    WeatherProfile? weather,
    OutfitRecommendation? recommendation,
    String? outfitId,
    String? favoriteId,
    String? message,
    bool? canFavorite,
    bool? isFavorite,
    bool? isRefreshing,
    bool? isReplacingPiece,
    bool? isSavingFavorite,
  }) {
    return _RecommendationDaySlot(
      date: date,
      requested: requested ?? this.requested,
      planType: planType ?? this.planType,
      weather: weather ?? this.weather,
      recommendation: recommendation ?? this.recommendation,
      outfitId: outfitId ?? this.outfitId,
      favoriteId: favoriteId ?? this.favoriteId,
      message: message ?? this.message,
      canFavorite: canFavorite ?? this.canFavorite,
      isFavorite: isFavorite ?? this.isFavorite,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isReplacingPiece: isReplacingPiece ?? this.isReplacingPiece,
      isSavingFavorite: isSavingFavorite ?? this.isSavingFavorite,
      index: index,
    );
  }
}

class _WeeklyPlanChip extends StatelessWidget {
  final String label;
  final bool isEnabled;
  final bool isSelected;
  final VoidCallback onTap;

  const _WeeklyPlanChip({
    required this.label,
    required this.isEnabled,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFC8A84B);
    final borderColor = isSelected && isEnabled
        ? gold
        : isEnabled
            ? const Color(0xFF343434)
            : const Color(0xFF272727);
    final backgroundColor = isSelected && isEnabled
        ? const Color(0xFF1E1A0F)
        : const Color(0xFF1A1A1A);
    final textColor = isSelected && isEnabled
        ? const Color(0xFFE8C76A)
        : isEnabled
            ? const Color(0xFF777777)
            : const Color(0xFF444444);

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor, width: 0.7),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
