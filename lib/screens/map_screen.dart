import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart'; // ปิดการใช้งาน Google Maps
import 'package:flutter_map/flutter_map.dart'; // ใช้ OpenStreetMap
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
import 'home_screen.dart';
import 'webview_screen.dart';
import 'intensity_map_screen.dart';
import 'dart:math';
import 'dart:convert';
import '../enums/data_fetch_mode.dart' as fetch_mode;
import 'package:location/location.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

// เพิ่มตัวแปรสำหรับ debug mode
const bool _DEBUG = true;

class MapScreen extends StatefulWidget {
  final fetch_mode.DataFetchMode dataMode;
  final Earthquake? selectedEarthquake;
  
  const MapScreen({
    super.key, 
    this.dataMode = fetch_mode.DataFetchMode.southeastAsia, 
    this.selectedEarthquake
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _mapController = MapController();
  final Map<String, Marker> _markers = {};
  final _mapKey = GlobalKey();
  
  bool _showLast24Hours = false;
  bool _isMapLoaded = false;
  bool _hasMapError = false;
  bool _isLoading = false;
  String _errorMessage = '';
  late fetch_mode.DataFetchMode _currentDataMode;
  
  final Location _locationService = Location();
  bool _locationPermissionGranted = false;
  LocationData? _currentLocation;
  
  // Set default position to somewhere in Thailand
  static const _defaultCenter = LatLng(13.7563, 100.5018); // Bangkok coordinates
  static const double _defaultZoom = 5.0;

  @override
  void initState() {
    super.initState();
    
    if (_DEBUG) debugPrint('🔍 MapScreen - initState ทำงาน');
    
    // ตรวจสอบสิทธิ์การเข้าถึงตำแหน่ง
    _checkLocationPermission();
    
    // โหลดค่าตั้งต้นก่อน แล้วค่อยสร้าง markers
    _loadSettings().then((_) {
      if (mounted) {
        if (_DEBUG) debugPrint('🔍 MapScreen - _loadSettings เสร็จสิ้น, mounted=$mounted');
        // หากมีการเลือกแผ่นดินไหวเฉพาะ ให้สร้าง markers ทันที
        if (widget.selectedEarthquake != null) {
          if (_DEBUG) debugPrint('🔍 MapScreen - มีการเลือกแผ่นดินไหวเฉพาะ, สร้าง markers ทันที');
          _createMarkers();
        } else {
          // ถ้าไม่มี ให้รอให้แผนที่โหลดเสร็จก่อน
          if (_DEBUG) debugPrint('🔍 MapScreen - ไม่มีการเลือกแผ่นดินไหวเฉพาะ, รอแผนที่โหลดเสร็จก่อน');
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              if (_DEBUG) debugPrint('🔍 MapScreen - สร้าง markers หลังจากรอ 300ms');
              _createMarkers();
            }
          });
        }
      }
    });
  }
  
  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // เพิ่มสีพื้นหลังสีดำเหมือนหน้าโฮม
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212), // สีแถบด้านบนเป็นสีดำเหมือนหน้าโฮม
        title: const Text('แผนที่แผ่นดินไหว',
        style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white), // กำหนดสีปุ่มกลับเป็นสีขาว
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'filter_24h') {
                setState(() {
                  _showLast24Hours = !_showLast24Hours;
                  _createMarkers();
                });
              } else if (value == 'view_chart') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ChartScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'filter_24h',
                child: Row(
                  children: [
                    _showLast24Hours
                        ? const Icon(Icons.check_box, size: 20)
                        : const Icon(Icons.check_box_outline_blank, size: 20),
                    const SizedBox(width: 8),
                    const Text('แสดงเฉพาะ 24 ชั่วโมงล่าสุด'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'view_chart',
                child: Row(
                  children: [
                    Icon(Icons.bar_chart, size: 20),
                    SizedBox(width: 8),
                    Text('ดูกราฟสถิติแผ่นดินไหว'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map or error message
          if (_hasMapError)
            Center(
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
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121212), // พื้นหลังสีดำเหมือนหน้าโฮม
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12), // เพิ่มขอบมน
                child: SafeArea(
                  child: FlutterMap(
                    key: _mapKey,
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _defaultCenter,
                      initialZoom: _defaultZoom,
                      // กำหนดขอบเขตการซูม
                      minZoom: 3.0, // ระดับซูมออกน้อยสุด (ป้องกันซูมออกไกลเกินไปแล้วค้าง)
                      maxZoom: 18.0, // ระดับซูมเข้ามากสุด
                      // กำหนดให้ไม่สามารถหมุนแผนที่ได้
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        enableMultiFingerGestureRace: true,
                      ),
                      // เพิ่ม debug logs เมื่อเริ่มต้นแผนที่
                      onMapReady: () {
                        if (_DEBUG) debugPrint('🔍 MapScreen - onMapReady ทำงาน, แผนที่พร้อมใช้งาน');
                        setState(() => _isMapLoaded = true);
                        _createMarkers();
                      },
                      // เพิ่ม onTap event เพื่อตรวจจับการแตะบนแผนที่
                      onTap: (tapPosition, latLng) {
                        if (_DEBUG) debugPrint('🔍 MapScreen - onTap บนแผนที่ที่ตำแหน่ง: $latLng');
                        _checkIfMarkerTapped(latLng);
                      },
                   
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      MarkerLayer(
                        markers: _markers.values.toList(),
                        rotate: false, // ไม่ให้ marker หมุนตามแผนที่
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Loading indicator
          if (!_isMapLoaded && !_hasMapError)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.orange, // สีเหมือนปุ่มรีเฟรชในหน้าโฮม
              ),
            ),
        ],
      ),
      floatingActionButton: !_hasMapError 
        ? Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // ปุ่มไปยังตำแหน่งของผู้ใช้
              FloatingActionButton(
                onPressed: _moveToUserLocation,
                heroTag: 'userLocationFAB',
                backgroundColor: Colors.white, // สีส้มที่เข้มขึ้นเหมือนหน้า home
                foregroundColor: Colors.blue,
                mini: true, // ทำให้ปุ่มเล็กลง
                child: const Icon(Icons.my_location),
                tooltip: 'ไปยังตำแหน่งของคุณ',
              ),
              const SizedBox(height: 16),
              // ปุ่มดูภาพรวมทั้งหมด
              FloatingActionButton(
                onPressed: _centerMapOnEarthquakes,
                heroTag: 'viewAllFAB',
                backgroundColor: Colors.white, // สีส้มที่เข้มขึ้นเหมือนหน้า home
                foregroundColor: Colors.green,
                child: const Icon(Icons.zoom_out_map),
                tooltip: 'แสดงแผ่นดินไหวทั้งหมด',
              ),
            ],
          ) 
        : null,
      // เพิ่ม bottom navigation bar หรือพื้นที่ด้านล่างเพื่อไม่ให้เป็นที่ว่าง
      bottomNavigationBar: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E), // สีเข้มกว่าพื้นหลังเล็กน้อย
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ส่วนซ้าย: แสดงจำนวนแผ่นดินไหว
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'แผ่นดินไหวทั้งหมด', 
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
                Text(
                  '${_markers.length} รายการ',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            // ส่วนขวา: ตัวกรอง
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showLast24Hours = !_showLast24Hours;
                  _createMarkers();
                });
              },
              icon: Icon(
                _showLast24Hours ? Icons.filter_list : Icons.filter_list_off,
                color: Colors.orange,
              ),
              label: Text(
                _showLast24Hours ? '24 ชั่วโมงล่าสุด' : 'แสดงทั้งหมด',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _onMapCreated(MapController controller) {
    try {
      setState(() {
        _isMapLoaded = true;
      });
      
      if (widget.selectedEarthquake != null) {
        _createMarkers();
      } else {
        if (_locationPermissionGranted) {
          _moveToUserLocation().then((_) {
            if (mounted) {
              _createMarkers();
            }
          });
        } else {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              _createMarkers();
            }
          });
        }
      }
    } catch (e) {
      print('Error creating map: $e');
      setState(() {
        _hasMapError = true;
        _errorMessage = 'เกิดข้อผิดพลาดในการโหลดแผนที่: $e';
      });
    }
  }

  // Create markers for each earthquake
  void _createMarkers() {
    if (_hasMapError || !mounted) {
      if (_DEBUG) debugPrint('❌ MapScreen - _createMarkers: มีข้อผิดพลาดหรือ widget ไม่ mounted');
      return;
    }
    
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    
    // ตรวจสอบว่ามีการเลือกแผ่นดินไหวเฉพาะหรือไม่
    if (widget.selectedEarthquake != null) {
      if (_DEBUG) debugPrint('🔍 MapScreen - สร้าง marker สำหรับแผ่นดินไหวที่เลือก');
      setState(() {
        _markers.clear();
        
        final quake = widget.selectedEarthquake!;
        
        // เพิ่มการตรวจสอบพิกัดที่ถูกต้อง
        if (quake.latitude == 0 && quake.longitude == 0) {
          debugPrint('พบแผ่นดินไหวที่มีพิกัด 0,0 - ข้ามการสร้าง marker: ${quake.id} - ${quake.location}');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถแสดงตำแหน่งแผ่นดินไหวบนแผนที่ได้เนื่องจากข้อมูลพิกัดไม่ถูกต้อง'),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
        
        try {
          final marker = Marker(
            width: 60.0,
            height: 60.0,
            point: LatLng(quake.latitude, quake.longitude),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  debugPrint('🎯 MapScreen - Marker tapped: ${quake.id}');
                  _showQuakeDetails(quake);
                },
                child: _getMarkerIcon(quake.magnitude),
              ),
            ),
          );
          
          _markers[quake.id] = marker;
          
          // Center map on this earthquake
          _mapController.move(LatLng(quake.latitude, quake.longitude), 10.0);
          
          debugPrint('แสดงแผ่นดินไหวที่เลือก: ${quake.location} (${quake.latitude}, ${quake.longitude})');
        } catch (e) {
          debugPrint('เกิดข้อผิดพลาดในการสร้าง marker สำหรับแผ่นดินไหวที่เลือก: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาดในการแสดงแผ่นดินไหวบนแผนที่: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
      
      // ซูมไปที่แผ่นดินไหวที่เลือก
      _zoomToSelectedEarthquake();
      return;
    }
    
    // ดึงข้อมูลทั้งหมดแบบไม่ผ่านการกรอง เพื่อหลีกเลี่ยงการกรองซ้ำซ้อน
    final allEarthquakes = earthquakeService.earthquakes;
    
    // ตรวจสอบว่ามีข้อมูลหรือไม่
    if (allEarthquakes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่พบข้อมูลแผ่นดินไหว กรุณารีเฟรชใหม่'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    debugPrint('กำลังสร้างมาร์คเกอร์จากข้อมูลแผ่นดินไหว ${allEarthquakes.length} รายการ');
    
    // กรองตามเงื่อนไข _showLast24Hours
    List<Earthquake> filteredEarthquakes = _showLast24Hours 
        ? allEarthquakes
            .where((e) => DateTime.now().difference(e.time).inHours <= 24)
            .toList()
        : allEarthquakes;
    
    // ตรวจสอบการกรองอื่นๆ จาก service
    final selectedRegion = earthquakeService.selectedRegion;
    if (selectedRegion != null && selectedRegion != 'all' && selectedRegion.isNotEmpty) {
      final filterFunction = CountryHelper.getFilterFunction(selectedRegion);
      filteredEarthquakes = filteredEarthquakes
          .where((quake) => filterFunction(quake.location))
          .toList();
      debugPrint('กรองตามภูมิภาค $selectedRegion เหลือ ${filteredEarthquakes.length} รายการ');
    }
    
    final selectedLocation = earthquakeService.selectedLocation;
    if (selectedLocation != null) {
      filteredEarthquakes = filteredEarthquakes
          .where((quake) => quake.location == selectedLocation)
          .toList();
      debugPrint('กรองตามตำแหน่ง $selectedLocation เหลือ ${filteredEarthquakes.length} รายการ');
    }
    
    // ตรวจสอบว่ามีข้อมูลหลังการกรองหรือไม่
    if (filteredEarthquakes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่พบข้อมูลแผ่นดินไหวตามเงื่อนไขที่กำหนด'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    // นับข้อมูลที่มีพิกัดไม่ถูกต้อง
    int invalidCoordinatesCount = 0;
    
    setState(() {
      _markers.clear();
      
      for (final quake in filteredEarthquakes) {
        try {
          // ข้ามข้อมูลที่มีพิกัดเป็น 0,0 หรือค่าที่ไม่สมเหตุสมผล
          if (quake.latitude == 0 && quake.longitude == 0) {
            invalidCoordinatesCount++;
            continue;
          }
          
          final marker = Marker(
            width: 60.0,
            height: 60.0,
            point: LatLng(quake.latitude, quake.longitude),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  debugPrint('🎯 MapScreen - Marker tapped: ${quake.id}');
                  _showQuakeDetails(quake);
                },
                child: _getMarkerIcon(quake.magnitude),
              ),
            ),
          );
          
          _markers[quake.id] = marker;
        } catch (e) {
          debugPrint('Error creating marker for earthquake ${quake.id}: $e');
          invalidCoordinatesCount++;
        }
      }
      
      if (invalidCoordinatesCount > 0) {
        debugPrint('ข้ามข้อมูลแผ่นดินไหวที่มีพิกัดไม่ถูกต้อง $invalidCoordinatesCount รายการ');
      }
      
      debugPrint('สร้างมาร์คเกอร์ทั้งหมด ${_markers.length} รายการ');
    });
    
    // Center map after creating markers
    if (_markers.isNotEmpty && _isMapLoaded && !_hasMapError && mounted) {
      _centerMapOnEarthquakes();
    } else if (_markers.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลแผ่นดินไหวที่มีพิกัดถูกต้องในช่วงเวลาที่เลือก'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  
  // Get marker icon based on earthquake magnitude
  Widget _getMarkerIcon(double magnitude) {
    Color color;
    
    // Define color based on magnitude
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
        color: color.withOpacity(0.8),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 3,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(
          magnitude.toStringAsFixed(1),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
  
  // Center map to show all earthquakes
  void _centerMapOnEarthquakes() {
    if (_markers.isEmpty) return;
    
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
    
    // Add padding around edges
    minLat -= 2.0;
    maxLat += 2.0;
    minLng -= 2.0;
    maxLng += 2.0;
    
    // Calculate center point and zoom level to fit bounds
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    
    // Calculate appropriate zoom level
    final latZoom = _calculateZoomLevel(maxLat - minLat);
    final lngZoom = _calculateZoomLevel(maxLng - minLng);
    final zoom = min(latZoom, lngZoom);
    
    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }
  
  // Calculate appropriate zoom level for a given span
  double _calculateZoomLevel(double span) {
    // Simple algorithm to calculate zoom based on span
    if (span <= 1) return 10.0;
    if (span <= 5) return 7.0;
    if (span <= 10) return 6.0;
    if (span <= 20) return 5.0;
    if (span <= 40) return 4.0;
    return 3.0;
  }
  
  // Refresh earthquake data from service based on current mode - ปิดการใช้งาน (ไม่มีปุ่ม refresh แล้ว)
  void _refreshEarthquakeData() async {
    // ฟังก์ชันนี้ถูกปิดการใช้งานเนื่องจากไม่มีปุ่ม refresh แล้ว
    return;
  }

  // ซูมไปที่แผ่นดินไหวที่เลือก
  Future<void> _zoomToSelectedEarthquake() async {
    if (widget.selectedEarthquake == null || !_isMapLoaded || _hasMapError || !mounted) return;
    
    try {
      // รอให้ controller พร้อมใช้งาน
      final controller = _mapController;
      
      if (controller == null || !mounted) return;
      
      final quake = widget.selectedEarthquake!;
      final position = LatLng(quake.latitude, quake.longitude);
      
      // รอสักครู่เพื่อให้มั่นใจว่ามาร์คเกอร์ถูกสร้างเรียบร้อยแล้ว
      await Future.delayed(const Duration(milliseconds: 100));
      
      // ซูมไปที่ตำแหน่งแผ่นดินไหวที่เลือกโดยใช้ CameraPosition ที่กำหนดชัดเจน
      await controller.move(position, 10.0);
      
      
      // รอให้การเคลื่อนไหวของกล้องเสร็จสิ้น แล้วจึงแสดง InfoWindow
      await Future.delayed(const Duration(milliseconds: 300));
      
      // แสดง InfoWindow
      if (_markers.containsKey(quake.id)) {
        controller.move(position, 10.0);
      }
      
    } catch (e) {
      debugPrint('Error zooming to selected earthquake: $e');
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // ตั้งค่า _currentDataMode จาก widget.dataMode โดยตรง
    _currentDataMode = widget.dataMode;
    
    if (mounted) {
      setState(() {});
    }
  }

  // เพิ่มฟังก์ชันตรวจสอบว่ามีการแตะที่หมุดหรือไม่
  void _checkIfMarkerTapped(LatLng tappedPoint) {
    // ตั้งค่าระยะห่างที่ยอมรับได้ในการแตะ (ในหน่วย degree)
    const double tapTolerance = 0.05; // เพิ่มค่าจาก 0.005 เป็น 0.05 ให้ตรวจจับการกดได้ง่ายขึ้น
    
    if (_DEBUG) debugPrint('🔍 MapScreen - _checkIfMarkerTapped เริ่มตรวจสอบที่ตำแหน่ง: $tappedPoint');
    if (_DEBUG) debugPrint('🔍 MapScreen - จำนวน markers ทั้งหมด: ${_markers.length}');
    
    for (final entry in _markers.entries) {
      final markerId = entry.key;
      final marker = entry.value;
      final markerPoint = marker.point;
      
      // คำนวณระยะห่างระหว่างจุดที่แตะกับตำแหน่งของ marker
      final distance = _calculateDistance(tappedPoint, markerPoint);
      
      if (_DEBUG) {
        debugPrint('🔍 MapScreen - ตรวจสอบ marker ID: $markerId ที่ตำแหน่ง: $markerPoint');
        debugPrint('🔍 MapScreen - ระยะห่าง: $distance (tapTolerance: $tapTolerance)');
      }
      
      // ถ้าระยะห่างน้อยกว่าค่าที่กำหนด ถือว่ามีการแตะที่ marker นี้
      if (distance < tapTolerance) {
        if (_DEBUG) debugPrint('✅ MapScreen - พบ marker ที่ถูกแตะ: $markerId');
        
        // หาข้อมูลแผ่นดินไหวจาก ID
        final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
        
        // ค้นหาแผ่นดินไหวจาก ID โดยใช้ firstWhere แทนการเรียก getEarthquakeById
        try {
          // เพิ่ม orElse เพื่อป้องกันข้อผิดพลาด State not found
          final quake = earthquakeService.earthquakes.firstWhere(
            (q) => q.id == markerId,
            orElse: () => throw Exception('ไม่พบข้อมูลแผ่นดินไหวสำหรับ ID: $markerId')
          );
          if (_DEBUG) debugPrint('✅ MapScreen - พบข้อมูลแผ่นดินไหว: ${quake.location} (${quake.magnitude})');
          // แสดงข้อมูลแผ่นดินไหว
          _showQuakeDetails(quake);
          return; // ออกจากลูปเมื่อพบ marker ที่ถูกแตะ
        } catch (e) {
          debugPrint('❌ MapScreen - ไม่พบข้อมูลแผ่นดินไหวสำหรับ ID $markerId: $e');
          // แจ้งเตือนผู้ใช้
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ไม่พบข้อมูลแผ่นดินไหวที่เลือก: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
    
    if (_DEBUG) debugPrint('❌ MapScreen - ไม่พบ marker ที่ถูกแตะ');
  }
  
  // คำนวณระยะห่างระหว่างสองจุดบนแผนที่
  double _calculateDistance(LatLng point1, LatLng point2) {
    final latDiff = (point1.latitude - point2.latitude).abs();
    final lngDiff = (point1.longitude - point2.longitude).abs();
    return sqrt(latDiff * latDiff + lngDiff * lngDiff);
  }

  // เพิ่มฟังก์ชันเปิด Google Maps
  Future<void> _openInGoogleMaps(double latitude, double longitude, String location) async {
    // ลิสต์ของ URL ที่จะลองเปิดตามลำดับ
    final List<String> mapUrls = [
      // 1. ลอง Google Maps app ก่อน (geo intent)
      'geo:$latitude,$longitude?q=$latitude,$longitude($location)',
      // 2. Google Maps web URL
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
      // 3. Google Maps direct URL
      'https://maps.google.com/?q=$latitude,$longitude',
      // 4. Generic maps URL
      'https://maps.google.com/maps?q=$latitude,$longitude',
    ];
    
    bool opened = false;
    String lastError = '';
    
    for (int i = 0; i < mapUrls.length; i++) {
      try {
        final String url = mapUrls[i];
        final Uri uri = Uri.parse(url);
        
        debugPrint('กำลังลองเปิด URL ที่ ${i + 1}: $url');
        
        // ลองเปิด URL โดยตรงแทนการตรวจสอบด้วย canLaunchUrl ก่อน
        // เพราะ canLaunchUrl อาจส่งคืนค่า false แม้ว่าจริงๆ แล้วเปิดได้
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        debugPrint('✅ เปิด URL สำเร็จ: $url');
        opened = true;
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เปิด Google Maps สำเร็จ'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
        
      } catch (e) {
        lastError = 'เกิดข้อผิดพลาด: $e';
        debugPrint('❌ เกิดข้อผิดพลาดในการเปิด URL ที่ ${i + 1}: $e');
        
        // ถ้าเป็น URL แรก (geo intent) และล้มเหลว ให้ลองต่อไป
        // ถ้าเป็น URL อื่นๆ และล้มเหลว ให้ลองต่อไป
        continue;
      }
    }
    
    // ถ้าเปิดไม่ได้เลย ให้แสดงข้อความแจ้งเตือนและเสนอทางเลือก
    if (!opened && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'ไม่สามารถเปิด Google Maps ได้',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'กรุณาลองวิธีใดวิธีหนึ่งต่อไปนี้:',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              const Text(
                '• ติดตั้งแอพ Google Maps',
                style: TextStyle(color: Colors.white70),
              ),
              const Text(
                '• คัดลอกพิกัดและค้นหาในแอพแผนที่อื่น',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  'พิกัด: $latitude, $longitude',
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ข้อผิดพลาดล่าสุด: $lastError',
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // คัดลอกพิกัดไปยังคลิปบอร์ด
                Clipboard.setData(ClipboardData(text: '$latitude, $longitude')).then((_) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('คัดลอกพิกัดแล้ว'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
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

  // เปิดหน้ารายละเอียดแผ่นดินไหวของ USGS
  Future<void> _showQuakeDetails(Earthquake quake) async {
    try {
      if (!mounted) return;
      
      if (_DEBUG) debugPrint('🔴 กำลังแสดง dialog ข้อมูลแผ่นดินไหว');
      
      await showDialog(
        context: context,
        barrierDismissible: false, // ทำให้ต้องกดปุ่มปิดเท่านั้น
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                    Text(
                      'รายละเอียดแผ่นดินไหว',
                      style: TextStyle(color: Colors.grey[200], fontWeight: FontWeight.bold),
                    ),
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
                _buildInfoRow('ละติจูด:', quake.latitude.toString()),
                _buildInfoRow('ลองจิจูด:', quake.longitude.toString()),
                const SizedBox(height: 12),
                // เพิ่ม Info ระยะทางจากจุดสนใจถ้ามีการใช้งานตำแหน่งปัจจุบัน
                if (_locationPermissionGranted && _currentLocation != null)
                  _buildDistanceInfo(quake),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
      
      if (_DEBUG) debugPrint('🔴 แสดง dialog เสร็จสิ้น');
    } catch (e) {
      debugPrint('❌ เกิดข้อผิดพลาดในการแสดง dialog: $e');
    }
  }
  
  // Helper widget to show distance from user's location to earthquake
  Widget _buildDistanceInfo(Earthquake quake) {
    if (_currentLocation == null) return const SizedBox.shrink();
    
    // Calculate distance
    final userLat = _currentLocation!.latitude ?? 0.0;
    final userLng = _currentLocation!.longitude ?? 0.0;
    
    if (userLat == 0.0 || userLng == 0.0) return const SizedBox.shrink();
    
    final distance = calculateDistance(
      userLat, 
      userLng, 
      quake.latitude, 
      quake.longitude
    );
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ห่างจากตำแหน่งของคุณประมาณ ${distance.toStringAsFixed(0)} กม.',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
  
  // Calculate distance between two points in kilometers using Haversine formula
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in kilometers
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = 
        sin(dLat/2) * sin(dLat/2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * 
        sin(dLon/2) * sin(dLon/2);
        
    final c = 2 * atan2(sqrt(a), sqrt(1-a));
    return R * c;
  }
  
  // Convert degrees to radians
  double _toRadians(double degree) {
    return degree * pi / 180;
  }
  
  // Get color based on magnitude
  Color _getMagnitudeColor(double magnitude) {
    if (magnitude < 3.0) {
      return Colors.green;
    } else if (magnitude < 4.0) {
      return Colors.yellow;
    } else if (magnitude < 5.0) {
      return Colors.orange;
    } else if (magnitude < 6.0) {
      return Colors.deepOrange;
    } else {
      return Colors.red;
    }
  }

  // Check location permission
  Future<void> _checkLocationPermission() async {
    try {
      bool serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _locationService.requestService();
        if (!serviceEnabled) {
          setState(() {
            _locationPermissionGranted = false;
          });
          return;
        }
      }
      
      PermissionStatus permissionStatus = await _locationService.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        permissionStatus = await _locationService.requestPermission();
        if (permissionStatus != PermissionStatus.granted) {
          setState(() {
            _locationPermissionGranted = false;
          });
          return;
        }
      }
      
      setState(() {
        _locationPermissionGranted = true;
      });
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      setState(() {
        _locationPermissionGranted = false;
      });
    }
  }

  // Helper สำหรับสร้างแถวข้อมูล
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ฟังก์ชันแสดงข่าวเกี่ยวกับแผ่นดินไหว
  void _showNewsSearchForEarthquake(Earthquake quake) {
    // สร้าง search query สำหรับการค้นหาข่าว
    final location = quake.location.split(' ').take(2).join(' ');
    final date = DateFormat('dd MMMM yyyy').format(quake.time);
    final searchQuery = 'แผ่นดินไหว $location $date';
    
    // เปิด URL ในเบราว์เซอร์
    final url = Uri.parse('https://news.google.com/search?q=$searchQuery');
    launchUrl(url, mode: LaunchMode.externalApplication);
  }

  // Move map to user's current location
  Future<void> _moveToUserLocation() async {
    if (!_locationPermissionGranted) {
      if (_DEBUG) debugPrint('🔍 MapScreen - ยังไม่ได้รับอนุญาตเข้าถึงตำแหน่ง, กำลังตรวจสอบสิทธิ์');
      await _checkLocationPermission();
      if (!_locationPermissionGranted) {
        // Show message that location permission is needed
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ต้องการสิทธิ์การเข้าถึงตำแหน่งเพื่อแสดงตำแหน่งของคุณ'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }
    
    try {
      if (_DEBUG) debugPrint('🔍 MapScreen - กำลังดึงข้อมูลตำแหน่งปัจจุบัน');
      
      // เพิ่มตัวแปรเพื่อตรวจสอบสถานะการทำงานของ Location Service
      final serviceEnabled = await _locationService.serviceEnabled();
      if (!serviceEnabled) {
        bool isEnabled = await _locationService.requestService();
        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กรุณาเปิดใช้บริการตำแหน่งบนอุปกรณ์ของคุณ'),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }
      
      // แสดงข้อความกำลังโหลด
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กำลังค้นหาตำแหน่งของคุณ...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      // ตั้งค่า timeout สำหรับการรับตำแหน่ง
      _currentLocation = await _locationService.getLocation().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('หมดเวลาในการค้นหาตำแหน่ง');
        },
      );
      
      if (_currentLocation != null && mounted) {
        final lat = _currentLocation!.latitude ?? _defaultCenter.latitude;
        final lng = _currentLocation!.longitude ?? _defaultCenter.longitude;
        
        if (_DEBUG) debugPrint('✅ MapScreen - พบตำแหน่งปัจจุบัน: $lat, $lng');
        
        // เพิ่มการตรวจสอบค่าพิกัดที่ได้รับ
        if (lat == 0.0 && lng == 0.0) {
          throw Exception('ได้รับตำแหน่งที่ไม่ถูกต้อง');
        }
        
        // เพิ่มหมุดแสดงตำแหน่งของผู้ใช้
        final userLocation = LatLng(lat, lng);
        
        // สร้าง Marker สำหรับตำแหน่งผู้ใช้
        final userMarker = Marker(
          width: 40.0,
          height: 40.0,
          point: userLocation,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF57C00).withOpacity(0.7), // เปลี่ยนเป็นสีส้มเข้มเหมือนหน้า home
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.my_location,
              color: Colors.white,
              size: 20,
            ),
          ),
        );
        
        // เพิ่มหรืออัปเดต marker ตำแหน่งของผู้ใช้
        setState(() {
          _markers['user_location'] = userMarker;
        });
        
        // เพิ่มหน่วงเวลาเล็กน้อยก่อนเลื่อนแผนที่
        await Future.delayed(const Duration(milliseconds: 300));
        _mapController.move(userLocation, 12.0);
        
        // แสดงข้อความเมื่อเลื่อนแผนที่สำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('แสดงตำแหน่งของคุณแล้ว'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        throw Exception('ไม่สามารถรับตำแหน่งได้');
      }
    } catch (e) {
      debugPrint('❌ MapScreen - Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถระบุตำแหน่งของคุณได้: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
} 