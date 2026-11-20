import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Registro de Asistencia',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFEAF2FA),
      ),
      home: const AttendanceScreen(),
    );
  }
}

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // Usa 10.0.2.2 para emulador Android o tu IP local (ej. 192.168.1.X) en teléfono físico
  final String baseUrl = 'http://10.0.2.2:8000';
  
  // ID del usuario registrado previamente en la tabla 'users'
  final int currentUserId = 1;

  String _address = 'Presiona el botón para registrar tu asistencia';
  bool _isLoading = false;
  List<dynamic> _history = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Los servicios de ubicación están desactivados.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permisos de ubicación denegados.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Los permisos de ubicación están denegados permanentemente.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _registerAttendance() async {
    setState(() => _isLoading = true);

    try {
      Position position = await _determinePosition();

      final response = await http.post(
        Uri.parse('$baseUrl/attendance/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': currentUserId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _address = data['address'] ?? 'Asistencia registrada';
        });
        _fetchHistory(); // Recarga el historial automáticamente
      } else {
        setState(() {
          _address = 'Error del servidor: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _address = 'Error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/attendance/?user_id=$currentUserId'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _history = json.decode(utf8.decode(response.bodyBytes));
        });
      }
    } catch (e) {
      debugPrint('Error cargando historial: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de Asistencia'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1D4E9E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar historial',
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _registerAttendance,
              icon: const Icon(Icons.location_on),
              label: Text(_isLoading ? 'Obteniendo ubicación...' : 'Registrar asistencia'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4E9E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                '📍 $_address',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Historial de asistencias',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _history.isEmpty
                  ? const Center(
                      child: Text(
                        'Aún no hay registros de asistencia.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.check_circle, color: Colors.green),
                            title: Text(
                              item['address'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text('Fecha: ${item['created_at'] ?? ''}'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}