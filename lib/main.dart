// lib/main.dart
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/fcm_service.dart';
import 'services/earthquake_service.dart';
import 'services/notification_service.dart';
import 'services/earthquake_probability_service.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';
import 'dart:convert';

// ไฟล์การตั้งค่า Firebase ที่ต้องสร้างโดยใช้ Firebase CLI
import 'firebase_options.dart';

// Function to diagnose iOS-specific notification issues
Future<void> diagnoseIOSNotifications() async {
  if (!Platform.isIOS) {
    debugPrint('⚠️ This function is only for iOS devices');
    return;
  }
  
  debugPrint('🔍 Starting iOS notification diagnostics...');
  
  try {
    // Check notification permissions
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.getNotificationSettings();
    
    debugPrint('📱 iOS Notification Authorization Status: ${settings.authorizationStatus}');
    
    // Check APNS token
    final apnsToken = await messaging.getAPNSToken();
    debugPrint('🔑 APNS Token: ${apnsToken ?? "None"}');
    
    // Check FCM token
    final fcmToken = await messaging.getToken();
    debugPrint('🔑 FCM Token: ${fcmToken ?? "None"}');
    
    // Check if sound files exist
    final notificationService = NotificationService();
    await notificationService.initialize();
    
    // Add this line to fix the undefined prefs error
    final prefs = await SharedPreferences.getInstance();
    
    // ตรวจสอบการเชื่อมต่อกับเซิร์ฟเวอร์โดยตรง
    debugPrint('🔄 Testing direct server connection...');
    final deviceId = prefs.getString('device_id');
    if (deviceId != null) {
      final result = await ApiService.checkEarthquakes();
      if (result != null) {
        debugPrint('✅ Server connection successful');
        debugPrint('📊 Server returned ${result['earthquakes']?.length ?? 0} earthquakes');
      } else {
        debugPrint('❌ ISSUE DETECTED: Could not connect to server');
        debugPrint('💡 SOLUTION: Check server status and internet connection');
      }
    } else {
      debugPrint('❌ ISSUE DETECTED: No device ID found');
      debugPrint('💡 SOLUTION: Reinstall app or clear app data to generate a new device ID');
    }
  } catch (e) {
    debugPrint('❌ Error during iOS notification diagnostics: $e');
  }
}

// Function to diagnose notification issues
Future<void> runNotificationDiagnostics() async {
  debugPrint('🔍 Starting comprehensive notification diagnostics...');
  
  try {
    // Run notification service diagnostics
    final notificationService = NotificationService();
    final notificationResults = await notificationService.runNotificationDiagnostics();
    
    // Run FCM diagnostics
    final fcmService = FCMService();
    final fcmResults = await fcmService.runFCMDiagnostics();
    
    // Check system settings
    if (Platform.isAndroid) {
      debugPrint('📱 For Android: Please check if battery optimization is disabled for this app');
      debugPrint('📱 For Android: Check notification permission in system settings');
    } else if (Platform.isIOS) {
      debugPrint('📱 For iOS: Check notification permission in system settings');
      debugPrint('📱 For iOS: Make sure Focus modes are not blocking notifications');
    }
    
    // Save diagnostic results to SharedPreferences for later review
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_notification_diagnostics', DateTime.now().toIso8601String());
    
    // Detailed permission information
    final permissionGranted = notificationResults['permissionsGranted'] ?? false;
    if (!permissionGranted) {
      debugPrint('❌ ISSUE DETECTED: Notification permissions are not granted');
      debugPrint('💡 SOLUTION: Open app settings to grant notification permission');
    } else {
      debugPrint('✅ Notification permissions are granted');
    }
    
    // Check FCM token and registration
    final hasToken = fcmResults['hasToken'] ?? false;
    final registrationSuccess = fcmResults['registrationSuccess'] ?? false;
    
    if (!hasToken) {
      debugPrint('❌ ISSUE DETECTED: No valid FCM token found');
      debugPrint('💡 SOLUTION: Check internet connection and Firebase configuration');
    } else if (!registrationSuccess) {
      debugPrint('❌ ISSUE DETECTED: FCM token not registered with server');
      debugPrint('💡 SOLUTION: Check server connection and try refreshing token');
    } else {
      debugPrint('✅ FCM token exists and is registered with server');
    }
    
    // Final summary
    debugPrint('📊 Notification diagnostics complete.');
    debugPrint(
      '📝 SUMMARY: Permissions: ${permissionGranted ? "✓" : "✗"}, '
      'FCM Token: ${hasToken ? "✓" : "✗"}, '
      'Registration: ${registrationSuccess ? "✓" : "✗"}'
    );
    
    // ตรวจสอบการเชื่อมต่อกับเซิร์ฟเวอร์โดยตรง
    debugPrint('🔄 Testing direct server connection...');
    final deviceId = prefs.getString('device_id');
    if (deviceId != null) {
      final result = await ApiService.checkEarthquakes();
      if (result != null) {
        debugPrint('✅ Server connection successful');
        debugPrint('📊 Server returned ${result['earthquakes']?.length ?? 0} earthquakes');
      } else {
        debugPrint('❌ ISSUE DETECTED: Could not connect to server');
        debugPrint('💡 SOLUTION: Check server status and internet connection');
      }
    } else {
      debugPrint('❌ ISSUE DETECTED: No device ID found');
      debugPrint('💡 SOLUTION: Reinstall app or clear app data to generate a new device ID');
    }
  } catch (e) {
    debugPrint('❌ Error during notification diagnostics: $e');
  }
}

// Moved outside the MyApp class to make it a top-level function
Future<void> initializeServices() async {
  if (kIsWeb) {
    // For web, we skip the native notification services
    debugPrint('Running on web platform - skipping native notifications setup');
    return;
  }
  
  try {
    // ตั้งค่า local notification service ก่อนเสมอ
    final notificationService = NotificationService();
    await notificationService.initialize();
    debugPrint('✅ Local notification service initialized');
    
    // ตั้งค่า Firebase Cloud Messaging (FCM)
    final fcmService = FCMService();
    await fcmService.initialize();
    debugPrint('✅ FCM service initialized');
    
    // ไม่ต้องใช้ delay อีกต่อไป FCM service จะจัดการเอง
    // await Future.delayed(const Duration(seconds: 2));
    
    // ใน iOS, เซ็ตค่า Firebase Message ไม่ให้แสดงการแจ้งเตือน (ใช้ Flutter Local Notifications เท่านั้น)
    if (Platform.isIOS) {
      debugPrint('📱 iOS detected - preventing duplicate notifications');
      
      // บันทึกการตั้งค่าเตือนซ้ำใน SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('prevent_ios_duplicate_notifications', true);
      
      // ปรับค่าพารามิเตอร์ลงทะเบียนเพื่อบอกว่าเราจะจัดการการแจ้งเตือนเอง
      try {
        final messaging = FirebaseMessaging.instance;
        // ขอสิทธิ์แจ้งเตือน
        await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          criticalAlert: true,
          provisional: false,
        );
        // แต่ทำให้ FCM รู้ว่าเราจะจัดการการแจ้งเตือนเอง
        await messaging.setForegroundNotificationPresentationOptions(
          alert: false,  // ไม่ต้องแสดงการแจ้งเตือนใน Foreground
          badge: true,
          sound: false,  // ไม่ต้องเล่นเสียงของ FCM 
        );
        debugPrint('✅ iOS FCM notification setup complete (notifications will be handled by Local Notifications)');
      } catch (e) {
        debugPrint('❌ Error setting up iOS notification options: $e');
      }
    }
    
    // ตรวจสอบการตั้งค่าจากการลงทะเบียนเดิม (ไม่ต้องลงทะเบียนใหม่)
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId != null) {
        debugPrint('📱 Using existing device ID: $deviceId');
        
        // ตรวจสอบว่ามีการลงทะเบียนซ้ำหรือไม่
        final isFirstRun = prefs.getBool('is_first_run') ?? true;
        if (isFirstRun) {
          debugPrint('📝 ครั้งแรกที่เปิดแอพ - ตรวจสอบแผ่นดินไหวกับเซิร์ฟเวอร์โดยตรง');
          
          // ตั้งค่าป้องกันการส่งแจ้งเตือนซ้ำเมื่อเปิดแอพครั้งแรก
          final preventDuplicateNotifications = true;
          await prefs.setBool('prevent_duplicate_notifications', preventDuplicateNotifications);
          debugPrint('⚠️ ตั้งค่าป้องกันการส่งแจ้งเตือนซ้ำเมื่อเปิดแอพครั้งแรก: $preventDuplicateNotifications');
          
          // ไม่ต้องรอให้เสร็จ ให้ทำงานเบื้องหลังได้
          ApiService.checkEarthquakes();
          await prefs.setBool('is_first_run', false);
        }
      } else {
        debugPrint('⚠️ No device ID found in preferences');
      }
    } catch (e) {
      debugPrint('❌ Non-critical error checking settings: $e');
    }
    
    // ล็อกเพื่อตรวจสอบการตั้งค่า
    debugPrint('✅ การตั้งค่าบริการสำเร็จ');
    if (Platform.isIOS) {
      debugPrint('📱 iOS: กำลังใช้ FlutterLocalNotifications สำหรับการแสดงการแจ้งเตือน');
    } else {
      debugPrint('📱 Android: กำลังใช้ทั้ง FCM และ FlutterLocalNotifications สำหรับการแจ้งเตือน');
    }
  } catch (e) {
    debugPrint('❌ เกิดข้อผิดพลาดในการตั้งค่าบริการ: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ตั้งค่าบริการแจ้งเตือนและ FCM
  await initializeServices();
  
  // สร้าง earthquake service
  final earthquakeService = EarthquakeService();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EarthquakeService()),
        Provider(create: (_) => EarthquakeProbabilityService()),
      ],
      child: MaterialApp(
        title: 'ไหวป่าว',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: Colors.red[700],
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
          useMaterial3: true,
          textTheme: GoogleFonts.promptTextTheme(
            Theme.of(context).textTheme,
          ),
          fontFamily: GoogleFonts.prompt().fontFamily,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}