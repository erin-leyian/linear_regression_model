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
  ['governance', 'Governance type', 'e.g. Federal or national ministry or agency'],
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
        _show('Server error (${response.statusCode}). Please try again.',
            error: true);
      }
    } on TimeoutException {
      _show('The server took too long to answer (it may be waking up). '
          'Please try again.', error: true);
    } catch (_) {
      _show('Could not reach the server. Check your internet connection.',
          error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Park Visitor Estimator')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final f in _fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _controllers[f[0]],
                  decoration: InputDecoration(
                    labelText: f[1],
                    hintText: f[2],
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _loading ? null : _predict,
                child: const Text('Predict'),
              ),
            ),
            const SizedBox(height: 16),
            // Display area: shows the prediction or a readable error
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isError
                    ? scheme.errorContainer
                    : scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _loading
                  ? const Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Contacting the server... the first request '
                            'can take up to a minute.'),
                      ],
                    )
                  : Text(
                      _message,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}