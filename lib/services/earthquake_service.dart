// lib/services/earthquake_service.dart
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/earthquake.dart';
import 'dart:async';
import 'notification_service.dart';
import '../utils/country_helper.dart'; // Add import for CountryHelper
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

class EarthquakeService extends ChangeNotifier {
  List<Earthquake> _earthquakes = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdate;

  // เพิ่มตัวแปรสำหรับการตั้งค่าการแจ้งเตือน
  bool _notifyAllMagnitudes = true;
  double _minNotifyMagnitude = 0.1;
  bool _isNotificationEnabled = true;

  bool _isCriticalAlertEnabled = false;
  double _criticalMagnitudeThreshold = 6.0;
  
  // เพิ่มตัวแปรสำหรับการตั้งค่าเสียง
  bool _useCustomSounds = false;
  String _regularSound = 'default';
  String _criticalSound = 'critical_alert';
  
  // เพิ่มตัวแปรสำหรับเก็บพื้นที่ที่เลือก
  String? _selectedLocation; // สำหรับกรองข้อมูล
  String? _starredLocation; // สำหรับการติดดาว
  List<String> _availableLocations = [];
  
  // เพิ่มตัวแปรสำหรับการตั้งค่าความถี่ในการตรวจสอบ
  int _checkIntervalMinutes = 5; // ตรวจสอบทุก 5 นาที
  Timer? _checkTimer;

  // สร้าง Instance ของ NotificationService
  final NotificationService _notificationService = NotificationService();

  // เพิ่มตัวแปรสำหรับการกรองตามภูมิภาค
  String? _selectedRegion;

  List<Earthquake> get earthquakes => _earthquakes;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime? get lastUpdate => _lastUpdate;
  bool get notifyAllMagnitudes => _notifyAllMagnitudes;
  double get minNotifyMagnitude => _minNotifyMagnitude;
  bool get isNotificationEnabled => _isNotificationEnabled;
  int get checkIntervalMinutes => _checkIntervalMinutes;
  bool get isCriticalAlertEnabled => _isCriticalAlertEnabled;
  double get criticalMagnitudeThreshold => _criticalMagnitudeThreshold;
  
  // Getters for sound settings
  bool get useCustomSounds => _useCustomSounds;
  String get regularSound => _regularSound;
  String get criticalSound => _criticalSound;
  
  // Getters for location
  String? get selectedLocation => _selectedLocation;
  String? get starredLocation => _starredLocation;
  List<String> get availableLocations => _availableLocations;

  // คำขอ API กำลังดำเนินการ
  bool _fetchInProgress = false;

  String? get selectedRegion => _selectedRegion;

  // Constructor
  EarthquakeService() {
    debugPrint('EarthquakeService initialized');
    //_loadSettings();
    _initializeCheckTimer();
    
    // Initialize device ID
    _initializeDeviceId();
  }

  // Generate and store a unique device ID
  Future<void> _initializeDeviceId() async {
    try {
      final String deviceId = await _getOrGenerateDeviceId();
      debugPrint('Device ID initialized: $deviceId');
    } catch (e) {
      debugPrint('Error initializing device ID: $e');
    }
  }
  
  // Get or generate device ID for FCM registration
  Future<String> _getOrGenerateDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we already have a device ID
      String? deviceId = prefs.getString('device_id');
      
      // If we already have a device ID, return it
      if (deviceId != null && deviceId.isNotEmpty) {
        debugPrint('Using existing device ID: $deviceId');
        return deviceId;
      }
      
      // No device ID yet, generate one
      deviceId = const Uuid().v4();
      
      // Try to get more device info to make the ID more specific
      final deviceInfo = DeviceInfoPlugin();
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          // Create a more specific ID using device model
          deviceId = 'android_${androidInfo.model}_$deviceId';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          // Create a more specific ID using device model
          deviceId = 'ios_${iosInfo.model}_$deviceId';
        }
      } catch (e) {
        // If we can't get device info, just use the UUID
        debugPrint('Could not get device info: $e');
      }
      
      // Save the device ID
      await prefs.setString('device_id', deviceId!);
      debugPrint('Generated and saved new device ID: $deviceId');
      return deviceId;
    } catch (e) {
      // In case of any error, generate a simple UUID
      final deviceId = 'fallback_${const Uuid().v4()}';
      debugPrint('Error generating device ID, using fallback: $e');
      
      // Try to save even the fallback ID
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_id', deviceId);
      } catch (_) {
        // Ignore error if we can't save
      }
      
      return deviceId;
    }
  }

  // โหลดการตั้งค่าจาก SharedPreferences
  // Future<void> _loadSettings() async {
  //   try {
  //     final prefs = await SharedPreferences.getInstance();
  //     _notifyAllMagnitudes = prefs.getBool('notifyAllMagnitudes') ?? true;
  //     _minNotifyMagnitude = prefs.getDouble('minNotifyMagnitude') ?? 0.1;
  //     _isNotificationEnabled = prefs.getBool('isNotificationEnabled') ?? true;
  //     _checkIntervalMinutes = prefs.getInt('checkIntervalMinutes') ?? 5;
  //     _isCriticalAlertEnabled = prefs.getBool('isCriticalAlertEnabled') ?? false;
  //     _criticalMagnitudeThreshold = prefs.getDouble('criticalMagnitudeThreshold') ?? 6.0;
      
  //     // ใส่การโหลดการตั้งค่าเสียง
  //     _useCustomSounds = prefs.getBool('useCustomSounds') ?? false;
  //     _regularSound = prefs.getString('regularSound') ?? 'default';
  //     _criticalSound = prefs.getString('criticalSound') ?? 'critical_alert';
      
  //     // โหลดพื้นที่ที่เลือก
  //     _selectedLocation = prefs.getString('selectedLocation');
  //     _starredLocation = prefs.getString('starredLocation');
  //     _selectedRegion = prefs.getString('selectedRegion');

  //     debugPrint(
  //       'Settings loaded: notifyAllMagnitudes=$_notifyAllMagnitudes, minNotifyMagnitude=$_minNotifyMagnitude',
  //     );
  //     debugPrint(
  //       'Notification enabled: $_isNotificationEnabled, checkInterval: $_checkIntervalMinutes minutes',
  //     );
  //     debugPrint(
  //       'Critical Alert: enabled=$_isCriticalAlertEnabled, threshold=$_criticalMagnitudeThreshold',
  //     );
  //     debugPrint(
  //       'Sound settings: useCustomSounds=$_useCustomSounds, regularSound=$_regularSound, criticalSound=$_criticalSound',
  //     );
  //     debugPrint(
  //       'Selected location: $_selectedLocation',
  //     );
  //     debugPrint(
  //       'Starred location: $_starredLocation',
  //     );
  //     debugPrint(
  //       'Selected region: $_selectedRegion',
  //     );

  //     notifyListeners();
  //   } catch (e) {
  //     debugPrint('Error loading settings: $e');
  //   }
  // }

  // บันทึกการตั้งค่าลง SharedPreferences
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifyAllMagnitudes', _notifyAllMagnitudes);
      await prefs.setDouble('minNotifyMagnitude', _minNotifyMagnitude);
      await prefs.setBool('isNotificationEnabled', _isNotificationEnabled);
      await prefs.setInt('checkIntervalMinutes', _checkIntervalMinutes);
      await prefs.setBool('isCriticalAlertEnabled', _isCriticalAlertEnabled);
      await prefs.setDouble('criticalMagnitudeThreshold', _criticalMagnitudeThreshold);
      
      // เพิ่มการบันทึกการตั้งค่าเสียง
      await prefs.setBool('useCustomSounds', _useCustomSounds);
      await prefs.setString('regularSound', _regularSound);
      await prefs.setString('criticalSound', _criticalSound);
      
      // บันทึกพื้นที่ที่เลือก
      if (_selectedLocation != null) {
        await prefs.setString('selectedLocation', _selectedLocation!);
      } else {
        await prefs.remove('selectedLocation');
      }

      if (_starredLocation != null) {
        await prefs.setString('starredLocation', _starredLocation!);
      } else {
        await prefs.remove('starredLocation');
      }

      // บันทึกภูมิภาคที่เลือก
      if (_selectedRegion != null) {
        await prefs.setString('selectedRegion', _selectedRegion!);
      } else {
        await prefs.remove('selectedRegion');
      }

      debugPrint('Settings saved successfully');
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Sets the selected location name for filtering
  void setSelectedLocation(String? location) {
    _selectedLocation = location;
    notifyListeners();
    _saveSettings();
  }

  /// Clears the selected location filter
  void clearSelectedLocation() {
    _selectedLocation = null;
    notifyListeners();
    _saveSettings();
  }
  
  /// Sets the starred location (favorite)
  void setStarredLocation(String? location) {
    _starredLocation = location;
    notifyListeners();
    _saveSettings();
    debugPrint('Set starred location: $location');
  }
  
  /// Clears the starred location
  void clearStarredLocation() {
    _starredLocation = null;
    notifyListeners();
    _saveSettings();
    debugPrint('Cleared starred location');
  }
  
  /// Toggle starred status for a location
  void toggleStarredLocation(String location) {
    if (_starredLocation == location) {
      clearStarredLocation();
    } else {
      setStarredLocation(location);
    }
  }
  
  /// Check if a location is starred
  bool isLocationStarred(String location) {
    return _starredLocation == location;
  }
  
  // เพิ่มเมธอดสำหรับอัปเดตรายการพื้นที่ที่มี
  void updateAvailableLocations() {
    final locationSet = <String>{};
    
    for (final earthquake in _earthquakes) {
      if (earthquake.location.isNotEmpty) {
        locationSet.add(earthquake.location);
      }
    }
    
    _availableLocations = locationSet.toList()..sort();
    notifyListeners();
    debugPrint('Updated available locations: ${_availableLocations.length} locations');
  }
  
  // อัปเดตเมธอด getFilteredEarthquakes เพื่อรองรับการกรองตามภูมิภาค
  List<Earthquake> getFilteredEarthquakes() {
    var filteredQuakes = _earthquakes;
    
    // กรองตามตำแหน่งที่เลือก (ถ้ามี)
    if (_selectedLocation != null && _selectedLocation!.isNotEmpty) {
      debugPrint('Filtering by location: $_selectedLocation');
      filteredQuakes = filteredQuakes.where((quake) => quake.location == _selectedLocation).toList();
      debugPrint('After location filter: ${filteredQuakes.length} earthquakes');
    }
    
    // กรองตามภูมิภาคที่เลือก (ถ้ามี)
    if (_selectedRegion != null && _selectedRegion != 'all') {
      debugPrint('Filtering by region: $_selectedRegion');
      final filterFunction = CountryHelper.getFilterFunction(_selectedRegion!);
      
      // Check how many earthquakes match this region filter
      final beforeCount = filteredQuakes.length;
      filteredQuakes = filteredQuakes.where((quake) => filterFunction(quake.location)).toList();
      final afterCount = filteredQuakes.length;
      
      debugPrint('Region filter results: $beforeCount → $afterCount earthquakes');
      
      // Debug: Print sample of locations being filtered
      if (afterCount < 5) {
        debugPrint('Sample filtered locations: ${filteredQuakes.map((e) => e.location).join(", ")}');
      }
    }
    
    return filteredQuakes;
  }

  // เพิ่มเมธอดสำหรับตั้งค่า Critical Alert
  void setCriticalAlertEnabled(bool value) {
    _isCriticalAlertEnabled = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set critical alert enabled: $value');
  }

  void setCriticalMagnitudeThreshold(double value) {
    _criticalMagnitudeThreshold = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set critical magnitude threshold: $value');
  }
  
  // เพิ่มเมธอดสำหรับตั้งค่าเสียง
  void setUseCustomSounds(bool value) {
    _useCustomSounds = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set use custom sounds: $value');
  }
  
  void setRegularSound(String value) {
    _regularSound = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set regular sound: $value');
  }
  
  void setCriticalSound(String value) {
    _criticalSound = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set critical sound: $value');
  }

  // ตั้งค่าการแจ้งเตือนทุกขนาด
  void setNotifyAllMagnitudes(bool value) {
    _notifyAllMagnitudes = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set notify all magnitudes: $value');
  }

  // ตั้งค่าขนาดแผ่นดินไหวขั้นต่ำที่จะแจ้งเตือน
  void setMinNotifyMagnitude(double value) {
    _minNotifyMagnitude = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set min notify magnitude: $value');
  }

  // เปิด/ปิดการแจ้งเตือน
  void setNotificationEnabled(bool value) {
    _isNotificationEnabled = value;
    _saveSettings();
    notifyListeners();
    debugPrint('Set notification enabled: $value');
  }

  // ตั้งค่าความถี่ในการตรวจสอบ
  void setCheckInterval(int minutes) {
    _checkIntervalMinutes = minutes;
    _saveSettings();
    _initializeCheckTimer(); // รีเซ็ต timer ด้วยค่าใหม่
    notifyListeners();
    debugPrint('Set check interval: $minutes minutes');
  }

  // เริ่มต้น timer สำหรับตรวจสอบแผ่นดินไหวเป็นระยะ
  void _initializeCheckTimer() {
    // ยกเลิก timer เดิมถ้ามี
    _checkTimer?.cancel();

    // หรือตั้งเวลานานๆ เช่น 6 ชั่วโมง เพื่อเช็คนานๆ ครั้ง
    _checkTimer = Timer.periodic(Duration(hours: 6), (timer) {
      debugPrint('Periodic maintenance check triggered');
      fetchLastHourEarthquakes(checkForNotifications: false);
    });

    debugPrint('Minimal maintenance timer initialized: check every 6 hours');
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  // ดึงข้อมูลแผ่นดินไหวในชั่วโมงล่าสุด
  Future<List<Earthquake>> fetchLastHourEarthquakes({
    bool checkForNotifications = false,
    bool respectMagnitudeFilter = true,
  }) async {
    // ถ้ามีการร้องขอ API อยู่แล้ว ไม่ต้องทำซ้ำ
    if (_fetchInProgress) {
      debugPrint('API request already in progress, skipping');
      return [];
    }

    _fetchInProgress = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final endTime = DateTime.now();
    final startTime = endTime.subtract(const Duration(hours: 1));

    // Format dates as ISO 8601
    final formattedStartTime = startTime.toIso8601String();
    final formattedEndTime = endTime.toIso8601String();

    // คำนวณค่า minmagnitude ต่ำสุดที่จะดึงมา
    // ดึงทั้งหมดมาก่อน แล้วค่อยกรองที่แอพเพื่อให้มีข้อมูลพร้อม
    double minMagnitude = 0.1;

    try {
      final url =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=$formattedStartTime&endtime=$formattedEndTime&minmagnitude=$minMagnitude&limit=500';

      debugPrint('Fetching earthquake data from: $url');

      // เพิ่ม timeout เพื่อไม่ให้แอพค้าง
      final response = await http.get(Uri.parse(url))
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('HTTP request timed out after 10 seconds');
            throw TimeoutException('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่ภายหลัง');
          },
        );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> features = data['features'];

        debugPrint('Received ${features.length} earthquakes in the last hour');

        List<Earthquake> lastHourEarthquakes = []; // เปลี่ยนชื่อตัวแปรให้ชัดเจน
        for (var feature in features) {
          try {
            final earthquake = Earthquake.fromJson(feature);
            lastHourEarthquakes.add(earthquake);
          } catch (e) {
            debugPrint('Error parsing earthquake data: $e');
          }
        }

        // เรียงตามเวลาล่าสุด
        lastHourEarthquakes.sort((a, b) => b.time.compareTo(a.time));

        // รวมข้อมูลเข้ากับข้อมูลเดิม (แทนที่เฉพาะข้อมูลที่ซ้ำกัน)
        _updateEarthquakesList(lastHourEarthquakes);

        _lastUpdate = DateTime.now();
        debugPrint(
          'Fetched ${lastHourEarthquakes.length} earthquakes in the last hour',
        );

        // ไม่ตรวจสอบการแจ้งเตือนอีกต่อไป - ใช้ FCM จากเซิร์ฟเวอร์เท่านั้น
        // การรีเฟรชแค่อัพเดทรายการเท่านั้น

        _isLoading = false;
        _error = null;
        notifyListeners();
        _fetchInProgress = false;
        return lastHourEarthquakes;
      } else {
        throw Exception(
          'Failed to load earthquake data: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching last hour earthquake data: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      _fetchInProgress = false;
      return [];
    }
  }

  // รับข้อมูลแผ่นดินไหวล่าสุดจาก USGS API ทุกขนาด ไม่จำกัดพื้นที่ (ทั่วโลก)
  Future<List<Earthquake>> fetchRecentEarthquakes({
    bool checkForNotifications = false,
    bool respectMagnitudeFilter = true,
  }) async {
    // ถ้ามีการร้องขอ API อยู่แล้ว ไม่ต้องทำซ้ำ
    if (_fetchInProgress) {
      debugPrint('API request already in progress, skipping');
      return [];
    }

    _fetchInProgress = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final endTime = DateTime.now();
    final startTime = endTime.subtract(const Duration(days: 30)); // ดึงข้อมูล 30 วันล่าสุด

    // Format dates as ISO 8601
    final formattedStartTime = startTime.toIso8601String();
    final formattedEndTime = endTime.toIso8601String();

    // คำนวณค่า minmagnitude ต่ำสุดที่จะดึงมา
    // ดึงที่ 0.1 แล้วค่อยกรองที่แอพเพื่อให้มีข้อมูลพร้อม
    double minMagnitude = 0.1;

    try {
      final url =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=$formattedStartTime&endtime=$formattedEndTime&minmagnitude=$minMagnitude&limit=500';

      debugPrint('Fetching earthquake data from: $url');

      // เพิ่ม timeout เพื่อไม่ให้แอพค้าง
      final response = await http.get(Uri.parse(url))
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('HTTP request timed out after 10 seconds');
            throw TimeoutException('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่ภายหลัง');
          },
        );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> features = data['features'];

        _earthquakes = [];
        debugPrint('Received ${features.length} earthquakes from API');

        for (var feature in features) {
          try {
            final earthquake = Earthquake.fromJson(feature);
            _earthquakes.add(earthquake);
          } catch (e) {
            debugPrint('Error parsing earthquake data: $e');
          }
        }

        // เรียงตามเวลาล่าสุด
        _earthquakes.sort((a, b) => b.time.compareTo(a.time));

        _lastUpdate = DateTime.now();
        debugPrint('Fetched ${_earthquakes.length} earthquakes from USGS API');

        // ไม่ตรวจสอบการแจ้งเตือนอีกต่อไป - ใช้ FCM จากเซิร์ฟเวอร์เท่านั้น

        _isLoading = false;
        _error = null;
        notifyListeners();
        _fetchInProgress = false;
        return _earthquakes;
      } else {
        throw Exception(
          'Failed to load earthquake data: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching earthquake data: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      _fetchInProgress = false;
      return [];
    }
  }
  
  // ดึงแผ่นดินไหวในเอเชียตะวันออกเฉียงใต้
  Future<List<Earthquake>> fetchSoutheastAsiaEarthquakes({
    bool checkForNotifications = false,
    bool respectMagnitudeFilter = true,
  }) async {
    // ถ้ามีการร้องขอ API อยู่แล้ว ไม่ต้องทำซ้ำ
    if (_fetchInProgress) {
      debugPrint('API request already in progress, skipping');
      return [];
    }

    _fetchInProgress = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final endTime = DateTime.now();
    final startTime = endTime.subtract(const Duration(days: 30)); // ดึงข้อมูล 30 วันล่าสุด

    // Format dates as ISO 8601
    final formattedStartTime = startTime.toIso8601String();
    final formattedEndTime = endTime.toIso8601String();

    // ซูมไปที่พื้นที่เอเชียตะวันออกเฉียงใต้
    // Rough bounding box for Southeast Asia
    final double minlat = -11.0; // Indonesia south
    final double maxlat = 29.0;  // China north
    final double minlon = 92.0;  // Myanmar west 
    final double maxlon = 141.0; // Indonesia east

    // คำนวณค่า minmagnitude ต่ำสุดที่จะดึงมา
    // ดึงที่ 0.1 แล้วค่อยกรองที่แอพเพื่อให้มีข้อมูลพร้อม
    double minMagnitude = 0.1;

    try {
      final url =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=$formattedStartTime&endtime=$formattedEndTime&minlat=$minlat&maxlat=$maxlat&minlon=$minlon&maxlon=$maxlon&minmagnitude=$minMagnitude&limit=500';

      debugPrint('Fetching Southeast Asia earthquake data from: $url');

      // เพิ่ม timeout เพื่อไม่ให้แอพค้าง
      final response = await http.get(Uri.parse(url))
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('HTTP request timed out after 10 seconds');
            throw TimeoutException('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่ภายหลัง');
          },
        );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> features = data['features'];

        _earthquakes = [];
        debugPrint('Received ${features.length} earthquakes from API (Southeast Asia)');

        for (var feature in features) {
          try {
            final earthquake = Earthquake.fromJson(feature);
            _earthquakes.add(earthquake);
          } catch (e) {
            debugPrint('Error parsing earthquake data: $e');
          }
        }

        // เรียงตามเวลาล่าสุด
        _earthquakes.sort((a, b) => b.time.compareTo(a.time));

        // อัปเดต available locations สำหรับตัวกรอง
        updateAvailableLocations();
        
        _lastUpdate = DateTime.now();
        debugPrint('Fetched ${_earthquakes.length} earthquakes from Southeast Asia');

        // ไม่ตรวจสอบการแจ้งเตือนอีกต่อไป - FCM จากเซิร์ฟเวอร์จะจัดการให้

        _isLoading = false;
        _error = null;
        notifyListeners();
        _fetchInProgress = false;
        return _earthquakes;
      } else {
        throw Exception(
          'Failed to load earthquake data: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching Southeast Asia earthquake data: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      _fetchInProgress = false;
      return [];
    }
  }
  
  // ดึงเฉพาะแผ่นดินไหวในไทยและประเทศใกล้เคียง
  Future<List<Earthquake>> fetchThailandAndNeighborsEarthquakes({
    bool checkForNotifications = false,
    bool respectMagnitudeFilter = true,
  }) async {
    // ถ้ามีการร้องขอ API อยู่แล้ว ไม่ต้องทำซ้ำ
    if (_fetchInProgress) {
      debugPrint('API request already in progress, skipping');
      return [];
    }

    _fetchInProgress = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final endTime = DateTime.now();
    final startTime = endTime.subtract(const Duration(days: 30)); // ดึงข้อมูล 30 วันล่าสุด

    // Format dates as ISO 8601
    final formattedStartTime = startTime.toIso8601String();
    final formattedEndTime = endTime.toIso8601String();

    // บริเวณประเทศไทยและประเทศเพื่อนบ้านใกล้เคียง
    final double minlat = 5.0;   // Malaysia south
    final double maxlat = 21.0;  // China border north
    final double minlon = 97.0;  // Myanmar west 
    final double maxlon = 106.0; // Cambodia/Vietnam east

    // คำนวณค่า minmagnitude ต่ำสุดที่จะดึงมา
    // ดึงที่ 0.1 แล้วค่อยกรองที่แอพเพื่อให้มีข้อมูลพร้อม
    double minMagnitude = 0.1; 

    try {
      final url =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&starttime=$formattedStartTime&endtime=$formattedEndTime&minlat=$minlat&maxlat=$maxlat&minlon=$minlon&maxlon=$maxlon&minmagnitude=$minMagnitude&limit=500';

      debugPrint('Fetching Thailand area earthquake data from: $url');

      // เพิ่ม timeout เพื่อไม่ให้แอพค้าง
      final response = await http.get(Uri.parse(url))
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('HTTP request timed out after 10 seconds');
            throw TimeoutException('การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่ภายหลัง');
          },
        );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> features = data['features'];

        _earthquakes = [];
        debugPrint('Received ${features.length} earthquakes from API (Thailand area)');

        for (var feature in features) {
          try {
            final earthquake = Earthquake.fromJson(feature);
            _earthquakes.add(earthquake);
          } catch (e) {
            debugPrint('Error parsing earthquake data: $e');
          }
        }

        // เรียงตามเวลาล่าสุด
        _earthquakes.sort((a, b) => b.time.compareTo(a.time));

        // อัปเดต available locations สำหรับตัวกรอง
        updateAvailableLocations();
        
        _lastUpdate = DateTime.now();
        debugPrint('Fetched ${_earthquakes.length} earthquakes from Thailand area');

        // ไม่ตรวจสอบการแจ้งเตือนอีกต่อไป - FCM จากเซิร์ฟเวอร์จะจัดการให้

        _isLoading = false;
        _error = null;
        notifyListeners();
        _fetchInProgress = false;
        return _earthquakes;
      } else {
        throw Exception(
          'Failed to load earthquake data: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('Error fetching Thailand area earthquake data: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      _fetchInProgress = false;
      return [];
    }
  }

  // ปรับปรุงวิธีอัพเดตรายการแผ่นดินไหว
  void _updateEarthquakesList(List<Earthquake> newEarthquakes) {
    if (newEarthquakes.isEmpty) return;

    // สร้าง Map จาก ID เพื่อตรวจสอบข้อมูลซ้ำได้เร็วขึ้น
    final Map<String, Earthquake> existingMap = {
      for (var quake in _earthquakes) quake.id: quake,
    };

    // เพิ่มหรืออัปเดตข้อมูลแผ่นดินไหว
    for (var newQuake in newEarthquakes) {
      // ข้ามถ้าเป็นแผ่นดินไหวที่เคยประมวลผลแล้ว
      if (_processedEarthquakeIds.contains(newQuake.id)) continue;
      
      existingMap[newQuake.id] = newQuake;
      _processedEarthquakeIds.add(newQuake.id);
    }

    // แปลงกลับเป็น List และเรียงตามเวลา
    _earthquakes =
        existingMap.values.toList()..sort((a, b) => b.time.compareTo(a.time));

    // ทำความสะอาด Set ถ้ามีขนาดใหญ่เกินไป
    if (_processedEarthquakeIds.length > 1000) {
      _processedEarthquakeIds.clear();
    }

    debugPrint('Updated earthquakes list: ${_earthquakes.length} items');
  }

  // เช็คว่าแผ่นดินไหวนี้ได้รับการแจ้งเตือนไปแล้วหรือไม่
  Future<bool> _hasNotifiedBefore(String quakeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final result = prefs.getBool('notified_$quakeId') ?? false;
      debugPrint(
        'Earthquake $quakeId notification status: ${result ? "already notified" : "not yet notified"}',
      );
      return result;
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
      debugPrint(
        'Marked earthquake $quakeId as notified at ${DateTime.now().toString()}',
      );

      // ทำความสะอาดข้อมูลเก่า
      _cleanupOldNotifications();
    } catch (e) {
      debugPrint('Error marking earthquake as notified: $e');
    }
  }

  // ลบข้อมูลการแจ้งเตือนที่เก่ากว่า 7 วัน
  Future<void> _cleanupOldNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final keysToRemove = <String>[];

      // ค้นหาคีย์ทั้งหมดที่เริ่มต้นด้วย 'notified_time_'
      final allKeys = prefs.getKeys();
      final timeKeys =
          allKeys.where((key) => key.startsWith('notified_time_')).toList();

      for (final timeKey in timeKeys) {
        final timeStr = prefs.getString(timeKey);
        if (timeStr != null) {
          try {
            final notifiedTime = DateTime.parse(timeStr);
            final difference = now.difference(notifiedTime);

            // ถ้าเก่ากว่า 7 วัน ให้ลบทิ้ง
            if (difference.inDays > 7) {
              final quakeId = timeKey.substring('notified_time_'.length);
              keysToRemove.add(timeKey);
              keysToRemove.add('notified_$quakeId');
            }
          } catch (e) {
            debugPrint('Error parsing date: $e');
          }
        }
      }

      // ลบคีย์เก่า
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        debugPrint(
          'Cleaned up ${keysToRemove.length} old notification records',
        );
      }
    } catch (e) {
      debugPrint('Error cleaning up old notifications: $e');
    }
  }

  // ตรวจสอบแผ่นดินไหวใหม่และส่งการแจ้งเตือน
  Future<void> _checkForNewEarthquakes(List<Earthquake>? earthquakesToCheck, bool respectMagnitudeFilter) async {
    // เนื่องจากเราไม่ต้องการส่งการแจ้งเตือนจากในแอปอีกต่อไป
    // แต่ยังคงต้องการฟังก์ชันนี้เพื่อ log ข้อมูลที่พบ
    
    // ข้ามการตรวจสอบการแจ้งเตือนทั้งหมด
    debugPrint('การแจ้งเตือนถูกจัดการโดย FCM จากเซิร์ฟเวอร์โดยตรง - ข้ามการตรวจสอบในแอป');
    
    // เพียงแค่รายงานจำนวนแผ่นดินไหวในช่วง 15 นาทีล่าสุด สำหรับการ debug เท่านั้น
    final earthquakes = earthquakesToCheck ?? _earthquakes;
    if (earthquakes.isEmpty) {
      debugPrint('ไม่มีข้อมูลแผ่นดินไหวสำหรับการตรวจสอบ');
      return;
    }

    final recentEarthquakes = earthquakes
        .where((quake) => DateTime.now().difference(quake.time).inMinutes < 15)
        .toList();

    debugPrint('พบ ${recentEarthquakes.length} รายการแผ่นดินไหวในช่วง 15 นาทีล่าสุด (ไม่มีการแจ้งเตือน)');
    
    // ไม่ส่งการแจ้งเตือนใดๆ - ข้ามขั้นตอนการตรวจสอบการแจ้งเตือนทั้งหมด
  }

  // บังคับตรวจสอบล่าสุดทันที (เพิ่มใหม่ - เรียกจากปุ่มในแอพ)
  Future<void> forceCheckImmediate() async {
    debugPrint('Forcing immediate check for new earthquakes (NO notifications will be sent)');
    // ส่งพารามิเตอร์ checkForNotifications เป็น false เพื่อป้องกันการส่งการแจ้งเตือน
    // เมื่อผู้ใช้กดรีเฟรชเพื่อดูข้อมูลล่าสุดเท่านั้น
    await fetchLastHourEarthquakes(checkForNotifications: false, respectMagnitudeFilter: true);
  }

  // เพิ่มเมธอดสำหรับตั้งค่าภูมิภาคที่เลือก
  void setSelectedRegion(String? region) {
    debugPrint('Setting selected region from: $_selectedRegion to: $region');
    _selectedRegion = region;
    _saveSettings();
    
    // For debugging: check if the region filter works with current data
    if (region != null && region != 'all') {
      final filterFunction = CountryHelper.getFilterFunction(region);
      final matchingQuakes = _earthquakes.where((quake) => filterFunction(quake.location)).toList();
      
      debugPrint('Found ${matchingQuakes.length} earthquakes matching region: $region out of ${_earthquakes.length} total earthquakes');
      
      if (matchingQuakes.isNotEmpty && matchingQuakes.length < 5) {
        debugPrint('Sample matches: ${matchingQuakes.map((e) => "${e.location} (${e.magnitude})").join(", ")}');
      } else if (matchingQuakes.isNotEmpty) {
        final sampleMatches = matchingQuakes.take(5).toList();
        debugPrint('Sample matches (first 5): ${sampleMatches.map((e) => "${e.location} (${e.magnitude})").join(", ")}');
      }
      
      // Display some that don't match
      if (_earthquakes.length > matchingQuakes.length) {
        final nonMatchingQuakes = _earthquakes.where((quake) => !filterFunction(quake.location)).take(3).toList();
        if (nonMatchingQuakes.isNotEmpty) {
          debugPrint('Sample non-matches: ${nonMatchingQuakes.map((e) => "${e.location} (${e.magnitude})").join(", ")}');
        }
      }
    }
    
    notifyListeners();
    debugPrint('Set selected region: $region');
  }

  // ในคลาส EarthquakeService
  final Set<String> _processedEarthquakeIds = {};
}