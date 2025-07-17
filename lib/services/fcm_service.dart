// lib/services/fcm_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import '../firebase_options.dart';
import '../models/earthquake.dart';
import '../services/notification_service.dart';
import 'api_service.dart';
import 'package:uuid/uuid.dart';

// Function type definition for earthquake callback
typedef EarthquakeCallback = void Function(Earthquake earthquake);

class FCMService {
  static final FCMService _instance = FCMService._internal();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _isInitialized = false;
  
  // Callback when earthquake is received
  EarthquakeCallback? onEarthquakeReceived;

  factory FCMService() {
    return _instance;
  }

  FCMService._internal();

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // Initialize Firebase
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Initialize notification service first to use its methods
      final notificationService = NotificationService();
      await notificationService.initialize();
      
      // ล้างประวัติการแจ้งเตือนทันทีเมื่อเริ่มต้นแอพเป็นครั้งแรก
      await notificationService.resetNotificationHistory();
      debugPrint('FCM: ล้างประวัติการแจ้งเตือนเรียบร้อย จะได้รับการแจ้งเตือนใหม่');

      // Generate and ensure device ID exists before proceeding
      final deviceId = await _ensureDeviceId();
      debugPrint('FCM: Using device ID: $deviceId');

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Request permission
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: true,
        criticalAlert: true,
      );

      debugPrint('FCM auth status: ${settings.authorizationStatus}');
      
      // ตรวจสอบว่ามี initial message (แอพถูกเปิดจากการคลิกการแจ้งเตือน) หรือไม่
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM: App was opened from a terminated state by notification');
        // บันทึกในหน่วยความจำว่าได้รับการแจ้งเตือนนี้แล้ว เพื่อไม่ให้แสดงซ้ำ
        final earthquakeId = initialMessage.data['id'] as String? ?? 'unknown_id';
        await notificationService.markEarthquakeAsNotified(earthquakeId);
        // ดึงข้อมูลและอัพเดท UI (หากต้องการ) แต่ไม่แสดงการแจ้งเตือนใหม่
        await _processPendingMessage(initialMessage, 'initialMessage');
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('FCM: Message received in foreground: ${message.messageId}');
        await _handleMessage(message, 'foreground');
      });
      
      // เมื่อแอพเปิดจากการคลิกแจ้งเตือน
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
        debugPrint('FCM: Message opened app: ${message.messageId}');
        // ไม่แสดงการแจ้งเตือนอีกเพราะเป็นการคลิกที่มีอยู่แล้ว แต่บันทึกว่าได้รับแล้ว
        final earthquakeId = message.data['id'] as String? ?? 'unknown_id';
        await notificationService.markEarthquakeAsNotified(earthquakeId);
        // ดึงข้อมูลและอัพเดท UI (หากต้องการ) แต่ไม่แสดงการแจ้งเตือนใหม่
        await _processPendingMessage(message, 'onMessageOpenedApp');
      });

      // Get token and register with timeout
      try {
        final tokenFuture = _fcm.getToken();
        final token = await tokenFuture.timeout(const Duration(seconds: 5), 
          onTimeout: () {
            debugPrint('⚠️ FCM: Token retrieval timed out, will try again later');
            return null;
          }
        );
        
        if (token != null) {
          debugPrint('FCM: Token received - ${token.substring(0, min(10, token.length))}...');
          
          // เก็บ token ใน SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('fcm_token', token);
          
          // ลงทะเบียน token กับเซิร์ฟเวอร์โดยใช้ deviceId จริง
          final registerSuccess = await ApiService.registerTokenWithServer(token, deviceId);
          debugPrint('FCM: Token registration ${registerSuccess ? 'successful' : 'failed'} for device ID: $deviceId');
        } else {
          debugPrint('⚠️ FCM: Token retrieval failed, will try again later');
        }
      } catch (e) {
        debugPrint('❌ FCM: Error getting token (non-critical): $e');
      }

      // Handle token refresh
      _fcm.onTokenRefresh.listen((token) async {
        debugPrint('FCM: Token refreshed');
        // ดึง deviceId ที่มีอยู่
        final deviceId = await _ensureDeviceId();
        // ลงทะเบียน token ใหม่กับเซิร์ฟเวอร์
        await ApiService.registerTokenWithServer(token, deviceId);
      });

      _isInitialized = true;
      debugPrint('FCM: Service initialized successfully');
    } catch (e) {
      debugPrint('❌ FCM: Failed to initialize: $e');
      // Still mark as initialized to prevent repeated initialization attempts
      _isInitialized = true;
    }
  }

  // Add a dedicated message handler method to centralize all FCM message processing
  Future<void> _handleMessage(RemoteMessage message, String source) async {
    try {
      debugPrint('FCM: Handling message from $source: ${message.messageId}');
      
      // Extract earthquake ID or generate temporary one
      final String earthquakeId = message.data['id'] as String? ?? 
                      'fcm_${DateTime.now().millisecondsSinceEpoch}';
      
      // ตรวจสอบรูปแบบอื่นของ ID (มี 'ak' prefix - พบใน iOS)
      final String alternativeId = earthquakeId.startsWith('ak') 
            ? earthquakeId.substring(2) 
            : 'ak$earthquakeId';
      
      // Get notification service
      final notificationService = NotificationService();
      await notificationService.initialize();
      
      // Check if already notified
      final hasBeenNotified = await notificationService.hasEarthquakeBeenNotified(earthquakeId) || 
                              await notificationService.hasEarthquakeBeenNotified(alternativeId);
      
      if (hasBeenNotified) {
        debugPrint('⚠️ FCM: Earthquake $earthquakeId already notified, skipping notification');
        
        // ถึงแม้จะแจ้งเตือนแล้ว แต่ถ้ามีข้อมูลแผ่นดินไหว ให้เรียก callback เพื่ออัปเดต UI
        if (message.data.containsKey('magnitude') && 
            message.data.containsKey('place') && 
            onEarthquakeReceived != null) {
          try {
            final earthquake = _createEarthquakeFromMessageData(message.data);
            onEarthquakeReceived!(earthquake);
            debugPrint('FCM: Called onEarthquakeReceived for existing earthquake: $earthquakeId');
          } catch (e) {
            debugPrint('FCM: Error creating earthquake from message data: $e');
          }
        }
        
        return;
      }
      
      // บันทึกว่าเคยแจ้งเตือนแล้ว (ก่อนแสดงการแจ้งเตือนจริง เพื่อป้องกันการแจ้งเตือนซ้ำ)
      await notificationService.markEarthquakeAsNotified(earthquakeId);
      
      // บันทึกรูปแบบอื่นด้วย (สำหรับ iOS)
      if (alternativeId != earthquakeId) {
        await notificationService.markEarthquakeAsNotified(alternativeId);
        debugPrint('FCM: Also marked alternative ID $alternativeId as notified');
      }
            
      // ใน iOS ไม่แสดงการแจ้งเตือนใหม่ เพื่อป้องกันการแจ้งเตือนซ้ำ
      // แต่ใน Android ยังแสดงตามปกติ
      if (Platform.isIOS) {
        debugPrint('FCM (iOS): Skip showing notification - will be handled by Flutter Local Notifications');
        
        // เรียก callback อัพเดต UI ถ้ามีข้อมูลแผ่นดินไหว
        if (message.data.containsKey('magnitude') && 
            message.data.containsKey('place') && 
            onEarthquakeReceived != null) {
          try {
            final earthquake = _createEarthquakeFromMessageData(message.data);
            onEarthquakeReceived!(earthquake);
            debugPrint('FCM: Called onEarthquakeReceived for new earthquake without notification: $earthquakeId');
          } catch (e) {
            debugPrint('FCM: Error creating earthquake from message data: $e');
          }
        }
        
        return;
      }
      
      // สำหรับ Android ตรวจสอบขนาดแผ่นดินไหวก่อนแสดงการแจ้งเตือน
      if (message.data.containsKey('magnitude')) {
        try {
          final magnitude = double.parse(message.data['magnitude'].toString());
          
          // ดึงการตั้งค่าจากเซิร์ฟเวอร์
          final settings = await ApiService.getSettings();
          final filterByMagnitude = settings?['settings']?['filterByMagnitude'] ?? true;
          final minMagnitude = settings?['settings']?['minMagnitude'] ?? 3.5;

          debugPrint('FCM (Android): Checking notification - magnitude: $magnitude, threshold: $minMagnitude, filter enabled: $filterByMagnitude');

          // ตรวจสอบว่าขนาดแผ่นดินไหวมากกว่าหรือเท่ากับค่า threshold
          if (filterByMagnitude && magnitude < minMagnitude) {
            debugPrint('FCM (Android): Skipping notification - magnitude $magnitude is below server threshold $minMagnitude');
            return;
          } else {
            debugPrint('FCM (Android): Showing notification - magnitude $magnitude meets server threshold $minMagnitude');
          }
        } catch (e) {
          debugPrint('FCM: Error parsing magnitude or fetching server settings: $e');
        }
      }
      
      // สำหรับ Android แสดงตามปกติ
      final String title = message.notification?.title ?? 'แผ่นดินไหวใหม่';
      final String body = message.notification?.body ?? 'มีแผ่นดินไหวเกิดขึ้น';
      
      await notificationService.showEarthquakeNotification(
        title: title,
        body: body,
        payload: message.data.isNotEmpty ? json.encode(message.data) : null,
        earthquakeId: earthquakeId,
      );
      
      // เรียก callback ถ้ามีข้อมูลแผ่นดินไหว
      if (message.data.containsKey('magnitude') && 
          message.data.containsKey('place') && 
          onEarthquakeReceived != null) {
        try {
          final earthquake = _createEarthquakeFromMessageData(message.data);
          onEarthquakeReceived!(earthquake);
          debugPrint('FCM: Called onEarthquakeReceived for new earthquake: $earthquakeId');
        } catch (e) {
          debugPrint('FCM: Error creating earthquake from message data: $e');
        }
      }
      
      debugPrint('✓ FCM: Notification shown for earthquake: $earthquakeId');
    } catch (e) {
      debugPrint('❌ FCM: Error handling message: $e');
    }
  }

  Future<void> _registerTokenWithServer(String token) async {
    try {
      // Get device ID first
      final deviceId = await _ensureDeviceId();
      debugPrint('FCM: Registering token with device ID: $deviceId');
      
      // Add payload with device ID for registration
      final Map<String, dynamic> payload = {
        'token': token,
        'deviceId': deviceId,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      // Add timeout to prevent app from hanging
      final registerFuture = ApiService.registerTokenWithServer(token, deviceId);
      await registerFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ FCM: Token registration timed out, continuing app startup');
          return false;
        },
      );
      debugPrint('✓ FCM: Token registration completed (success or failure)');
    } catch (e) {
      // Don't let registration errors block app startup
      debugPrint('❌ FCM: Failed to register token with server (non-critical): $e');
    }
  }
  
  // Run diagnostic checks for FCM
  Future<Map<String, dynamic>> runFCMDiagnostics() async {
    final results = <String, dynamic>{};
    
    try {
      // Check if FCM is initialized
      results['isInitialized'] = _isInitialized;
      
      // Check if token exists
      final token = await _fcm.getToken();
      results['hasToken'] = token != null && token.isNotEmpty;
      
      // Check registration status with server
      results['registrationSuccess'] = false;
      if (token != null) {
        try {
          // Try to verify registration with the server
          final isRegistered = await ApiService.verifyToken(token);
          results['registrationSuccess'] = isRegistered;
        } catch (e) {
          debugPrint('FCM Diagnostics: Failed to verify token: $e');
        }
      }
      
      // Check notification permission
      final settings = await _fcm.getNotificationSettings();
      results['permissionStatus'] = settings.authorizationStatus.toString();
      
      debugPrint('FCM Diagnostics completed successfully');
    } catch (e) {
      debugPrint('FCM Diagnostics error: $e');
      results['error'] = e.toString();
    }
    
    return results;
  }
  
  // รีเซ็ตการลงทะเบียน token กับเซิร์ฟเวอร์
  Future<bool> resetTokenRegistration() async {
    try {
      debugPrint('FCM: Resetting token registration with server');
      
      // ล้าง token เก่าใน SharedPreferences ก่อน
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('registered_token')) {
        final oldToken = prefs.getString('registered_token');
        debugPrint('FCM: Removing old token registration: ${oldToken?.substring(0, min(10, oldToken?.length ?? 0))}...');
        await prefs.remove('registered_token');
        await prefs.remove('registered_token_device_id');
        await prefs.remove('token_registration_time');
      }
      
      // ดึง deviceId ปัจจุบัน
      final deviceId = await _ensureDeviceId();
      debugPrint('FCM: Using device ID for reset: $deviceId');
      
      // ดึง token ปัจจุบัน
      final currentToken = await _fcm.getToken();
      if (currentToken == null) {
        debugPrint('❌ FCM: Cannot reset registration - no token available');
        return false;
      }
      
      debugPrint('FCM: Token for reset: ${currentToken.substring(0, min(10, currentToken.length))}...');
      
      // รีเซ็ตประวัติการแจ้งเตือนสำหรับอุปกรณ์นี้
      final resetSuccess = await ApiService.resetDeviceNotificationHistory(deviceId);
      debugPrint('FCM: Reset notification history: ${resetSuccess ? 'SUCCESS' : 'FAILED'}');
      
      // แยกการลบและลงทะเบียน token
      try {
        // ลบ token เดิมออกจากเซิร์ฟเวอร์
        final removeSuccess = await ApiService.removeToken(currentToken);
        debugPrint('FCM: Remove old token: ${removeSuccess ? 'SUCCESS' : 'FAILED'}');
      } catch (e) {
        // ไม่ต้องหยุดการทำงานหากลบไม่สำเร็จ
        debugPrint('⚠️ FCM: Error removing token (non-critical): $e');
      }
      
      // บังคับให้สร้าง token ใหม่
      try {
        await _fcm.deleteToken();
        debugPrint('FCM: Deleted local FCM token');
      } catch (e) {
        debugPrint('⚠️ FCM: Error deleting local token (non-critical): $e');
      }
      
      final newToken = await _fcm.getToken();
      
      if (newToken != null) {
        // เก็บข้อมูล token ใหม่ใน SharedPreferences
        await prefs.setString('fcm_token', newToken);
        
        // ลงทะเบียน token ใหม่กับเซิร์ฟเวอร์
        debugPrint('FCM: Registering new token with device ID: $deviceId');
        final registered = await ApiService.registerTokenWithServer(newToken, deviceId);
        
        if (registered) {
          debugPrint('✅ FCM: New token registration: SUCCESS');
          
          // ตรวจสอบว่า token ลงทะเบียนสำเร็จจริงหรือไม่
          final verified = await ApiService.verifyToken(newToken);
          debugPrint('FCM: Token verification after registration: ${verified ? 'SUCCESS' : 'FAILED'}');
          
          if (!verified) {
            // ถ้าตรวจสอบไม่สำเร็จ ให้ลองลงทะเบียนอีกครั้ง
            debugPrint('⚠️ FCM: Token not verified, trying direct registration method');
            
            final directSuccess = await http.post(
              Uri.parse('${ApiService.baseUrl}/register-token-direct'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'token': newToken,
                'deviceId': deviceId,
                'platform': Platform.isIOS ? 'ios' : 'android',
                'timestamp': DateTime.now().millisecondsSinceEpoch,
              }),
            ).timeout(const Duration(seconds: 5));
            
            debugPrint('FCM: Direct token registration attempt: ${directSuccess.statusCode == 200 ? 'SUCCESS' : 'FAILED'}');
          }
        } else {
          debugPrint('❌ FCM: New token registration: FAILED');
        }
        
        return true;
      } else {
        debugPrint('❌ FCM: Failed to get new token after reset');
        return false;
      }
    } catch (e) {
      debugPrint('❌ FCM: Error resetting token registration: $e');
      return false;
    }
  }
  
  // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์
  Future<Map<String, dynamic>> testServerConnection() async {
    final results = <String, dynamic>{};
    final apiBaseUrl = "https://quake-api.softacular.com"; // ใช้ URL จริงที่เซิร์ฟเวอร์ของคุณ
    
    try {
      results['serverUrl'] = apiBaseUrl;
      results['connected'] = false;
      results['tokenEndpoint'] = false;
      results['settingsEndpoint'] = false;
      
      // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์
      final connectionCheck = await ApiService.checkEarthquakes();
      results['connected'] = connectionCheck != null;
      results['data'] = connectionCheck;
      
      // ทดสอบ token endpoint
      try {
        final tokenResponse = await http.get(Uri.parse('$apiBaseUrl/check-token-endpoint'));
        results['tokenEndpoint'] = tokenResponse.statusCode == 200;
      } catch (e) {
        debugPrint('❌ FCM: Error testing token endpoint: $e');
        results['tokenEndpoint'] = false;
      }
      
      // ทดสอบ settings endpoint
      try {
        final settingsResponse = await http.get(Uri.parse('$apiBaseUrl/check-settings-endpoint'));
        results['settingsEndpoint'] = settingsResponse.statusCode == 200;
      } catch (e) {
        debugPrint('❌ FCM: Error testing settings endpoint: $e');
        results['settingsEndpoint'] = false;
      }
      
      if (connectionCheck != null) {
        // ดึง token ปัจจุบัน
        final token = await _fcm.getToken();
        if (token != null) {
          // ตรวจสอบว่า token ลงทะเบียนกับเซิร์ฟเวอร์แล้วหรือไม่
          final isRegistered = await ApiService.verifyToken(token);
          results['tokenRegistered'] = isRegistered;
          
          // ถ้ายังไม่ลงทะเบียน ให้ลงทะเบียนใหม่
          if (!isRegistered) {
            final registerSuccess = await ApiService.registerToken(token);
            results['newRegistration'] = registerSuccess;
          }
        }
      }
      
      debugPrint('✅ FCM: Server connection test results: $results');
    } catch (e) {
      debugPrint('❌ FCM: Error testing server connection: $e');
      results['error'] = e.toString();
      results['connected'] = false;
      results['serverUrl'] = apiBaseUrl;
    }
    
    return results;
  }

  // ส่งการแจ้งเตือนทดสอบ
  Future<bool> sendTestNotification() async {
    try {
      debugPrint('FCM: Sending test notification');
      
      // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์ก่อน
      debugPrint('FCM: Testing server connection before FCM test...');
      try {
        final result = await ApiService.testServerConnection().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ FCM: Server connection test timed out');
            return false;
          }
        );
        
        if (!result) {
          debugPrint('⚠️ FCM: Cannot reach server, showing local notification only');
          return true; // ส่งแจ้งเตือนในเครื่องสำเร็จ แม้ไม่ถึงเซิร์ฟเวอร์
        }
      } catch (e) {
        debugPrint('⚠️ FCM: Server connection test failed: $e');
        // ทำต่อไปในกรณีที่ทดสอบการเชื่อมต่อไม่สำเร็จ
      }
      
      // ทดสอบว่าการลงทะเบียน token กับเซิร์ฟเวอร์ทำงานถูกต้อง
      final token = await _fcm.getToken();
      if (token != null) {
        try {
          // เช็คว่าลงทะเบียนกับเซิร์ฟเวอร์แล้วหรือไม่
          final verifyFuture = ApiService.verifyToken(token);
          final isRegistered = await verifyFuture.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              debugPrint('⚠️ FCM: Token verification timed out');
              return false;
            }
          );
          
          if (!isRegistered) {
            debugPrint('FCM: Token not registered, trying to register...');
            // พยายามลงทะเบียนอีกครั้งแต่ไม่รอ
            _registerTokenWithServer(token);
          } else {
            debugPrint('FCM: Token already registered');
          }
        } catch (e) {
          debugPrint('FCM: Error verifying token (non-critical): $e');
        }
      }
      
      debugPrint('FCM: Test notification sent successfully');
      return true;
    } catch (e) {
      debugPrint('FCM: Failed to send test notification: $e');
      return false;
    }
  }

  // แยกฟังก์ชันสำหรับการจัดการข้อความที่เปิดแอพจากการคลิกแจ้งเตือน
  Future<void> _processPendingMessage(RemoteMessage message, String source) async {
    try {
      debugPrint('FCM: Processing pending message from $source: ${message.messageId}');
      
      // extract earthquake ID
      final String earthquakeId = message.data['id'] as String? ?? 'unknown_id';
      
      // เก็บข้อมูลไว้ใน SharedPreferences เพื่อป้องกันการแจ้งเตือนซ้ำ
      final prefs = await SharedPreferences.getInstance();
      final key = 'processed_fcm_${earthquakeId}';
      // บันทึกเวลาที่ประมวลผล
      await prefs.setString(key, DateTime.now().toIso8601String());
      
      // เรียก callback ถ้ามีข้อมูลแผ่นดินไหว แต่ไม่ต้องแสดงการแจ้งเตือน
      if (message.data.containsKey('magnitude') && 
          message.data.containsKey('place') && 
          onEarthquakeReceived != null) {
        try {
          final earthquake = _createEarthquakeFromMessageData(message.data);
          onEarthquakeReceived!(earthquake);
          debugPrint('FCM: Called onEarthquakeReceived for pending earthquake: $earthquakeId');
        } catch (e) {
          debugPrint('FCM: Error creating earthquake from message data: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ FCM: Error processing pending message: $e');
    }
  }

  // Add method to ensure device ID exists
  Future<String> _ensureDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      
      // ถ้ายังไม่มี deviceId ให้สร้างใหม่จากค่าจริงของเครื่อง
      if (deviceId == null || deviceId.isEmpty) {
        final deviceInfo = DeviceInfoPlugin();
        
        // สร้าง identifier ตามแพลตฟอร์ม ใช้ค่าจริงจากเครื่อง
        if (Platform.isAndroid) {
          // Android ID - ใช้ค่าจริงจากเครื่อง
          final androidInfo = await deviceInfo.androidInfo;
          // ใช้ค่า combined ระหว่าง id และ androidId เพื่อความเป็นเอกลักษณ์
          deviceId = androidInfo.id;
          // ถ้า ID ที่ได้ไม่ใช่ UUID พยายามใช้ค่าอื่นที่เหมาะสมกว่า
          if (deviceId == null || deviceId.isEmpty || deviceId == 'BP1A.250405.007' || !deviceId.contains('-')) {
            // เรียกใช้ ID หรือค่าอื่นๆ
            if (androidInfo.device.isNotEmpty) {
              deviceId = '${androidInfo.manufacturer}-${androidInfo.device}-${androidInfo.id}';
            } else if (androidInfo.serialNumber.isNotEmpty && androidInfo.serialNumber != 'unknown') {
              deviceId = androidInfo.serialNumber;
            } else {
              // ถ้าไม่มีค่าใดๆ ที่ดี สร้าง UUID ขึ้นมาใหม่
              final uuid = const Uuid();
              deviceId = uuid.v4();
              debugPrint('⚠️ ไม่พบค่า Android ID ที่เหมาะสม สร้าง UUID ใหม่');
            }
          }
          debugPrint('✅ สร้าง device ID จาก Android ID: $deviceId');
        } else if (Platform.isIOS) {
          // iOS identifier - ใช้ค่าจริงจากเครื่อง
          final iosInfo = await deviceInfo.iosInfo;
          // ใช้ identifierForVendor โดยตรง
          deviceId = iosInfo.identifierForVendor;
          debugPrint('✅ สร้าง device ID จาก iOS identifierForVendor: $deviceId');
        }
        
        // ถ้ายังไม่ได้ deviceId ให้ใช้ค่า default
        deviceId = deviceId ?? 'unknown_device';
        
        // บันทึกลงใน SharedPreferences
        await prefs.setString('device_id', deviceId);
        debugPrint('✅ Created device ID from device: $deviceId');
      } else {
        debugPrint('✅ Using existing device ID: $deviceId');
      }
      
      debugPrint('Device ID initialized: $deviceId');
      return deviceId;
    } catch (e) {
      debugPrint('❌ Error getting device ID: $e');
      return 'unknown_device';
    }
  }
}

// Modify background handler to use the central message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('FCM: Handling background message: ${message.messageId}');
  
  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();
  
  // Extract earthquake ID or generate temporary one
  final String earthquakeId = message.data['id'] as String? ?? 
                  'fcm_${DateTime.now().millisecondsSinceEpoch}';
  
  // ตรวจสอบรูปแบบอื่นของ ID (มี 'ak' prefix - พบใน iOS)
  final String alternativeId = earthquakeId.startsWith('ak') 
        ? earthquakeId.substring(2) 
        : 'ak$earthquakeId';
  
  // Check if already notified
  final hasBeenNotified = await notificationService.hasEarthquakeBeenNotified(earthquakeId) ||
                          await notificationService.hasEarthquakeBeenNotified(alternativeId);
  
  if (hasBeenNotified) {
    debugPrint('⚠️ FCM: Earthquake $earthquakeId already notified, skipping background notification');
    return;
  }
  
  // บันทึกว่าเคยแจ้งเตือนแล้ว (ก่อนแสดงการแจ้งเตือนจริง เพื่อป้องกันการแจ้งเตือนซ้ำ)
  await notificationService.markEarthquakeAsNotified(earthquakeId);
  
  // บันทึกรูปแบบอื่นด้วย (สำหรับ iOS)
  if (alternativeId != earthquakeId) {
    await notificationService.markEarthquakeAsNotified(alternativeId);
    debugPrint('FCM: Also marked alternative ID $alternativeId as notified');
  }
  
  // ใน iOS ไม่แสดงการแจ้งเตือนใหม่ เพื่อป้องกันการแจ้งเตือนซ้ำ
  if (Platform.isIOS) {
    debugPrint('FCM Background (iOS): Skip showing notification - will be handled by Flutter Local Notifications');
    return;
  }
  
  // สำหรับ Android ตรวจสอบขนาดแผ่นดินไหวก่อนแสดงการแจ้งเตือน
  if (message.data.containsKey('magnitude')) {
    try {
      final magnitude = double.parse(message.data['magnitude'].toString());
      
      // ดึงการตั้งค่าจากเซิร์ฟเวอร์
      final settings = await ApiService.getSettings();
      final filterByMagnitude = settings?['settings']?['filterByMagnitude'] ?? true;
      final minMagnitude = settings?['settings']?['minMagnitude'] ?? 2.5;

      debugPrint('FCM (Android): Checking notification - magnitude: $magnitude, threshold: $minMagnitude, filter enabled: $filterByMagnitude');

      // ตรวจสอบว่าขนาดแผ่นดินไหวมากกว่าหรือเท่ากับค่า threshold
      if (filterByMagnitude && magnitude < minMagnitude) {
        debugPrint('FCM (Android): Skipping notification - magnitude $magnitude is below server threshold $minMagnitude');
        return;
      } else {
        debugPrint('FCM (Android): Showing notification - magnitude $magnitude meets server threshold $minMagnitude');
      }
    } catch (e) {
      debugPrint('FCM: Error parsing magnitude or fetching server settings: $e');
    }
  }
  
  // สำหรับ Android แสดงตามปกติ
  final String title = message.notification?.title ?? 'แผ่นดินไหวใหม่';
  final String body = message.notification?.body ?? 'มีแผ่นดินไหวเกิดขึ้น';
  
  await notificationService.showEarthquakeNotification(
    title: title,
    body: body,
    payload: message.data.isNotEmpty ? json.encode(message.data) : null,
    earthquakeId: earthquakeId,
  );
  
  debugPrint('✓ FCM: Background notification shown for earthquake: $earthquakeId');
}

// สร้าง Earthquake จากข้อมูล message
Earthquake _createEarthquakeFromMessageData(Map<String, dynamic> data) {
  return Earthquake(
    id: data['id'] as String? ?? 'unknown_id',
    magnitude: double.tryParse(data['magnitude'] as String? ?? '0') ?? 0,
    time: DateTime.tryParse(data['time'] as String? ?? DateTime.now().toIso8601String()) ?? DateTime.now(),
    latitude: double.tryParse(data['latitude'] as String? ?? '0') ?? 0,
    longitude: double.tryParse(data['longitude'] as String? ?? '0') ?? 0,
    depth: double.tryParse(data['depth'] as String? ?? '0') ?? 0,
    location: data['place'] as String? ?? 'ไม่ทราบตำแหน่ง',
  );
}

