import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // Add import for TimeoutException
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

class ApiService {
  // ตั้งค่า base URL สำหรับการเชื่อมต่อกับเซิร์ฟเวอร์
  // เปลี่ยนเป็น URL ใหม่
  static const String _devBaseUrl = 'https://earthquake.softacular.net'; // URL ใหม่สำหรับการพัฒนา
  static const String _prodBaseUrl = 'https://earthquake.softacular.net'; // URL ใหม่สำหรับการผลิต

  static String get baseUrl {
    if (kDebugMode) {
      return _devBaseUrl;
    } else {
      return _prodBaseUrl;
    }
  }

  // ลงทะเบียน FCM Token กับเซิร์ฟเวอร์
  static Future<bool> registerToken(String token) async {
    try {
      // ดึง deviceId จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      
      // ถ้าไม่มี deviceId ให้ใช้ค่าเริ่มต้น
      deviceId ??= 'unknown_device';
      
      return await registerTokenWithServer(token, deviceId);
    } catch (e) {
      debugPrint('API: Failed to register token: $e');
      return false;
    }
  }

  // ตรวจสอบว่า token ลงทะเบียนกับเซิร์ฟเวอร์แล้วหรือไม่
  static Future<bool> verifyToken(String token) async {
    try {
      // ดึง deviceId จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? deviceId = prefs.getString('device_id');
      
      // ถ้าไม่มี deviceId ให้ใช้ค่าเริ่มต้น
      deviceId ??= 'unknown_device';
      
      final url = Uri.parse('$baseUrl/verify-token');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'deviceId': deviceId,
        }),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final bool isRegistered = data['registered'] ?? false;
        debugPrint('API: Token verification result: $isRegistered for device: $deviceId');
        return isRegistered;
      } else {
        debugPrint('API: Failed to verify token: HTTP ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('API: Exception during token verification: $e');
      return false;
    }
  }

  // Register token with explicit device ID
  static Future<bool> registerTokenWithServer(String token, String deviceId) async {
    try {
      final url = Uri.parse('$baseUrl/register-token');
      
      // บันทึก device ID ลงใน SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
      
      debugPrint('API: Registering token with device ID: $deviceId');
      
      // เพิ่ม deviceId ในการลงทะเบียน token
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'deviceId': deviceId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout เป็น 10 วินาที
      
      if (response.statusCode == 200) {
        debugPrint('API: Token registered successfully with device ID: $deviceId');
        
        // ตรวจสอบว่า token ลงทะเบียนถูกต้องหรือไม่
        try {
          final verifyResponse = await verifyToken(token);
          if (verifyResponse) {
            debugPrint('API: Verified token registration success for device: $deviceId');
            
            // บันทึกข้อมูลการลงทะเบียน
            await prefs.setString('registered_token_device_id', deviceId);
            await prefs.setString('registered_token', token);
            await prefs.setString('token_registration_time', DateTime.now().toIso8601String());
            return true;
          } else {
            debugPrint('⚠️ API: Token verification failed after registration for device: $deviceId');
            // พยายามลงทะเบียนอีกครั้งด้วยวิธีการอื่น
            await _retryTokenRegistration(token, deviceId);
            return false;
          }
        } catch (e) {
          debugPrint('⚠️ API: Error verifying token after registration: $e');
          return true; // ถือว่าสำเร็จเพราะได้ 200 แล้ว แต่การยืนยันล้มเหลว
        }
      } else {
        debugPrint('API: Failed to register token: HTTP ${response.statusCode}');
        
        // พยายามลงทะเบียนอีกครั้งด้วยวิธีการอื่น
        return await _retryTokenRegistration(token, deviceId);
      }
    } catch (e) {
      debugPrint('API: Exception during token registration: $e');
      return false;
    }
  }
  
  // เมธอดที่ใช้พยายามลงทะเบียน token อีกครั้งด้วยวิธีการอื่น
  static Future<bool> _retryTokenRegistration(String token, String deviceId) async {
    try {
      debugPrint('API: Retrying token registration with alternative method');
      
      // ใช้การลงทะเบียนแบบแยกส่วน
      final url = Uri.parse('$baseUrl/register-token-alternative');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'deviceId': deviceId,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'forceUpdate': true, // บังคับให้อัพเดท
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        debugPrint('API: Alternative registration method successful');
        return true;
      } else {
        // ลองใช้วิธีการเดิมแต่ใส่พารามิเตอร์เพิ่มเติม
        debugPrint('API: Trying one last registration method');
        
        final lastTryUrl = Uri.parse('$baseUrl/register-token?deviceId=$deviceId&force=true');
        
        final lastResponse = await http.post(
          lastTryUrl,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'token': token,
            'deviceId': deviceId,
            'platform': Platform.isIOS ? 'ios' : 'android',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        ).timeout(const Duration(seconds: 10));
        
        return lastResponse.statusCode == 200;
      }
    } catch (e) {
      debugPrint('API: Alternative registration method also failed: $e');
      return false;
    }
  }

  // ตั้งค่าภูมิภาคที่ต้องการติดตาม
  static Future<Map<String, dynamic>?> setRegion(String region) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      final payload = {
        'region': region,
      };
      
      if (deviceId != null) {
        payload['deviceId'] = deviceId;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/set-region'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Region set successfully: $region');
        await _saveRegion(region); // บันทึกภูมิภาคลงใน SharedPreferences
        return data;
      } else {
        debugPrint('Failed to set region: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error setting region: $e');
      return null;
    }
  }

  // เปิด/ปิดการกรองตามภูมิภาค
  static Future<Map<String, dynamic>?> toggleRegionFilter(bool enabled) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        debugPrint('Error: No device ID available when toggling region filter');
        return null;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/toggle-region-filter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'enabled': enabled,
          'deviceId': deviceId
        }),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Region filtering ${enabled ? 'enabled' : 'disabled'}');
        await _saveRegionFilterEnabled(enabled);
        return data;
      } else {
        debugPrint('Failed to toggle region filter: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error toggling region filter: $e');
      return null;
    }
  }

  // ส่งการแจ้งเตือนทดสอบ
   // ดึงข้อมูลการตั้งค่าจากเซิร์ฟเวอร์
  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      // ดึง deviceId จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        debugPrint('Error: No device ID available when fetching settings');
        return null;
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/settings?deviceId=$deviceId'),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout 10 วินาที

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Server settings retrieved: ${data['settings']}');
        return data;
      } else {
        debugPrint('Failed to get server settings: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting server settings: $e');
      return null;
    }
  }

  // ตรวจสอบแผ่นดินไหวทันทีและเรียกดูข้อมูล
  static Future<Map<String, dynamic>?> checkEarthquakes() async {
    try {
      // ดึง deviceId จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      final response = await http.get(
        Uri.parse('$baseUrl/check-earthquakes' + (deviceId != null ? '?deviceId=$deviceId' : '')),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Earthquake check completed: ${data['earthquakes'].length} earthquakes found');
        return data;
      } else {
        debugPrint('Failed to check earthquakes: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error checking earthquakes: $e');
      return null;
    }
  }

  // รีเซ็ตประวัติการแจ้งเตือน
  static Future<bool> resetNotifications() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-notifications'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        debugPrint('Notification history reset successfully');
        return true;
      } else {
        debugPrint('Failed to reset notification history: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error resetting notification history: $e');
      return false;
    }
  }

  // ลบ FCM Token จากเซิร์ฟเวอร์
  static Future<bool> removeToken(String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/token/$token'),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM Token removed successfully from server');
        return true;
      } else {
        debugPrint('Failed to remove FCM token: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error removing FCM token: $e');
      return false;
    }
  }

  // บันทึกภูมิภาคที่เลือกใน SharedPreferences
  static Future<void> _saveRegion(String region) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('serverRegion', region);
    } catch (e) {
      debugPrint('Error saving region setting: $e');
    }
  }

  // บันทึกสถานะการกรองภูมิภาคใน SharedPreferences
  static Future<void> _saveRegionFilterEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serverRegionFilterEnabled', enabled);
    } catch (e) {
      debugPrint('Error saving region filter setting: $e');
    }
  }

  // โหลดภูมิภาคที่เลือกจาก SharedPreferences
  static Future<String?> getSelectedRegion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('serverRegion');
    } catch (e) {
      debugPrint('Error loading region setting: $e');
      return null;
    }
  }

  // โหลดสถานะการกรองภูมิภาคจาก SharedPreferences
  static Future<bool> getRegionFilterEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('serverRegionFilterEnabled') ?? true;
    } catch (e) {
      debugPrint('Error loading region filter setting: $e');
      return true;
    }
  }

  // ตั้งค่าขนาดแผ่นดินไหวขั้นต่ำ
  static Future<Map<String, dynamic>?> setMinMagnitude(double magnitude) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        debugPrint('Error: No device ID available when setting minimum magnitude');
        return null;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/set-min-magnitude'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'magnitude': magnitude,
          'deviceId': deviceId
        }),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Minimum magnitude set successfully: $magnitude');
        await _saveMinMagnitude(magnitude);
        return data;
      } else {
        debugPrint('Failed to set minimum magnitude: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error setting minimum magnitude: $e');
      return null;
    }
  }

  // เปิด/ปิดการกรองตามขนาดแผ่นดินไหว
  static Future<Map<String, dynamic>?> toggleMagnitudeFilter(bool enabled) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        debugPrint('Error: No device ID available when toggling magnitude filter');
        return null;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/toggle-magnitude-filter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'enabled': enabled,
          'deviceId': deviceId
        }),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Magnitude filtering ${enabled ? 'enabled' : 'disabled'}');
        await _saveMagnitudeFilterEnabled(enabled);
        return data;
      } else {
        debugPrint('Failed to toggle magnitude filter: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error toggling magnitude filter: $e');
      return null;
    }
  }
  
  // บันทึกขนาดแผ่นดินไหวขั้นต่ำใน SharedPreferences
  static Future<void> _saveMinMagnitude(double magnitude) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('serverMinMagnitude', magnitude);
    } catch (e) {
      debugPrint('Error saving minimum magnitude setting: $e');
    }
  }

  // บันทึกสถานะการกรองขนาดแผ่นดินไหวใน SharedPreferences
  static Future<void> _saveMagnitudeFilterEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('serverMagnitudeFilterEnabled', enabled);
    } catch (e) {
      debugPrint('Error saving magnitude filter setting: $e');
    }
  }
  
  // โหลดขนาดแผ่นดินไหวขั้นต่ำจาก SharedPreferences
  static Future<double?> getMinMagnitude() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('serverMinMagnitude');
    } catch (e) {
      debugPrint('Error loading minimum magnitude setting: $e');
      return null;
    }
  }

  // โหลดสถานะการกรองขนาดแผ่นดินไหวจาก SharedPreferences
  static Future<bool> getMagnitudeFilterEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('serverMagnitudeFilterEnabled') ?? true;
    } catch (e) {
      debugPrint('Error loading magnitude filter setting: $e');
      return true;
    }
  }

  // ตั้งค่าการกรองตามระยะทาง
  static Future<Map<String, dynamic>?> setLocationFilter({
    required double latitude,
    required double longitude,
    required double maxDistanceKm,
    required bool enabled,
  }) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      if (deviceId == null) {
        debugPrint('Error: No device ID available when setting location filter');
        return null;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/set-location-filter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'latitude': latitude,
          'longitude': longitude,
          'maxDistanceKm': maxDistanceKm,
          'enabled': enabled,
          'deviceId': deviceId
        }),
      ).timeout(const Duration(seconds: 10)); // เพิ่ม timeout

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Location filter set successfully: lat=$latitude, lng=$longitude, distance=${maxDistanceKm}km, enabled=$enabled');
        
        // บันทึกการตั้งค่าลงใน SharedPreferences
        await _saveLocationFilter(latitude, longitude, maxDistanceKm, enabled);
        return data;
      } else {
        debugPrint('Failed to set location filter: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error setting location filter: $e');
      return null;
    }
  }

  // ทดสอบการคำนวณระยะทาง
  static Future<Map<String, dynamic>?> testDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) async {
    try {
      // Get device ID
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');
      
      final payload = <String, dynamic>{
        'lat1': lat1,
        'lon1': lon1,
        'lat2': lat2,
        'lon2': lon2,
      };
      
      if (deviceId != null) {
        payload['deviceId'] = deviceId;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/test-distance'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('Distance calculation result: ${data['distanceKm']}');
        return data;
      } else {
        debugPrint('Failed to calculate distance: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error calculating distance: $e');
      return null;
    }
  }

  // บันทึกการตั้งค่าการกรองตามระยะทางใน SharedPreferences
  static Future<void> _saveLocationFilter(double latitude, double longitude, double maxDistanceKm, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('userLatitude', latitude);
      await prefs.setDouble('userLongitude', longitude);
      await prefs.setDouble('maxDistanceKm', maxDistanceKm);
      await prefs.setBool('distanceFilterEnabled', enabled);
    } catch (e) {
      debugPrint('Error saving location filter setting: $e');
    }
  }

  // โหลดการตั้งค่าการกรองตามระยะทางจาก SharedPreferences
  static Future<Map<String, dynamic>> getLocationFilterSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'userLatitude': prefs.getDouble('userLatitude'),
        'userLongitude': prefs.getDouble('userLongitude'),
        'maxDistanceKm': prefs.getDouble('maxDistanceKm') ?? 2000.0,
        'distanceFilterEnabled': prefs.getBool('distanceFilterEnabled') ?? false,
      };
    } catch (e) {
      debugPrint('Error loading location filter settings: $e');
      return {
        'userLatitude': null,
        'userLongitude': null,
        'maxDistanceKm': 2000.0,
        'distanceFilterEnabled': false,
      };
    }
  }

  // ตรวจสอบและลงทะเบียน FCM token กับเซิร์ฟเวอร์
  static Future<bool> verifyTokenRegistration() async {
    try {
      // ดึงข้อมูลการลงทะเบียนจาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final tokenRegistered = prefs.getBool('token_registration_success') ?? false;
      final token = prefs.getString('last_registered_token');
      final deviceId = prefs.getString('device_id');
      
      debugPrint('📝 Verifying FCM token registration...');
      debugPrint('📱 Device ID: $deviceId');
      debugPrint('🔑 Registered token: ${token != null ? "${token.substring(0, 10)}..." : "null"}');
      debugPrint('✅ Token registered (previous status): $tokenRegistered');
      
      // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์
      bool serverReachable = false;
      try {
        final testResponse = await http.get(
          Uri.parse('$baseUrl/tokens'),
        ).timeout(const Duration(seconds: 5));
        
        serverReachable = testResponse.statusCode == 200;
        debugPrint('📡 Server connection test: ${serverReachable ? "SUCCESS" : "FAILED"}');
      } catch (e) {
        debugPrint('❌ Server connection test failed: $e');
      }
      
      if (!serverReachable) {
        debugPrint('⚠️ Cannot reach server at $baseUrl - check server URL and network connection');
        return false;
      }
      
      // ดึง token ปัจจุบันจาก FirebaseMessaging
      final fcmToken = await FirebaseMessaging.instance.getToken();
        
      if (fcmToken != null) {
        debugPrint('🔑 Current FCM Token: ${fcmToken.substring(0, 10)}...');
          
        // เช็คว่า device ID มีค่าหรือไม่
        if (deviceId == null || deviceId.isEmpty) {
          debugPrint('⚠️ Device ID not found, cannot register token');
          return false;
        }
          
        // ลงทะเบียน token กับเซิร์ฟเวอร์ทุกครั้ง ไม่ว่าจะเคยลงทะเบียนไปแล้วหรือไม่
        debugPrint('🔄 Register/renew FCM token registration with server...');
        final success = await registerTokenWithServer(fcmToken, deviceId);
        debugPrint('📝 Token registration result: ${success ? "SUCCESS" : "FAILED"}');
          
        if (success) {
          // บันทึกสถานะการลงทะเบียนสำเร็จ
          await prefs.setBool('token_registration_success', true);
          await prefs.setString('last_registered_token', fcmToken);
          await prefs.setString('last_registration_time', DateTime.now().toIso8601String());
            
          // ดึงและบันทึกการตั้งค่าจากเซิร์ฟเวอร์
          try {
            final settings = await getSettings();
            if (settings != null && settings['settings'] != null) {
              debugPrint('⚙️ Received server settings: ${settings['settings']}');
            }
          } catch (e) {
            debugPrint('⚠️ Error fetching server settings: $e');
          }
            
          return true;
        } else {
          debugPrint('❌ Failed to register FCM token with server');
          return false;
        }
      } else {
        debugPrint('❌ Could not retrieve FCM token from Firebase');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error in verifyTokenRegistration: $e');
      return false;
    }
  }
  
  // ทดสอบการเชื่อมต่อกับเซิร์ฟเวอร์
  static Future<bool> testServerConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/tokens'),
      ).timeout(const Duration(seconds: 5));
      
      debugPrint('📡 Server connection test result: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Server connection test failed: $e');
      return false;
    }
  }

  // รีเซ็ตข้อมูลการลงทะเบียนใน SharedPreferences
  static Future<void> resetTokenRegistration() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('token_registration_success', false);
      await prefs.remove('last_registered_token');
      await prefs.remove('last_registration_time');
      
      debugPrint('🔄 FCM token registration has been reset');
      
      // ลงทะเบียน token ใหม่ทันที
      await verifyTokenRegistration();
    } catch (e) {
      debugPrint('❌ Error in resetTokenRegistration: $e');
    }
  }

  // ล้างประวัติการแจ้งเตือนสำหรับอุปกรณ์นี้
  static Future<bool> resetDeviceNotificationHistory(String? deviceId) async {
    try {
      if (deviceId == null || deviceId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString('device_id');
        
        if (deviceId == null) {
          debugPrint('❌ ไม่พบ device ID สำหรับล้างประวัติการแจ้งเตือน');
          return false;
        }
      }
      
      debugPrint('API: กำลังล้างประวัติการแจ้งเตือนสำหรับอุปกรณ์ $deviceId');
      
      // 1. ลบที่เซิร์ฟเวอร์
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/reset-device-notifications'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'deviceId': deviceId,
          }),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          debugPrint('✅ API: ล้างประวัติการแจ้งเตือนบนเซิร์ฟเวอร์สำหรับอุปกรณ์ $deviceId สำเร็จ');
        } else {
          debugPrint('⚠️ API: ล้างประวัติการแจ้งเตือนบนเซิร์ฟเวอร์ไม่สำเร็จ: ${response.body}');
        }
      } catch (e) {
        debugPrint('⚠️ API: ไม่สามารถติดต่อเซิร์ฟเวอร์เพื่อล้างประวัติการแจ้งเตือน: $e');
      }
      
      // 2. ล้างข้อมูลการแจ้งเตือนใน SharedPreferences ทุกกรณี
      debugPrint('API: กำลังล้างประวัติการแจ้งเตือนในอุปกรณ์');
      final prefs = await SharedPreferences.getInstance();
      
      // ลบ keys ที่ขึ้นต้นด้วย 'notified_'
      final keys = prefs.getKeys();
      int removedCount = 0;
      for (final key in keys) {
        if (key.startsWith('notified_')) {
          await prefs.remove(key);
          removedCount++;
        }
      }
      
      debugPrint('✅ API: ล้างประวัติการแจ้งเตือนในอุปกรณ์สำเร็จ (ลบไป $removedCount รายการ)');
      return true;
    } catch (e) {
      debugPrint('❌ API: เกิดข้อผิดพลาดในการล้างประวัติการแจ้งเตือน: $e');
      return false;
    }
  }
} 