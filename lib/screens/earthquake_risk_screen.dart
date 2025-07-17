import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';
import 'package:intl/intl.dart';
import '../models/earthquake.dart';
import '../services/earthquake_probability_service.dart';
import 'dart:math' as math;

class EarthquakeRiskScreen extends StatefulWidget {
  final LatLng? initialLocation;
  
  const EarthquakeRiskScreen({
    Key? key,
    this.initialLocation,
  }) : super(key: key);

  @override
  State<EarthquakeRiskScreen> createState() => _EarthquakeRiskScreenState();
}

class _EarthquakeRiskScreenState extends State<EarthquakeRiskScreen> {
  final EarthquakeProbabilityService _probabilityService = EarthquakeProbabilityService();
  final MapController _mapController = MapController();
  
  bool _isLoading = false;
  bool _hasData = false;
  LatLng _selectedLocation = const LatLng(13.7563, 100.5018); // กรุงเทพฯ
  List<Earthquake> _historicalEarthquakes = [];
  Map<String, dynamic> _probabilityData = {};
  Map<String, dynamic> _trendData = {};
  
  @override
  void initState() {
    super.initState();
    
    if (widget.initialLocation != null) {
      _selectedLocation = widget.initialLocation!;
    }
    
    _loadUserLocation();
  }
  
  // เรียกตำแหน่งปัจจุบันของผู้ใช้
  Future<void> _loadUserLocation() async {
    if (widget.initialLocation != null) {
      return; // ถ้ามีการระบุตำแหน่งมาแล้ว ไม่ต้องโหลดตำแหน่งผู้ใช้
    }
    
    try {
      final locationService = Location();
      bool serviceEnabled = await locationService.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await locationService.requestService();
        if (!serviceEnabled) {
          return;
        }
      }
      
      final permissionStatus = await locationService.hasPermission();
      if (permissionStatus == PermissionStatus.denied) {
        final newPermission = await locationService.requestPermission();
        if (newPermission != PermissionStatus.granted) {
          return;
        }
      }
      
      final locationData = await locationService.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        setState(() {
          _selectedLocation = LatLng(
            locationData.latitude!,
            locationData.longitude!,
          );
        });
        
        // เลื่อนแผนที่ไปยังตำแหน่งปัจจุบัน
        _mapController.move(_selectedLocation, 8.0);
      }
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }
  
  // โหลดข้อมูลความเสี่ยงและประวัติแผ่นดินไหว
  Future<void> _loadEarthquakeData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _hasData = false;
    });
    
    try {
      // ดึงข้อมูลประวัติแผ่นดินไหวในพื้นที่
      final earthquakes = await _probabilityService.fetchHistoricalEarthquakeData(
        _selectedLocation.latitude,
        _selectedLocation.longitude,
      );
      
      // คำนวณโอกาสเกิดแผ่นดินไหว
      final probabilityData = _probabilityService.calculateEarthquakeProbability(
        _selectedLocation.latitude,
        _selectedLocation.longitude,
      );
      
      // วิเคราะห์แนวโน้ม
      final trendData = _probabilityService.analyzeEarthquakeTrends();
      
      if (mounted) {
        setState(() {
          _historicalEarthquakes = earthquakes;
          _probabilityData = probabilityData;
          _trendData = trendData;
          _isLoading = false;
          _hasData = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading earthquake data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // เปลี่ยนเป็นสีดำเหมือนหน้าอื่นๆ
      appBar: AppBar(
        title: const Text('วิเคราะห์ความเสี่ยงแผ่นดินไหว',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF121212), // เปลี่ยนเป็นสีดำเหมือนหน้าอื่นๆ
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white), // สีไอคอนเป็นขาว
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location, color: Colors.white),
            onPressed: _loadUserLocation,
            tooltip: 'ไปยังตำแหน่งปัจจุบัน',
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF121212), // พื้นหลังสีดำ
        child: Column(
          children: [
            // แผนที่สำหรับเลือกตำแหน่ง
            Container(
              height: 200,
              margin: const EdgeInsets.all(8.0), // เพิ่มขอบ
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12), // เพิ่มขอบมน
                border: Border.all(color: Colors.grey.shade800), // เพิ่มเส้นขอบ
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12), // ตัดมุมให้มน
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _selectedLocation,
                    initialZoom: 8.0,
                    minZoom: 3.0,
                    maxZoom: 18.0,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedLocation = point;
                        _hasData = false; // รีเซ็ตข้อมูลเมื่อเลือกตำแหน่งใหม่
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.softacular.whaipao',
                    ),
                    MarkerLayer(
                      markers: [
                        // มาร์คเกอร์ตำแหน่งที่เลือก
                        Marker(
                          width: 40.0,
                          height: 40.0,
                          point: _selectedLocation,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                        // มาร์คเกอร์แผ่นดินไหวย้อนหลัง
                        ..._historicalEarthquakes.map((quake) {
                          // คำนวณสีตามขนาดแผ่นดินไหว
                          Color color;
                          if (quake.magnitude < 4.0) {
                            color = Colors.green;
                          } else if (quake.magnitude < 5.0) {
                            color = Colors.lime;
                          } else if (quake.magnitude < 6.0) {
                            color = Colors.amber;
                          } else if (quake.magnitude < 7.0) {
                            color = Colors.orange;
                          } else {
                            color = Colors.red;
                          }
                          
                          // คำนวณขนาดตามขนาดแผ่นดินไหว
                          final double size = math.min(30.0, math.max(15.0, quake.magnitude * 4.0));
                          
                          return Marker(
                            width: size,
                            height: size,
                            point: LatLng(quake.latitude, quake.longitude),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  quake.magnitude.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: size / 3,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // ปุ่มตรวจสอบความเสี่ยง
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _loadEarthquakeData,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange, // เปลี่ยนสีเป็นสีส้มเหมือนปุ่มในหน้าอื่น
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8), // มุมมน
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'ตรวจสอบความเสี่ยงแผ่นดินไหว',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
            
            // แสดงข้อมูลความเสี่ยงและประวัติแผ่นดินไหว
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.orange, // สีส้มเหมือนปุ่ม
                      ),
                    )
                  : !_hasData
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              'เลือกตำแหน่งบนแผนที่และกดปุ่มตรวจสอบความเสี่ยง',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.white70, // ข้อความสีขาวกึ่งโปร่งใส
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _buildRiskDataUI(),
            ),
          ],
        ),
      ),
    );
  }
  
  // สร้าง UI แสดงข้อมูลความเสี่ยงและประวัติแผ่นดินไหว
  Widget _buildRiskDataUI() {
    return Container(
      color: const Color(0xFF121212), // พื้นหลังสีดำ
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // ข้อมูลที่ตั้ง
          Text(
            'ข้อมูลตำแหน่งที่เลือก:',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white, // ข้อความสีขาว
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ละติจูด: ${_selectedLocation.latitude.toStringAsFixed(4)}, ลองจิจูด: ${_selectedLocation.longitude.toStringAsFixed(4)}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white70, // ข้อความสีขาวกึ่งโปร่งใส
            ),
          ),
          const SizedBox(height: 16),
          
          // ข้อมูลความเสี่ยง
          Card(
            color: const Color(0xFF1E1E1E), // สีเข้มกว่าพื้นหลังเล็กน้อย
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: _getConfidenceLevelColor(_probabilityData['confidenceLevel'] ?? 'ไม่ทราบ'),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ความเสี่ยง: ${_probabilityData['confidenceLevel'] ?? 'ไม่ทราบ'}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // ข้อความสีขาว
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Text(
                  //   _getRecommendationText(_probabilityData['confidenceLevel'] ?? 'ไม่ทราบ'),
                  //   style: TextStyle(
                  //     fontSize: 14,
                  //     color: Colors.white70, // ข้อความสีขาวกึ่งโปร่งใส
                  //   ),
                  // ),
                  if (_probabilityData.containsKey('confidence'))
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'ความเชื่อมั่นของการวิเคราะห์: ${_probabilityData['confidence']}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.white60, // ข้อความสีขาวกึ่งโปร่งใสมากขึ้น
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // แผ่นดินไหวย้อนหลัง
          Card(
            color: const Color(0xFF1E1E1E), // สีเข้มกว่าพื้นหลังเล็กน้อย
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ประวัติแผ่นดินไหวในรัศมี 100 กม.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // ข้อความสีขาว
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'พบ ${_historicalEarthquakes.length} เหตุการณ์',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70, // ข้อความสีขาวกึ่งโปร่งใส
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._historicalEarthquakes.map((quake) => _buildEarthquakeItem(quake)).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // การวิเคราะห์แนวโน้ม
          Card(
            color: const Color(0xFF1E1E1E), // สีเข้มกว่าพื้นหลังเล็กน้อย
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'การวิเคราะห์แนวโน้ม',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white, // ข้อความสีขาว
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _trendData['trend'] ?? 'ไม่มีข้อมูลเพียงพอสำหรับการวิเคราะห์',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white70, // ข้อความสีขาวกึ่งโปร่งใส
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // สร้างรายการแผ่นดินไหว
  Widget _buildEarthquakeItem(Earthquake quake) {
    // คำนวณสีตามขนาดแผ่นดินไหว
    Color color;
    if (quake.magnitude < 4.0) {
      color = Colors.green;
    } else if (quake.magnitude < 5.0) {
      color = Colors.lime;
    } else if (quake.magnitude < 6.0) {
      color = Colors.amber;
    } else if (quake.magnitude < 7.0) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                quake.magnitude.toStringAsFixed(1),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quake.location,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white, // ข้อความสีขาว
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(quake.time) + 
                  ' (${_getTimeAgo(quake.time)})',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60, // ข้อความสีขาวกึ่งโปร่งใสมากขึ้น
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // แปลงระดับความเชื่อมั่นเป็นสี
  Color _getConfidenceLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'สูงมาก':
        return Colors.red;
      case 'สูง':
        return Colors.deepOrange;
      case 'ปานกลาง':
        return Colors.amber;
      case 'ปานกลาง-ต่ำ':
        return Colors.yellow;
      case 'ต่ำ':
        return Colors.lightGreen;
      default:
        return Colors.grey;
    }
  }
  
  // คำนวณเวลาที่ผ่านมา
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} ปีที่แล้ว';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} เดือนที่แล้ว';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} วันที่แล้ว';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ชั่วโมงที่แล้ว';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} นาทีที่แล้ว';
    } else {
      return 'เมื่อสักครู่';
    }
  }
  
  // สร้างข้อความคำแนะนำที่สอดคล้องกับระดับความเสี่ยง
  String _getRecommendationText(String riskLevel) {
    // ถ้ามีข้อความแนะนำจาก API ให้ใช้อันนั้นก่อน
    if (_probabilityData.containsKey('recommendation') && 
        _probabilityData['recommendation'] != null &&
        _probabilityData['recommendation'].toString().isNotEmpty) {
      return _probabilityData['recommendation'];
    }
    
    // ถ้าไม่มี ให้สร้างข้อความตามระดับความเสี่ยง
    switch (riskLevel.toLowerCase()) {
      case 'สูงมาก':
        return 'บริเวณนี้มีความเสี่ยงสูงมาก ควรเตรียมพร้อมรับมือแผ่นดินไหวและมีแผนอพยพฉุกเฉิน';
      case 'สูง':
        return 'บริเวณนี้มีความเสี่ยงสูง ควรเรียนรู้วิธีรับมือแผ่นดินไหวและตรวจสอบความปลอดภัยของที่พักอาศัย';
      case 'ปานกลาง':
        return 'บริเวณนี้มีความเสี่ยงปานกลาง ควรทราบวิธีปฏิบัติตัวเมื่อเกิดแผ่นดินไหว';
      case 'ปานกลาง-ต่ำ':
        return 'บริเวณนี้มีความเสี่ยงปานกลางถึงต่ำ แต่ควรรู้วิธีรับมือแผ่นดินไหวไว้';
      case 'ต่ำ':
        return 'บริเวณนี้มีความเสี่ยงต่ำ แต่ควรรู้วิธีรับมือแผ่นดินไหวไว้';
      default:
        return 'ไม่สามารถระบุระดับความเสี่ยงได้ ควรศึกษาข้อมูลเพิ่มเติมจากกรมทรัพยากรธรณี';
    }
  }
} 