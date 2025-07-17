// lib/screens/home_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math'; // Add import for min function
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:clipboard/clipboard.dart';
import 'package:thai_thermo_3/screens/notificaion_screen_setting.dart';
import 'package:thai_thermo_3/utils/country_helper.dart';
import 'package:thai_thermo_3/utils/date_helper.dart';
import '../main.dart'; // Import for runNotificationDiagnostics
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart'; // Change from google_maps_flutter to flutter_map
import 'package:latlong2/latlong.dart'; // For LatLng
import 'package:location/location.dart';
import 'package:url_launcher/url_launcher.dart'; // เพิ่ม import สำหรับเปิด URL

import '../models/earthquake.dart';
import '../services/earthquake_service.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import 'map_screen.dart'; // Add this import
import 'notificaion_screen_setting.dart';
import '../enums/data_fetch_mode.dart';
import 'earthquake_risk_screen.dart'; // Add this import

// Add enum for date filter options near the top of the file
enum DateFilterOption {
  today,
  thisWeek,
  thisMonth,
  threeMonths,
  all
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = false;
  DateTime? _lastRefresh;
  String? _fcmToken;
  bool _showLastRefreshed = true;
  String? _selectedRegionCode;
  
  // เหลือเพียงตัวแปรสำหรับอัพเดทอัตโนมัติแต่ไม่แสดงให้ผู้ใช้ทราบ
  Timer? _autoRefreshTimer;
  // กำหนดให้อัพเดททุก 5 นาทีโดยไม่ให้ผู้ใช้ปรับแก้
  final int _refreshIntervalMinutes = 5;
  
  // Add location service
  final Location _locationService = Location();
  
  // เพิ่มตัวแปรสำหรับเก็บตำแหน่งผู้ใช้
  LocationData? _currentUserLocation;
  
  // Date filter option
  DateFilterOption _selectedDateFilter = DateFilterOption.all;
  
  // เพิ่มตัวแปรสำหรับโหมดการดึงข้อมูล
  DataFetchMode _dataFetchMode = DataFetchMode.southeastAsia;

  // เพิ่มตัวแปรสำหรับชนิดของแผนที่
  String _mapType = 'normal';

  final NotificationService _notificationService = NotificationService();
  final FCMService _fcmService = FCMService();

  // เพิ่มตัวแปรสำหรับแผนที่
  final MapController _mapController = MapController();
  final Map<String, Marker> _markers = {};
  bool _isMapLoaded = false;
  
  // กำหนดพิกัดเริ่มต้น (กรุงเทพฯ)
  static const LatLng _defaultCenter = LatLng(13.7563, 100.5018);
  static const double _defaultZoom = 5.0;

  @override
  void initState() {
    super.initState();
    _initialize();
    _checkLocationPermission();
    _getCurrentLocation(); // เพิ่มการดึงตำแหน่งผู้ใช้
    
    // Start auto-refresh timer
    _startAutoRefreshTimer();
  }
  
  @override
  void dispose() {
    // Cancel timer when widget is disposed
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _initialize() async {
    await Firebase.initializeApp();

    // ตั้งค่า SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedRegionCode = prefs.getString('selectedRegion') ?? 'all';
      // Load date filter preference
      final savedDateFilter = prefs.getString('selectedDateFilter') ?? DateFilterOption.all.toString();
      _selectedDateFilter = DateFilterOption.values.firstWhere(
        (e) => e.toString() == savedDateFilter,
        orElse: () => DateFilterOption.all
      );
      
      // โหลดโหมดการดึงข้อมูล
      final savedFetchMode = prefs.getString('dataFetchMode');
      if (savedFetchMode != null) {
        _dataFetchMode = DataFetchMode.values.firstWhere(
          (e) => e.toString() == savedFetchMode,
          orElse: () => DataFetchMode.southeastAsia
        );
      }
      
      // โหลดชนิดของแผนที่
      final savedMapType = prefs.getString('mapType');
      if (savedMapType != null) {
        _mapType = savedMapType;
      }
    });

    // แสดงผลลัพธ์การโหลดการตั้งค่า
    debugPrint('Loaded date filter: $_selectedDateFilter');
    debugPrint('Loaded region code: $_selectedRegionCode');
    debugPrint('Loaded data fetch mode: $_dataFetchMode');

    // ดึง FCM token
    _getFCMToken();

    // โหลดข้อมูลครั้งแรกเมื่อเปิดแอพ
    _loadEarthquakes(checkForNotifications: false).then((_) {
      // สร้างมาร์คเกอร์บนแผนที่หลังจากโหลดข้อมูลเสร็จ
      _createMarkers();
    });

    // ตั้งค่าป้องกันการแจ้งเตือนซ้ำเมื่อเปิดแอพ
    _preventDuplicateNotifications();

    // ตั้งค่า callback เมื่อได้รับ FCM
    _fcmService.onEarthquakeReceived = (earthquake) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ได้รับข้อมูลแผ่นดินไหวใหม่: ${earthquake.magnitude} ${earthquake.location}',
            ),
            action: SnackBarAction(
              label: 'ดูเดี๋ยวนี้',
              onPressed: () => _loadEarthquakes(checkForNotifications: false),
            ),
          ),
        );
      }
    };
  }
  
  // Start auto-refresh timer - ทำให้เรียบง่ายไม่มี UI ให้ตั้งค่า
  void _startAutoRefreshTimer() {
    // Cancel existing timer if any
    _autoRefreshTimer?.cancel();
    
    // Create new timer - ใช้ค่าคงที่โดยไม่ให้ผู้ใช้ปรับแก้
    _autoRefreshTimer = Timer.periodic(
      Duration(minutes: _refreshIntervalMinutes), 
      (timer) {
        if (mounted) {
          debugPrint('Auto-refreshing earthquake data...');
          // ดึงข้อมูลโดยไม่แจ้งเตือนในทุกกรณี
          if (!_isLoading) { // เพิ่มเงื่อนไขตรวจสอบว่าไม่ได้กำลังโหลดข้อมูลอยู่
            _loadEarthquakes(checkForNotifications: false);
          } else {
            debugPrint('Skip auto-refresh because app is already loading data');
          }
        }
      }
    );
    
    debugPrint('Started auto-refresh timer (every $_refreshIntervalMinutes minutes)');
  }

  Future<void> _checkForNewEarthquakes() async {
    debugPrint('กำลังตรวจสอบแผ่นดินไหวใหม่...');
    try {
      final earthquakeService = Provider.of<EarthquakeService>(
        context,
        listen: false,
      );

      // ดึงข้อมูลเฉพาะช่วง 1 ชั่วโมงล่าสุด (ใช้ฟังก์ชันใหม่)
      await earthquakeService.fetchLastHourEarthquakes(
        checkForNotifications: false,  // ปิดการแจ้งเตือนในทุกกรณี
        respectMagnitudeFilter: true,
      );

      // อัปเดตเวลารีเฟรชล่าสุด
      setState(() {
        _lastRefresh = DateTime.now();
      });

      debugPrint('ตรวจสอบแผ่นดินไหวใหม่เรียบร้อย');

      // ตรวจสอบว่ามีข้อมูลใหม่หรือไม่ (ข้อมูลในช่วง 30 นาทีล่าสุด) แต่ไม่ส่งการแจ้งเตือน
      final recentQuakes =
          earthquakeService.earthquakes
              .where(
                (quake) =>
                    DateTime.now().difference(quake.time).inMinutes <= 30,
              )
              .toList();

      if (recentQuakes.isNotEmpty) {
        debugPrint(
          'พบแผ่นดินไหวใหม่ ${recentQuakes.length} รายการในช่วง 30 นาทีล่าสุด (ไม่ส่งการแจ้งเตือน)',
        );
      }
    } catch (e) {
      debugPrint('เกิดข้อผิดพลาดในการตรวจสอบแผ่นดินไหวใหม่: $e');
    }
  }

  void _testFCMWithEarthquakeData(Earthquake quake) async {
    try {
      await _notificationService.showEarthquakeNotification(
        title: 'ทดสอบ: แผ่นดินไหว ${quake.magnitude}',
        body:
            'ทดสอบแจ้งเตือนที่ ${quake.location} เวลา ${DateFormat('HH:mm').format(quake.time)}',
        payload:
            '{"id":"${quake.id}","magnitude":"${quake.magnitude}","time":"${quake.time.toIso8601String()}","latitude":"${quake.latitude}","longitude":"${quake.longitude}","depth":"${quake.depth}","place":"${quake.location}"}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งการแจ้งเตือนทดสอบด้วยข้อมูลแผ่นดินไหวแล้ว'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // แสดง Snackbar เมื่อพบแผ่นดินไหวใหม่
  void _showNewEarthquakeSnackbar(Earthquake quake) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'พบแผ่นดินไหวใหม่: ${quake.magnitude} ที่ ${quake.location}',
        ),
        backgroundColor: _getMagnitudeColor(quake.magnitude),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'ดูรายละเอียด',
          textColor: Colors.white,
          onPressed: () => _showEarthquakeDetails(quake),
        ),
      ),
    );
  }

  // ตรวจสอบว่าเคยแจ้งเตือนแผ่นดินไหวนี้ไปแล้วหรือยัง
  Future<bool> _hasNotifiedBefore(String quakeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('notified_$quakeId') ?? false;
    } catch (e) {
      debugPrint('Error checking notification status: $e');
      return false;
    }
  }

  // บันทึกว่าได้แจ้งเตือนแผ่นดินไหวนี้แล้ว
  Future<void> _markAsNotified(String quakeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notified_$quakeId', true);
      await prefs.setString(
        'notified_time_$quakeId',
        DateTime.now().toIso8601String(),
      );
      debugPrint('บันทึกการแจ้งเตือน earthquake $quakeId เรียบร้อย');
    } catch (e) {
      debugPrint('Error marking earthquake as notified: $e');
    }
  }

  Future<void> _getFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      setState(() {
        _fcmToken = token;
      });
      debugPrint('FCM Token: $_fcmToken');
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  Future<void> _loadEarthquakes({bool checkForNotifications = false}) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final earthquakeService = Provider.of<EarthquakeService>(
        context,
        listen: false,
      );

      // เลือกวิธีการดึงข้อมูลตามโหมด
      switch (_dataFetchMode) {
        case DataFetchMode.global:
          await earthquakeService.fetchRecentEarthquakes(
            checkForNotifications: false,  // ปิดการแจ้งเตือนในทุกกรณี
            respectMagnitudeFilter: true,
          );
          break;
          
        case DataFetchMode.southeastAsia:
          await earthquakeService.fetchSoutheastAsiaEarthquakes(
            checkForNotifications: false,  // ปิดการแจ้งเตือนในทุกกรณี
            respectMagnitudeFilter: true,
          );
          break;
          
        case DataFetchMode.thailandArea:
          await earthquakeService.fetchThailandAndNeighborsEarthquakes(
            checkForNotifications: false,  // ปิดการแจ้งเตือนในทุกกรณี
            respectMagnitudeFilter: true,
          );
          break;
      }

      // ปิดการตรวจสอบการแจ้งเตือนทั้งหมด - ให้แจ้งเตือนผ่าน FCM จากเซิร์ฟเวอร์แทน
      // ไม่จำเป็นต้องตรวจสอบหรือส่งการแจ้งเตือนในแอพอีก
      
      // เพิ่มการอัพเดทมาร์คเกอร์หลังโหลดข้อมูล
      _createMarkers();

      setState(() {
        _lastRefresh = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        // ปรับข้อความแสดง error ให้เป็นมิตรกับผู้ใช้มากขึ้น
        String errorMessage = 'เกิดข้อผิดพลาดในการโหลดข้อมูล';
        
        // ตรวจสอบว่าเป็น timeout หรือไม่
        if (e.toString().contains('timeout') || e.toString().contains('นานเกินไป')) {
          errorMessage = 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาตรวจสอบการเชื่อมต่ออินเทอร์เน็ตและลองใหม่อีกครั้ง';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'ลองใหม่',
              onPressed: () => _loadEarthquakes(checkForNotifications: false),
            ),
          ),
        );
      }
    }
  }

  // Future<void> _sendTestLocalNotification() async {
  //   try {
  //     await _notificationService.showTestNotification(
  //       title: 'ทดสอบการแจ้งเตือนในแอพ',
  //       body:
  //           'นี่คือการทดสอบส่งแจ้งเตือนจากในแอพโดยตรง (${DateTime.now().toString()})',
  //     );

  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('ส่งการแจ้งเตือนทดสอบแล้ว'),
  //         backgroundColor: Colors.green,
  //         duration: Duration(seconds: 2),
  //       ),
  //     );
  //   } catch (e) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('เกิดข้อผิดพลาด: $e'),
  //         backgroundColor: Colors.red,
  //         duration: const Duration(seconds: 5),
  //       ),
  //     );
  //   }
  // }

  // Future<void> _testFCMService() async {
  //   try {
  //     final result = await _fcmService.sendTestNotification();

  //     if (result) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('ส่งการแจ้งเตือนทดสอบผ่าน FCM แล้ว'),
  //           backgroundColor: Colors.green,
  //           duration: Duration(seconds: 2),
  //         ),
  //       );
  //     } else {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('ไม่สามารถส่งการแจ้งเตือนได้'),
  //           backgroundColor: Colors.orange,
  //           duration: Duration(seconds: 3),
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('เกิดข้อผิดพลาด: $e'),
  //         backgroundColor: Colors.red,
  //         duration: const Duration(seconds: 5),
  //       ),
  //     );
  //   }
  // }

  // ตั้งค่าป้องกันการแจ้งเตือนซ้ำเมื่อเปิดแอพ
  Future<void> _preventDuplicateNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('prevent_duplicate_notifications', true);
      debugPrint('⚠️ ตั้งค่าป้องกันการแจ้งเตือนซ้ำเมื่อเปิดแอพ: true');
    } catch (e) {
      debugPrint('เกิดข้อผิดพลาดในการตั้งค่าป้องกันการแจ้งเตือนซ้ำ: $e');
    }
  }

  // Future<void> _sendMultipleTestNotifications() async {
  //   try {
  //     await _notificationService.showMultipleTestNotifications(count: 5);

  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(
  //         content: Text('ส่งการแจ้งเตือนหลายรายการแล้ว'),
  //         backgroundColor: Colors.green,
  //         duration: Duration(seconds: 2),
  //       ),
  //     );
  //   } catch (e) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Text('เกิดข้อผิดพลาด: $e'),
  //         backgroundColor: Colors.red,
  //         duration: const Duration(seconds: 5),
  //       ),
  //     );
  //   }
  // }

  void _copyTokenToClipboard() {
    if (_fcmToken != null) {
      FlutterClipboard.copy(_fcmToken!).then((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('คัดลอก FCM Token ไปยังคลิปบอร์ดแล้ว'),
            duration: Duration(seconds: 2),
          ),
        );
      });
    }
  }

  // Run notification diagnostics
  // Future<void> _runDiagnostics() async {
  //   try {
  //     // Show dialog while running diagnostics
  //     showDialog(
  //       context: context,
  //       barrierDismissible: false,
  //       builder: (context) => const AlertDialog(
  //         title: Text('กำลังตรวจสอบการแจ้งเตือน'),
  //         content: Column(
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             CircularProgressIndicator(),
  //             SizedBox(height: 16),
  //             Text('กรุณารอสักครู่...'),
  //           ],
  //         ),
  //       ),
  //     );
      
  //     // Run the diagnostics
  //     if (Platform.isIOS) {
  //       // Run iOS-specific diagnostics first
  //       await diagnoseIOSNotifications();
  //     }
      
  //     // Run general diagnostics
  //     await runNotificationDiagnostics();
      
  //     // Close progress dialog
  //     if (mounted && Navigator.canPop(context)) {
  //       Navigator.pop(context);
  //     }
      
  //     // Show results dialog
  //     if (mounted) {
  //       showDialog(
  //         context: context,
  //         builder: (context) => AlertDialog(
  //           title: const Text('ผลการตรวจสอบ'),
  //           content: SingleChildScrollView(
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               mainAxisSize: MainAxisSize.min,
  //               children: [
  //                 const Text('การตรวจสอบระบบแจ้งเตือนเสร็จสิ้น โปรดตรวจสอบ log เพื่อดูรายละเอียด'),
  //                 const SizedBox(height: 16),
  //                 const Text('หากไม่ได้รับการแจ้งเตือน โปรดตรวจสอบ:', style: TextStyle(fontWeight: FontWeight.bold)),
  //                 if (Platform.isIOS) ...[
  //                   const Text('• ตั้งค่าการแจ้งเตือนใน Settings > การแจ้งเตือน > แอปนี้'),
  //                   const Text('• ปิดโหมด Focus หรือห้ามรบกวน'),
  //                   const Text('• ตรวจสอบว่าอนุญาตการแจ้งเตือนฉุกเฉิน (Critical Alerts)'),
  //                   const Text('• ตรวจสอบว่ามีไฟล์เสียงครบถ้วน'),
  //                 ] else ...[
  //                   const Text('• ตั้งค่าการแจ้งเตือนในแอพ'),
  //                   const Text('• ตั้งค่าแอพในระบบเพื่ออนุญาตการแจ้งเตือน'),
  //                   const Text('• ปิดโหมดประหยัดแบตเตอรี่'),
  //                   const Text('• ตรวจสอบว่ามีไฟล์เสียงครบถ้วน'),
  //                 ],
  //               ],
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.pop(context);
  //                 // Test notification with different sounds
  //                 _notificationService.showTestNotification(
  //                   title: 'ทดสอบการแจ้งเตือน',
  //                   body: 'นี่คือการทดสอบระบบแจ้งเตือน',
  //                   sound: Platform.isIOS ? 'alarm' : 'alert',
  //                 );
  //               },
  //               child: const Text('ทดสอบแจ้งเตือน'),
  //             ),
  //             TextButton(
  //               onPressed: () => Navigator.pop(context),
  //               child: const Text('เข้าถึงแล้ว'),
  //             ),
  //           ],
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     debugPrint('Error running diagnostics: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('เกิดข้อผิดพลาด: $e'),
  //           backgroundColor: Color(0xFF121212),
  //         ),
  //       );
  //     }
  //   }
  // }

  void _toggleViewMode() async {
    setState(() {
      // Toggle between 24 hours and all
      _selectedDateFilter = (_selectedDateFilter == DateFilterOption.all) 
          ? DateFilterOption.thisWeek 
          : DateFilterOption.all;
    });
    
    // Save the preference
    _saveDateFilterPreference();
    
    // Refresh the data
    _loadEarthquakes();
  }

  @override
  Widget build(BuildContext context) {
    final earthquakeService = Provider.of<EarthquakeService>(context);
    List<Earthquake> filteredEarthquakes = earthquakeService.getFilteredEarthquakes();
    
    // Apply date filtering - replaces _viewOnly24Hours check
    filteredEarthquakes = _getDateFilteredEarthquakes(filteredEarthquakes, _selectedDateFilter);

    return Scaffold(
      backgroundColor: const Color(0xFF121212), // พื้นหลังสีดำ
      appBar: AppBar(
        title:  Text('ข้อมูลแผ่นดินไหวล่าสุด',
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        ),
        backgroundColor: const Color(0xFF121212), // เปลี่ยนเป็นสีดำเหมือนเดิม
        iconTheme: const IconThemeData(color: Colors.white),
        // ลบ actions ที่เกี่ยวกับการรีเฟรชและตั้งค่าออก
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF1E1E1E), // เพิ่มสีพื้นหลังเป็นสีดำเข้ม
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Color(0xFF121212), // สีดำเหมือนพื้นหลังหน้าหลัก
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'ไหวป่าว',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'ข้อมูลแผ่นดินไหวล่าสุด',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // ปุ่มไปหน้าแผนที่
            ListTile(
              leading: const Icon(Icons.map, color: Colors.white), // ไอคอนสีขาว
              title: const Text('แผนที่แผ่นดินไหว', style: TextStyle(color: Colors.white)), // ข้อความสีขาว
              onTap: () {
                Navigator.pop(context); // ปิด drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(
                      dataMode: _dataFetchMode,
                    ),
                  ),
                );
              },
            ),
            // ปุ่มวิเคราะห์ความเสี่ยงแผ่นดินไหว
            ListTile(
              leading: const Icon(Icons.analytics_outlined, color: Colors.white), // ไอคอนสีขาว
              title: const Text('วิเคราะห์ความเสี่ยงแผ่นดินไหว', style: TextStyle(color: Colors.white)), // ข้อความสีขาว
              onTap: () {
                Navigator.pop(context); // ปิด drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EarthquakeRiskScreen(),
                  ),
                );
              },
            ),
            const Divider(color: Colors.grey), // สีของเส้นกั้น
            // เลือกแหล่งข้อมูล
            ListTile(
              leading: const Icon(Icons.data_usage, color: Colors.white), // ไอคอนสีขาว
              title: const Text('พื้นที่', style: TextStyle(color: Colors.white)), // ข้อความสีขาว
              trailing: Container(
                width: 140, // จำกัดความกว้าง
                child: DropdownButton<DataFetchMode>(
                  isExpanded: true, // ทำให้ dropdown ขยายเต็มพื้นที่ container
                  dropdownColor: const Color(0xFF1E1E1E),
                  iconEnabledColor: Colors.white,
                  value: _dataFetchMode,
                  underline: Container(),
                  elevation: 16,
                  items: DataFetchMode.values.map<DropdownMenuItem<DataFetchMode>>((DataFetchMode value) {
                    String label;
                    switch (value) {
                      case DataFetchMode.global:
                        label = 'ทั่วโลก';
                        break;
                      case DataFetchMode.southeastAsia:
                        label = 'เอเชียตะวันออกเฉียงใต้';
                        break;
                      case DataFetchMode.thailandArea:
                        label = 'ประเทศไทย';
                        break;
                    }
                    return DropdownMenuItem<DataFetchMode>(
                      value: value,
                      child: Text(
                        label, 
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (DataFetchMode? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _dataFetchMode = newValue;
                        _saveDataFetchMode();
                      });
                      _loadEarthquakes(checkForNotifications: false);
                    }
                  },
                ),
              ),
            ),
            // เลือกรูปแบบแผนที่
            ListTile(
              leading: const Icon(Icons.layers, color: Colors.white), // ไอคอนสีขาว
              title: const Text('รูปแบบแผนที่', style: TextStyle(color: Colors.white)), // ข้อความสีขาว
              trailing: DropdownButton<String>(
                dropdownColor: const Color(0xFF1E1E1E), // สีพื้นหลังของเมนู dropdown
                iconEnabledColor: Colors.white, // สีไอคอน dropdown
                value: _mapType,
                underline: Container(),
                elevation: 16,
                items: <String>['normal', 'satellite', 'terrain', 'hybrid'].map<DropdownMenuItem<String>>((String value) {
                  String label;
                  switch (value) {
                    case 'normal':
                      label = 'ปกติ';
                      break;
                    case 'satellite':
                      label = 'ดาวเทียม';
                      break;
                    case 'terrain':
                      label = 'ภูมิประเทศ';
                      break;
                    case 'hybrid':
                      label = 'ผสม';
                      break;
                    default:
                      label = 'ปกติ';
                  }
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(label, style: const TextStyle(color: Colors.white)), // ข้อความในเมนู dropdown สีขาว
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _mapType = newValue;
                      _saveMapType();
                    });
                  }
                },
              ),
            ),
            // เพิ่มเมนูอื่นๆที่เดิมอยู่ใน PopupMenuButton ได้ตามต้องการ
            const Divider(color: Colors.grey), // สีของเส้นกั้น
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white), // ไอคอนสีขาว
              title: const Text('การตั้งค่าการแจ้งเตือน', style: TextStyle(color: Colors.white)), // ข้อความสีขาว
              onTap: () {
                Navigator.pop(context); // ปิด drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSettingsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // แผนที่ส่วนบน (ประมาณ 40% ของหน้าจอ)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.4,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: _defaultZoom,
                    minZoom: 3.0, // ระดับซูมออกน้อยสุด (ป้องกันซูมออกไกลเกินไปแล้วค้าง)
                    maxZoom: 18.0, // ระดับซูมเข้ามากสุด
                    onMapReady: () {
                      setState(() => _isMapLoaded = true);
                      _createMarkers();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _mapType == 'satellite' 
                         ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                         : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: ['a', 'b', 'c'],
                    ),
                    MarkerLayer(
                      markers: _markers.values.toList(),
                    ),
                  ],
                 ),
                // Add multiple map control buttons
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Current location button
                      FloatingActionButton(
                        mini: true,
                        onPressed: _moveToUserLocation,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue,
                        child: const Icon(Icons.my_location),
                        tooltip: 'ไปยังตำแหน่งปัจจุบัน',
                        heroTag: 'unique_home_map_location_fab',
                      ),
                      const SizedBox(height: 8),
                      // Zoom out to show all earthquakes
                      FloatingActionButton(
                        mini: true,
                        onPressed: _centerMapOnAllEarthquakes,
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green,
                        child: const Icon(Icons.zoom_out_map),
                        tooltip: 'แสดงแผ่นดินไหวทั้งหมด',
                        heroTag: 'unique_home_map_center_fab',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // แสดงสถานะการอัพเดทแต่ไม่มีปุ่มควบคุม
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: const Color(0xFF1A1A1A),
            child: Row(
              children: [
                if (_isLoading)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 12,
                    height: 12,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                    ),
                  ),
                if (_lastRefresh != null)
                  Expanded(
                    child: Text(
                      'อัพเดทล่าสุด: ${DateFormat('dd/MM HH:mm').format(_lastRefresh!)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),
          
          // รายการแผ่นดินไหวส่วนล่าง
          Expanded(
            // Wrap ListView with RefreshIndicator ให้คงอยู่เพื่อผู้ใช้สามารถดึงลงเพื่อรีเฟรชได้
            child: RefreshIndicator(
              onRefresh: () => _loadEarthquakes(checkForNotifications: false),
              color: Colors.orange,
              backgroundColor: const Color(0xFF1E1E1E),
              child: ListView.builder(
                itemCount: filteredEarthquakes.length,
                itemBuilder: (context, index) {
                  final quake = filteredEarthquakes[index];
                  return GestureDetector(
                    onTap: () {
                      // เมื่อกดรายการให้ซูมไปยังตำแหน่งบนแผนที่
                      _zoomToSelectedEarthquake(quake);
                    },
                    child: // รายการแผ่นดินไหวที่มีอยู่เดิม
                    _buildEarthquakeItem(quake)
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  // Update the filter options bottom sheet
  void _showFilterOptions(BuildContext context) {
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    
    // Create a temporary filter option to track changes
    DateFilterOption tempDateFilter = _selectedDateFilter;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Calculate counts for each date filter
            final allEarthquakes = earthquakeService.earthquakes;
            
            final todayCount = _getDateFilteredEarthquakes(
              allEarthquakes, DateFilterOption.today).length;
              
            final weekCount = _getDateFilteredEarthquakes(
              allEarthquakes, DateFilterOption.thisWeek).length;
              
            final monthCount = _getDateFilteredEarthquakes(
              allEarthquakes, DateFilterOption.thisMonth).length;
              
            final threeMonthsCount = _getDateFilteredEarthquakes(
              allEarthquakes, DateFilterOption.threeMonths).length;
            
            final allCount = allEarthquakes.length;
            
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16.0),
                        child: ListView(
                          controller: scrollController,
                          children: [
                            // Header
                            const Text(
                              'กรองข้อมูลแผ่นดินไหว',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Divider(),
                            
                            // Date filter options
                            const Text(
                              'ช่วงเวลา:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            
                            const SizedBox(height: 8),
                            
                            // Date range options with better styling
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey.shade100,
                              ),
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                children: [
                                  RadioListTile<DateFilterOption>(
                                    title: Row(
                                      children: [
                                        const Icon(Icons.today, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('วันนี้'),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('$todayCount รายการ', 
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: const Text('แสดงเฉพาะแผ่นดินไหววันนี้'),
                                    value: DateFilterOption.today,
                                    groupValue: tempDateFilter,
                                    onChanged: (value) {
                                      setState(() {
                                        tempDateFilter = value!;
                                      });
                                    },
                                  ),
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                  RadioListTile<DateFilterOption>(
                                    title: Row(
                                      children: [
                                        const Icon(Icons.view_week, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('สัปดาห์นี้'),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('$weekCount รายการ', 
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: const Text('แสดงแผ่นดินไหวในสัปดาห์นี้'),
                                    value: DateFilterOption.thisWeek,
                                    groupValue: tempDateFilter,
                                    onChanged: (value) {
                                      setState(() {
                                        tempDateFilter = value!;
                                      });
                                    },
                                  ),
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                  RadioListTile<DateFilterOption>(
                                    title: Row(
                                      children: [
                                        const Icon(Icons.calendar_month, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('เดือนนี้'),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('$monthCount รายการ', 
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: const Text('แสดงแผ่นดินไหวในเดือนนี้'),
                                    value: DateFilterOption.thisMonth,
                                    groupValue: tempDateFilter,
                                    onChanged: (value) {
                                      setState(() {
                                        tempDateFilter = value!;
                                      });
                                    },
                                  ),
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                  RadioListTile<DateFilterOption>(
                                    title: Row(
                                      children: [
                                        const Icon(Icons.calendar_view_month, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('3 เดือนที่ผ่านมา'),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('$threeMonthsCount รายการ', 
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: const Text('แสดงแผ่นดินไหวย้อนหลัง 3 เดือน'),
                                    value: DateFilterOption.threeMonths,
                                    groupValue: tempDateFilter,
                                    onChanged: (value) {
                                      setState(() {
                                        tempDateFilter = value!;
                                      });
                                    },
                                  ),
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                  RadioListTile<DateFilterOption>(
                                    title: Row(
                                      children: [
                                        const Icon(Icons.all_inclusive, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('ทั้งหมด'),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text('$allCount รายการ', 
                                            style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: const Text('แสดงข้อมูลทั้งหมดที่มี'),
                                    value: DateFilterOption.all,
                                    groupValue: tempDateFilter,
                                    onChanged: (value) {
                                      setState(() {
                                        tempDateFilter = value!;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Bottom action buttons
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('ยกเลิก'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                this.setState(() {
                                  _selectedDateFilter = tempDateFilter;
                                  _saveDateFilterPreference();
                                });
                                Navigator.pop(context);
                              },
                              
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('นำไปใช้'),
                              
                            ),
                            
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    ).then((_) {
      // Refresh the data when the bottom sheet is closed
      _loadEarthquakes(checkForNotifications: false);
    });
  }

  Widget _buildEarthquakeItem(Earthquake quake) {
    // คำนวณสีตามขนาดแผ่นดินไหว
    Color magnitudeColor;
    if (quake.magnitude < 4.0) {
      magnitudeColor = Colors.green;
    } else if (quake.magnitude < 5.0) {
      magnitudeColor = const Color(0xFF8BC34A); // สีเขียวอ่อน
    } else if (quake.magnitude < 6.0) {
      magnitudeColor = const Color(0xFFFFD700); // สีเหลือง
    } else if (quake.magnitude < 7.0) {
      magnitudeColor = const Color(0xFFFFA500); // สีส้ม
    } else {
      magnitudeColor = const Color(0xFFFF4500); // สีแดง
    }

    // ระยะเวลาที่ผ่านมา
    final timeAgo = DateTime.now().difference(quake.time);
    String timeAgoText;
    if (timeAgo.inMinutes < 60) {
      timeAgoText = '${timeAgo.inMinutes} นาทีที่แล้ว';
    } else if (timeAgo.inHours < 24) {
      timeAgoText = '${timeAgo.inHours} ชั่วโมงที่แล้ว';
    } else {
      timeAgoText = '${timeAgo.inDays} วันที่แล้ว';
    }

    // คำนวณระยะห่างจากตำแหน่งผู้ใช้
    String distanceText = 'ไม่ทราบระยะห่าง';
    if (_currentUserLocation != null && 
        _currentUserLocation!.latitude != null && 
        _currentUserLocation!.longitude != null) {
      final distance = _calculateDistance(
        _currentUserLocation!.latitude!,
        _currentUserLocation!.longitude!,
        quake.latitude,
        quake.longitude,
      );
      distanceText = 'ห่าง ${distance.toStringAsFixed(0)} กม.';
    }

    // สร้างการ์ดในรูปแบบใหม่
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E), // สีพื้นหลังการ์ดเข้มกว่าพื้นหลังหลัก
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _zoomToSelectedEarthquake(quake),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ขนาดแผ่นดินไหว
              SizedBox(
                width: 70,
                child: Column(
                  children: [
                    Text(
                      quake.magnitude.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: magnitudeColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('HH:mm').format(quake.time),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Text(
                      DateFormat('dd MMM yy').format(quake.time),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              // เส้นแบ่ง
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                width: 1,
                height: 100,
                color: Colors.grey.shade800,
              ),
              // รายละเอียด
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          timeAgoText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // เพิ่มธงชาติตรงนี้
                            CountryHelper.buildCountryFlag(
                              quake.location,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            if (DateTime.now().difference(quake.time).inHours <
                                1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      quake.location,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${quake.latitude.toStringAsFixed(4)}° N, ${quake.longitude.toStringAsFixed(4)}° E',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // แก้ไขส่วนนี้ให้แสดงระยะห่างจากตำแหน่งผู้ใช้จริง
                    Wrap(
                      spacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_downward,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'ความลึก: ${quake.depth.toStringAsFixed(1)} กม.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.place, color: Colors.red, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              distanceText,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEarthquakeDetails(Earthquake quake) {
    final magnitudeColor = _getMagnitudeColor(quake.magnitude);

    // คำนวณระยะห่างจากตำแหน่งผู้ใช้
    String distanceInfo = 'ไม่ทราบระยะห่าง';
    if (_currentUserLocation != null && 
        _currentUserLocation!.latitude != null && 
        _currentUserLocation!.longitude != null) {
      final distance = _calculateDistance(
        _currentUserLocation!.latitude!,
        _currentUserLocation!.longitude!,
        quake.latitude,
        quake.longitude,
      );
      distanceInfo = '${distance.toStringAsFixed(1)} กม.';
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
                    color: magnitudeColor.withOpacity(0.2),
                  ),
                  child: Center(
                    child: Text(
                      quake.magnitude.toStringAsFixed(1),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: magnitudeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'รายละเอียดแผ่นดินไหว',
                          style: TextStyle(color: Colors.grey[200]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      CountryHelper.buildCountryFlag(quake.location, size: 24),
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
                  _buildInfoRow('ระยะห่างจากคุณ:', distanceInfo),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontWeight: FontWeight.bold,
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

  Color _getMagnitudeColor(double magnitude) {
    if (magnitude < 3.0) {
      return Colors.green;
    } else if (magnitude < 4.5) {
      return Colors.orange;
    } else if (magnitude < 6.0) {
      return Colors.deepOrange;
    } else {
      return Colors.red;
    }
  }

  void _showRegionSelector(BuildContext context) {
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.3,
              maxChildSize: 0.7,
              expand: false,
              builder: (_, scrollController) {
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      const Text(
                        'เลือกภูมิภาค',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      
                      // Region selector
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: CountryHelper.seaRegions.length,
                          itemBuilder: (context, index) {
                            final region = CountryHelper.seaRegions[index];
                            return ListTile(
                              title: Text(region.name),
                              subtitle: Text(
                                region.description,
                                style: const TextStyle(fontSize: 12),
                              ),
                              leading: const Icon(Icons.public),
                              trailing: _selectedRegionCode == region.code
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : null,
                              onTap: () {
                                // Update both the local state and service
                                this.setState(() {
                                  _selectedRegionCode = region.code;
                                });
                                earthquakeService.setSelectedRegion(region.code);
                                debugPrint('Selected region: ${region.name} (${region.code})');
                                debugPrint('Current _selectedRegionCode value: $_selectedRegionCode');
                                
                                // Force a refresh of the earthquake list
                                _loadEarthquakes(checkForNotifications: false);
                                
                                Navigator.pop(context);
                              },
                            );
                          },
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

  // Add method to save date filter preference
  Future<void> _saveDateFilterPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selectedDateFilter', _selectedDateFilter.toString());
  }

  // Add method to get filtered earthquakes by date range
  List<Earthquake> _getDateFilteredEarthquakes(List<Earthquake> earthquakes, DateFilterOption filter) {
    switch (filter) {
      case DateFilterOption.today:
        final startDate = DateHelper.getStartOfToday();
        return earthquakes.where((quake) => quake.time.isAfter(startDate)).toList();
      
      case DateFilterOption.thisWeek:
        final startDate = DateHelper.getStartOfWeek();
        return earthquakes.where((quake) => quake.time.isAfter(startDate)).toList();
      
      case DateFilterOption.thisMonth:
        final startDate = DateHelper.getStartOfMonth();
        return earthquakes.where((quake) => quake.time.isAfter(startDate)).toList();
      
      case DateFilterOption.threeMonths:
        final startDate = DateHelper.getStartOfThreeMonthsAgo();
        return earthquakes.where((quake) => quake.time.isAfter(startDate)).toList();
      
      case DateFilterOption.all:
      default:
        return earthquakes;
    }
  }

  // Add a new method to display the current date filter as text
  String _getDateFilterText() {
    switch (_selectedDateFilter) {
      case DateFilterOption.today:
        return 'วันนี้';
      case DateFilterOption.thisWeek:
        return 'สัปดาห์นี้';
      case DateFilterOption.thisMonth:
        return 'เดือนนี้';
      case DateFilterOption.threeMonths:
        return '3 เดือนที่ผ่านมา';
      case DateFilterOption.all:
        return 'ทั้งหมด';
    }
  }

  // Method to toggle the date filter - will be called when user taps on date filter in the UI
  void _toggleDateFilter(DateFilterOption newFilter) {
    setState(() {
      _selectedDateFilter = newFilter;
      _saveDateFilterPreference();
    });
    // Refresh data
    _loadEarthquakes(checkForNotifications: false);
  }

  // บันทึกโหมดการดึงข้อมูล
  Future<void> _saveDataFetchMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('dataFetchMode', _dataFetchMode.toString());
    debugPrint('Saved data fetch mode: $_dataFetchMode');
  }
  
  // เพิ่มแสดงชื่อแหล่งข้อมูลที่เลือก
  String _getDataSourceName() {
    switch (_dataFetchMode) {
      case DataFetchMode.global:
        return 'ทั่วโลก';
      case DataFetchMode.southeastAsia:
        return 'เอเชียตะวันออกเฉียงใต้';
      case DataFetchMode.thailandArea:
        return 'ประเทศไทย';
    }
  }
  
  // แสดงเมนูเลือกโหลดข้อมูล
  void _showDataSourceMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เลือกแหล่งข้อมูล'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('เอเชียตะวันออกเฉียงใต้'),
              subtitle: const Text('ข้อมูลแผ่นดินไหวในภูมิภาคเอเชียตะวันออกเฉียงใต้'),
              leading: Radio<DataFetchMode>(
                value: DataFetchMode.southeastAsia,
                groupValue: _dataFetchMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _dataFetchMode = value!;
                    _saveDataFetchMode();
                  });
                  _loadEarthquakes();
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _dataFetchMode = DataFetchMode.southeastAsia;
                  _saveDataFetchMode();
                });
                _loadEarthquakes();
              },
            ),
            ListTile(
              title: const Text('ประเทศไทย'),
              subtitle: const Text('เฉพาะไทย ลาว กัมพูชา พม่า และมาเลเซียตอนเหนือ'),
              leading: Radio<DataFetchMode>(
                value: DataFetchMode.thailandArea,
                groupValue: _dataFetchMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _dataFetchMode = value!;
                    _saveDataFetchMode();
                  });
                  _loadEarthquakes();
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _dataFetchMode = DataFetchMode.thailandArea;
                  _saveDataFetchMode();
                });
                _loadEarthquakes();
              },
            ),
            ListTile(
              title: const Text('ทั่วโลก'),
              subtitle: const Text('ข้อมูลแผ่นดินไหวทั่วโลก (จะมีข้อมูลมากกว่า)'),
              leading: Radio<DataFetchMode>(
                value: DataFetchMode.global,
                groupValue: _dataFetchMode,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _dataFetchMode = value!;
                    _saveDataFetchMode();
                  });
                  _loadEarthquakes();
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _dataFetchMode = DataFetchMode.global;
                  _saveDataFetchMode();
                });
                _loadEarthquakes();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  // Create map markers for earthquakes
  void _createMarkers() {
    if (!_isMapLoaded) return;
    
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    final List<Earthquake> displayedEarthquakes = _getFilteredEarthquakes(earthquakeService.earthquakes);
    
    setState(() {
      _markers.clear();
      
      for (final quake in displayedEarthquakes) {
        // Skip invalid coordinates
        if (quake.latitude == 0 && quake.longitude == 0) continue;
        
        final marker = Marker(
          width: 40.0,
          height: 40.0,
          point: LatLng(quake.latitude, quake.longitude),
          child: GestureDetector(
            onTap: () {
              _showQuakeDetails(quake);
            },
            child: _getMarkerIcon(quake.magnitude),
          ),
        );
        
        _markers[quake.id] = marker;
      }
    });
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
  
  // ฟังก์ชันซูมไปยังแผ่นดินไหวที่เลือก
  void _zoomToSelectedEarthquake(Earthquake quake) {
    if (quake.latitude == 0 && quake.longitude == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถแสดงตำแหน่งแผ่นดินไหวได้เนื่องจากข้อมูลพิกัดไม่ถูกต้อง'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // ซูมไปยังตำแหน่งแผ่นดินไหว
    _mapController.move(LatLng(quake.latitude, quake.longitude), 10.0);
  }
  
  // เพิ่มฟังก์ชันศูนย์กลางแผนที่เพื่อแสดงแผ่นดินไหวทั้งหมด
  void _centerMapOnAllEarthquakes() {
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

  // บันทึกชนิดของแผนที่
  Future<void> _saveMapType() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mapType', _mapType);
    debugPrint('Saved map type: $_mapType');
  }
  
  // แสดงเมนูเลือกชนิดของแผนที่
  void _showMapTypeMenu(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เลือกรูปแบบแผนที่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('แผนที่ปกติ'),
              leading: Radio<String>(
                value: 'normal',
                groupValue: _mapType,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _mapType = value!;
                    _saveMapType();
                  });
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _mapType = 'normal';
                  _saveMapType();
                });
              },
            ),
            ListTile(
              title: const Text('ดาวเทียม'),
              leading: Radio<String>(
                value: 'satellite',
                groupValue: _mapType,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _mapType = value!;
                    _saveMapType();
                  });
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _mapType = 'satellite';
                  _saveMapType();
                });
              },
            ),
            ListTile(
              title: const Text('ภูมิประเทศ'),
              leading: Radio<String>(
                value: 'terrain',
                groupValue: _mapType,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _mapType = value!;
                    _saveMapType();
                  });
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _mapType = 'terrain';
                  _saveMapType();
                });
              },
            ),
            ListTile(
              title: const Text('ผสม'),
              leading: Radio<String>(
                value: 'hybrid',
                groupValue: _mapType,
                onChanged: (value) {
                  Navigator.pop(context);
                  setState(() {
                    _mapType = value!;
                    _saveMapType();
                  });
                },
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _mapType = 'hybrid';
                  _saveMapType();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
  }

  // Add location permission check
  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // Check if location services are enabled
    serviceEnabled = await _locationService.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _locationService.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    // Check if location permission is granted
    permissionGranted = await _locationService.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _locationService.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }

  // Function to show current user location
  Future<void> _moveToUserLocation() async {
    try {
      final locationData = await _locationService.getLocation();
      
      if (locationData.latitude == null || locationData.longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถระบุตำแหน่งของคุณได้'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      // Move map to user location
      _mapController.move(
        LatLng(locationData.latitude!, locationData.longitude!),
        14.0,
      );
      
      // Create marker for user location
      setState(() {
        _markers['current_location'] = Marker(
          width: 40.0,
          height: 40.0,
          point: LatLng(locationData.latitude!, locationData.longitude!),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.8),
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
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถระบุตำแหน่งของคุณได้: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Get filtered earthquakes based on current settings
  List<Earthquake> _getFilteredEarthquakes(List<Earthquake> earthquakes) {
    // Apply date filter
    DateTime? startDate;
    final now = DateTime.now();
    
    switch (_selectedDateFilter) {
      case DateFilterOption.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case DateFilterOption.thisWeek:
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        break;
      case DateFilterOption.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case DateFilterOption.threeMonths:
        startDate = DateTime(now.year, now.month - 3, now.day);
        break;
      case DateFilterOption.all:
        startDate = null;
        break;
    }
    
    // Apply region filter
    return earthquakes.where((quake) {
      // Apply date filter if set
      if (startDate != null && quake.time.isBefore(startDate)) {
        return false;
      }
      
      // Apply region filter if set
      if (_selectedRegionCode != null && _selectedRegionCode != 'all') {
        if (_selectedRegionCode == 'thailand') {
          return _isInThailand(quake.latitude, quake.longitude);
        } else if (_selectedRegionCode == 'southeast_asia') {
          return _isInSoutheastAsia(quake.latitude, quake.longitude);
        }
      }
      
      return true;
    }).toList();
  }
  
  // Helper method to check if coordinates are in Thailand
  bool _isInThailand(double lat, double lng) {
    // Thailand rough bounding box
    return lat >= 5.5 && lat <= 20.5 && lng >= 97.3 && lng <= 105.6;
  }
  
  // Helper method to check if coordinates are in Southeast Asia
  bool _isInSoutheastAsia(double lat, double lng) {
    // Southeast Asia rough bounding box
    return lat >= -11.0 && lat <= 29.0 && lng >= 92.0 && lng <= 141.0;
  }
  
  // Show earthquake details
  void _showQuakeDetails(Earthquake quake) {
    // คำนวณระยะห่างจากตำแหน่งผู้ใช้
    String distanceInfo = 'ไม่ทราบระยะห่าง';
    if (_currentUserLocation != null && 
        _currentUserLocation!.latitude != null && 
        _currentUserLocation!.longitude != null) {
      final distance = _calculateDistance(
        _currentUserLocation!.latitude!,
        _currentUserLocation!.longitude!,
        quake.latitude,
        quake.longitude,
      );
      distanceInfo = '${distance.toStringAsFixed(1)} กม.';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          'แผ่นดินไหว ${quake.magnitude}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('สถานที่:', quake.location),
              _buildInfoRow('เวลา:', DateFormat('dd/MM/yyyy HH:mm:ss').format(quake.time)),
              _buildInfoRow('ความลึก:', '${quake.depth} กม.'),
              _buildInfoRow('ระยะห่างจากคุณ:', distanceInfo),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // นำทางไปยังหน้าแผนที่พร้อมแสดงเฉพาะแผ่นดินไหวที่เลือก
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MapScreen(
                    dataMode: DataFetchMode.values.byName(_dataFetchMode.name),
                    selectedEarthquake: quake,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.map),
            label: const Text('แสดงในแผนที่'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Add a new function to handle notifications more carefully
  Future<void> _checkForNewEarthquakesAndNotify(List<Earthquake> earthquakes) async {
    debugPrint('เช็คข้อมูลแผ่นดินไหวใหม่ (ไม่มีการแจ้งเตือน)');
    
    // ไม่ส่งการแจ้งเตือนในทุกกรณี
    // แจ้งเตือนจะมาจาก FCM เท่านั้น
    
    // Filter earthquakes to only those in the last 15 minutes
    final recentEarthquakes = earthquakes.where(
      (quake) => DateTime.now().difference(quake.time).inMinutes <= 15
    ).toList();
    
    if (recentEarthquakes.isNotEmpty) {
      debugPrint('พบ ${recentEarthquakes.length} แผ่นดินไหวในช่วง 15 นาทีที่ผ่านมา (ไม่ส่งการแจ้งเตือน)');
    } else {
      debugPrint('ไม่พบแผ่นดินไหวใหม่ในช่วง 15 นาทีที่ผ่านมา');
    }
  }

  // เพิ่มฟังก์ชันดึงตำแหน่งผู้ใช้
  Future<void> _getCurrentLocation() async {
    try {
      final locationData = await _locationService.getLocation();
      setState(() {
        _currentUserLocation = locationData;
      });
      debugPrint('User location: ${locationData.latitude}, ${locationData.longitude}');
    } catch (e) {
      debugPrint('Error getting user location: $e');
    }
  }

  // เพิ่มฟังก์ชันคำนวณระยะห่างโดยใช้ Haversine formula
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
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
                FlutterClipboard.copy('$latitude, $longitude').then((_) {
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
}