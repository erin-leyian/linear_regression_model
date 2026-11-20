import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// The deployed API on Render. The app calls its /predict endpoint.
const String apiUrl =
    'https://linear-regression-model-kxzq.onrender.com/predict';

// [json key, label shown on screen, hint]
const List<List<String>> _fields = [
  ['country', 'Country', 'e.g. Kenya'],
  ['iucn_cat', 'IUCN category', 'e.g. II, IV or Not Reported'],
  [
    'governance',
    'Governance type',
    'e.g. Federal or national ministry or agency',
  ],
  ['rep_area_km2', 'Area (km²)', 'e.g. 265.87'],
  ['year', 'Year', 'e.g. 2019'],
  ['lat', 'Latitude', 'e.g. 36.401'],
  ['lon', 'Longitude', 'e.g. 2.853'],
  ['status_year', 'Status year', 'e.g. 1983'],
];

const Set<String> _intFields = {'year', 'status_year'};
const Set<String> _doubleFields = {'rep_area_km2', 'lat', 'lon'};

void main() => runApp(const VisitorApp());

class VisitorApp extends StatelessWidget {
  const VisitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Park Visitor Estimator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const PredictPage(),
    );
  }
}

class PredictPage extends StatefulWidget {
  const PredictPage({super.key});

  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  final Map<String, TextEditingController> _controllers = {
    for (final f in _fields) f[0]: TextEditingController(),
  };

  String _message = 'Fill in the fields and tap Predict.';
  bool _isError = false;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // 12345 -> "12,345"
  String _withCommas(num n) => n.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );

  void _show(String text, {required bool error}) {
    setState(() {
      _message = text;
      _isError = error;
      _loading = false;
    });
  }

  Future<void> _predict() async {
    // 1. Missing values
    final missing = [
      for (final f in _fields)
        if (_controllers[f[0]]!.text.trim().isEmpty) f[1],
    ];
    if (missing.isNotEmpty) {
      _show('Please fill in: ${missing.join(', ')}.', error: true);
      return;
    }

    // 2. Build the request body. If a number cannot be parsed, the raw text
    //    is sent as-is so the API itself reports the wrong-type error.
    final body = <String, dynamic>{};
    for (final f in _fields) {
      final key = f[0];
      final text = _controllers[key]!.text.trim();
      if (_intFields.contains(key)) {
        body[key] = int.tryParse(text) ?? text;
      } else if (_doubleFields.contains(key)) {
        body[key] = double.tryParse(text) ?? text;
      } else {
        body[key] = text;
      }
    }

    // 3. Call the API
    setState(() => _loading = true);
    try {
      final response = await http
          .post(
            Uri.parse(apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        _show(
          'Estimated annual visitors:\n'
          '${_withCommas(data['predicted_annual_visitors'])}',
          error: false,
        );
      } else if (response.statusCode == 422 && data['detail'] is List) {
        // Validation errors from the API (wrong type, out of range, unknown category)
        final lines = (data['detail'] as List)
            .map((d) => '${(d['loc'] as List).last}: ${d['msg']}')
            .join('\n');
        _show(lines, error: true);
      } else {
        _show(
          'Server error (${response.statusCode}). Please try again.',
          error: true,
        );
      }
    } on TimeoutException {
      _show(
        'The server took too long to answer (it may be waking up). '
        'Please try again.',
        error: true,
      );
    } catch (_) {
      _show(
        'Could not reach the server. Check your internet connection.',
        error: true,
      );
    }
  }

  Widget _field(String key) {
    final f = _fields.firstWhere((f) => f[0] == key);
    return TextField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: f[1],
        hintText: f[2],
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _pair(String a, String b) {
    return Row(
      children: [
        Expanded(child: _field(a)),
        const SizedBox(width: 12),
        Expanded(child: _field(b)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Park Visitor Estimator'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Estimate the yearly visitors to an African protected area.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            _section('THE PARK'),
            _field('country'),
            const SizedBox(height: 12),
            _field('iucn_cat'),
            const SizedBox(height: 12),
            _field('governance'),
            _section('SIZE AND LOCATION'),
            _field('rep_area_km2'),
            const SizedBox(height: 12),
            _pair('lat', 'lon'),
            _section('YEARS'),
            _pair('year', 'status_year'),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _loading ? null : _predict,
                icon: const Icon(Icons.insights),
                label: const Text('Predict'),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              color: _isError ? scheme.errorContainer : scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _loading
                    ? const Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text(
                            'Contacting the server... the first request '
                            'can take up to a minute.',
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _isError ? Icons.error_outline : Icons.eco,
                            color: _isError ? scheme.error : scheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _message,
                              style: _isError
                                  ? Theme.of(context).textTheme.titleMedium
                                  : Theme.of(context).textTheme.headlineSmall,
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
