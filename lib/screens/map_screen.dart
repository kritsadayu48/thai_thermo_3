// lib/screens/map_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as AM;

import 'package:flutter_map/flutter_map.dart'; // ใช้ OpenStreetMap
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:latlong2/latlong.dart'; // สำหรับ LatLng
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thai_thermo_3/utils/country_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../models/earthquake.dart';
import '../services/earthquake_service.dart';
import 'chart_screen.dart';
import 'dart:math';
import '../enums/data_fetch_mode.dart' as fetch_mode;
import 'package:location/location.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

// เพิ่มตัวแปรสำหรับ debug mode
const bool _DEBUG = true;

class MapScreen extends StatefulWidget {
  final fetch_mode.DataFetchMode dataMode;
  final Earthquake? selectedEarthquake;

  const MapScreen({
    super.key,
    this.dataMode = fetch_mode.DataFetchMode.southeastAsia,
    this.selectedEarthquake,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // iOS Apple Maps
  AM.AppleMapController? _iosMapController;
  final Set<AM.Annotation> _iosAnnotations = {};

  final _mapController = MapController();
  final Map<String, Marker> _markers = {};
  final _mapKey = GlobalKey();

  bool _isMapLoaded = false;
  bool _hasMapError = false;
  String _errorMessage = '';
  late fetch_mode.DataFetchMode _currentDataMode;

  final PopupController _popupController = PopupController();

  // รูปแบบแผนที่
  String _mapType = 'normal'; // normal, satellite, terrain, hybrid

  // ตำแหน่งผู้ใช้
  final Location _locationService = Location();
  bool _locationPermissionGranted = false;
  LocationData? _currentLocation;

  // ค่าตั้งต้นแผนที่ (Bangkok)
  static const _defaultCenter = LatLng(13.7563, 100.5018);
  static const double _defaultZoom = 5.0;

  // ------------------------------
  // NEW: ฟีเจอร์ #2 – ไทม์ไลน์สไลเดอร์
  // ------------------------------
  int _hoursBack = 24; // แสดงข้อมูลภายในกี่ชั่วโมงล่าสุด (1–168 ชั่วโมง)
  static const int _minHoursBack = 1;
  static const int _maxHoursBack = 168; // 7 วัน

  // ------------------------------
  // NEW: ฟีเจอร์ #8 – Safety mode
  // ------------------------------
  bool _safetyMode = false; // เปิด/ปิดโหมดความปลอดภัย
  double _safetyRadiusKm = 300; // รัศมี (กม.) รอบตำแหน่งผู้ใช้
  static const double _minSafetyKm = 50;
  static const double _maxSafetyKm = 1000;

  @override
  void initState() {
    super.initState();

    if (_DEBUG) debugPrint('🔍 MapScreen - initState');

    _checkLocationPermission();
    _loadSettings().then((_) {
      if (mounted) {
        if (_DEBUG) debugPrint('🔍 MapScreen - settings loaded');
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  AM.LatLng _amFrom(LatLng p) => AM.LatLng(p.latitude, p.longitude);

  Widget _buildAppleMap() {
    final AM.LatLng initial = _amFrom(_defaultCenter);

    return AM.AppleMap(
      key: ValueKey(_mapType),
      initialCameraPosition: AM.CameraPosition(
        target: initial,
        zoom: _defaultZoom,
      ),
      myLocationEnabled: true,
      compassEnabled: true,
      annotations: _iosAnnotations,
      mapType: _getAppleMapType(),
      onMapCreated: (c) {
        _iosMapController = c;
        setState(() {
          _isMapLoaded = true;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _createMarkers();
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canShowSafetyOverlay =
        !Platform.isIOS; // วาดวงกลม Safety overlay เฉพาะ FlutterMap

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('แผนที่แผ่นดินไหว', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // รูปแบบแผนที่
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'map_normal') {
                setState(() => _mapType = 'normal');
                _saveMapType();
              } else if (value == 'map_satellite') {
                setState(() => _mapType = 'satellite');
                _saveMapType();
              } else if (value == 'map_terrain') {
                setState(() => _mapType = 'terrain');
                _saveMapType();
              } else if (value == 'map_hybrid') {
                setState(() => _mapType = 'hybrid');
                _saveMapType();
              }
            },
            icon: const Icon(Icons.layers),
            tooltip: 'เลือกรูปแบบแผนที่',
            itemBuilder: (context) => [
              _mapMenuItem('map_normal', 'แผนที่ปกติ', _mapType == 'normal'),
              _mapMenuItem('map_satellite', 'ดาวเทียม', _mapType == 'satellite'),
              _mapMenuItem('map_terrain', 'ภูมิประเทศ', _mapType == 'terrain'),
              _mapMenuItem('map_hybrid', 'ผสม', _mapType == 'hybrid'),
            ],
          ),
          const SizedBox(width: 8),
          // สลับ Safety mode เร็ว ๆ
          IconButton(
            tooltip: 'Safety mode',
            icon: Icon(
              _safetyMode ? Icons.shield : Icons.shield_outlined,
              color: _safetyMode ? Colors.orange : Colors.white,
            ),
            onPressed: () {
              setState(() => _safetyMode = !_safetyMode);
              _createMarkers();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_hasMapError)
            _buildMapError(context)
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SafeArea(
                  child: Platform.isIOS
                      ? _buildAppleMap()
                      : FlutterMap(
                          key: _mapKey,
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _defaultCenter,
                            initialZoom: _defaultZoom,
                            minZoom: 3.0,
                            maxZoom: 18.0,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                              enableMultiFingerGestureRace: true,
                            ),
                            onMapReady: () {
                              setState(() => _isMapLoaded = true);
                              Future.delayed(const Duration(milliseconds: 100), () {
                                if (mounted) _createMarkers();
                              });
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: _getTileLayerUrl(),
                              subdomains: const ['a', 'b', 'c'],
                            ),

                            // ------------------------------
                            // NEW: Safety overlay (Android/FlutterMap)
                            // ------------------------------
                            if (_safetyMode &&
                                canShowSafetyOverlay &&
                                _currentLocation?.latitude != null &&
                                _currentLocation?.longitude != null)
                              CircleLayer(
                                circles: _buildSafetyCircles(),
                              ),

                            PopupMarkerLayer(
                              options: PopupMarkerLayerOptions(
                                popupController: _popupController,
                                markers: _markers.values.toList(),
                                popupDisplayOptions: PopupDisplayOptions(
                                  builder: (BuildContext ctx, Marker marker) {
                                    final quakes = Provider.of<EarthquakeService>(
                                      context,
                                      listen: false,
                                    ).earthquakes;

                                    final String? quakeId = _markers.entries
                                        .firstWhere(
                                          (e) => identical(e.value, marker),
                                          orElse: () => MapEntry('', marker),
                                        )
                                        .key;

                                    final quake = (quakeId != null && quakeId.isNotEmpty)
                                        ? quakes.firstWhere(
                                            (e) => e.id == quakeId,
                                            orElse: () => quakes.first,
                                          )
                                        : quakes.first;

                                    return GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _showQuakeDetails(quake),
                                      child: Container(
                                        constraints: const BoxConstraints(maxWidth: 260),
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1E1E),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.white24),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'M ${quake.magnitude.toStringAsFixed(1)} • ${quake.location}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              DateFormat('dd/MM/yyyy HH:mm').format(quake.time),
                                              style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton(
                                                onPressed: () => _popupController.hideAllPopups(),
                                                child: const Text(
                                                  'ปิด',
                                                  style: TextStyle(color: Colors.orange),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

          if (!_isMapLoaded && !_hasMapError)
            const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
        ],
      ),

      // ------------------------------
      // NEW: แถบควบคุมด้านล่าง (Timeline + Safety)
      // ------------------------------
      bottomNavigationBar: _buildControlBar(),

      floatingActionButton: !_hasMapError
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ไปตำแหน่งผู้ใช้
                FloatingActionButton(
                  onPressed: _moveToUserLocation,
                  heroTag: 'userLocationFAB',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
                  mini: true,
                  child: const Icon(Icons.my_location),
                  tooltip: 'ไปยังตำแหน่งของคุณ',
                ),
                const SizedBox(height: 16),
                // โชว์ทั้งหมด
                FloatingActionButton(
                  onPressed: _centerMapOnEarthquakes,
                  heroTag: 'viewAllFAB',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.green,
                  child: const Icon(Icons.zoom_out_map),
                  tooltip: 'แสดงแผ่นดินไหวทั้งหมด',
                ),
              ],
            )
          : null,
    );
  }

  PopupMenuItem<String> _mapMenuItem(String value, String label, bool active) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            active ? Icons.check : Icons.radio_button_unchecked,
            color: active ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildMapError(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'ไม่สามารถโหลดแผนที่ได้',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage.isNotEmpty
                ? _errorMessage
                : 'กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตและลองใหม่อีกครั้ง',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasMapError = false;
                _errorMessage = '';
              });
            },
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }

  // ------------------------------
  // NEW: Bottom Control Bar
  // ------------------------------
  Widget _buildControlBar() {
    final total = _markers.length;
    final safetyOn = _safetyMode ? 'ON' : 'OFF';
    final hoursLabel = 'ช่วงเวลา: $_hoursBack ชม';
    final safetyLabel = _safetyMode
        ? 'Safety: $_safetyRadiusKm กม.'
        : 'Safety: OFF';

    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      ),
      child: Row(
        children: [
          // สรุปซ้ายมือ
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('เหตุการณ์ที่แสดง', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                Text('$total รายการ', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(hoursLabel, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                Text(safetyLabel, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
              ],
            ),
          ),
          // ปุ่มควบคุมขวา
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ตั้งค่า Timeline
              TextButton.icon(
                onPressed: _openTimelineSheet,
                icon: const Icon(Icons.timeline, color: Colors.orange),
                label: const Text('Timeline', style: TextStyle(color: Colors.orange)),
              ),
              const SizedBox(width: 8),
              // ตั้งค่า Safety
              TextButton.icon(
                onPressed: _openSafetySheet,
                icon: Icon(_safetyMode ? Icons.shield : Icons.shield_outlined,
                    color: _safetyMode ? Colors.orange : Colors.white),
                label: Text('Safety', style: TextStyle(color: _safetyMode ? Colors.orange : Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
  

  // ------------------------------
  // NEW: Timeline sheet (ชั่วโมงย้อนหลัง)
  // ------------------------------
  void _openTimelineSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        int tempHours = _hoursBack;
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('เลือกช่วงเวลา (ชั่วโมงล่าสุด)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('$tempHours ชั่วโมง', style: const TextStyle(color: Colors.white70)),
                  Slider(
                    min: _minHoursBack.toDouble(),
                    max: _maxHoursBack.toDouble(),
                    divisions: _maxHoursBack - _minHoursBack,
                    value: tempHours.toDouble(),
                    label: '$tempHours ชม',
                    onChanged: (v) => setModal(() => tempHours = v.round()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _hoursBack = tempHours);
                          Navigator.pop(context);
                          _createMarkers();
                        },
                        child: const Text('นำไปใช้'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ------------------------------
  // NEW: Safety sheet (เปิด/ปิด + รัศมี กม.)
  // ------------------------------
  void _openSafetySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        bool tempSafety = _safetyMode;
        double tempRadius = _safetyRadiusKm;

        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Safety Mode', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SwitchListTile.adaptive(
                    activeColor: Colors.orange,
                    title: const Text('เปิดโหมดความปลอดภัย', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'จะแสดงเฉพาะเหตุการณ์ภายในรัศมีที่กำหนดรอบตำแหน่งของคุณ',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                    value: tempSafety,
                    onChanged: (v) => setModal(() => tempSafety = v),
                  ),
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: tempSafety ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: !tempSafety,
                      child: Column(
                        children: [
                          Text('รัศมี: ${tempRadius.toStringAsFixed(0)} กม.',
                              style: const TextStyle(color: Colors.white70)),
                          Slider(
                            min: _minSafetyKm,
                            max: _maxSafetyKm,
                            divisions: (_maxSafetyKm - _minSafetyKm).toInt(),
                            value: tempRadius,
                            label: '${tempRadius.toStringAsFixed(0)} กม.',
                            onChanged: (v) => setModal(() => tempRadius = v),
                          ),
                          if (Platform.isIOS)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'หมายเหตุ: iOS ยังไม่แสดงวงกลมรัศมีบนแผนที่ แต่จะกรองเหตุการณ์ให้แล้ว',
                                style: TextStyle(color: Colors.orange, fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ยกเลิก'),
                      ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _safetyMode = tempSafety;
                            _safetyRadiusKm = tempRadius;
                          });
                          Navigator.pop(context);
                          _createMarkers();
                        },
                        child: const Text('นำไปใช้'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // วงกลม Safety overlay (เฉพาะ FlutterMap)
  List<CircleMarker> _buildSafetyCircles() {
    if (_currentLocation?.latitude == null || _currentLocation?.longitude == null) {
      return const <CircleMarker>[];
    }
    final center = LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!);

    // สร้างวงกลมรัศมีเดียวตามที่ผู้ใช้ตั้ง
    return [
      CircleMarker(
        point: center,
        useRadiusInMeter: true,
        radius: _safetyRadiusKm * 1000.0,
        color: Colors.orange.withOpacity(0.12),
        borderStrokeWidth: 2,
        borderColor: Colors.orange.withOpacity(0.6),
      ),
    ];
  }

  // Create markers (คำนึงถึง Timeline + Safety)
  void _createMarkers() {
    if (_hasMapError || !mounted) return;
    if (!_isMapLoaded) return;

    // iOS: rebuild annotations จาก markers เสมอหลังอัปเดต
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    final now = DateTime.now();

    // ดึงข้อมูลทั้งหมด
    List<Earthquake> list = earthquakeService.earthquakes;

    // กรองตาม "ชั่วโมงล่าสุด" (ฟีเจอร์ #2)
    final start = now.subtract(Duration(hours: _hoursBack.clamp(_minHoursBack, _maxHoursBack)));
    list = list.where((e) => e.time.isAfter(start)).toList();

    // กรองตาม Safety mode (ฟีเจอร์ #8) ถ้าเปิดและมีตำแหน่ง
    if (_safetyMode && _currentLocation?.latitude != null && _currentLocation?.longitude != null) {
      final userLat = _currentLocation!.latitude!;
      final userLng = _currentLocation!.longitude!;
      list = list.where((e) {
        final d = _distanceKm(userLat, userLng, e.latitude, e.longitude);
        return d <= _safetyRadiusKm;
      }).toList();
    }

    // กรองพิกัดผิดปกติ
    int invalid = 0;

    setState(() {
      _markers.clear();
      for (final quake in list) {
        if (quake.latitude == 0 && quake.longitude == 0) {
          invalid++;
          continue;
        }
        // แสดงมาร์คเกอร์ตาม magnitude (เดิม)
        _markers[quake.id] = Marker(
          key: ValueKey(quake.id),
          width: 60.0,
          height: 60.0,
          point: LatLng(quake.latitude, quake.longitude),
          child: _getMarkerIcon(quake.magnitude),
        );
      }
    });

    if (Platform.isIOS) {
      _rebuildIOSAnnotationsFromMarkers();
    }

    if (_markers.isNotEmpty && _isMapLoaded && !_hasMapError && mounted) {
      _centerMapOnEarthquakes();
    }
  }

  // ไอคอน marker ตาม magnitude (เดิม)
  Widget _getMarkerIcon(double magnitude) {
    Color color;
    if (magnitude < 3.0) {
      color = Colors.green;
    } else if (magnitude < 4.0) {
      color = Colors.yellow;
    } else if (magnitude < 5.0) {
      color = Colors.orange;
    } else if (magnitude < 6.0) {
      color = Colors.deepOrange;
    } else {
      color = Colors.red;
    }

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 3, spreadRadius: 1),
        ],
      ),
      child: Center(
        child: Text(
          magnitude.toStringAsFixed(1),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
        ),
      ),
    );
  }

  void _rebuildIOSAnnotationsFromMarkers() {
    try {
      final quakes = Provider.of<EarthquakeService>(context, listen: false).earthquakes;
      setState(() {
        _iosAnnotations.clear();
        _markers.forEach((id, m) {
          final pos = m.point;
          Earthquake? q;
          try {
            q = quakes.firstWhere((e) => e.id == id);
          } catch (_) {}
          _iosAnnotations.add(
            AM.Annotation(
              annotationId: AM.AnnotationId(id),
              position: AM.LatLng(pos.latitude, pos.longitude),
              infoWindow: AM.InfoWindow(
                title: q != null ? 'M ${q!.magnitude.toStringAsFixed(1)}' : '',
                snippet: q?.location ?? '',
                onTap: () {
                  if (q != null) _showQuakeDetails(q!);
                },
              ),
            ),
          );
        });
      });
    } catch (e) {
      debugPrint('MapScreen - rebuild iOS annotations error: $e');
    }
  }

  void _centerMapOnEarthquakes() {
    if (Platform.isIOS && _iosMapController != null && _markers.isNotEmpty) {
      double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;
      for (final m in _markers.values) {
        final p = m.point;
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      final bounds = AM.LatLngBounds(
        southwest: AM.LatLng(minLat, minLng),
        northeast: AM.LatLng(maxLat, maxLng),
      );
      _iosMapController!.animateCamera(AM.CameraUpdate.newLatLngBounds(bounds, 48));
      return;
    }

    if (_markers.isEmpty || !_isMapLoaded) return;

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;

    for (final marker in _markers.values) {
      final position = marker.point;
      if (position.latitude < minLat) minLat = position.latitude;
      if (position.latitude > maxLat) maxLat = position.latitude;
      if (position.longitude < minLng) minLng = position.longitude;
      if (position.longitude > maxLng) maxLng = position.longitude;
    }

    minLat -= 2.0;
    maxLat += 2.0;
    minLng -= 2.0;
    maxLng += 2.0;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    final latZoom = _calculateZoomLevel(maxLat - minLat);
    final lngZoom = _calculateZoomLevel(maxLng - minLng);
    final zoom = min(latZoom, lngZoom);

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  double _calculateZoomLevel(double span) {
    if (span <= 1) return 10.0;
    if (span <= 5) return 7.0;
    if (span <= 10) return 6.0;
    if (span <= 20) return 5.0;
    if (span <= 40) return 4.0;
    return 3.0;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDataMode = widget.dataMode;
    _mapType = prefs.getString('mapType') ?? 'normal';

    // ลองโหลดค่าที่เคยตั้ง (ถ้ามี)
    _hoursBack = prefs.getInt('map_hours_back') ?? _hoursBack;
    _safetyMode = prefs.getBool('map_safety_mode') ?? _safetyMode;
    _safetyRadiusKm = prefs.getDouble('map_safety_radius_km') ?? _safetyRadiusKm;

    if (mounted) setState(() {});
  }

  Future<void> _saveMapType() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapType', _mapType);

    // บันทึกค่าควบคุมใหม่ ๆ ด้วย
    await prefs.setInt('map_hours_back', _hoursBack);
    await prefs.setBool('map_safety_mode', _safetyMode);
    await prefs.setDouble('map_safety_radius_km', _safetyRadiusKm);

    setState(() {});
    if (Platform.isIOS && _iosMapController != null) {
      _rebuildIOSAnnotationsFromMarkers();
    } else if (!Platform.isIOS && _isMapLoaded) {
      _createMarkers();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เปลี่ยนรูปแบบแผนที่เป็น: ${_getMapTypeLabel()}'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  String _getTileLayerUrl() {
    return switch (_mapType) {
      'satellite' =>
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'terrain' =>
        'https://stamen-tiles.a.ssl.fastly.net/terrain/{z}/{x}/{y}.png',
      'hybrid' =>
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      _ => 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    };
  }

  AM.MapType _getAppleMapType() {
    return switch (_mapType) {
      'satellite' => AM.MapType.satellite,
      'hybrid' => AM.MapType.hybrid,
      'terrain' => AM.MapType.satellite, // iOS ไม่มี terrain
      _ => AM.MapType.standard,
    };
  }

  String _getMapTypeLabel() {
    return switch (_mapType) {
      'satellite' => 'ดาวเทียม',
      'terrain' => 'ภูมิประเทศ',
      'hybrid' => 'ผสม',
      _ => 'ปกติ',
    };
  }

  // --------------------------------
  // Dialog รายละเอียด (คงเดิม + แสดงระยะ)
  // --------------------------------
  Future<void> _showQuakeDetails(Earthquake quake) async {
    try {
      if (!mounted) return;

      // ระยะทางจากผู้ใช้ (ถ้ามี)
      String distanceInfo = '—';
      if (_currentLocation?.latitude != null && _currentLocation?.longitude != null) {
        final d = _distanceKm(_currentLocation!.latitude!, _currentLocation!.longitude!,
            quake.latitude, quake.longitude);
        distanceInfo = '${d.toStringAsFixed(0)} กม.';
      }

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _getMagnitudeColor(quake.magnitude).withOpacity(0.2),
                ),
                child: Center(
                  child: Text(
                    quake.magnitude.toStringAsFixed(1),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: _getMagnitudeColor(quake.magnitude),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('รายละเอียดแผ่นดินไหว',
                        style: TextStyle(color: Colors.grey[200], fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(quake.time),
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoRow('สถานที่:', quake.location),
                _buildInfoRow('เวลา:', DateFormat('dd/MM/yyyy HH:mm:ss').format(quake.time)),
                _buildInfoRow('ความลึก:', '${quake.depth} กม.'),
                _buildInfoRow('ระยะจากคุณ:', distanceInfo),
                _buildInfoRow('ละติจูด:', quake.latitude.toString()),
                _buildInfoRow('ลองจิจูด:', quake.longitude.toString()),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('ปิด', style: TextStyle(color: Colors.orange)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton.icon(
              onPressed: () {
                _openInGoogleMaps(quake.latitude, quake.longitude, quake.location);
              },
              icon: const Icon(Icons.map),
              label: const Text('Google Maps'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('❌ Error showing dialog: $e');
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 15))),
        ],
      ),
    );
  }

  // ตำแหน่งผู้ใช้
  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          setState(() => _locationPermissionGranted = false);
          return;
        }
      }

      PermissionStatus permissionStatus = await _locationService.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await _locationService.requestPermission();
        if (permissionStatus != PermissionStatus.granted) {
          setState(() => _locationPermissionGranted = false);
          return;
        }
      }

      setState(() => _locationPermissionGranted = true);
    } catch (_) {
      setState(() => _locationPermissionGranted = false);
    }
  }

  Future<void> _moveToUserLocation() async {
    if (!_locationPermissionGranted) {
      await _checkLocationPermission();
      if (!_locationPermissionGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ต้องการสิทธิ์การเข้าถึงตำแหน่งเพื่อแสดงตำแหน่งของคุณ')),
        );
        return;
      }
    }

    try {
      final serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        bool isEnabled = await _locationService.requestService();
        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กรุณาเปิดใช้บริการตำแหน่งบนอุปกรณ์ของคุณ')),
          );
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังค้นหาตำแหน่งของคุณ...'), duration: Duration(seconds: 2)),
      );

      _currentLocation = await _locationService.getLocation().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('หมดเวลาในการค้นหาตำแหน่ง'),
      );

      if (_currentLocation != null && mounted) {
        final lat = _currentLocation!.latitude ?? _defaultCenter.latitude;
        final lng = _currentLocation!.longitude ?? _defaultCenter.longitude;

        if (lat == 0.0 && lng == 0.0) {
          throw Exception('ได้รับตำแหน่งที่ไม่ถูกต้อง');
        }

        final userLocation = LatLng(lat, lng);

        // สร้าง/อัปเดต marker ผู้ใช้
        setState(() {
          _markers['user_location'] = Marker(
            width: 40.0,
            height: 40.0,
            point: userLocation,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF57C00).withOpacity(0.7),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 3, spreadRadius: 1)],
              ),
              child: const Icon(Icons.my_location, color: Colors.white, size: 20),
            ),
          );
          if (Platform.isIOS) {
            _iosAnnotations.removeWhere((a) => a.annotationId.value == 'user_location');
            _iosAnnotations.add(
              AM.Annotation(
                annotationId:  AM.AnnotationId('user_location'),
                position: AM.LatLng(lat, lng),
                infoWindow: const AM.InfoWindow(title: 'ตำแหน่งของคุณ'),
              ),
            );
          }
        });

        await Future.delayed(const Duration(milliseconds: 300));
        if (Platform.isIOS && _iosMapController != null) {
          await _iosMapController!.animateCamera(
            AM.CameraUpdate.newLatLngZoom(AM.LatLng(lat, lng), 12),
          );
        } else if (!Platform.isIOS && _isMapLoaded) {
          _mapController.move(userLocation, 12.0);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แสดงตำแหน่งของคุณแล้ว'), duration: Duration(seconds: 2)),
        );

        // อัปเดต markers หลังได้ตำแหน่ง (กรณี Safety mode กรองด้วยตำแหน่ง)
        _createMarkers();
      } else {
        throw Exception('ไม่สามารถรับตำแหน่งได้');
      }
    } catch (e) {
      debugPrint('❌ MapScreen - Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถระบุตำแหน่งของคุณได้: $e')),
      );
    }
  }

  // เปิด Google Maps
  Future<void> _openInGoogleMaps(double latitude, double longitude, String location) async {
    final List<String> mapUrls = [
      'geo:$latitude,$longitude?q=$latitude,$longitude($location)',
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      'https://maps.google.com/?q=$latitude,$longitude',
      'https://maps.google.com/maps?q=$latitude,$longitude',
    ];

    bool opened = false;
    String lastError = '';

    for (final url in mapUrls) {
      try {
        final uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        opened = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เปิด Google Maps สำเร็จ'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
          );
        }
        break;
      } catch (e) {
        lastError = 'เกิดข้อผิดพลาด: $e';
        continue;
      }
    }

    if (!opened && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('ไม่สามารถเปิด Google Maps ได้', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('กรุณาลองวิธีใดวิธีหนึ่งต่อไปนี้:', style: TextStyle(color: Colors.white)),
              const SizedBox(height: 16),
              const Text('• ติดตั้งแอพ Google Maps', style: TextStyle(color: Colors.white70)),
              const Text('• คัดลอกพิกัดและค้นหาในแอพแผนที่อื่น', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(8)),
                child: SelectableText('พิกัด: $latitude, $longitude',
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
              ),
              const SizedBox(height: 12),
              Text('ข้อผิดพลาดล่าสุด: $lastError', style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '$latitude, $longitude')).then((_) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกพิกัดแล้ว'), backgroundColor: Colors.green, duration: Duration(seconds: 2)),
                  );
                });
              },
              child: const Text('คัดลอกพิกัด', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด', style: TextStyle(color: Colors.orange)),
            ),
          ],
        ),
      );
    }
  }

  // Utilities
  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * pi / 180;

  Color _getMagnitudeColor(double magnitude) {
    if (magnitude < 3.0) return Colors.green;
    if (magnitude < 4.0) return Colors.yellow;
    if (magnitude < 5.0) return Colors.orange;
    if (magnitude < 6.0) return Colors.deepOrange;
    return Colors.red;
  }
}
