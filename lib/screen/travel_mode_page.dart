import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../models/outfit_recommendation_models.dart';
import '../models/travel_mode_models.dart';
import '../services/outfit_recommendation_service.dart';
import '../services/travel_plan_repository.dart';
import '../services/travel_mode_service.dart';
import '../services/weather_service.dart';
import 'clothing_detail_page.dart';

class TravelModePage extends StatefulWidget {
  const TravelModePage({super.key});

  @override
  State<TravelModePage> createState() => _TravelModePageState();
}

class _TravelModePageState extends State<TravelModePage> {
  final TravelModeService _travelModeService = TravelModeService();
  final TravelPlanRepository _travelPlanRepository = TravelPlanRepository();
  final OutfitRecommendationService _recommendationService =
      OutfitRecommendationService();
  final TextEditingController _destinationController = TextEditingController(
    text: 'İstanbul',
  );

  int _tripDays = 2;
  String _luggageType = 'carry_on';
  String _packingGoal = 'compact';
  String _tripType = 'gezi';
  bool _isLoading = false;
  bool _isLoadingWeather = false;
  PackingResult? _result;
  String? _activePlanId;
  String? _previousPlanId;
  String? _error;
  String? _weatherError;
  String? _selectedCity;
  WeatherData? _destinationWeather;
  List<WeatherForecastDay> _destinationForecast = const [];
  WeatherLocation? _selectedLocation;
  LatLng? _selectedMapPoint;
  List<_TravelDestinationLeg> _routeLegs = const [];
  List<_TravelDestinationLeg> _activePlanLegs = const [];
  List<WeatherLocation> _citySuggestions = const [];
  int _weatherRequestId = 0;
  int _citySearchRequestId = 0;
  int _planGenerationNonce = 0;
  int _activeGenerationCount = 1;
  bool _isSearchingCities = false;
  Timer? _citySearchDebounce;

  static const Map<String, String> _tripTypeLabels = {
    'bayram_memleket': 'Bayram / Memleket',
    'is_seyahati': 'İş Seyahati',
    'deniz_tatili': 'Deniz Tatili',
    'gezi': 'Gezi',
  };

  static const Map<String, IconData> _tripTypeIcons = {
    'bayram_memleket': Icons.mosque_outlined,
    'is_seyahati': Icons.business_center_outlined,
    'deniz_tatili': Icons.beach_access_outlined,
    'gezi': Icons.map_outlined,
  };

  static const Map<String, String> _occasionDisplayLabels = {
    'travel': 'Yolculuk',
    'casual': 'Günlük',
    'sightseeing': 'Gezi',
    'work': 'İş',
    'dinner': 'Akşam',
    'bayram': 'Bayram',
    'memleket': 'Memleket',
    'beach': 'Deniz',
  };

  @override
  void initState() {
    super.initState();
    _searchCities(_destinationController.text);
  }

  @override
  void dispose() {
    _citySearchDebounce?.cancel();
    _destinationController.dispose();
    super.dispose();
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

  Future<void> _handlePlanButton() async {
    final hasSavedPlan = _result != null && _activePlanId != null;
    if (!hasSavedPlan) {
      await _createPlan();
      return;
    }

    final feedback = await _showPackingFeedbackSheet();
    if (feedback == null) return;
    await _createPlan(feedback: feedback);
  }

  Future<void> _createPlan({PackingFeedback? feedback}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Valiz planı için giriş yapmalısın.');
      return;
    }

    final replacingPlanId = _activePlanId;
    final isRegenerating = _result != null && replacingPlanId != null;
    final parentPlanId = isRegenerating ? replacingPlanId : null;
    final nextGenerationCount =
        isRegenerating ? _activeGenerationCount + 1 : 1;
    if (isRegenerating) _planGenerationNonce++;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final wardrobe = await _recommendationService.fetchWardrobeItems(user.uid);
      final userGender = await _fetchUserGender(user.uid);
      if (wardrobe.isEmpty) {
        setState(() {
          _error = 'Dolabında henüz kıyafet yok. Önce birkaç parça eklemelisin.';
        });
        return;
      }

      final routeLegs = _effectiveRouteLegs();
      final trip = TripDetails(
        destination: routeLegs.map((leg) => leg.cityName).join(' + '),
        tripDays: routeLegs.fold<int>(0, (total, leg) => total + leg.days),
        occasions: _occasionsForRoute(routeLegs),
        weatherTemp: _averageRouteTemp(routeLegs),
        luggageType: _packingGoal == 'compact' ? 'carry_on' : _luggageType,
        departureDate: DateTime.now(),
      );

      final result = _travelModeService.createPackingPlan(
        wardrobe: wardrobe,
        trip: trip,
        userGender: userGender,
        variationSeed: _planGenerationNonce,
        feedback: feedback,
      );

      if (!mounted) return;
      setState(() {
        _activePlanLegs = routeLegs;
        _result = result;
      });

      try {
        if (parentPlanId != null) {
          await _travelPlanRepository.archivePlan(planId: parentPlanId);
        }

        final planId = await _travelPlanRepository.savePlan(
          trip: trip,
          result: result,
          userId: user.uid,
          feedback: feedback,
          parentPlanId: parentPlanId,
          generationCount: nextGenerationCount,
        );
        if (!mounted) return;
        setState(() {
          _activePlanId = planId;
          _previousPlanId = parentPlanId;
          _activeGenerationCount = nextGenerationCount;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              replacingPlanId == null
                  ? 'Valiz planı kaydedildi.'
                  : 'Yeni plan kaydedildi. Önceki plan arşivlendi.',
            ),
          ),
        );
      } catch (e) {
        debugPrint('TRAVEL PLAN SAVE ERROR: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plan hazırlandı ama veritabanına kaydedilemedi.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Valiz planı hazırlanamadı.');
      debugPrint('TRAVEL MODE ERROR: $e');
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppTheme.bg(isDark),
      appBar: AppBar(
        title: const Text('Valiz Asistanı'),
        backgroundColor: AppTheme.bg(isDark),
        elevation: 0,
      ),
      body: AppTheme.auroraBackground(
        isDark: isDark,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _buildTripCard(isDark),
            const SizedBox(height: 14),
            if (_error != null) _buildError(isDark, _error!),
            if (_result != null) ...[
              _buildSummary(isDark, _result!),
              const SizedBox(height: 14),
              _buildSelectedItems(isDark, _result!),
              const SizedBox(height: 14),
              _buildDayPlans(isDark, _result!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard(bool isDark) {
    final canCreatePlan = !_isLoading &&
        !_isLoadingWeather &&
        (_routeLegs.isNotEmpty || _destinationWeather != null);
    final hasSavedPlan = _result != null && _activePlanId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panelDecoration(isDark, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Seyahat Bilgileri',
            style: AppTheme.heading2(isDark),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _destinationController,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            onTap: () => _searchCities(_destinationController.text),
            onChanged: _onDestinationChanged,
            decoration: _fieldDecoration(
              isDark: isDark,
              labelText: 'Gidilecek yer',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          if (_citySuggestions.isNotEmpty || _isSearchingCities)
            _buildCitySuggestions(isDark),
          const SizedBox(height: 8),
          _buildWeatherStatus(isDark),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isLoadingWeather ? null : _openMapPicker,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text(
                'Haritadan seç',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD4A017),
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              ),
            ),
          ),
          if (_destinationWeather != null) ...[
            const SizedBox(height: 6),
            _buildDestinationReadyBanner(isDark),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildDropdown<int>(
                  value: _tripDays,
                  label: 'Bu şehirde gün',
                  items: const [2, 3, 4, 5, 6, 7],
                  itemLabel: (value) => '$value gün',
                  onChanged: (value) => setState(() => _tripDays = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdown<String>(
                  value: _luggageType,
                  label: 'Valiz',
                  items: const ['carry_on', 'checked'],
                  itemLabel: (value) =>
                      value == 'carry_on' ? 'Küçük' : 'Büyük',
                  onChanged: (value) {
                    setState(() {
                      _luggageType = value;
                      _packingGoal = value == 'carry_on' ? 'compact' : 'varied';
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Bu şehir için tatil tipi',
            style: TextStyle(
              color: Colors.grey[300],
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.55,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: _tripTypeLabels.entries.map((entry) {
              return _TripTypeCard(
                title: entry.value,
                icon: _tripTypeIcons[entry.key] ?? Icons.travel_explore,
                selected: _tripType == entry.key,
                onTap: () => setState(() => _tripType = entry.key),
              );
            }).toList(),
          ),
          if (_routeLegs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildRouteLegs(isDark),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canCreatePlan ? _handlePlanButton : null,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      hasSavedPlan
                          ? Icons.refresh_rounded
                          : Icons.luggage_rounded,
                    ),
              label: Text(
                _isLoading
                    ? 'Hazırlanıyor'
                    : hasSavedPlan
                        ? 'Yeniden Üret'
                        : 'Valizi Planla',
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_previousPlanId != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showTravelPlanDetail(_previousPlanId!),
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Önceki Planı Gör'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: _showTravelPlanHistory,
              icon: const Icon(Icons.history_rounded),
              label: const Text('Geçmiş Planlarım'),
            ),
          ),
        ],
      ),
    );
  }

  void _onDestinationChanged(String value) {
    setState(() {
      _selectedCity = null;
      _selectedLocation = null;
      _destinationWeather = null;
      _destinationForecast = const [];
      _weatherError = null;
      _result = null;
    });

    _citySearchDebounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _citySuggestions = const []);
      return;
    }

    _citySearchDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _searchCities(value),
    );
  }

  Future<void> _searchCities(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) return;

    final requestId = ++_citySearchRequestId;
    setState(() {
      _isSearchingCities = true;
      _weatherError = null;
    });

    try {
      final suggestions = await WeatherService.searchCities(trimmedQuery);
      if (!mounted || requestId != _citySearchRequestId) return;
      setState(() {
        _citySuggestions = suggestions;
        if (suggestions.isEmpty) {
          _weatherError = 'Şehir bulunamadı, tekrar deneyin';
        }
      });
    } catch (_) {
      if (!mounted || requestId != _citySearchRequestId) return;
      setState(() {
        _citySuggestions = const [];
        _weatherError = 'Şehir bulunamadı, tekrar deneyin';
      });
    } finally {
      if (!mounted || requestId != _citySearchRequestId) return;
      setState(() => _isSearchingCities = false);
    }
  }

  Future<void> _selectCity(WeatherLocation location) async {
    final requestId = ++_weatherRequestId;
    setState(() {
      _selectedCity = location.name;
      _selectedLocation = location;
      _selectedMapPoint = LatLng(location.latitude, location.longitude);
      _destinationController.text = location.displayName;
      _destinationController.selection = TextSelection.collapsed(
        offset: location.displayName.length,
      );
      _citySuggestions = const [];
      _isLoadingWeather = true;
      _weatherError = null;
      _destinationWeather = null;
      _destinationForecast = const [];
      _result = null;
    });

    try {
      final responses = await Future.wait([
        WeatherService.getWeather(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
        WeatherService.getDailyForecast(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
      ]);
      final weather = responses[0] as WeatherData;
      final forecast = responses[1] as List<WeatherForecastDay>;
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() {
        _destinationWeather = weather;
        _destinationForecast = forecast;
      });
    } catch (e) {
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() => _weatherError = 'Şehir bulunamadı, tekrar deneyin');
    } finally {
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() => _isLoadingWeather = false);
    }
  }

  Future<void> _openMapPicker() async {
    final pickedPoint = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final initialPoint =
            _selectedMapPoint ?? const LatLng(41.0082, 28.9784);
        return _MapPickerSheet(
          isDark: isDark,
          initialPoint: initialPoint,
        );
      },
    );

    if (pickedPoint == null) return;
    await _selectMapPoint(pickedPoint);
  }

  Future<void> _selectMapPoint(LatLng point) async {
    final requestId = ++_weatherRequestId;
    setState(() {
      _selectedMapPoint = point;
      _selectedLocation = null;
      _selectedCity = 'Haritadan seçilen konum';
      _destinationController.text = _selectedCity!;
      _destinationController.selection = TextSelection.collapsed(
        offset: _destinationController.text.length,
      );
      _citySuggestions = const [];
      _isLoadingWeather = true;
      _weatherError = null;
      _destinationWeather = null;
      _destinationForecast = const [];
      _result = null;
    });

    try {
      final responses = await Future.wait([
        WeatherService.getWeather(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
        WeatherService.getDailyForecast(
          latitude: point.latitude,
          longitude: point.longitude,
        ),
      ]);
      final weather = responses[0] as WeatherData;
      final forecast = responses[1] as List<WeatherForecastDay>;
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() {
        _destinationWeather = weather;
        _destinationForecast = forecast;
        _selectedCity = weather.cityName;
        _destinationController.text = weather.cityName;
        _destinationController.selection = TextSelection.collapsed(
          offset: weather.cityName.length,
        );
      });
    } catch (_) {
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() => _weatherError = 'Konum hava durumu alınamadı.');
    } finally {
      if (!mounted || requestId != _weatherRequestId) return;
      setState(() => _isLoadingWeather = false);
    }
  }

  void _addDestinationLeg() {
    final weather = _destinationWeather;
    if (weather == null) return;

    final leg = _TravelDestinationLeg(
      cityName: _selectedCity ?? weather.cityName,
      displayName: _selectedLocation?.displayName ?? weather.cityName,
      days: _tripDays,
      tripType: _tripType,
      temperature: weather.temperature.round(),
      description: weather.description,
      iconCode: weather.iconCode,
      forecastDays: _forecastForTripDays(
        forecast: _destinationForecast,
        fallback: weather,
        days: _tripDays,
      ),
    );

    setState(() {
      _routeLegs = [..._routeLegs, leg];
      _selectedCity = null;
      _selectedLocation = null;
      _selectedMapPoint = null;
      _destinationController.clear();
      _destinationWeather = null;
      _destinationForecast = const [];
      _citySuggestions = const [];
      _weatherError = null;
      _result = null;
    });
  }

  void _removeDestinationLeg(int index) {
    setState(() {
      _routeLegs = [
        for (var i = 0; i < _routeLegs.length; i++)
          if (i != index) _routeLegs[i],
      ];
      _result = null;
    });
  }

  List<_TravelDestinationLeg> _effectiveRouteLegs() {
    if (_routeLegs.isNotEmpty) return _routeLegs;
    final weather = _destinationWeather!;
    return [
      _TravelDestinationLeg(
        cityName: _selectedCity ?? weather.cityName,
        displayName: _selectedLocation?.displayName ?? weather.cityName,
        days: _tripDays,
        tripType: _tripType,
        temperature: weather.temperature.round(),
        description: weather.description,
        iconCode: weather.iconCode,
        forecastDays: _forecastForTripDays(
          forecast: _destinationForecast,
          fallback: weather,
          days: _tripDays,
        ),
      ),
    ];
  }

  int _averageRouteTemp(List<_TravelDestinationLeg> legs) {
    final weightedTotal = legs.fold<int>(
      0,
      (total, leg) => total + (leg.averageTemperature * leg.days),
    );
    final dayTotal = legs.fold<int>(0, (total, leg) => total + leg.days);
    if (dayTotal == 0) return _destinationWeather?.temperature.round() ?? 20;
    return (weightedTotal / dayTotal).round();
  }

  List<WeatherForecastDay> _forecastForTripDays({
    required List<WeatherForecastDay> forecast,
    required WeatherData fallback,
    required int days,
  }) {
    final fallbackDay = WeatherForecastDay(
      date: DateTime.now(),
      temperature: fallback.temperature,
      humidity: fallback.humidity,
      description: fallback.description,
      iconCode: fallback.iconCode,
      mainCondition: fallback.mainCondition,
    );

    return List.generate(days, (index) {
      if (index < forecast.length) return forecast[index];
      return WeatherForecastDay(
        date: fallbackDay.date.add(Duration(days: index)),
        temperature: fallbackDay.temperature,
        humidity: fallbackDay.humidity,
        description: fallbackDay.description,
        iconCode: fallbackDay.iconCode,
        mainCondition: fallbackDay.mainCondition,
      );
    });
  }

  _TravelDestinationLeg? _legForDay(int day) {
    var cursor = 0;
    for (final leg in _activePlanLegs) {
      cursor += leg.days;
      if (day <= cursor) return leg;
    }
    return _activePlanLegs.isEmpty ? null : _activePlanLegs.last;
  }

  Widget _buildCitySuggestions(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppTheme.layer2(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.subtleBorder(isDark)),
      ),
      child: Column(
        children: [
          if (_isSearchingCities)
            const ListTile(
              dense: true,
              leading: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Şehirler aranıyor'),
            ),
          ..._citySuggestions.map((city) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.location_city_outlined, size: 18),
            title: Text(city.displayName),
            onTap: () => _selectCity(city),
          );
          }),
        ],
      ),
    );
  }

  Widget _buildDestinationReadyBanner(bool isDark) {
    final weather = _destinationWeather;
    if (weather == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF202026),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF34343A)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFD4A017),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 16,
              color: Colors.black,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_selectedCity ?? weather.cityName} hazır. Tek şehir için direkt planlayabilirsin.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey[200],
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: _addDestinationLeg,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD4A017),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
            ),
            child: const Text(
              'Rotaya ekle',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherStatus(bool isDark) {
    final weather = _destinationWeather;

    if (_isLoadingWeather) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF202026),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF34343A)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                'Hava durumu alınıyor',
                style: TextStyle(
                  color: Colors.grey[200],
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_weatherError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF202026),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 16),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _weatherError!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (weather == null) {
      return Text(
        'Plan için şehir seçip hava durumunu yükle.',
        style: TextStyle(
          color: Colors.grey[300],
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF202026),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF34343A)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              'https://openweathermap.org/img/wn/${weather.iconCode}@2x.png',
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.cloud_outlined, size: 16),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${weather.temperature.round()}°C · '
                '${_capitalizeFirst(weather.description)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRouteLegs(bool isDark) {
    final totalDays = _routeLegs.fold<int>(0, (total, leg) => total + leg.days);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF202026),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF34343A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rota · $totalDays gün',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ..._routeLegs.asMap().entries.map((entry) {
            final index = entry.key;
            final leg = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Image.network(
                    'https://openweathermap.org/img/wn/${leg.iconCode}@2x.png',
                    width: 28,
                    height: 28,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.cloud_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${leg.days} gün · ${leg.cityName} · '
                      '${_tripTypeLabels[leg.tripType] ?? ''} · '
                      '${leg.averageTemperature}°C ort.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey[200],
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _removeDestinationLeg(index),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String label,
    required List<T> items,
    required String Function(T value) itemLabel,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      dropdownColor: const Color(0xFF202026),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      decoration: _fieldDecoration(
        isDark: Theme.of(context).brightness == Brightness.dark,
        labelText: label,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(itemLabel(item)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  InputDecoration _fieldDecoration({
    required bool isDark,
    required String labelText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon,
      labelStyle: TextStyle(
        color: Colors.grey[300],
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      floatingLabelStyle: const TextStyle(
        color: Color(0xFFD4A017),
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
      filled: true,
      fillColor: const Color(0xFF202026),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF34343A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFD4A017)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2A2A2F)),
      ),
    );
  }

  Widget _buildError(bool isDark, String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(isDark, radius: 16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTheme.body(isDark))),
        ],
      ),
    );
  }

  Widget _buildSummary(bool isDark, PackingResult result) {
    final efficiency = result.pieceCount == 0
        ? 0
        : (result.outfitCount / result.pieceCount).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panelDecoration(isDark, radius: 20),
      child: Row(
        children: [
          _metric(isDark, 'Parça', result.pieceCount.toString()),
          _metric(isDark, 'Kombin', result.outfitCount.toString()),
          _metric(
            isDark,
            'Uyum',
            '${(result.coverageScore * 100).round()}%',
          ),
          _metric(
            isDark,
            'Verimlilik',
            '1 parça · $efficiency kombin',
          ),
        ],
      ),
    );
  }

  Widget _metric(bool isDark, String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.heading2(isDark).copyWith(fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption(isDark).copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedItems(bool isDark, PackingResult result) {
    final keyPieceIds = _keyPieceIds(result);

    return _section(
      isDark: isDark,
      title: 'Valize Giren Parçalar',
      child: SizedBox(
        height: 120,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: result.selectedItems.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = result.selectedItems[index];
            return _PackingItemCard(
              item: item,
              isKeyPiece: keyPieceIds.contains(item.id),
              onTap: () => _openClothingDetail(item),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDayPlans(bool isDark, PackingResult result) {
    return _section(
      isDark: isDark,
      title: 'Gün Gün Plan',
      child: Column(
        children: result.dayPlans
            .map(
              (plan) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TravelDayOutfitCard(
                  plan: plan,
                  occasionLabel: _dayTitle(plan),
                  weatherText: _dayWeatherText(plan.day),
                  onTap: () => _openTravelDayDetail(plan),
                  onItemTap: _openClothingDetail,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Set<String> _keyPieceIds(PackingResult result) {
    final counts = <String, int>{};
    for (final plan in result.dayPlans) {
      for (final item in plan.outfitItems) {
        counts[item.id] = (counts[item.id] ?? 0) + 1;
      }
    }
    return counts.entries
        .where((entry) => entry.value >= 3)
        .map((entry) => entry.key)
        .toSet();
  }

  List<String> _occasionsForRoute(List<_TravelDestinationLeg> legs) {
    final occasions = <String>[];

    for (final leg in legs) {
      final legOccasions = _occasionsForTripType(leg.tripType);
      for (var day = 0; day < leg.days; day++) {
        occasions.add(legOccasions[day % legOccasions.length]);
      }
    }

    if (_packingGoal == 'compact') {
      return occasions.isEmpty ? _occasionsForTripType(_tripType) : occasions;
    }

    return [
      ...occasions,
      if (!occasions.contains('casual')) 'casual',
      if (!occasions.contains('dinner')) 'dinner',
    ];
  }

  List<String> _occasionsForTripType(String tripType) {
    switch (tripType) {
      case 'bayram_memleket':
        return ['travel', 'bayram', 'memleket', 'dinner'];
      case 'is_seyahati':
        return ['travel', 'work', 'dinner'];
      case 'deniz_tatili':
        return ['travel', 'beach', 'casual', 'sightseeing'];
      case 'gezi':
        return ['travel', 'sightseeing', 'casual'];
    }
    return ['travel', 'casual'];
  }

  String? _occasionLabel(String occasion) {
    return _occasionDisplayLabels[occasion] ?? _tripTypeLabels[occasion];
  }

  String _dayTitle(TravelDayPlan plan) {
    final leg = _legForDay(plan.day);
    final tripLabel = leg == null
        ? (_tripTypeLabels[_tripType] ?? _occasionLabel(plan.occasion) ?? '')
        : (_tripTypeLabels[leg.tripType] ?? _occasionLabel(plan.occasion) ?? '');
    if (leg == null) return tripLabel;
    return '${leg.cityName} · $tripLabel';
  }

  String _dayWeatherText(int day) {
    var cursor = 0;
    for (final leg in _activePlanLegs) {
      final localDay = day - cursor;
      if (localDay >= 1 && localDay <= leg.days) {
        final forecast = leg.forecastForDay(localDay);
        return '${forecast.temperature.round()}°C · ${_capitalizeFirst(forecast.description)}';
      }
      cursor += leg.days;
    }
    final weather = _destinationWeather;
    if (weather == null) return '';
    final forecast = _forecastForTripDays(
      forecast: _destinationForecast,
      fallback: weather,
      days: _tripDays,
    );
    final index = day - 1;
    if (index >= 0 && index < forecast.length) {
      final dayForecast = forecast[index];
      return '${dayForecast.temperature.round()}°C · ${_capitalizeFirst(dayForecast.description)}';
    }
    return '${weather.temperature.round()}°C';
  }

  void _openTravelDayDetail(TravelDayPlan plan) {
    // TODO: Save Travel Mode day outfits and pass the saved outfitId to
    // OutfitDetailPage. Current OutfitDetailPage requires a persisted outfitId.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${plan.outfitItemIds.length} parça seçildi. Detay sayfası kayıtlı outfitId bekliyor.',
        ),
      ),
    );
  }

  void _openClothingDetail(ClothingItem item) {
    if (item.collection.trim().isEmpty || item.id.trim().isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClothingDetailPage(
          collection: item.collection,
          documentId: item.id,
        ),
      ),
    );
  }

  Future<PackingFeedback?> _showPackingFeedbackSheet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final wardrobe = await _recommendationService.fetchWardrobeItems(user.uid);
    if (!mounted) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final complaintOptions = const <String, ({String label, IconData icon})>{
      'too_repetitive': (label: 'Çok tekrar var', icon: Icons.repeat_rounded),
      'too_formal': (label: 'Çok formal', icon: Icons.business_center_outlined),
      'color_mismatch': (label: 'Renkler uyumsuz', icon: Icons.palette_outlined),
      'too_many_items': (label: 'Fazla parça', icon: Icons.inventory_2_outlined),
      'weather_wrong': (label: 'Hava için yanlış', icon: Icons.cloud_outlined),
      'general': (label: 'Genel olarak', icon: Icons.tune_rounded),
    };

    return showModalBottomSheet<PackingFeedback>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final selectedComplaints = <String>{};
        final pinnedItemIds = <String>{};
        final excludedItemIds = <String>{};

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget itemPicker({
              required String title,
              required Set<String> selectedIds,
              required Set<String> blockedIds,
              required ValueChanged<String> onToggle,
            }) {
              final candidates = wardrobe.take(20).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final item = candidates[index];
                        final selected = selectedIds.contains(item.id);
                        final blocked = blockedIds.contains(item.id);
                        return _FeedbackWardrobeCard(
                          item: item,
                          selected: selected,
                          disabled: blocked,
                          onTap: blocked
                              ? null
                              : () {
                                  setSheetState(() => onToggle(item.id));
                                },
                        );
                      },
                    ),
                  ),
                ],
              );
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.86,
              minChildSize: 0.55,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bg(isDark),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _sheetHandle(isDark),
                      const SizedBox(height: 14),
                      Text('Neyi değiştirelim?', style: AppTheme.heading2(isDark)),
                      const SizedBox(height: 14),
                      Text(
                        'Ne beğenmedin?',
                        style: AppTheme.caption(isDark).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: complaintOptions.entries.map((entry) {
                          final selected = selectedComplaints.contains(entry.key);
                          return FilterChip(
                            selected: selected,
                            avatar: Icon(entry.value.icon, size: 16),
                            label: Text(entry.value.label),
                            onSelected: (_) {
                              setSheetState(() {
                                if (selected) {
                                  selectedComplaints.remove(entry.key);
                                } else {
                                  selectedComplaints.add(entry.key);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      itemPicker(
                        title: 'Hangi parçayı kesinlikle iste? (en fazla 2)',
                        selectedIds: pinnedItemIds,
                        blockedIds: excludedItemIds,
                        onToggle: (itemId) {
                          if (pinnedItemIds.contains(itemId)) {
                            pinnedItemIds.remove(itemId);
                          } else if (pinnedItemIds.length < 2) {
                            pinnedItemIds.add(itemId);
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      itemPicker(
                        title: 'Hangi parçayı hiç istemiyorsun? (en fazla 2)',
                        selectedIds: excludedItemIds,
                        blockedIds: pinnedItemIds,
                        onToggle: (itemId) {
                          if (excludedItemIds.contains(itemId)) {
                            excludedItemIds.remove(itemId);
                          } else if (excludedItemIds.length < 2) {
                            excludedItemIds.add(itemId);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop(
                              PackingFeedback(
                                complaints: selectedComplaints.toList(),
                                pinnedItemIds: pinnedItemIds.toList(),
                                excludedItemIds: excludedItemIds.toList(),
                                givenAt: DateTime.now(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Yeniden Üret'),
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

  Future<void> _showTravelPlanHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'Geçmiş planlar için giriş yapmalısın.');
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.bg(isDark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: FutureBuilder<List<TravelPlanSummary>>(
                future: _travelPlanRepository.fetchActivePlans(
                  userId: user.uid,
                ),
                builder: (context, snapshot) {
                  final plans = snapshot.data ?? const <TravelPlanSummary>[];

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _sheetHandle(isDark),
                      const SizedBox(height: 14),
                      Text('Geçmiş Planlarım', style: AppTheme.heading2(isDark)),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (snapshot.hasError)
                        _buildError(isDark, 'Planlar yüklenemedi.')
                      else if (plans.isEmpty)
                        Text(
                          'Henüz kayıtlı valiz planın yok.',
                          style: AppTheme.body(isDark),
                        )
                      else
                        ...plans.map(
                          (plan) => _TravelPlanSummaryTile(
                            plan: plan,
                            isActive: plan.planId == _activePlanId,
                            onTap: () {
                              Navigator.of(context).pop();
                              _showTravelPlanDetail(plan.planId);
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showTravelPlanDetail(String planId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.48,
          maxChildSize: 0.94,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.bg(isDark),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: FutureBuilder<TravelPlanDetail?>(
                future: _travelPlanRepository.fetchPlanDetail(planId: planId),
                builder: (context, detailSnapshot) {
                  final detail = detailSnapshot.data;

                  if (detailSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (detailSnapshot.hasError || detail == null) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _sheetHandle(isDark),
                        const SizedBox(height: 14),
                        _buildError(isDark, 'Plan detayı yüklenemedi.'),
                      ],
                    );
                  }

                  final itemIds = <String>{
                    ...detail.selectedItemIds,
                    for (final plan in detail.dayPlans) ...plan.outfitItemIds,
                  };

                  return FutureBuilder<List<ClothingItem>>(
                    future: _recommendationService.fetchWardrobeItemsByIds(
                      userId: user.uid,
                      itemIds: itemIds,
                    ),
                    builder: (context, itemSnapshot) {
                      final itemsById = {
                        for (final item in itemSnapshot.data ??
                            const <ClothingItem>[])
                          item.id: item,
                      };

                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          _sheetHandle(isDark),
                          const SizedBox(height: 14),
                          Text(
                            detail.summary.destination,
                            style: AppTheme.heading2(isDark),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${detail.summary.tripDays} gün · '
                            '${detail.summary.pieceCount} parça · '
                            '${(detail.summary.coverageScore * 100).round()}% uyum',
                            style: AppTheme.caption(isDark),
                          ),
                          const SizedBox(height: 16),
                          if (itemSnapshot.connectionState ==
                              ConnectionState.waiting)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          else ...[
                            _SavedSelectedItemsStrip(
                              itemIds: detail.selectedItemIds,
                              itemsById: itemsById,
                            ),
                            const SizedBox(height: 14),
                            ...detail.dayPlans.map(
                              (dayPlan) => _SavedTravelDayCard(
                                planId: planId,
                                dayPlan: dayPlan,
                                itemsById: itemsById,
                                repository: _travelPlanRepository,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetHandle(bool isDark) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.tertiaryText(isDark).withOpacity(0.5),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _section({
    required bool isDark,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panelDecoration(isDark, radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.heading2(isDark)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String _capitalizeFirst(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _MapPickerSheet extends StatefulWidget {
  final bool isDark;
  final LatLng initialPoint;

  const _MapPickerSheet({
    required this.isDark,
    required this.initialPoint,
  });

  @override
  State<_MapPickerSheet> createState() => _MapPickerSheetState();
}

class _TravelDestinationLeg {
  final String cityName;
  final String displayName;
  final int days;
  final String tripType;
  final int temperature;
  final String description;
  final String iconCode;
  final List<WeatherForecastDay> forecastDays;

  const _TravelDestinationLeg({
    required this.cityName,
    required this.displayName,
    required this.days,
    required this.tripType,
    required this.temperature,
    required this.description,
    required this.iconCode,
    this.forecastDays = const [],
  });

  WeatherForecastDay forecastForDay(int localDay) {
    final index = localDay - 1;
    if (index >= 0 && index < forecastDays.length) {
      return forecastDays[index];
    }
    return WeatherForecastDay(
      date: DateTime.now().add(Duration(days: index < 0 ? 0 : index)),
      temperature: temperature.toDouble(),
      humidity: 0,
      description: description,
      iconCode: iconCode,
      mainCondition: '',
    );
  }

  int get averageTemperature {
    if (forecastDays.isEmpty) return temperature;
    final usableDays = forecastDays.take(days).toList();
    final total = usableDays.fold<double>(
      0,
      (sum, forecast) => sum + forecast.temperature,
    );
    return (total / usableDays.length).round();
  }
}

class _TravelPlanSummaryTile extends StatelessWidget {
  final TravelPlanSummary plan;
  final bool isActive;
  final VoidCallback onTap;

  const _TravelPlanSummaryTile({
    required this.plan,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final createdAt = plan.createdAt;
    final statusText = switch (plan.status) {
      'archived' => 'Arşiv',
      'completed' => 'Tamamlandı',
      _ => 'Aktif',
    };
    final dateText = createdAt == null
        ? ''
        : '${createdAt.day.toString().padLeft(2, '0')}.'
            '${createdAt.month.toString().padLeft(2, '0')}.'
            '${createdAt.year}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF171717),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive
                    ? const Color(0xFFD4A017)
                    : const Color(0xFF2A2A2A),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.luggage_rounded, color: Color(0xFFD4A017)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.destination.isEmpty
                            ? 'Valiz planı'
                            : plan.destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${plan.tripDays} gün · ${plan.pieceCount} parça · '
                        '${plan.outfitCount} kombin · '
                        '${(plan.coverageScore * 100).round()}% uyum'
                        '${dateText.isEmpty ? '' : ' · $dateText'} · $statusText',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackWardrobeCard extends StatelessWidget {
  final ClothingItem item;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  const _FeedbackWardrobeCard({
    required this.item,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = item.subCategory.trim().isEmpty ? item.category.name : item.subCategory;
    final borderColor = selected
        ? const Color(0xFFD4A017)
        : disabled
            ? const Color(0xFF2A2A2A)
            : const Color(0xFF34343A);

    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            width: 82,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF2A2516) : const Color(0xFF171717),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                Expanded(child: _SmallOutfitImage(imageUrl: item.imageUrl)),
                const SizedBox(height: 5),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedSelectedItemsStrip extends StatelessWidget {
  final List<String> itemIds;
  final Map<String, ClothingItem> itemsById;

  const _SavedSelectedItemsStrip({
    required this.itemIds,
    required this.itemsById,
  });

  @override
  Widget build(BuildContext context) {
    if (itemIds.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: itemIds.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = itemsById[itemIds[index]];
          return _SavedPackingItemCard(item: item, fallbackId: itemIds[index]);
        },
      ),
    );
  }
}

class _SavedTravelDayCard extends StatefulWidget {
  final String planId;
  final SavedDayPlan dayPlan;
  final Map<String, ClothingItem> itemsById;
  final TravelPlanRepository repository;

  const _SavedTravelDayCard({
    required this.planId,
    required this.dayPlan,
    required this.itemsById,
    required this.repository,
  });

  @override
  State<_SavedTravelDayCard> createState() => _SavedTravelDayCardState();
}

class _SavedTravelDayCardState extends State<_SavedTravelDayCard> {
  late Set<String> _checkedItems;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _checkedItems = widget.dayPlan.checkedItems.toSet();
  }

  Future<void> _toggleChecked(String itemId, bool checked) async {
    final nextChecked = {..._checkedItems};
    if (checked) {
      nextChecked.add(itemId);
    } else {
      nextChecked.remove(itemId);
    }

    setState(() {
      _checkedItems = nextChecked;
      _isSaving = true;
    });

    try {
      await widget.repository.updateDayCheckedItems(
        planId: widget.planId,
        dayPlanId: widget.dayPlan.dayPlanId,
        checkedItems: nextChecked.toList(),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openItemDetail(ClothingItem? item) {
    if (item == null) return;
    if (item.collection.trim().isEmpty || item.id.trim().isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ClothingDetailPage(
          collection: item.collection,
          documentId: item.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4A017),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  widget.dayPlan.day.toString(),
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.dayPlan.occasion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_isSaving)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (widget.dayPlan.note.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.dayPlan.note,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...widget.dayPlan.outfitItemIds.map((itemId) {
            final item = widget.itemsById[itemId];
            return CheckboxListTile(
              value: _checkedItems.contains(itemId),
              onChanged: _isSaving
                  ? null
                  : (value) => _toggleChecked(itemId, value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(
                children: [
                  GestureDetector(
                    onTap: () => _openItemDetail(item),
                    child: _SmallOutfitImage(imageUrl: item?.imageUrl ?? ''),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _openItemDetail(item),
                      child: Text(
                        item?.subCategory ?? itemId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SavedPackingItemCard extends StatelessWidget {
  final ClothingItem? item;
  final String fallbackId;

  const _SavedPackingItemCard({
    required this.item,
    required this.fallbackId,
  });

  @override
  Widget build(BuildContext context) {
    final name = item?.subCategory.trim().isNotEmpty == true
        ? item!.subCategory
        : fallbackId;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item == null
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClothingDetailPage(
                      collection: item!.collection,
                      documentId: item!.id,
                    ),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 90,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
          ),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: _SmallOutfitImage(imageUrl: item?.imageUrl ?? ''),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackingItemCard extends StatelessWidget {
  final ClothingItem item;
  final bool isKeyPiece;
  final VoidCallback onTap;

  const _PackingItemCard({
    required this.item,
    required this.isKeyPiece,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.imageUrl.toString();
    final name = item.subCategory.toString().trim().isEmpty
        ? item.category.name.toString()
        : item.subCategory.toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 90,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 0.5),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: imageUrl.isEmpty
                            ? Icon(
                                Icons.checkroom,
                                color: Colors.grey[600],
                                size: 32,
                              )
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.checkroom,
                                  color: Colors.grey[600],
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Center(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isKeyPiece)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4A017),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.star,
                        size: 10,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTypeCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TripTypeCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? const Color(0xFFD4A017)
        : const Color(0xFF34343A);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2A2516) : const Color(0xFF202026),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? const Color(0xFFD4A017) : Colors.grey[500],
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TravelDayOutfitCard extends StatelessWidget {
  final TravelDayPlan plan;
  final String occasionLabel;
  final String weatherText;
  final VoidCallback onTap;
  final ValueChanged<ClothingItem> onItemTap;

  const _TravelDayOutfitCard({
    required this.plan,
    required this.occasionLabel,
    required this.weatherText,
    required this.onTap,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF222222), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFFD4A017),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      plan.day.toString(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      occasionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (weatherText.isNotEmpty)
                    Flexible(
                      child: Text(
                        weatherText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: plan.outfitItems.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final item = plan.outfitItems[index];
                    return GestureDetector(
                      onTap: () => onItemTap(item),
                      child: _SmallOutfitImage(imageUrl: item.imageUrl),
                    );
                  },
                ),
              ),
              if (plan.note.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  plan.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallOutfitImage extends StatelessWidget {
  final String imageUrl;

  const _SmallOutfitImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.trim().isEmpty
          ? Icon(Icons.checkroom, color: Colors.grey[600], size: 24)
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.checkroom,
                color: Colors.grey[600],
                size: 24,
              ),
            ),
    );
  }
}

class _MapPickerSheetState extends State<_MapPickerSheet> {
  late LatLng _pickedPoint;

  @override
  void initState() {
    super.initState();
    _pickedPoint = widget.initialPoint;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.bg(widget.isDark),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.tertiaryText(widget.isDark).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Konum Seç',
                        style: AppTheme.heading2(widget.isDark),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: _pickedPoint,
                        initialZoom: 8,
                        onTap: (_, point) {
                          setState(() => _pickedPoint = point);
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.smartstyle.deneme_1',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pickedPoint,
                              width: 46,
                              height: 46,
                              child: Icon(
                                Icons.location_on_rounded,
                                color: AppTheme.gold(widget.isDark),
                                size: 42,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(_pickedPoint),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Bu konumu kullan'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
