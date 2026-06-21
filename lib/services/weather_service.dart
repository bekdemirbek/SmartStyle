import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final String cityName;
  final double temperature;
  final int humidity;
  final String description;
  final String iconCode;
  final String mainCondition;

  WeatherData({
    required this.cityName,
    required this.temperature,
    required this.humidity,
    required this.description,
    required this.iconCode,
    required this.mainCondition,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      cityName: json["name"] ?? "Bilinmeyen Konum",
      temperature: (json["main"]["temp"] ?? 0).toDouble(),
      humidity: json["main"]["humidity"] ?? 0,
      description: json["weather"][0]["description"] ?? "",
      iconCode: json["weather"][0]["icon"] ?? "01d",
      mainCondition: json["weather"][0]["main"] ?? "",
    );
  }
}

class WeatherForecastDay {
  final DateTime date;
  final double temperature;
  final int humidity;
  final String description;
  final String iconCode;
  final String mainCondition;

  const WeatherForecastDay({
    required this.date,
    required this.temperature,
    required this.humidity,
    required this.description,
    required this.iconCode,
    required this.mainCondition,
  });
}

class WeatherLocation {
  final String name;
  final String country;
  final String state;
  final double latitude;
  final double longitude;

  const WeatherLocation({
    required this.name,
    required this.country,
    required this.state,
    required this.latitude,
    required this.longitude,
  });

  factory WeatherLocation.fromJson(Map<String, dynamic> json) {
    return WeatherLocation(
      name: (json["local_names"] is Map &&
              (json["local_names"] as Map)["tr"] != null)
          ? (json["local_names"] as Map)["tr"].toString()
          : (json["name"] ?? "").toString(),
      country: (json["country"] ?? "").toString(),
      state: (json["state"] ?? "").toString(),
      latitude: (json["lat"] as num).toDouble(),
      longitude: (json["lon"] as num).toDouble(),
    );
  }

  String get displayName {
    final parts = [
      name,
      if (state.trim().isNotEmpty) state,
      if (country.trim().isNotEmpty) country,
    ];
    return parts.join(', ');
  }
}

class WeatherService {
  static const String _apiKey = "4b15ea041a69970d02be7e93368d6f52";

  static Future<WeatherData> getWeather({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      "https://api.openweathermap.org/data/2.5/weather"
      "?lat=$latitude&lon=$longitude&appid=$_apiKey&units=metric&lang=tr",
    );

    debugPrint("WEATHER URL: $url");

    final response = await http.get(url);

    debugPrint("WEATHER STATUS CODE: ${response.statusCode}");
    debugPrint("WEATHER RESPONSE BODY: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return WeatherData.fromJson(data);
    } else {
      throw Exception(
        "Hava durumu verisi alınamadı. Kod: ${response.statusCode}",
      );
    }
  }

  static Future<WeatherData> getWeatherByCity(String cityName) async {
    final trimmedCity = cityName.trim();
    final url = Uri.https(
      "api.openweathermap.org",
      "/data/2.5/weather",
      {
        "q": trimmedCity,
        "appid": _apiKey,
        "units": "metric",
        "lang": "tr",
      },
    );

    debugPrint("WEATHER CITY URL: $url");

    final response = await http.get(url);

    debugPrint("WEATHER CITY STATUS CODE: ${response.statusCode}");
    debugPrint("WEATHER CITY RESPONSE BODY: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return WeatherData.fromJson(data);
    }

    throw Exception("Şehir bulunamadı, tekrar deneyin");
  }

  static Future<List<WeatherLocation>> searchCities(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];

    final url = Uri.https(
      "api.openweathermap.org",
      "/geo/1.0/direct",
      {
        "q": trimmedQuery,
        "limit": "8",
        "appid": _apiKey,
      },
    );

    debugPrint("WEATHER GEO URL: $url");

    final response = await http.get(url);

    debugPrint("WEATHER GEO STATUS CODE: ${response.statusCode}");
    debugPrint("WEATHER GEO RESPONSE BODY: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception("Şehir bulunamadı, tekrar deneyin");
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((item) => WeatherLocation.fromJson(Map<String, dynamic>.from(item)))
        .where((location) => location.name.trim().isNotEmpty)
        .toList();
  }

  static Future<List<WeatherForecastDay>> getDailyForecast({
    required double latitude,
    required double longitude,
  }) async {
    final url = Uri.parse(
      "https://api.openweathermap.org/data/2.5/forecast"
      "?lat=$latitude&lon=$longitude&appid=$_apiKey&units=metric&lang=tr",
    );

    debugPrint("FORECAST URL: $url");

    final response = await http.get(url);

    debugPrint("FORECAST STATUS CODE: ${response.statusCode}");
    debugPrint("FORECAST RESPONSE BODY: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception(
        "Hava tahmini alınamadı. Kod: ${response.statusCode}",
      );
    }

    final data = jsonDecode(response.body);
    final rawList = data is Map<String, dynamic> ? data["list"] : null;
    if (rawList is! List) return const [];

    final grouped = <DateTime, List<Map<String, dynamic>>>{};
    for (final item in rawList.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final dateText = (map["dt_txt"] ?? "").toString();
      final parsedDate = DateTime.tryParse(dateText);
      if (parsedDate == null) continue;

      final date = DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
      grouped.putIfAbsent(date, () => []).add(map);
    }

    final days = <WeatherForecastDay>[];
    for (final entry in grouped.entries) {
      final items = entry.value;
      if (items.isEmpty) continue;

      final temps = items
          .map((item) => item["main"])
          .whereType<Map>()
          .map((main) => main["temp"])
          .whereType<num>()
          .map((temp) => temp.toDouble())
          .toList();
      if (temps.isEmpty) continue;

      final humidities = items
          .map((item) => item["main"])
          .whereType<Map>()
          .map((main) => main["humidity"])
          .whereType<num>()
          .map((humidity) => humidity.round())
          .toList();
      final representative = _representativeForecastItem(items);
      final weather = (representative["weather"] is List &&
              (representative["weather"] as List).isNotEmpty)
          ? Map<String, dynamic>.from((representative["weather"] as List).first)
          : const <String, dynamic>{};

      days.add(
        WeatherForecastDay(
          date: entry.key,
          temperature:
              temps.reduce((total, temp) => total + temp) / temps.length,
          humidity: humidities.isEmpty
              ? 0
              : (humidities.reduce((total, item) => total + item) /
                      humidities.length)
                  .round(),
          description: (weather["description"] ?? "").toString(),
          iconCode: (weather["icon"] ?? "01d").toString(),
          mainCondition: (weather["main"] ?? "").toString(),
        ),
      );
    }

    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }

  static Map<String, dynamic> _representativeForecastItem(
    List<Map<String, dynamic>> items,
  ) {
    Map<String, dynamic>? midday;
    var bestDistance = 24;

    for (final item in items) {
      final parsedDate = DateTime.tryParse((item["dt_txt"] ?? "").toString());
      if (parsedDate == null) continue;

      final distance = (parsedDate.hour - 12).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        midday = item;
      }
    }

    return midday ?? items.first;
  }
}
