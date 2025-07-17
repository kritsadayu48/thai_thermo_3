// lib/services/notification_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:app_settings/app_settings.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Channel IDs for different notification types
  static const String earthquakeChannelId = 'earthquake_alerts';
  // static const String testChannelId = 'test_alerts';

  // Channel names
  static const String earthquakeChannelName = 'Earthquake Alerts';
  // static const String testChannelName = 'Test Alerts';

  // Channel descriptions
  static const String earthquakeChannelDescription =
      'แจ้งเตือนแผ่นดินไหวที่สำคัญ';
  // static const String testChannelDescription = 'แจ้งเตือนทดสอบระบบ';
      
  // ปิดการทำงานของการเลือกเสียงแจ้งเตือนทั้งหมด
  // Map of available sounds for Android
  /*
  final Map<String, String> _androidSoundMap = {
    'default': 'notification_me',
    'alert': 'alert',
    'beep': 'beep',
    'chime': 'chime',
    'soft': 'soft_notification',
    'siren': 'siren',
    'alarm': 'alarm',
    'warning': 'warning',
  };
  
  // Map of available sounds for iOS
  final Map<String, String> _iosSoundMap = {
    'default': 'default',
    'alert': 'alert.aiff',
    'beep': 'beep.aiff',
    'chime': 'chime.aiff',
    'soft': 'soft_notification.aiff',
    'siren': 'siren.aiff',
    'alarm': 'alarm.aiff',
    'warning': 'warning.aiff',
  };
  */
  
  // ใช้เสียงเดียวเท่านั้น
  final String _defaultAndroidSound = 'notification_me';
  final String _defaultIOSSound = 'default';

  // เก็บ ID การแจ้งเตือนล่าสุดเพื่อป้องกันการซ้ำ
  final Set<String> _recentNotificationIds = {};
  final int _maxRecentNotifications = 50;

  // เพิ่ม Set เก็บ ID ของแผ่นดินไหวที่แสดงแล้ว
  final Set<String> _displayedEarthquakes = {};
  
  // เพิ่ม timestamp เพื่อป้องกันการแจ้งเตือนถี่เกินไป
  DateTime? _lastNotificationTime;
  
  // เพิ่ม Map เก็บเวลาล่าสุดของการแจ้งเตือนแต่ละ ID
  final Map<String, DateTime> _lastNotificationTimeByID = {};

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz_data.initializeTimeZones(); // Initialize timezone data

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsIOS =
        const DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      // เพิ่มเพื่อรองรับการแจ้งเตือนแบบ critical
      requestCriticalPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response);
      },
    );

    // ตั้งค่า notification channels สำหรับ Android
    await _setupNotificationChannels();
    
    // ตรวจสอบความพร้อมของไฟล์เสียง
    if (Platform.isAndroid) {
      final soundResults = await _checkAndroidSoundResources();
      debugPrint('Android sound resources status: ${soundResults.length} sounds checked');
      
      // พิมพ์รายการเสียงทั้งหมดเพื่อการอ้างอิง
      debugPrint('Available sound options on Android:');
      debugPrint('- $_defaultAndroidSound');
    }
    
    // โหลดข้อมูล notifications ที่แสดงแล้วจาก SharedPreferences
    await _loadNotifiedEarthquakesFromPrefs();
    
    _isInitialized = true;
    debugPrint('Notification service initialized successfully');
  }

  Future<bool> checkPermissions() async {
    bool? result;

    if (Platform.isIOS) {
      result = await notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (Platform.isAndroid) {
      result =
          await notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled();
    } else {
      result = true;
    }

    return result ?? false;
  }

  Future<void> openAppSettings() async {
    await AppSettings.openAppSettings();
  }

  // Setup notification channels for Android
  Future<void> _setupNotificationChannels() async {
    if (!Platform.isAndroid) return;

    // Regular earthquake channel
    AndroidNotificationChannel earthquakeChannel =
        const AndroidNotificationChannel(
          earthquakeChannelId,
          earthquakeChannelName,
          description: earthquakeChannelDescription,
          importance: Importance.max, // ความสำคัญสูงสุด
          enableLights: true,
          enableVibration: true,
        );

    // Test channel
    /*
    AndroidNotificationChannel testChannel = const AndroidNotificationChannel(
      testChannelId,
      testChannelName,
      description: testChannelDescription,
      importance: Importance.high,
      enableVibration: true,
    );
    */

    try {
      final androidPlugin =
          notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(earthquakeChannel);
        // await androidPlugin.createNotificationChannel(testChannel);
        debugPrint('All notification channels created successfully');
      }
    } catch (e) {
      debugPrint('Error creating notification channels: $e');
    }
  }

  /// แสดงการแจ้งเตือนเกี่ยวกับแผ่นดินไหว
  Future<void> showEarthquakeNotification({
    required String title,
    required String body,
    String? payload,
    String? sound,
    String? earthquakeId,
  }) async {
    try {
      // ตรวจสอบการซับซ้อนโดยเชคทั้ง ID ต้นฉบับและ ID ที่อาจมีการเพิ่ม prefix
      if (earthquakeId != null) {
        // ตรวจสอบทั้ง ID ปกติและ ID ที่มี prefix 'ak' (มักพบใน iOS)
        final originalId = earthquakeId;
        final alternativeId = earthquakeId.startsWith('ak') 
            ? earthquakeId.substring(2) 
            : 'ak$earthquakeId';
            
        final alreadyNotifiedOriginal = await hasEarthquakeBeenNotified(originalId);
        final alreadyNotifiedAlternative = await hasEarthquakeBeenNotified(alternativeId);
        
        if (alreadyNotifiedOriginal || alreadyNotifiedAlternative) {
          debugPrint('⚠️ NotificationService: Earthquake $earthquakeId (or alternative form) already notified, skipping notification');
          return;
        }
        
        // บันทึกทั้งรูปแบบดั้งเดิมและรูปแบบทางเลือกเพื่อป้องกันการแจ้งเตือนซ้ำ
        await markEarthquakeAsNotified(originalId);
        if (originalId != alternativeId) {
          await markEarthquakeAsNotified(alternativeId);
          debugPrint('✓ NotificationService: Also marked alternative ID $alternativeId as notified');
        }
      }
      
      if (!_isInitialized) {
        await initialize();
      }

      final now = DateTime.now();
      final uniqueId = _generateNotificationId(earthquakeId);
      
      // บันทึกข้อมูลในหน่วยความจำ
      if (earthquakeId != null) {
        // บันทึกเวลาที่แจ้งเตือนในหน่วยความจำ
        _lastNotificationTimeByID[earthquakeId] = now;
        
        // ล้างข้อมูลเก่าหากมีมากเกินไป
        if (_recentNotificationIds.length > _maxRecentNotifications) {
          _recentNotificationIds.clear();
        }
        _recentNotificationIds.add(earthquakeId);
      }

      // กำหนดเสียงการแจ้งเตือน
      String soundFile = sound ?? 'default';

      // แสดงการแจ้งเตือนบน Android
      if (Platform.isAndroid) {
        final androidPlatformChannelSpecifics = AndroidNotificationDetails(
          'earthquake_alerts',
          'Earthquake Alerts',
          channelDescription: 'Notification channel for earthquake alerts',
          importance: Importance.high,
          priority: Priority.high,
          sound: (soundFile != 'default') ? RawResourceAndroidNotificationSound(soundFile) : null,
          playSound: true,
          enableVibration: true,
        );

        final platformChannelSpecifics = NotificationDetails(
          android: androidPlatformChannelSpecifics,
        );

        await notificationsPlugin.show(
          uniqueId,
          title,
          body,
          platformChannelSpecifics,
          payload: payload,
        );
      }
      // แสดงการแจ้งเตือนบน iOS
      else if (Platform.isIOS) {
        final darwinNotificationDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: (soundFile != 'default') ? '$soundFile.aiff' : null,
          badgeNumber: 1,
        );

        final platformChannelSpecifics = NotificationDetails(
          iOS: darwinNotificationDetails,
        );

        await notificationsPlugin.show(
          uniqueId,
          title,
          body,
          platformChannelSpecifics,
          payload: payload,
        );
      }

      // บันทึกรายละเอียดการแจ้งเตือน
      debugPrint('✅ NOTIFICATION SHOWN: ID=$uniqueId, EarthquakeID=$earthquakeId');
    } catch (e) {
      debugPrint('❌ NotificationService: Error showing earthquake notification: $e');
    }
  }

  bool _verifySoundResource(String soundName, bool isAndroid) {
    // In production, this would check if the resource exists
    // For now, just log for debugging
    debugPrint('Verifying ${isAndroid ? "Android" : "iOS"} sound: $soundName');
    return true;
  }

  // ล้างการแจ้งเตือนทั้งหมด
  Future<void> clearAllNotifications() async {
    await notificationsPlugin.cancelAll();
    debugPrint('All notifications cleared');
  }
  
  // Diagnostic method to check notification system
  Future<Map<String, dynamic>> runNotificationDiagnostics() async {
    Map<String, dynamic> diagnosticResults = {};
    
    debugPrint('🔍 Running notification diagnostics...');
    
    // Check permissions
    bool permissionsGranted = await checkPermissions();
    diagnosticResults['permissionsGranted'] = permissionsGranted;
    debugPrint('📱 Notification permissions granted: $permissionsGranted');
    
    // Check Android-specific things
    if (Platform.isAndroid) {
      try {
        // Check if channels exist
        final androidPlugin = notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
                
        if (androidPlugin != null) {
          List<AndroidNotificationChannel>? channels = 
              await androidPlugin.getNotificationChannels();
          
          diagnosticResults['channelsCount'] = channels?.length ?? 0;
          List<String> channelIds = channels?.map((c) => c.id).toList() ?? [];
          diagnosticResults['channelIds'] = channelIds;
          
          debugPrint('📲 Android notification channels: ${channels?.length ?? 0}');
          debugPrint('📲 Channel IDs: ${channelIds.join(', ')}');
          
          // Check if our required channels exist
          bool hasEarthquakeChannel = channelIds.contains(earthquakeChannelId);
          // bool hasTestChannel = channelIds.contains(testChannelId);
          
          diagnosticResults['hasEarthquakeChannel'] = hasEarthquakeChannel;
          // diagnosticResults['hasTestChannel'] = hasTestChannel;
          
          debugPrint('📲 Has earthquake channel: $hasEarthquakeChannel');
          // debugPrint('📲 Has test channel: $hasTestChannel');
          
          // List sound files that should be available
          List<String> expectedSoundFiles = [_defaultAndroidSound].map((s) => '$s.mp3').toList();
          diagnosticResults['expectedSoundFiles'] = expectedSoundFiles;
          debugPrint('🔊 Expected sound files: ${expectedSoundFiles.join(', ')}');
        }
      } catch (e) {
        debugPrint('❌ Error checking Android notification channels: $e');
        diagnosticResults['androidChannelError'] = e.toString();
      }
    }
    
    // Check iOS-specific things
    if (Platform.isIOS) {
      try {
        final iosPlugin = notificationsPlugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        
        if (iosPlugin != null) {
          final settings = await iosPlugin.getNotificationAppLaunchDetails();
          diagnosticResults['iosLaunchedFromNotification'] = 
              settings?.notificationResponse != null;
          
          // List expected sound files
          List<String> expectedSoundFiles = [_defaultIOSSound].toList();
          diagnosticResults['iosExpectedSoundFiles'] = expectedSoundFiles;
          debugPrint('🔊 iOS expected sound files: ${expectedSoundFiles.join(', ')}');
        }
      } catch (e) {
        debugPrint('❌ Error checking iOS notification settings: $e');
        diagnosticResults['iosSettingsError'] = e.toString();
      }
    }
    
    return diagnosticResults;
  }

  // Add a method to verify sound file configurations
  Future<Map<String, dynamic>> checkSoundFilesConfiguration() async {
    Map<String, dynamic> results = {};
    
    try {
      debugPrint('📱 Checking sound file configuration...');
      
      // For iOS, list all available sound files in the map
      if (Platform.isIOS) {
        debugPrint('📱 iOS sound configuration:');
        debugPrint('Sound files expected in bundle:');
        for (var entry in {_defaultIOSSound: _defaultIOSSound}.entries) {
          debugPrint('- ${entry.key}: ${entry.value}');
        }
        results['iosSoundFiles'] = [_defaultIOSSound];
      }
      
      // For Android, list all available sound files in the map
      if (Platform.isAndroid) {
        debugPrint('📱 Android sound configuration:');
        debugPrint('Sound files expected in raw resources:');
        for (var entry in {_defaultAndroidSound: _defaultAndroidSound}.entries) {
          debugPrint('- ${entry.key}: ${entry.value}.mp3');
        }
        results['androidSoundFiles'] = [_defaultAndroidSound];
      }
      
      // Test a notification with normal sounds
      debugPrint('📱 Testing notification with different sounds...');
      List<String> testSounds = ['alarm', 'siren', 'warning'];
      for (var sound in testSounds) {
        await showEarthquakeNotification(
          title: 'ทดสอบเสียง: $sound',
          body: 'ทดสอบเสียงแจ้งเตือนปกติ: $sound',
          sound: sound,
        );
        await Future.delayed(const Duration(milliseconds: 800));
      }
      
      results['testSent'] = true;
    } catch (e) {
      debugPrint('❌ Error checking sound configuration: $e');
      results['error'] = e.toString();
      results['testSent'] = false;
    }
    
    return results;
  }

  // ตรวจสอบว่าแผ่นดินไหวได้รับการแจ้งเตือนไปแล้วหรือไม่
  Future<bool> hasEarthquakeBeenNotified(String quakeId) async {
    try {
      // ตรวจสอบว่า ID เป็นค่าว่างหรือไม่
      if (quakeId.isEmpty || quakeId == 'unknown' || quakeId == 'unknown_id') {
        debugPrint('🔍 NotificationService: Empty or unknown earthquake ID, returning false');
        return false;
      }
      
      // เตรียมรูปแบบ ID ทั้งหมดที่เป็นไปได้สำหรับตรวจสอบ
      List<String> possibleIds = [quakeId];
      
      // เพิ่มรูปแบบ ID ที่อาจมี prefix 'ak' (พบบ่อยใน iOS แต่ใช้ตรวจสอบทุก platform)
      if (quakeId.startsWith('ak')) {
        possibleIds.add(quakeId.substring(2)); // แบบไม่มี prefix
      } else {
        possibleIds.add('ak$quakeId'); // แบบมี prefix
      }
      
      // เพิ่มรูปแบบ ID ที่อาจมี prefix 'fcm_' (ใช้ใน FCMService)
      if (quakeId.startsWith('fcm_')) {
        possibleIds.add(quakeId.substring(4)); // แบบไม่มี prefix
      } else {
        possibleIds.add('fcm_$quakeId'); // แบบมี prefix
      }
      
      // เช็คทุกรูปแบบกับเงื่อนไขทุกอย่าง
      for (final id in possibleIds) {
        // (1) ตรวจสอบจากหน่วยความจำก่อน (การแจ้งเตือนภายในเซสชัน)
        if (_displayedEarthquakes.contains(id) || _recentNotificationIds.contains(id)) {
          debugPrint('🔍 NotificationService: Earthquake $id found in memory notification cache');
          return true;
        }
        
        // (2) ตรวจสอบจาก ID-based timestamp
        if (_lastNotificationTimeByID.containsKey(id)) {
          final lastTime = _lastNotificationTimeByID[id]!;
          final now = DateTime.now();
          final difference = now.difference(lastTime);
          
          // ถ้าเพิ่งแจ้งเตือนไปไม่เกิน 30 วินาที ให้ถือว่าแจ้งเตือนแล้ว
          if (difference.inSeconds < 30) {
            debugPrint('🔍 NotificationService: Earthquake $id notified ${difference.inSeconds}s ago (memory timestamp)');
            return true;
          }
        }
      }
      
      // (3) ตรวจสอบจาก SharedPreferences (การแจ้งเตือนถาวร)
      final prefs = await SharedPreferences.getInstance();
      
      // ตรวจสอบทุกรูปแบบ ID
      for (final id in possibleIds) {
        // ตรวจสอบข้อมูลจาก FCM ที่ประมวลผลไปแล้ว
        final fcmProcessed = prefs.getString('processed_fcm_$id');
        if (fcmProcessed != null) {
          try {
            final processedTime = DateTime.parse(fcmProcessed);
            final now = DateTime.now();
            final difference = now.difference(processedTime);
            
            // ถ้าเพิ่งประมวลผลภายใน 6 ชั่วโมง
            if (difference.inHours < 6) {
              debugPrint('🔍 NotificationService: Earthquake $id was processed by FCM ${difference.inMinutes}m ago');
              _displayedEarthquakes.add(id); // เก็บในแคชเพื่อการตรวจสอบครั้งต่อไป
              return true;
            }
          } catch (e) {
            debugPrint('❌ NotificationService: Error parsing FCM processed timestamp: $e');
          }
        }
        
        // ตรวจสอบด้วยหลายคีย์ที่เป็นไปได้
        bool directResult = false;
        bool platformResult = false;
        bool flutterResult = false;
        bool fcmResult = false;
        
        // ป้องกัน type cast exception โดยตรวจสอบประเภทข้อมูลก่อน
        try {
          final dirValue = prefs.get('notified_$id');
          directResult = dirValue is bool ? dirValue : (dirValue is String ? dirValue.toLowerCase() == 'true' : false);
          
          final platValue = prefs.get('${Platform.isIOS ? 'ios' : 'android'}_notification_$id');
          platformResult = platValue is bool ? platValue : (platValue is String ? platValue.toLowerCase() == 'true' : false);
          
          final flutValue = prefs.get('flutter_notification_$id');
          flutterResult = flutValue is bool ? flutValue : (flutValue is String ? flutValue.toLowerCase() == 'true' : false);
          
          final fcmValue = prefs.get('fcm_notification_$id');
          fcmResult = fcmValue is bool ? fcmValue : (fcmValue is String ? fcmValue.toLowerCase() == 'true' : false);
        } catch (e) {
          debugPrint('❌ NotificationService: Error checking notification flags: $e');
        }
        
        // ตรวจสอบคีย์ใหม่
        final newFormatResult = prefs.getString('earthquake_notified_$id') != null;
        
        // เพิ่มการตรวจสอบ timestamp จาก SharedPreferences
        final notifiedTimeStr = prefs.getString('notified_time_$id');
        bool timestampCheck = false;
        
        if (notifiedTimeStr != null) {
          try {
            final notifiedTime = DateTime.parse(notifiedTimeStr);
            final now = DateTime.now();
            final difference = now.difference(notifiedTime);
            
            // ถ้าเพิ่งแจ้งเตือนภายใน 6 ชั่วโมง
            if (difference.inHours < 6) {
              debugPrint('🔍 NotificationService: Earthquake $id notified ${difference.inMinutes}m ago (shared prefs timestamp)');
              timestampCheck = true;
            }
          } catch (e) {
            debugPrint('❌ NotificationService: Error parsing notification timestamp: $e');
          }
        }
        
        // ตรวจสอบเพิ่มเติมสำหรับรูปแบบที่เกี่ยวข้องกับ iOS
        final iosRawFormat = prefs.getBool('ios_raw_notification_${id}') ?? false;
        
        final result = directResult || platformResult || flutterResult || fcmResult || 
                       timestampCheck || newFormatResult || iosRawFormat;
        
        if (result) {
          // เก็บผลลัพธ์ไว้ในหน่วยความจำเพื่อลดการอ่าน SharedPreferences ในครั้งถัดไป
          _displayedEarthquakes.add(id);
          
          // บันทึก quakeId ต้นฉบับด้วย
          if (id != quakeId) {
            _displayedEarthquakes.add(quakeId);
          }
          
          // ลบ entry เก่าถ้ามีข้อมูลมากเกินไป
          if (_displayedEarthquakes.length > 200) {
            // ลบข้อมูลเก่าทั้งหมดแล้วเก็บแค่รายการปัจจุบัน
            _displayedEarthquakes.clear();
            _displayedEarthquakes.add(id);
            _displayedEarthquakes.add(quakeId);
            debugPrint('⚠️ NotificationService: Reset notification cache due to size limit, keeping only current IDs');
          }
          
          return true;
        }
      }
      
      // ไม่พบการแจ้งเตือนสำหรับทุกรูปแบบ ID
      return false;
    } catch (e) {
      debugPrint('❌ NotificationService: Error checking earthquake notification status: $e');
      return false;
    }
  }
  
  // ปรับปรุงเมธอด markEarthquakeAsNotified
  Future<void> markEarthquakeAsNotified(String earthquakeId) async {
    try {
      // ตรวจสอบว่า ID เป็นค่าว่างหรือไม่
      if (earthquakeId.isEmpty || earthquakeId == 'unknown' || earthquakeId == 'unknown_id') {
        debugPrint('⚠️ NotificationService: Cannot mark empty or unknown earthquake ID as notified');
        return;
      }
      
      // เตรียมรูปแบบ ID ทั้งหมดที่เป็นไปได้สำหรับบันทึก
      List<String> possibleIds = [earthquakeId];
      
      // เพิ่มรูปแบบ ID ที่อาจมี prefix 'ak' (พบบ่อยใน iOS)
      if (earthquakeId.startsWith('ak')) {
        possibleIds.add(earthquakeId.substring(2)); // แบบไม่มี prefix
      } else {
        possibleIds.add('ak$earthquakeId'); // แบบมี prefix
      }
      
      // เพิ่มรูปแบบ ID ที่อาจมี prefix 'fcm_' (ใช้ใน FCMService)
      if (earthquakeId.startsWith('fcm_')) {
        possibleIds.add(earthquakeId.substring(4)); // แบบไม่มี prefix
      } else {
        possibleIds.add('fcm_$earthquakeId'); // แบบมี prefix
      }
      
      // เพิ่มเข้าไปใน cache ในหน่วยความจำสำหรับทุก ID
      for (final id in possibleIds) {
        _displayedEarthquakes.add(id);
        _lastNotificationTimeByID[id] = DateTime.now();
      }
      
      // บันทึกเวลาปัจจุบัน
      final now = DateTime.now().toIso8601String();
      
      // บันทึกลงใน SharedPreferences ทุกรูปแบบที่เป็นไปได้เพื่อป้องกันการซ้ำซ้อน
      final prefs = await SharedPreferences.getInstance();
      
      // บันทึกทุกรูปแบบ ID
      for (final id in possibleIds) {
        // รูปแบบใหม่
        await prefs.setString('earthquake_notified_$id', now);
        
        // รูปแบบเก่า
        await prefs.setBool('notified_$id', true);
        await prefs.setString('notified_time_$id', now);
        
        // บันทึกตาม platform
        final platformKey = '${Platform.isIOS ? 'ios' : 'android'}_notification_$id';
        await prefs.setBool(platformKey, true);
        await prefs.setString('${platformKey}_time', now);
        
        // เพิ่มรูปแบบพิเศษสำหรับ iOS
        if (Platform.isIOS) {
          await prefs.setBool('ios_raw_notification_$id', true);
          await prefs.setString('ios_raw_notification_${id}_time', now);
        }
        
        // บันทึกแบบ Flutter local notification
        await prefs.setBool('flutter_notification_$id', true);
        
        // บันทึกแบบ FCM
        await prefs.setBool('fcm_notification_$id', true);
        await prefs.setString('fcm_notification_${id}_time', now);
        
        // บันทึกใน FCM processed key
        await prefs.setString('processed_fcm_$id', now);
      }
      
      debugPrint('✓ NotificationService: Marked earthquake $earthquakeId (and variants) as notified (ALL FORMATS)');
    } catch (e) {
      debugPrint('❌ NotificationService: Error marking earthquake as notified: $e');
    }
  }

  // ตรวจสอบสถานะของไฟล์เสียง Android ใน resources
  Future<Map<String, bool>> _checkAndroidSoundResources() async {
    // ใช้สำหรับตรวจสอบว่าไฟล์เสียงมีอยู่จริงหรือไม่
    final Map<String, bool> results = {};
    
    if (!Platform.isAndroid) {
      return results; // ไม่ต้องตรวจสอบหากไม่ใช่ Android
    }
    
    try {
      // ตรวจสอบการมีอยู่ของไฟล์เสียงในแอพ
      // ในทางปฏิบัติควรใช้ MetadataRetriever หรือ Resources API ของ Android 
      // เนื่องจากเรากำลังอยู่ในบริบทของ Flutter เราจะทำการตรวจสอบเบื้องต้นโดยใช้ 
      // AndroidFlutterLocalNotificationsPlugin
      
      final androidPlugin = notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
          >();
      
      if (androidPlugin != null) {
        debugPrint('🔍 Checking Android sound resources...');
        
        // วนตรวจสอบเสียงทั้งหมด
        for (final entry in {_defaultAndroidSound: _defaultAndroidSound}.entries) {
          final soundName = entry.key;
          
          // ในทางปฏิบัติเราต้องใช้ AssetManager ของ Android เพื่อตรวจสอบจริงๆ
          // แต่เราทำการจำลองการทดสอบโดยสมมติว่าไฟล์มีอยู่ตามที่คาดหวัง
          
          results[soundName] = true;
          debugPrint('🔊 Android sound $soundName.mp3 should be available in raw resources');
        }
        
        // แสดงคำเตือนหากมีเสียงที่ไม่พบ
        final missingFiles = results.entries.where((entry) => !entry.value).toList();
        if (missingFiles.isNotEmpty) {
          debugPrint('⚠️ Some Android sound files might be missing: ${missingFiles.map((e) => "${e.key}.mp3").join(", ")}');
        } else {
          debugPrint('✅ All Android sound files seem to be available');
        }
      } else {
        debugPrint('❌ Unable to check Android sounds: AndroidFlutterLocalNotificationsPlugin not available');
      }
    } catch (e) {
      debugPrint('❌ Error checking Android sound resources: $e');
    }
    
    return results;
  }

  // จัดการการคลิกที่การแจ้งเตือน
  void _handleNotificationTap(NotificationResponse response) {
    try {
      debugPrint('Notification clicked: ID=${response.id}, payload=${response.payload}');
      
      // ดึงข้อมูลจาก payload (ถ้ามี)
      if (response.payload != null && response.payload!.isNotEmpty) {
        try {
          final data = json.decode(response.payload!) as Map<String, dynamic>;
          // ตรวจสอบว่าเป็นการแจ้งเตือนแผ่นดินไหวหรือไม่
          if (data.containsKey('id') && data.containsKey('magnitude')) {
            debugPrint('Earthquake notification tapped: ID=${data['id']}, magnitude=${data['magnitude']}');
            
            // อาจจะเพิ่มการทำงานเพิ่มเติมเมื่อผู้ใช้แตะที่การแจ้งเตือนได้ที่นี่
            // เช่น เปิดหน้าแสดงรายละเอียดแผ่นดินไหว
          }
        } catch (e) {
          debugPrint('Error parsing notification payload: $e');
        }
      }
    } catch (e) {
      debugPrint('Error handling notification tap: $e');
    }
  }

  // เพิ่มเมธอดโหลดข้อมูลแผ่นดินไหวที่แจ้งเตือนแล้วจาก SharedPreferences
  Future<void> _loadNotifiedEarthquakesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // โหลดข้อมูลจาก SharedPreferences
      final notifiedKeys = prefs.getKeys()
          .where((key) => key.startsWith('notified_'))
          .toList();
          
      // เคลียร์ข้อมูลเก่าก่อน
      _displayedEarthquakes.clear();
      _recentNotificationIds.clear();
      
      // บันทึกค่าลงใน Set ที่ใช้ในหน่วยความจำ
      for (final key in notifiedKeys) {
        // ป้องกัน type cast exception โดยตรวจสอบประเภทข้อมูลก่อน
        bool isNotified = false;
        try {
          final value = prefs.get(key);
          isNotified = value is bool ? value : (value is String ? value.toLowerCase() == 'true' : false);
        } catch (e) {
          debugPrint('Error checking notification flag for $key: $e');
          continue; // ข้ามไปยัง key ถัดไป
        }
        
        if (isNotified) {
          final earthquakeId = key.replaceFirst('notified_', '');
          _displayedEarthquakes.add(earthquakeId);
          _recentNotificationIds.add(earthquakeId);
          
          // โหลดเวลาล่าสุดที่แจ้งเตือน
          final timeKey = '${key}_time';
          final timeStr = prefs.getString(timeKey);
          if (timeStr != null) {
            try {
              final notifTime = DateTime.parse(timeStr);
              _lastNotificationTimeByID[earthquakeId] = notifTime;
            } catch (e) {
              debugPrint('Error parsing notification time for $earthquakeId: $e');
            }
          }
        }
      }
      
      debugPrint('Loaded ${_displayedEarthquakes.length} previously notified earthquakes from SharedPreferences');
    } catch (e) {
      debugPrint('Error loading notified earthquakes from SharedPreferences: $e');
    }
  }
  
  // ลบข้อมูลการแจ้งเตือนทั้งหมด
  Future<void> clearAllNotificationData() async {
    try {
      // ลบข้อมูลในหน่วยความจำ
      _displayedEarthquakes.clear();
      _recentNotificationIds.clear();
      _lastNotificationTimeByID.clear();
      
      // ลบข้อมูลใน SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final notificationKeys = prefs.getKeys()
          .where((key) => key.startsWith('notified_') || 
                           key.startsWith('ios_notification_') || 
                           key.startsWith('android_notification_') ||
                           key.startsWith('flutter_notification_'))
          .toList();
      
      for (final key in notificationKeys) {
        await prefs.remove(key);
      }
      
      // ยกเลิกการแจ้งเตือนทั้งหมดที่ปรากฏอยู่
      await notificationsPlugin.cancelAll();
      
      debugPrint('Cleared all notification data - ${notificationKeys.length} keys removed');
    } catch (e) {
      debugPrint('Error clearing notification data: $e');
    }
  }
  
  // เพิ่มเมธอดสำหรับตรวจสอบการแจ้งเตือนถี่เกินไป
  bool _isNotificationRateLimited() {
    if (_lastNotificationTime == null) return false;
    
    final now = DateTime.now();
    final difference = now.difference(_lastNotificationTime!);
    
    // ป้องกันการแจ้งเตือนถี่เกินไป (ห่างกันน้อยกว่า 3 วินาที)
    if (difference.inSeconds < 3) {
      debugPrint('⚠️ RATE LIMITED: Last notification was only ${difference.inSeconds}s ago');
      return true;
    }
    
    return false;
  }

  // สร้าง notification ID ที่ไม่ซ้ำกัน
  int _generateNotificationId(String? earthquakeId) {
    if (earthquakeId == null || earthquakeId.isEmpty) {
      // ใช้ timestamp ถ้าไม่มี earthquake ID
      return DateTime.now().millisecondsSinceEpoch.remainder(100000);
    } else {
      // ใช้ hashCode ของ earthquake ID เพื่อให้ ID เหมือนเดิมสำหรับแผ่นดินไหวเดียวกัน
      return earthquakeId.hashCode.abs().remainder(100000);
    }
  }

  // เพิ่มปุ่มสำหรับล้างประวัติการแจ้งเตือนในหน้า settings
  Future<bool> resetNotificationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // ค้นหา keys ทั้งหมดที่เกี่ยวกับการแจ้งเตือน
      final keys = prefs.getKeys();
      int count = 0;
      
      // ลบทุก key ที่เริ่มต้นด้วย notified_
      for (final key in keys) {
        if (key.startsWith('notified_')) {
          await prefs.remove(key);
          count++;
        }
      }
      
      debugPrint('Notification Service: ล้างประวัติการแจ้งเตือนแล้ว $count รายการ');
      return true;
    } catch (e) {
      debugPrint('Notification Service: เกิดข้อผิดพลาดในการล้างประวัติการแจ้งเตือน: $e');
      return false;
    }
  }
}