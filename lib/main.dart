// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgriPrice Predictor',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green[700],
        colorScheme: ColorScheme.dark(
          primary: Colors.green[700]!,
          secondary: Colors.green[500]!,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: const Color(0xFF1E1E1E),
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _cropController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  
  String _prediction = '';
  Position? _currentPosition;
  Map<String, dynamic> _weatherData = {};
  bool _isLoading = false;
  List<FlSpot> _predictedPricePoints = [];

  final List<String> _units = ['kg', 'quintal', 'ton'];
  String _selectedUnit = 'kg';

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.denied) {
        _getCurrentLocation();
      }
    } else {
      _getCurrentLocation();
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
      _getWeatherData(position.latitude, position.longitude);
    } catch (e) {
      _showErrorSnackBar("Could not get location. Please check permissions.");
    }
  }

  Future<void> _getWeatherData(double lat, double lon) async {
    final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code&forecast_days=1';
    
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          _weatherData = json.decode(response.body)['current'];
        });
      }
    } catch (e) {
      _showErrorSnackBar("Could not fetch weather data.");
    }
  }

  Future<void> _predictPrice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final prompt = _generatePredictionPrompt();
      final model = GenerativeModel(
        model: 'gemini-pro',
        apiKey: 'AIzaSyALPelkD_VVKoYNVzk1XuKadvpDayOQw1Y', 
      );
      
      final response = await model.generateContent([Content.text(prompt)]);
      
      setState(() {
        _prediction = response.text ?? 'Unable to generate prediction';
        _updatePredictedPricePoints(response.text ?? '');
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar("Error generating prediction. Please try again.");
    }
  }

  String _generatePredictionPrompt() {
    final weather = _weatherData.isNotEmpty 
      ? 'Temperature: ${_weatherData['temperature_2m']}°C, Humidity: ${_weatherData['relative_humidity_2m']}%'
      : 'Weather data unavailable';

    final priceInfo = _priceController.text.isNotEmpty 
      ? 'Current Price: ${_priceController.text} per $_selectedUnit'
      : 'Current price not provided';

    return '''
    Predict the price of ${_cropController.text} in India for the next 5 days:
    
    Current Data:
    - Location: ${_currentPosition?.latitude ?? 'Unknown'}, ${_currentPosition?.longitude ?? 'Unknown'}
    - Weather: $weather
    - $priceInfo
    
    Please provide:
    1. Daily price predictions for the next 5 days in ₹ per $_selectedUnit
    2. Explanation of factors considered
    3. Market trend analysis
    4. Confidence level in the prediction
    
    Format as:
    Day 1: [Price]
    Day 2: [Price]
    Day 3: [Price]
    Day 4: [Price]
    Day 5: [Price]
    
    Analysis: [Your detailed explanation]
    ''';
  }

  void _updatePredictedPricePoints(String prediction) {
    final RegExp priceRegex = RegExp(r'Day (\d+): (\d+(\.\d+)?)');
    _predictedPricePoints = priceRegex
        .allMatches(prediction)
        .map((match) => FlSpot(
              double.parse(match.group(1)!),
              double.parse(match.group(2)!),
            ))
        .toList();
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AgriPrice Predictor'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWeatherCard(),
                const SizedBox(height: 16),
                _buildInputSection(),
                const SizedBox(height: 16),
                _buildPredictionButton(),
                if (_isLoading) 
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_prediction.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildPredictionCard(),
                ],
                if (_predictedPricePoints.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildPriceGraph(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Weather',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _weatherData.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Temperature: ${_weatherData['temperature_2m']}°C'),
                      Text('Humidity: ${_weatherData['relative_humidity_2m']}%'),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _cropController,
          decoration: const InputDecoration(
            labelText: 'Enter Crop Name',
            hintText: 'e.g., Rice, Wheat, Tomato',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          validator: (value) =>
              value?.isEmpty ?? true ? 'Please enter a crop name' : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Current Price (Optional)',
                  hintText: 'Enter current market price',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedUnit,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                  border: OutlineInputBorder(),
                ),
                items: _units
                    .map((unit) =>
                        DropdownMenuItem(value: unit, child: Text(unit)))
                    .toList(),
                onChanged: (value) => setState(() => _selectedUnit = value!),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPredictionButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _predictPrice,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(_isLoading ? 'Predicting...' : 'Predict Price'),
    );
  }

  Widget _buildPredictionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price Prediction',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(_prediction),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceGraph() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Price Trend',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('Day ${value.toInt()}'),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Text('₹${value.toInt()}'),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _predictedPricePoints,
                      isCurved: true,
                      color: Colors.green[500],
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) => 
                          FlDotCirclePainter(
                            radius: 6,
                            color: Colors.green[500]!,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green[500]?.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}