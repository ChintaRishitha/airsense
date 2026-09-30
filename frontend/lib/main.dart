import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const AirSenseApp());
}

// ============================================================
// APP
// ============================================================

class AirSenseApp extends StatelessWidget {
  const AirSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AirSense',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xfff5f7fb),
      ),
      home: const DashboardPage(),
    );
  }
}

// ============================================================
// AIR QUALITY MODEL
// ============================================================

class AirQualityData {
  final double aqi;
  final double pm25;
  final double pm10;
  final double co;
  final double no2;
  final double so2;
  final double o3;
  final String time;

  AirQualityData({
    required this.aqi,
    required this.pm25,
    required this.pm10,
    required this.co,
    required this.no2,
    required this.so2,
    required this.o3,
    required this.time,
  });

  factory AirQualityData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] ?? {};

    return AirQualityData(
      aqi: _toDouble(current['us_aqi']),
      pm25: _toDouble(current['pm2_5']),
      pm10: _toDouble(current['pm10']),
      co: _toDouble(current['carbon_monoxide']),
      no2: _toDouble(current['nitrogen_dioxide']),
      so2: _toDouble(current['sulphur_dioxide']),
      o3: _toDouble(current['ozone']),
      time: current['time']?.toString() ?? '',
    );
  }
}

// ============================================================
// WEATHER MODEL
// ============================================================

class WeatherData {
  final double temperature;
  final double humidity;
  final double windSpeed;
  final String time;

  WeatherData({
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.time,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final current = json['current'] ?? {};

    return WeatherData(
      temperature: _toDouble(current['temperature_2m']),
      humidity: _toDouble(current['relative_humidity_2m']),
      windSpeed: _toDouble(current['wind_speed_10m']),
      time: current['time']?.toString() ?? '',
    );
  }
}

// ============================================================
// HOURLY AQI MODEL
// ============================================================

class HourlyAqiPoint {
  final DateTime time;
  final double aqi;

  HourlyAqiPoint({
    required this.time,
    required this.aqi,
  });
}

// ============================================================
// SAFE NUMBER CONVERSION
// ============================================================

double _toDouble(dynamic value) {
  if (value == null) {
    return 0;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value.toString()) ?? 0;
}

// ============================================================
// DASHBOARD
// ============================================================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  AirQualityData? airData;
  WeatherData? weatherData;

  List<HourlyAqiPoint> hourlyAqi = [];

  bool loading = true;
  bool geminiLoading = false;

  String? error;

  double latitude = 17.3850;
  double longitude = 78.4867;

  String cityName = 'Hyderabad';
  String countryName = 'India';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  // ==========================================================
  // GEMINI AI ANALYSIS
  // ==========================================================

  Future<void> analyzeWithGemini() async {
    if (airData == null || weatherData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Air-quality data is not available yet.',
          ),
        ),
      );
      return;
    }

    setState(() {
      geminiLoading = true;
    });

    try {
      // ======================================================
      // DEPLOYED RENDER BACKEND
      // ======================================================

      final response = await http.post(
        Uri.parse(
          'https://airsense-backend-m1iw.onrender.com/api/analyze-air',
        ),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'city': cityName,
          'country': countryName,

          // Air quality
          'aqi': airData!.aqi,
          'pm25': airData!.pm25,
          'pm10': airData!.pm10,
          'co': airData!.co,
          'no2': airData!.no2,
          'so2': airData!.so2,
          'o3': airData!.o3,

          // Weather
          'temperature': weatherData!.temperature,
          'humidity': weatherData!.humidity,
          'windSpeed': weatherData!.windSpeed,
        }),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        geminiLoading = false;
      });

      // ======================================================
      // SUCCESS
      // ======================================================

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map<String, dynamic>) {
          showGeminiResult(decoded);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Invalid response received from Gemini backend.',
              ),
            ),
          );
        }
      }

      // ======================================================
      // ERROR RESPONSE
      // ======================================================

      else {
        String message = 'Gemini request failed.';

        try {
          final errorData = jsonDecode(response.body);

          if (errorData is Map<String, dynamic>) {
            if (errorData['message'] != null) {
              message = errorData['message'].toString();
            } else if (errorData['error'] != null) {
              message = errorData['error'].toString();
            }
          }
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Gemini Error: $message',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        geminiLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not connect to AirSense backend.\n$e',
          ),
        ),
      );
    }
  }

  // ==========================================================
  // GEMINI RESULT DIALOG
  // ==========================================================

  void showGeminiResult(Map<String, dynamic> result) {
    final recommendations = result['recommendations'] is List
        ? List.from(result['recommendations'])
        : <dynamic>[];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: Colors.blue,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text('Gemini AI Analysis'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SUMMARY
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  result['summary']?.toString() ??
                      'No summary available.',
                ),

                const SizedBox(height: 18),

                // MAIN POLLUTANT
                const Text(
                  'Main Pollutant',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  result['mainPollutant']?.toString() ??
                      'Unknown',
                ),

                const SizedBox(height: 18),

                // HEALTH
                const Text(
                  'Health Considerations',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  result['healthConsiderations']?.toString() ??
                      'No information available.',
                ),

                const SizedBox(height: 18),

                // OUTDOOR ADVICE
                const Text(
                  'Outdoor Advice',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  result['outdoorAdvice']?.toString() ??
                      'No advice available.',
                ),

                const SizedBox(height: 18),

                // RECOMMENDATIONS
                const Text(
                  'Recommendations',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (recommendations.isEmpty)
                  const Text(
                    'No recommendations available.',
                  ),

                ...recommendations.map(
                  (item) {
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: 8,
                      ),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '• ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              item.toString(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // SEARCH LOCATION
  // ==========================================================

  Future<void> searchLocation(String city) async {
    if (city.trim().isEmpty) {
      setState(() {
        error = 'Please enter a city name.';
      });
      return;
    }

    try {
      setState(() {
        loading = true;
        error = null;
      });

      final encodedCity =
          Uri.encodeComponent(city.trim());

      final url = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=$encodedCity'
        '&count=1'
        '&language=en'
        '&format=json',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception(
          'Location search failed: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data['results'] == null ||
          data['results'].isEmpty) {
        throw Exception(
          'Location not found. Please try another city.',
        );
      }

      final location = data['results'][0];

      latitude = _toDouble(
        location['latitude'],
      );

      longitude = _toDouble(
        location['longitude'],
      );

      cityName =
          location['name']?.toString() ?? city;

      countryName =
          location['country']?.toString() ?? '';

      await Future.wait([
        fetchAirQuality(),
        fetchWeather(),
        fetchHourlyAqi(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  // ==========================================================
  // CURRENT AIR QUALITY
  // ==========================================================

  Future<void> fetchAirQuality() async {
    final url = Uri.parse(
      'https://air-quality-api.open-meteo.com/v1/air-quality'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current='
      'us_aqi,'
      'pm2_5,'
      'pm10,'
      'carbon_monoxide,'
      'nitrogen_dioxide,'
      'sulphur_dioxide,'
      'ozone'
      '&timezone=auto',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Air Quality API Error: ${response.statusCode}',
      );
    }

    final jsonData = jsonDecode(response.body);

    airData =
        AirQualityData.fromJson(jsonData);
  }

  // ==========================================================
  // WEATHER
  // ==========================================================

  Future<void> fetchWeather() async {
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current='
      'temperature_2m,'
      'relative_humidity_2m,'
      'wind_speed_10m'
      '&timezone=auto',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Weather API Error: ${response.statusCode}',
      );
    }

    final jsonData = jsonDecode(response.body);

    weatherData =
        WeatherData.fromJson(jsonData);
  }

  // ==========================================================
  // HOURLY AQI
  // ==========================================================

  Future<void> fetchHourlyAqi() async {
    final url = Uri.parse(
      'https://air-quality-api.open-meteo.com/v1/air-quality'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&hourly=us_aqi'
      '&past_days=1'
      '&forecast_days=1'
      '&timezone=auto',
    );

    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception(
        'Hourly AQI API Error: ${response.statusCode}',
      );
    }

    final jsonData = jsonDecode(response.body);

    final hourly = jsonData['hourly'];

    if (hourly == null) {
      hourlyAqi = [];
      return;
    }

    final times =
        List<dynamic>.from(
      hourly['time'] ?? [],
    );

    final aqiValues =
        List<dynamic>.from(
      hourly['us_aqi'] ?? [],
    );

    final List<HourlyAqiPoint> points = [];

    final count = times.length <
            aqiValues.length
        ? times.length
        : aqiValues.length;

    for (int i = 0; i < count; i++) {
      final timeString =
          times[i].toString();

      final parsedTime =
          DateTime.tryParse(timeString);

      final aqi =
          _toDouble(aqiValues[i]);

      if (parsedTime != null) {
        points.add(
          HourlyAqiPoint(
            time: parsedTime,
            aqi: aqi,
          ),
        );
      }
    }

    if (points.length > 24) {
      hourlyAqi =
          points.sublist(
        points.length - 24,
      );
    } else {
      hourlyAqi = points;
    }
  }

  // ==========================================================
  // FETCH EVERYTHING
  // ==========================================================

  Future<void> fetchAllData() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }

    try {
      await Future.wait([
        fetchAirQuality(),
        fetchWeather(),
        fetchHourlyAqi(),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  // ==========================================================
  // AQI STATUS
  // ==========================================================

  String getAqiStatus(double aqi) {
    if (aqi <= 50) {
      return 'Good';
    }

    if (aqi <= 100) {
      return 'Moderate';
    }

    if (aqi <= 150) {
      return 'Unhealthy for Sensitive Groups';
    }

    if (aqi <= 200) {
      return 'Unhealthy';
    }

    if (aqi <= 300) {
      return 'Very Unhealthy';
    }

    return 'Hazardous';
  }

  // ==========================================================
  // AQI COLOR
  // ==========================================================

  Color getAqiColor(double aqi) {
    if (aqi <= 50) {
      return Colors.green;
    }

    if (aqi <= 100) {
      return Colors.orange;
    }

    if (aqi <= 150) {
      return Colors.deepOrange;
    }

    if (aqi <= 200) {
      return Colors.red;
    }

    if (aqi <= 300) {
      return Colors.purple;
    }

    return Colors.brown;
  }

  // ==========================================================
  // AQI ICON
  // ==========================================================

  IconData getAqiIcon(double aqi) {
    if (aqi <= 50) {
      return Icons.sentiment_very_satisfied;
    }

    if (aqi <= 100) {
      return Icons.sentiment_satisfied;
    }

    if (aqi <= 150) {
      return Icons.sentiment_neutral;
    }

    if (aqi <= 200) {
      return Icons.sentiment_dissatisfied;
    }

    return Icons.warning_amber_rounded;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.air),
            SizedBox(width: 10),
            Text(
              'AirSense',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed:
                loading ? null : fetchAllData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh live data',
          ),
        ],
      ),

      // ======================================================
      // DRAWER
      // ======================================================

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration:
                  const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue,
                    Colors.lightBlue,
                  ],
                ),
              ),
              child: const Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.air,
                    color: Colors.white,
                    size: 45,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'AirSense',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Real-Time Air Quality',
                    style: TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

            ListTile(
              leading:
                  const Icon(Icons.dashboard),
              title:
                  const Text('Dashboard'),
              selected: true,
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading:
                  const Icon(Icons.air),
              title:
                  const Text('Air Quality'),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading:
                  const Icon(Icons.science),
              title:
                  const Text('Pollutants'),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading:
                  const Icon(Icons.smart_toy),
              title:
                  const Text('AI Analysis'),
              onTap: () {
                Navigator.pop(context);

                if (!geminiLoading) {
                  analyzeWithGemini();
                }
              },
            ),

            ListTile(
              leading:
                  const Icon(Icons.history),
              title:
                  const Text('History'),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            ListTile(
              leading:
                  const Icon(Icons.settings),
              title:
                  const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),

      // ======================================================
      // BODY
      // ======================================================

      body: RefreshIndicator(
        onRefresh: fetchAllData,
        child: SingleChildScrollView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding:
              const EdgeInsets.all(16),
          child: loading
              ? const SizedBox(
                  height: 600,
                  child: Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          'Fetching real-time data...',
                          style: TextStyle(
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : error != null
                  ? buildError()
                  : buildDashboard(),
        ),
      ),
    );
  }

  // ==========================================================
  // ERROR SCREEN
  // ==========================================================

  Widget buildError() {
    return SizedBox(
      height: 500,
      child: Center(
        child: Card(
          child: Padding(
            padding:
                const EdgeInsets.all(25),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 60,
                ),

                const SizedBox(height: 15),

                const Text(
                  'Unable to fetch live data',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                  ),
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 10),

                Text(
                  error ?? 'Unknown error',
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 20),

                ElevatedButton.icon(
                  onPressed:
                      fetchAllData,
                  icon:
                      const Icon(Icons.refresh),
                  label:
                      const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // DASHBOARD
  // ==========================================================

  Widget buildDashboard() {
    final air = airData!;
    final weather = weatherData!;

    final aqiColor =
        getAqiColor(air.aqi);

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        const Text(
          'Air Quality Dashboard',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 8),

        // LOCATION SEARCH
        LocationSearchBox(
          currentCity: cityName,
          onSearch: searchLocation,
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            const Icon(
              Icons.location_on,
              color: Colors.red,
              size: 18,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '$cityName, $countryName',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ====================================================
        // AQI CARD
        // ====================================================

        Card(
          elevation: 3,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(20),
          ),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(25),
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(20),
              gradient:
                  LinearGradient(
                colors: [
                  aqiColor.withOpacity(0.18),
                  Colors.white,
                ],
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Current Air Quality Index',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 15),

                Icon(
                  getAqiIcon(air.aqi),
                  size: 55,
                  color: aqiColor,
                ),

                const SizedBox(height: 5),

                Text(
                  air.aqi.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 65,
                    fontWeight:
                        FontWeight.bold,
                    color: aqiColor,
                  ),
                ),

                Text(
                  getAqiStatus(air.aqi),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight:
                        FontWeight.bold,
                    color: aqiColor,
                  ),
                  textAlign:
                      TextAlign.center,
                ),

                const SizedBox(height: 10),

                const Text(
                  'U.S. AQI',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 25),

        // ====================================================
        // AQI HISTORY
        // ====================================================

        const Text(
          '24-Hour AQI History',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        buildAqiChart(),

        const SizedBox(height: 25),

        // ====================================================
        // WEATHER
        // ====================================================

        const Text(
          'Current Weather',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: weatherCard(
                'Temperature',
                '${weather.temperature.toStringAsFixed(1)} °C',
                Icons.thermostat,
                Colors.orange,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: weatherCard(
                'Humidity',
                '${weather.humidity.toStringAsFixed(0)} %',
                Icons.water_drop,
                Colors.blue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        weatherCard(
          'Wind Speed',
          '${weather.windSpeed.toStringAsFixed(1)} km/h',
          Icons.air,
          Colors.teal,
        ),

        const SizedBox(height: 25),

        // ====================================================
        // POLLUTANTS
        // ====================================================

        const Text(
          'Live Pollutant Levels',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 12),

        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            pollutantCard(
              'PM2.5',
              air.pm25,
              Icons.blur_on,
              Colors.orange,
            ),

            pollutantCard(
              'PM10',
              air.pm10,
              Icons.cloud,
              Colors.deepOrange,
            ),

            pollutantCard(
              'CO',
              air.co,
              Icons.cloud_queue,
              Colors.blue,
            ),

            pollutantCard(
              'NO₂',
              air.no2,
              Icons.science,
              Colors.purple,
            ),

            pollutantCard(
              'SO₂',
              air.so2,
              Icons.factory,
              Colors.red,
            ),

            pollutantCard(
              'O₃',
              air.o3,
              Icons.wb_sunny,
              Colors.green,
            ),
          ],
        ),

        const SizedBox(height: 25),

        // ====================================================
        // AI ANALYSIS
        // ====================================================

        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(18),
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.smart_toy,
                      color: Colors.blue,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'AI Air Quality Analysis',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 15),

                Text(
                  generateAnalysis(air),
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 15),

                SizedBox(
                  width: double.infinity,
                  child:
                      ElevatedButton.icon(
                    onPressed:
                        geminiLoading
                            ? null
                            : analyzeWithGemini,
                    icon: geminiLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.auto_awesome,
                          ),
                    label: Text(
                      geminiLoading
                          ? 'Analyzing with Gemini...'
                          : 'Analyze with Gemini',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ====================================================
        // DATA SOURCE
        // ====================================================

        Card(
          child: Padding(
            padding:
                const EdgeInsets.all(15),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.cloud_done,
                  color: Colors.blue,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    'Live data connected\n'
                    'Air Quality: Open-Meteo\n'
                    'Weather: Open-Meteo\n'
                    'AI: Gemini\n'
                    'Updated: ${air.time}',
                    style:
                        const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            'AirSense • Real-Time Air Quality Monitoring',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  // ==========================================================
  // AQI CHART
  // ==========================================================

  Widget buildAqiChart() {
    if (hourlyAqi.isEmpty) {
      return Card(
        child: SizedBox(
          height: 280,
          child: Center(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.show_chart,
                  size: 50,
                  color: Colors.grey,
                ),

                const SizedBox(height: 10),

                const Text(
                  'Historical AQI data unavailable',
                ),

                const SizedBox(height: 5),

                TextButton(
                  onPressed: fetchAllData,
                  child:
                      const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    double maxAqi = 0;

    for (final point in hourlyAqi) {
      if (point.aqi > maxAqi) {
        maxAqi = point.aqi;
      }
    }

    double chartMax = maxAqi + 20;

    if (chartMax < 100) {
      chartMax = 100;
    }

    final spots = <FlSpot>[];

    for (int i = 0;
        i < hourlyAqi.length;
        i++) {
      spots.add(
        FlSpot(
          i.toDouble(),
          hourlyAqi[i].aqi,
        ),
      );
    }

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(
          10,
          20,
          20,
          15,
        ),
        child: Column(
          children: [
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  minX: 0,

                  maxX: spots.length > 1
                      ? (spots.length - 1)
                          .toDouble()
                      : 1,

                  minY: 0,

                  maxY: chartMax,

                  gridData:
                      const FlGridData(
                    show: true,
                    drawVerticalLine:
                        false,
                  ),

                  borderData:
                      FlBorderData(
                    show: true,
                  ),

                  titlesData:
                      FlTitlesData(
                    topTitles:
                        const AxisTitles(
                      sideTitles:
                          SideTitles(
                        showTitles: false,
                      ),
                    ),

                    rightTitles:
                        const AxisTitles(
                      sideTitles:
                          SideTitles(
                        showTitles: false,
                      ),
                    ),

                    leftTitles:
                        AxisTitles(
                      axisNameWidget:
                          const Text(
                        'AQI',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      sideTitles:
                          SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval:
                            chartMax / 4,
                        getTitlesWidget:
                            (value, meta) {
                          return Text(
                            value
                                .toInt()
                                .toString(),
                            style:
                                const TextStyle(
                              fontSize: 11,
                            ),
                          );
                        },
                      ),
                    ),

                    bottomTitles:
                        AxisTitles(
                      axisNameWidget:
                          const Text(
                        'Time',
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      sideTitles:
                          SideTitles(
                        showTitles: true,
                        reservedSize: 35,
                        interval:
                            _chartInterval(),
                        getTitlesWidget:
                            (value, meta) {
                          final index =
                              value.round();

                          if (index < 0 ||
                              index >=
                                  hourlyAqi
                                      .length) {
                            return const SizedBox();
                          }

                          final time =
                              hourlyAqi[index]
                                  .time;

                          final hour =
                              time.hour
                                  .toString()
                                  .padLeft(
                                    2,
                                    '0',
                                  );

                          return Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              top: 8,
                            ),
                            child: Text(
                              '$hour:00',
                              style:
                                  const TextStyle(
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  lineTouchData:
                      LineTouchData(
                    enabled: true,
                    touchTooltipData:
                        LineTouchTooltipData(
                      getTooltipItems:
                          (touchedSpots) {
                        return touchedSpots
                            .map((spot) {
                          final index =
                              spot.x.round();

                          if (index < 0 ||
                              index >=
                                  hourlyAqi
                                      .length) {
                            return null;
                          }

                          final point =
                              hourlyAqi[index];

                          final hour =
                              point.time.hour
                                  .toString()
                                  .padLeft(
                                    2,
                                    '0',
                                  );

                          return LineTooltipItem(
                            '$hour:00\n'
                            'AQI: '
                            '${point.aqi.toStringAsFixed(0)}',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),

                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      barWidth: 3,
                      isStrokeCapRound:
                          true,
                      dotData:
                          const FlDotData(
                        show: false,
                      ),
                      belowBarData:
                          BarAreaData(
                        show: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 15),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: [
                chartInfo(
                  'Latest',
                  hourlyAqi.last.aqi
                      .toStringAsFixed(0),
                ),

                chartInfo(
                  'Highest',
                  maxAqi.toStringAsFixed(0),
                ),

                chartInfo(
                  'Hours',
                  hourlyAqi.length
                      .toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CHART INTERVAL
  // ==========================================================

  double _chartInterval() {
    if (hourlyAqi.length <= 8) {
      return 1;
    }

    if (hourlyAqi.length <= 16) {
      return 2;
    }

    return 4;
  }

  // ==========================================================
  // CHART INFO
  // ==========================================================

  Widget chartInfo(
    String title,
    String value,
  ) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // WEATHER CARD
  // ==========================================================

  Widget weatherCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              icon,
              color: color,
              size: 35,
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                      color: Colors.grey,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    value,
                    style:
                        const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // POLLUTANT CARD
  // ==========================================================

  Widget pollutantCard(
    String name,
    double value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(15),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  color.withOpacity(0.12),
              child: Icon(
                icon,
                color: color,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    value.toStringAsFixed(1),
                    style:
                        const TextStyle(
                      fontSize: 20,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const Text(
                    'µg/m³',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // LOCAL ANALYSIS
  // ==========================================================

  String generateAnalysis(
    AirQualityData data,
  ) {
    if (data.aqi <= 50) {
      return 'The current air quality is good. '
          'Pollution levels are relatively low '
          'and outdoor activities are generally suitable.';
    }

    if (data.aqi <= 100) {
      return 'The current air quality is moderate. '
          'Most people can continue normal outdoor '
          'activities, while sensitive individuals '
          'may want to monitor their exposure.';
    }

    if (data.aqi <= 150) {
      return 'Air quality may affect sensitive groups. '
          'Consider reducing prolonged or intense '
          'outdoor activities if you experience discomfort.';
    }

    if (data.aqi <= 200) {
      return 'The current air quality is unhealthy. '
          'Consider limiting prolonged outdoor exposure.';
    }

    return 'The current air quality is very poor. '
        'Consider avoiding prolonged outdoor exposure '
        'and monitoring official health guidance.';
  }
}

// ============================================================
// LOCATION SEARCH BOX
// ============================================================

class LocationSearchBox extends StatefulWidget {
  final String currentCity;

  final Future<void> Function(String) onSearch;

  const LocationSearchBox({
    super.key,
    required this.currentCity,
    required this.onSearch,
  });

  @override
  State<LocationSearchBox> createState() =>
      _LocationSearchBoxState();
}

class _LocationSearchBoxState
    extends State<LocationSearchBox> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();

    controller =
        TextEditingController(
      text: widget.currentCity,
    );
  }

  @override
  void didUpdateWidget(
    LocationSearchBox oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.currentCity !=
        widget.currentCity) {
      controller.text =
          widget.currentCity;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void search() {
    final city =
        controller.text.trim();

    if (city.isEmpty) {
      return;
    }

    widget.onSearch(city);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(15),
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 5,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              color: Colors.blue,
            ),

            const SizedBox(width: 10),

            Expanded(
              child: TextField(
                controller: controller,
                textInputAction:
                    TextInputAction.search,
                onSubmitted: (_) {
                  search();
                },
                decoration:
                    const InputDecoration(
                  hintText:
                      'Search city...',
                  border:
                      InputBorder.none,
                ),
              ),
            ),

            const SizedBox(width: 5),

            ElevatedButton.icon(
              onPressed: search,
              icon: const Icon(
                Icons.location_on,
                size: 18,
              ),
              label:
                  const Text('Search'),
            ),
          ],
        ),
      ),
    );
  }
}