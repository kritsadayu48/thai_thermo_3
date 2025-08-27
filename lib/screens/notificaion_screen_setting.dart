// lib/screens/notification_settings.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:location/location.dart';
import '../services/notification_service.dart';
import '../services/fcm_service.dart';
import '../services/api_service.dart';
import '../services/earthquake_service.dart';
import '../main.dart';
import '../enums/sound_setting.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  // ตัวแปรสำหรับเก็บการตั้งค่า
  bool _isNotificationEnabled = true;
  bool _notifyAllMagnitudes = true;
  double _minNotifyMagnitude = 0.1;
  bool _isCriticalAlertEnabled = true;
  double _criticalMagnitudeThreshold = 5.4;
  int _checkIntervalMinutes = 60; // นาที
  
  // ปิดการใช้งานการตั้งค่าเสียงแจ้งเตือน
  /*
  bool _useCustomSounds = true;
  String _regularSound = 'beep';
  String _criticalSound = 'critical_alert';
  */
  
  bool _isLoading = false;
  
  // เพิ่มตัวแปรสำหรับการตั้งค่า API server
  bool _isServerRegionFilterEnabled = true;
  String _selectedServerRegion = 'sea'; // ค่าเริ่มต้น: เอเชียตะวันออกเฉียงใต้
  bool _isServerMagnitudeFilterEnabled = true;
  double _serverMinMagnitude = 2.0; // ค่าเริ่มต้น

  // เพิ่มตัวแปรสำหรับการตั้งค่าการกรองตามระยะทาง
  bool _isDistanceFilterEnabled = false;
  double _maxDistanceKm = 2000.0; // ค่าคงที่ 2000 กม.
  double? _userLatitude;
  double? _userLongitude;
  bool _isLocationPermissionGranted = false;
  
  // ตัวเลือกสำหรับภูมิภาคใน API server
  final List<Map<String, dynamic>> _availableServerRegions = [
    {'id': 'all', 'name': 'ทั้งหมด (ทั่วโลก)'},
    {'id': 'sea', 'name': 'เอเชียตะวันออกเฉียงใต้'},
    {'id': 'th', 'name': 'ประเทศไทย'},
    {'id': 'jp', 'name': 'ญี่ปุ่น'},
    {'id': 'cn', 'name': 'จีน'},
    {'id': 'ph', 'name': 'ฟิลิปปินส์'},
    {'id': 'id', 'name': 'อินโดนีเซีย'},
    {'id': 'mm', 'name': 'พม่า (เมียนมาร์)'},
  ];
  
  // Service สำหรับการส่งการแจ้งเตือน
  final NotificationService _notificationService = NotificationService();
  
  // ปิดการใช้งานตัวเลือกเสียงแจ้งเตือน
  /*
  // Available sound options
  final List<Map<String, dynamic>> _availableRegularSounds = [
    {'id': 'default', 'name': 'มาตรฐาน'},
    {'id': 'alert', 'name': 'เตือนภัย'},
    {'id': 'beep', 'name': 'เสียงบี๊บ'},
    {'id': 'chime', 'name': 'เสียงระฆัง'},
    {'id': 'soft', 'name': 'เสียงนุ่ม'},
  ];
  
  final List<Map<String, dynamic>> _availableCriticalSounds = [
    {'id': 'critical_alert', 'name': 'เตือนภัยฉุกเฉิน'},
    {'id': 'siren', 'name': 'ไซเรน'},
    {'id': 'alarm', 'name': 'นาฬิกาปลุก'},
    {'id': 'warning', 'name': 'เตือนภัยรุนแรง'},
  ];
  */
  
  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _loadServerSettings();
  }

  // โหลดการตั้งค่าปัจจุบัน
  void _loadCurrentSettings() {
    final earthquakeService = Provider.of<EarthquakeService>(
      context,
      listen: false,
    );
    setState(() {
      _notifyAllMagnitudes = earthquakeService.notifyAllMagnitudes;
      _minNotifyMagnitude = earthquakeService.minNotifyMagnitude;
      _isNotificationEnabled = earthquakeService.isNotificationEnabled;
      _checkIntervalMinutes = earthquakeService.checkIntervalMinutes;
      _isCriticalAlertEnabled = earthquakeService.isCriticalAlertEnabled;
      _criticalMagnitudeThreshold = earthquakeService.criticalMagnitudeThreshold;
      
      // Load sound settings
      /*
      _regularSound = earthquakeService.regularSound;
      _criticalSound = earthquakeService.criticalSound;
      _useCustomSounds = earthquakeService.useCustomSounds;
      */
    });
  }

  // บันทึกการตั้งค่า
  void _saveSettings() {
    final earthquakeService = Provider.of<EarthquakeService>(
      context,
      listen: false,
    );
    earthquakeService.setNotifyAllMagnitudes(_notifyAllMagnitudes);
    earthquakeService.setMinNotifyMagnitude(_minNotifyMagnitude);
    earthquakeService.setNotificationEnabled(_isNotificationEnabled);
    earthquakeService.setCheckInterval(_checkIntervalMinutes);
    earthquakeService.setCriticalAlertEnabled(_isCriticalAlertEnabled);
    earthquakeService.setCriticalMagnitudeThreshold(_criticalMagnitudeThreshold);
    
    // Save sound settings
    /*
    earthquakeService.setUseCustomSounds(_useCustomSounds);
    earthquakeService.setRegularSound(_regularSound);
    earthquakeService.setCriticalSound(_criticalSound);
    */

    // แสดงข้อความยืนยัน
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บันทึกการตั้งค่าเรียบร้อยแล้ว'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ทดสอบการแจ้งเตือน
  Future<void> _testNotification() async {
    try {
      final fcmService = FCMService();
      await fcmService.sendTestNotification();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งการแจ้งเตือนทดสอบแล้ว'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการส่งการแจ้งเตือน: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }
  
  // ทดสอบการแจ้งเตือนฉุกเฉิน
  Future<void> _testCriticalNotification() async {
    try {
      await _notificationService.showEarthquakeNotification(
        title: 'ทดสอบแจ้งเตือนฉุกเฉิน',
        body: 'นี่คือการทดสอบการแจ้งเตือนแผ่นดินไหวฉุกเฉิน (${DateTime.now().toString()})',
        sound: 'default',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ส่งการแจ้งเตือนฉุกเฉินทดสอบแล้ว'),
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

  // ตรวจสอบการตั้งค่าการแจ้งเตือน
  Future<void> _checkNotificationPermissions() async {
    final hasPermission = await _notificationService.checkPermissions();

    if (hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('แอพมีสิทธิ์ในการแจ้งเตือนแล้ว'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // แสดงกล่องโต้ตอบเพื่อขอสิทธิ์
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('ต้องการสิทธิ์การแจ้งเตือน'),
              content: const Text(
                'แอพจำเป็นต้องได้รับสิทธิ์เพื่อส่งการแจ้งเตือนแผ่นดินไหว คุณต้องการเปิดการตั้งค่าเพื่ออนุญาตหรือไม่?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // เปิดการตั้งค่าของแอพ
                    _notificationService.openAppSettings();
                  },
                  child: const Text('ไปที่การตั้งค่า'),
                ),
              ],
            ),
      );
    }
  }

  // บังคับรีเฟรชข้อมูลแผ่นดินไหวล่าสุด
  Future<void> _forceCheckNow() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กำลังรีเฟรชข้อมูลแผ่นดินไหวล่าสุด...'),
          duration: Duration(seconds: 2),
        ),
      );

      final earthquakeService = Provider.of<EarthquakeService>(
        context,
        listen: false,
      );
      await earthquakeService.forceCheckImmediate();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('รีเฟรชข้อมูลแผ่นดินไหวล่าสุดเรียบร้อยแล้ว'),
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

  // ตรวจสอบไฟล์เสียงแจ้งเตือน
  Future<void> _runSoundDiagnostics() async {
    try {
      // แสดง dialog บอกว่ากำลังตรวจสอบ
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          title: Text('กำลังตรวจสอบไฟล์เสียง'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('กรุณารอสักครู่...'),
            ],
          ),
        ),
      );
      
      // ตรวจสอบไฟล์เสียง
      final results = await _notificationService.checkSoundFilesConfiguration();
      
      // ปิด dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // แสดงผลการตรวจสอบ
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ผลการตรวจสอบไฟล์เสียง'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('การทดสอบเสียงเสร็จสิ้น: ${results['testSent'] == true ? "✓" : "✗"}'),
                  const SizedBox(height: 8),
                  const Text('คำแนะนำในการแก้ไขปัญหาเสียงแจ้งเตือนบน iOS:'),
                  const SizedBox(height: 8),
                  const Text('• ตรวจสอบว่าเสียงของอุปกรณ์เปิดอยู่'),
                  const Text('• ตรวจสอบว่าโหมดเงียบไม่ได้เปิดอยู่'),
                  const Text('• ตรวจสอบว่าโหมด Focus ไม่ได้เปิดอยู่'),
                  const Text('• ตรวจสอบการตั้งค่าแจ้งเตือนของแอพในการตั้งค่าของ iOS'),
                  if (results['error'] != null) ...[
                    const SizedBox(height: 8),
                    Text('ข้อผิดพลาด: ${results['error']}', 
                      style: const TextStyle(color: Colors.red)
                    ),
                  ],
                ],
              ),
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
    } catch (e) {
      // ปิด dialog หากยังเปิดอยู่
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      // แสดงข้อผิดพลาด
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการตรวจสอบ: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // โหลดการตั้งค่าเซิร์ฟเวอร์
  Future<void> _loadServerSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // โหลดการตั้งค่าจาก SharedPreferences ก่อน (ไม่ต้องรอเซิร์ฟเวอร์)
      final serverRegion = await ApiService.getSelectedRegion();
      final regionFilterEnabled = await ApiService.getRegionFilterEnabled();
      final minMagnitude = await ApiService.getMinMagnitude();
      final magnitudeFilterEnabled = await ApiService.getMagnitudeFilterEnabled();
      
      // โหลดการตั้งค่าการกรองตามระยะทาง
      final locationFilterSettings = await ApiService.getLocationFilterSettings();
      
      // ตั้งค่าเริ่มต้นจาก SharedPreferences ก่อน
      setState(() {
        _selectedServerRegion = serverRegion ?? 'sea';
        _isServerRegionFilterEnabled = regionFilterEnabled;
        _serverMinMagnitude = minMagnitude ?? 2.0;
        _isServerMagnitudeFilterEnabled = magnitudeFilterEnabled;
        
        // โหลดการตั้งค่าการกรองตามระยะทาง
        _isDistanceFilterEnabled = locationFilterSettings['distanceFilterEnabled'] ?? false;
        _maxDistanceKm = locationFilterSettings['maxDistanceKm'] ?? 2000.0;
        _userLatitude = locationFilterSettings['userLatitude'];
        _userLongitude = locationFilterSettings['userLongitude'];
        
        _isLoading = false; // ปิด loading หลังจากโหลดจาก SharedPreferences เสร็จ
      });
      
      // ตรวจสอบสิทธิ์ location (ไม่บล็อก UI)
      _checkLocationPermission().catchError((e) {
        debugPrint('Error checking location permission: $e');
      });
      
      // ดึงการตั้งค่าจากเซิร์ฟเวอร์ในพื้นหลัง (ไม่บล็อก UI)
      _loadServerSettingsFromAPI().catchError((e) {
        debugPrint('Error loading server settings from API: $e');
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading server settings: $e');
    }
  }
  
  // โหลดการตั้งค่าจากเซิร์ฟเวอร์ในพื้นหลัง
  Future<void> _loadServerSettingsFromAPI() async {
    try {
      // ดึงการตั้งค่าปัจจุบันจากเซิร์ฟเวอร์ด้วย timeout
      final settings = await ApiService.getSettings().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ Server settings request timed out after 10 seconds');
          return null;
        },
      );
      
      // อัปเดตค่าจากการตั้งค่าเซิร์ฟเวอร์ (ถ้ามี) แต่ไม่รวมการตั้งค่าการกรองตามระยะทาง
      if (settings != null && settings['settings'] != null && mounted) {
        final serverSettings = settings['settings'];
        setState(() {
          _isServerRegionFilterEnabled = serverSettings['filterByRegion'] ?? _isServerRegionFilterEnabled;
          _selectedServerRegion = serverSettings['defaultRegion'] ?? _selectedServerRegion;
          _isServerMagnitudeFilterEnabled = serverSettings['filterByMagnitude'] ?? _isServerMagnitudeFilterEnabled;
          _serverMinMagnitude = serverSettings['minMagnitude']?.toDouble() ?? _serverMinMagnitude;
          
          // ไม่อัปเดตการตั้งค่าการกรองตามระยะทางจากเซิร์ฟเวอร์
          // เพื่อป้องกันการเขียนทับค่าที่ผู้ใช้ตั้งไว้ใน SharedPreferences
          // การตั้งค่าการกรองตามระยะทางจะใช้ค่าจาก SharedPreferences เป็นหลัก
        });
        debugPrint('✅ Server settings loaded successfully (excluding distance filter settings)');
      } else {
        debugPrint('⚠️ No server settings received or widget unmounted');
      }
    } catch (e) {
      debugPrint('❌ Error loading server settings from API: $e');
      // ไม่ต้องแสดง error ให้ผู้ใช้เห็น เพราะอาจจะเป็นปัญหาเครือข่าย
    }
  }

  // บันทึกการตั้งค่าเซิร์ฟเวอร์
  Future<void> _saveServerSettings() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // เรียกใช้ API เพื่อบันทึกการตั้งค่า
      await ApiService.setRegion(_selectedServerRegion);
      await ApiService.toggleRegionFilter(_isServerRegionFilterEnabled);
      await ApiService.setMinMagnitude(_serverMinMagnitude);
      await ApiService.toggleMagnitudeFilter(_isServerMagnitudeFilterEnabled);
      
      // บันทึกการตั้งค่าการกรองตามระยะทางทุกครั้ง (ไม่ว่าจะเปิดหรือปิด)
      if (_userLatitude != null && _userLongitude != null) {
        await ApiService.setLocationFilter(
          latitude: _userLatitude!,
          longitude: _userLongitude!,
          maxDistanceKm: _maxDistanceKm,
          enabled: _isDistanceFilterEnabled,
        );
      }
      
      setState(() {
        _isLoading = false;
      });
      
      // แสดงข้อความยืนยัน
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกการตั้งค่าเซิร์ฟเวอร์เรียบร้อยแล้ว'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการบันทึกการตั้งค่าเซิร์ฟเวอร์: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  // รีเซ็ตประวัติการแจ้งเตือนบนเซิร์ฟเวอร์
  Future<void> _resetServerNotifications() async {
    try {
      // แสดงกล่องโต้ตอบเพื่อยืนยันการรีเซ็ต
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('รีเซ็ตประวัติการแจ้งเตือน'),
          content: const Text(
            'การรีเซ็ตประวัติจะทำให้ระบบส่งการแจ้งเตือนซ้ำสำหรับแผ่นดินไหวที่เคยเกิดขึ้น ต้องการดำเนินการต่อหรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('รีเซ็ต'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
      
      setState(() {
        _isLoading = true;
      });
      
      final result = await ApiService.resetNotifications();
      
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result 
            ? 'รีเซ็ตประวัติการแจ้งเตือนเรียบร้อยแล้ว' 
            : 'ไม่สามารถรีเซ็ตประวัติการแจ้งเตือนได้'),
          backgroundColor: result ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  // รีเซ็ตการลงทะเบียน FCM token
  Future<void> _resetTokenRegistration() async {
    try {
      // แสดงกล่องโต้ตอบเพื่อยืนยันการรีเซ็ต
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('รีเซ็ตการลงทะเบียน Token'),
          content: const Text(
            'การรีเซ็ตจะลบข้อมูลการลงทะเบียนการแจ้งเตือนปัจจุบันและลงทะเบียนใหม่ ควรใช้ตัวเลือกนี้เมื่อเกิดปัญหาไม่ได้รับการแจ้งเตือน\n\nต้องการดำเนินการต่อหรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('รีเซ็ต'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
      
      setState(() {
        _isLoading = true;
      });
      
      // เรียกใช้ FCMService สำหรับรีเซ็ตการลงทะเบียน token
      final fcmService = FCMService();
      await fcmService.resetTokenRegistration();
      
      // ทดสอบการเชื่อมต่อเซิร์ฟเวอร์
      final connectionTest = await fcmService.testServerConnection();
      
      setState(() {
        _isLoading = false;
      });
      
      // แสดงผลการรีเซ็ต
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ผลการรีเซ็ต Token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('สถานะเซิร์ฟเวอร์: ${connectionTest['connected'] == true ? '✅ เชื่อมต่อได้' : '❌ ไม่สามารถเชื่อมต่อได้'}'),
              const SizedBox(height: 8),
              Text('URL เซิร์ฟเวอร์: ${connectionTest['serverUrl'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 8),
              Text('Tokens Endpoint: ${connectionTest['tokenEndpoint'] == true ? '✅ OK' : '❌ ไม่สามารถเข้าถึงได้'}'),
              const SizedBox(height: 8),
              Text('Settings Endpoint: ${connectionTest['settingsEndpoint'] == true ? '✅ OK' : '❌ ไม่สามารถเข้าถึงได้'}'),
              const SizedBox(height: 8),
              Text('สถานะการลงทะเบียน: ${connectionTest['tokenRegistered'] == true ? '✅ ลงทะเบียนแล้ว' : '❌ ยังไม่ได้ลงทะเบียน'}'),
              const SizedBox(height: 16),
              const Text('หมายเหตุ: หากพบปัญหาการเชื่อมต่อ ให้ลองเปลี่ยนเครือข่ายหรือตรวจสอบการตั้งค่าเซิร์ฟเวอร์'),
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
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์
  Future<void> _testServerConnection() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // ทดสอบการเชื่อมต่อเซิร์ฟเวอร์
      final fcmService = FCMService();
      final connectionTest = await fcmService.testServerConnection();
      
      setState(() {
        _isLoading = false;
      });
      
      // แสดงผลการทดสอบ
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ผลการทดสอบเซิร์ฟเวอร์'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('สถานะเซิร์ฟเวอร์: ${connectionTest['connected'] == true ? '✅ เชื่อมต่อได้' : '❌ ไม่สามารถเชื่อมต่อได้'}'),
              const SizedBox(height: 8),
              Text('URL เซิร์ฟเวอร์: ${connectionTest['serverUrl'] ?? 'ไม่มีข้อมูล'}'),
              const SizedBox(height: 8),
              Text('Tokens Endpoint: ${connectionTest['tokenEndpoint'] == true ? '✅ OK' : '❌ ไม่สามารถเข้าถึงได้'}'),
              const SizedBox(height: 8),
              Text('Settings Endpoint: ${connectionTest['settingsEndpoint'] == true ? '✅ OK' : '❌ ไม่สามารถเข้าถึงได้'}'),
              const SizedBox(height: 8),
              Text('สถานะการลงทะเบียน: ${connectionTest['tokenRegistered'] == true ? '✅ ลงทะเบียนแล้ว' : '❌ ยังไม่ได้ลงทะเบียน'}'),
              const SizedBox(height: 16),
              const Text('หมายเหตุ: หากพบปัญหาการเชื่อมต่อ ให้ลองเปลี่ยนเครือข่ายหรือตรวจสอบการตั้งค่าเซิร์ฟเวอร์'),
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
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // เพิ่มฟังก์ชันแสดง dialog เกี่ยวกับแอปพลิเคชัน
  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Image.asset(
              'assets/icon/icon.png', // ถ้าไม่มีไฟล์นี้ อาจใช้ไอคอนอื่นแทน
              width: 40,
              height: 40,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.info, size: 40, color: Colors.orange),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'เกี่ยวกับแอปพลิเคชัน',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'แอปพลิเคชันแจ้งเตือนแผ่นดินไหว',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'พัฒนาโดย:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                'SOFTACULAR CO., LTD.',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'แหล่งข้อมูล:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                '• USGS (United States Geological Survey)\n• EMSC (European-Mediterranean Seismological Centre)\n• กรมอุตุนิยมวิทยา ประเทศไทย',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ข้อมูลการใช้งาน:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                'แอปพลิเคชันนี้ให้บริการฟรี เพื่อใช้สำหรับติดตามและรับการแจ้งเตือนเหตุการณ์แผ่นดินไหวที่เกิดขึ้นทั่วโลก',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'หมายเหตุ: ข้อมูลที่แสดงผลในแอปพลิเคชันอาจมีความคลาดเคลื่อนหรือล่าช้าได้ โดยขึ้นอยู่กับแหล่งข้อมูลต้นทาง',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  // ตรวจสอบสิทธิ์การเข้าถึงตำแหน่ง
  Future<void> _checkLocationPermission() async {
    try {
      final location = Location();
      
      // ตรวจสอบว่าบริการ location เปิดอยู่หรือไม่
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          setState(() {
            _isLocationPermissionGranted = false;
          });
          return;
        }
      }
      
      // ตรวจสอบสิทธิ์
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          setState(() {
            _isLocationPermissionGranted = false;
          });
          return;
        }
      }
      
      setState(() {
        _isLocationPermissionGranted = true;
      });
      
      // ถ้ายังไม่มีตำแหน่งที่บันทึกไว้ ให้ดึงตำแหน่งปัจจุบัน
      if (_userLatitude == null || _userLongitude == null) {
        await _getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      setState(() {
        _isLocationPermissionGranted = false;
      });
    }
  }
  
  // ดึงตำแหน่งปัจจุบัน
  Future<void> _getCurrentLocation() async {
    try {
      if (!_isLocationPermissionGranted) {
        await _checkLocationPermission();
        if (!_isLocationPermissionGranted) return;
      }
      
      final location = Location();
      final locationData = await location.getLocation();
      
      setState(() {
        _userLatitude = locationData.latitude;
        _userLongitude = locationData.longitude;
      });
      
      debugPrint('Current location: $_userLatitude, $_userLongitude');
    } catch (e) {
      debugPrint('Error getting current location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถดึงตำแหน่งปัจจุบันได้: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  // บันทึกการตั้งค่าการกรองตามระยะทาง
  Future<void> _saveLocationFilter() async {
    try {
      // ถ้าเปิดการกรองตามระยะทางแต่ไม่มีตำแหน่ง ให้แสดงข้อความเตือน
      if (_isDistanceFilterEnabled && (_userLatitude == null || _userLongitude == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กรุณาตั้งค่าตำแหน่งก่อนเปิดใช้งานการกรองตามระยะทาง'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      setState(() {
        _isLoading = true;
      });
      
      // ถ้าไม่มีตำแหน่งและปิดการกรอง ให้ใช้ตำแหน่งเริ่มต้น (กรุงเทพฯ)
      double lat = _userLatitude ?? 13.7563;
      double lng = _userLongitude ?? 100.5018;
      
      final result = await ApiService.setLocationFilter(
        latitude: lat,
        longitude: lng,
        maxDistanceKm: _maxDistanceKm,
        enabled: _isDistanceFilterEnabled,
      );
      
      setState(() {
        _isLoading = false;
      });
      
      if (result != null) {
        debugPrint('✅ Location filter saved: enabled=$_isDistanceFilterEnabled, lat=$lat, lng=$lng, distance=${_maxDistanceKm}km');
        
        // แสดงข้อความยืนยันเฉพาะเมื่อเปิดการกรอง
        if (_isDistanceFilterEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('บันทึกการตั้งค่าการกรองตามระยะทางเรียบร้อยแล้ว'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('❌ Failed to save location filter');
        if (_isDistanceFilterEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ไม่สามารถบันทึกการตั้งค่าการกรองตามระยะทางได้'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      debugPrint('❌ Error saving location filter: $e');
      if (_isDistanceFilterEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  // ทดสอบการคำนวณระยะทาง
  Future<void> _testDistanceCalculation() async {
    try {
      if (_userLatitude == null || _userLongitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('กรุณาตั้งค่าตำแหน่งก่อนทดสอบการคำนวณระยะทาง'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      
      setState(() {
        _isLoading = true;
      });
      
      // ทดสอบกับตำแหน่งกรุงเทพฯ
      const bangkokLat = 13.7563;
      const bangkokLng = 100.5018;
      
      final result = await ApiService.testDistance(
        lat1: _userLatitude!,
        lon1: _userLongitude!,
        lat2: bangkokLat,
        lon2: bangkokLng,
      );
      
      setState(() {
        _isLoading = false;
      });
      
      if (result != null && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ผลการทดสอบการคำนวณระยะทาง'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ตำแหน่งของคุณ: ${_userLatitude!.toStringAsFixed(4)}, ${_userLongitude!.toStringAsFixed(4)}'),
                const Text('ตำแหน่งกรุงเทพฯ: 13.7563, 100.5018'),
                const SizedBox(height: 8),
                Text('ระยะทาง: ${result['distanceKm']}'),
                const SizedBox(height: 8),
                Text('อยู่ในขอบเขตที่กำหนด (${_maxDistanceKm.toStringAsFixed(0)} กม.): ${result['deviceSettings']?['withinRange'] == true ? 'ใช่' : 'ไม่'}'),
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
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการทดสอบ: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่าการแจ้งเตือน'),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        actions: [
          // เพิ่มไอคอนข้อมูลเกี่ยวกับแอป
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'เกี่ยวกับแอปพลิเคชัน',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212), // พื้นหลังสีดำเหมือนหน้าหลัก
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // เพิ่มส่วนการตั้งค่าเสียงแจ้งเตือน
              /*
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                color: const Color(0xFF1E1E1E), // ปรับสีพื้นหลังการ์ด
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.volume_up, color: Colors.blue[400]),
                          const SizedBox(width: 8),
                          const Text(
                            'เสียงแจ้งเตือน',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('ใช้เสียงแจ้งเตือนที่กำหนดเอง', 
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: const Text(
                          'ใช้เสียงตามที่คุณเลือกสำหรับการแจ้งเตือนต่างๆ',
                          style: TextStyle(color: Colors.grey),
                        ),
                        value: false,
                        onChanged: _isNotificationEnabled
                            ? (value) {}
                            : null,
                        activeColor: Colors.blue,
                      ),
                      const Divider(color: Colors.grey),
                      if (false) ...[
                        // เลือกเสียงแจ้งเตือนปกติ
                        const Padding(
                          padding: EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 8,
                            bottom: 4,
                          ),
                          child: Text(
                            'เสียงแจ้งเตือนแผ่นดินไหวทั่วไป:',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: DropdownButtonFormField<String>(
                            value: null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.grey),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(color: Colors.blue),
                              ),
                            ),
                            dropdownColor: const Color(0xFF2C2C2C),
                            style: const TextStyle(color: Colors.white),
                            items: [],
                            onChanged: _isNotificationEnabled && false
                                ? (value) {}
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ปุ่มทดสอบเสียง
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isNotificationEnabled && false
                                  ? _testNotification
                                  : null,
                              icon: const Icon(Icons.volume_up),
                              label: const Text('ทดสอบเสียง'),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.blue[600],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        
                        // บันทึกการตั้งค่าเสียง
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ElevatedButton.icon(
                            onPressed: _isNotificationEnabled
                                ? () {
                                    // Save sound settings to EarthquakeService
                                    final earthquakeService =
                                        Provider.of<EarthquakeService>(
                                      context,
                                      listen: false,
                                    );
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('บันทึกการตั้งค่าเสียงเรียบร้อย'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                : null,
                            icon: const Icon(Icons.save),
                            label: const Text('บันทึกการตั้งค่าเสียง'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: const Color(0xFF388E3C), // สีเขียว
                              minimumSize: const Size.fromHeight(50),
                            ),
                          ),
                        ),
                      ],
                      if (false) ...[
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'การตั้งค่าเสียงจะใช้เสียงเริ่มต้นของระบบ',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              */

              const SizedBox(height: 16),
              
              // เพิ่มส่วนการตั้งค่าเซิร์ฟเวอร์ API
              const Divider(color: Colors.grey),
              // const SizedBox(height: 16.0),
              // const Text(
              //   'การตั้งค่าเซิร์ฟเวอร์',
              //   style: TextStyle(
              //     fontSize: 20,
              //     fontWeight: FontWeight.bold,
              //     color: Colors.white,
              //   ),
              // ),
              const SizedBox(height: 8.0),
              
              // เปิด/ปิดการกรองตามภูมิภาค
              SwitchListTile(
                title: const Text('กรองแผ่นดินไหวตามภูมิภาค', 
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'รับการแจ้งเตือนเฉพาะแผ่นดินไหวในภูมิภาคที่เลือก',
                  style: TextStyle(color: Colors.grey),
                ),
                value: _isServerRegionFilterEnabled,
                onChanged: (value) {
                  setState(() {
                    _isServerRegionFilterEnabled = value;
                  });
                },
                activeColor: Colors.blue,
              ),
              
              // เลือกภูมิภาค
              ListTile(
                title: const Text('ภูมิภาค', 
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _availableServerRegions
                    .firstWhere(
                      (region) => region['id'] == _selectedServerRegion,
                      orElse: () => {'id': 'sea', 'name': 'เอเชียตะวันออกเฉียงใต้'}
                    )['name'],
                  style: const TextStyle(color: Colors.grey),
                ),
                enabled: _isServerRegionFilterEnabled,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF2C2C2C),
                      title: const Text('เลือกภูมิภาค', style: TextStyle(color: Colors.white)),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _availableServerRegions.length,
                          itemBuilder: (context, index) {
                            final region = _availableServerRegions[index];
                            return RadioListTile<String>(
                              title: Text(region['name'], style: const TextStyle(color: Colors.white)),
                              value: region['id'],
                              groupValue: _selectedServerRegion,
                              onChanged: (value) {
                                setState(() {
                                  _selectedServerRegion = value!;
                                });
                                Navigator.pop(context);
                              },
                              activeColor: Colors.blue,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              const Divider(color: Colors.grey, height: 24),
              
              // เปิด/ปิดการกรองตามขนาดแผ่นดินไหว
              SwitchListTile(
                title: const Text('กรองตามขนาดแผ่นดินไหว', 
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'รับการแจ้งเตือนเฉพาะแผ่นดินไหวที่มีขนาดตั้งแต่ค่าที่กำหนด',
                  style: TextStyle(color: Colors.grey),
                ),
                value: _isServerMagnitudeFilterEnabled,
                onChanged: (value) {
                  setState(() {
                    _isServerMagnitudeFilterEnabled = value;
                  });
                },
                activeColor: Colors.blue,
              ),
              
              // ตั้งค่าขนาดแผ่นดินไหวขั้นต่ำ
              ListTile(
                title: const Text('ขนาดแผ่นดินไหวขั้นต่ำ', 
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${_serverMinMagnitude.toStringAsFixed(1)} ริกเตอร์',
                  style: const TextStyle(color: Colors.grey),
                ),
                enabled: _isServerMagnitudeFilterEnabled,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF2C2C2C),
                      title: const Text('ตั้งค่าขนาดแผ่นดินไหวขั้นต่ำ', style: TextStyle(color: Colors.white)),
                      content: StatefulBuilder(
                        builder: (context, setModalState) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${_serverMinMagnitude.toStringAsFixed(1)} ริกเตอร์',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Slider(
                                        value: _serverMinMagnitude,
                                        min: 0.1,
                                        max: 8.0,
                                        divisions: 79,
                                        label: _serverMinMagnitude.toStringAsFixed(1),
                                        onChanged: (value) {
                                          setModalState(() {
                                            setState(() {
                                              _serverMinMagnitude = value;
                                            });
                                          });
                                        },
                                        activeColor: Colors.blue,
                                        inactiveColor: Colors.grey[700],
                                      ),
                                    ),
                                    Container(
                                      width: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: Text(
                                        _serverMinMagnitude.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                'เลือกขนาดแผ่นดินไหวขั้นต่ำที่ต้องการรับการแจ้งเตือน',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          );
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('ตกลง', style: TextStyle(color: Colors.blue)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              
              const Divider(color: Colors.grey, height: 24),
              
              // เพิ่มส่วนการตั้งค่าการกรองตามระยะทาง
              SwitchListTile(
                title: const Text('กรองตามระยะทาง', 
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'รับการแจ้งเตือนเฉพาะแผ่นดินไหวที่เกิดขึ้นในระยะทางที่กำหนด',
                  style: TextStyle(color: Colors.grey),
                ),
                value: _isDistanceFilterEnabled,
                onChanged: (value) async {
                  if (value && !_isLocationPermissionGranted) {
                    await _checkLocationPermission();
                    if (!_isLocationPermissionGranted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณาอนุญาตการเข้าถึงตำแหน่งก่อนเปิดใช้งานการกรองตามระยะทาง'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                  }
                  
                  setState(() {
                    _isDistanceFilterEnabled = value;
                  });
                  
                  if (value) {
                    await _getCurrentLocation();
                  }
                  
                  // บันทึกการตั้งค่าทันทีหลังจากเปลี่ยนสถานะ
                  await _saveLocationFilter();
                },
                activeColor: Colors.blue,
              ),
              
              // แสดงตำแหน่งปัจจุบัน
              if (_isDistanceFilterEnabled) ...[
                ListTile(
                  title: const Text('ตำแหน่งปัจจุบัน', 
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _userLatitude != null && _userLongitude != null
                        ? 'ละติจูด: ${_userLatitude!.toStringAsFixed(4)}, ลองจิจูด: ${_userLongitude!.toStringAsFixed(4)}'
                        : 'ยังไม่ได้ตั้งค่าตำแหน่ง',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: _getCurrentLocation,
                    tooltip: 'อัปเดตตำแหน่งปัจจุบัน',
                  ),
                ),
                
                // แสดงระยะทางคงที่ 2000 กม.
                ListTile(
                  title: const Text('ระยะทางการกรอง', 
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${_maxDistanceKm.toStringAsFixed(0)} กิโลเมตร (ค่าคงที่)',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  leading: const Icon(Icons.straighten, color: Colors.blue),
                ),
                
                // ปุ่มขอสิทธิ์การเข้าถึงตำแหน่ง (ถ้ายังไม่ได้รับสิทธิ์)
                if (!_isLocationPermissionGranted) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: _checkLocationPermission,
                      icon: const Icon(Icons.location_on, color: Colors.orange),
                      label: const Text('ขอสิทธิ์การเข้าถึงตำแหน่ง', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45),
                        side: const BorderSide(color: Colors.orange),
                      ),
                    ),
                  ),
                ],
                
                // ปุ่มทดสอบการคำนวณระยะทาง
                const SizedBox(height: 8),
                // Padding(
                //   padding: const EdgeInsets.symmetric(horizontal: 16),
                //   child: OutlinedButton.icon(
                //     onPressed: _userLatitude != null && _userLongitude != null 
                //         ? _testDistanceCalculation 
                //         : null,
                //     icon: const Icon(Icons.calculate, color: Colors.green),
                //     label: const Text('ทดสอบการคำนวณระยะทาง', style: TextStyle(color: Colors.white)),
                //     style: OutlinedButton.styleFrom(
                //       minimumSize: const Size(double.infinity, 45),
                //       side: const BorderSide(color: Colors.green),
                //     ),
                //   ),
                // ),
              ],
              
              // ปุ่มบันทึกการตั้งค่าเซิร์ฟเวอร์
              const SizedBox(height: 8.0),
              ElevatedButton.icon(
                onPressed: _saveServerSettings,
                icon: const Icon(Icons.save),
                label: const Text('บันทึกการตั้งค่า'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blue, // เปลี่ยนสีปุ่ม
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}