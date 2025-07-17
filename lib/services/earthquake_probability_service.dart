import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/earthquake.dart';
import 'dart:math' as math;

class EarthquakeProbabilityService {
  // ข้อมูลแผ่นดินไหวย้อนหลัง
  List<Earthquake> _historicalEarthquakes = [];
  
  // ความถี่แผ่นดินไหวในแต่ละพื้นที่ (จำนวนต่อปี)
  Map<String, double> _regionalFrequency = {};
  
  // ช่วงเวลาที่คำนวณ (ปี)
  static const int _historyYears = 10;
  
  // ขนาดพื้นที่สำหรับการวิเคราะห์ (รัศมีเป็นกิโลเมตร)
  static const double _analysisScopeRadius = 100.0;
  
  // เรียกข้อมูลแผ่นดินไหวย้อนหลังในบริเวณใกล้เคียงพิกัดที่ระบุ
  Future<List<Earthquake>> fetchHistoricalEarthquakeData(double latitude, double longitude) async {
    try {
      // ดึงข้อมูลย้อนหลัง _historyYears ปี
      final endDate = DateTime.now();
      final startDate = DateTime(endDate.year - _historyYears, endDate.month, endDate.day);
      
      // กำหนดขอบเขตพิกัดประมาณ (bounding box)
      // 1 องศาละติจูด ≈ 111 กม., 1 องศาลองจิจูด ≈ 111*cos(lat) กม.
      final double latDelta = _analysisScopeRadius / 111.0;
      final double lonDelta = _analysisScopeRadius / (111.0 * math.cos(latitude * math.pi / 180.0));
      
      final minLatitude = latitude - latDelta;
      final maxLatitude = latitude + latDelta;
      final minLongitude = longitude - lonDelta;
      final maxLongitude = longitude + lonDelta;
      
      final apiUrl =
          'https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson'
          '&starttime=${startDate.toIso8601String()}'
          '&endtime=${endDate.toIso8601String()}'
          '&minlatitude=$minLatitude'
          '&maxlatitude=$maxLatitude'
          '&minlongitude=$minLongitude'
          '&maxlongitude=$maxLongitude'
          '&minmagnitude=0.1'; // เฉพาะแผ่นดินไหวที่มีขนาดตั้งแต่ 3.0 ขึ้นไป
      
      debugPrint('Fetching historical earthquake data from: $apiUrl');
      
      final response = await http.get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> features = data['features'];
        
        _historicalEarthquakes = [];
        for (var feature in features) {
          try {
            final earthquake = Earthquake.fromJson(feature);
            _historicalEarthquakes.add(earthquake);
          } catch (e) {
            debugPrint('Error parsing historical earthquake data: $e');
          }
        }
        
        // เรียงลำดับตามเวลา จากใหม่ไปเก่า
        _historicalEarthquakes.sort((a, b) => b.time.compareTo(a.time));
        
        _calculateRegionalFrequency();
        
        return _historicalEarthquakes;
      } else {
        throw Exception('Failed to load historical earthquake data: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching historical earthquake data: $e');
      return [];
    }
  }
  
  // คำนวณความถี่ของแผ่นดินไหวในแต่ละขนาด
  void _calculateRegionalFrequency() {
    _regionalFrequency = {};
    
    // คำนวณความถี่ตามขนาด (magnitude) โดยแบ่งเป็นช่วง
    for (var i = 3; i <= 9; i++) {
      final lowerMag = i.toDouble();
      final upperMag = (i + 1).toDouble();
      
      final earthquakesInRange = _historicalEarthquakes.where(
        (quake) => quake.magnitude >= lowerMag && quake.magnitude < upperMag
      ).length;
      
      // คำนวณความถี่ต่อปี
      final frequencyPerYear = earthquakesInRange / _historyYears;
      _regionalFrequency['$lowerMag-$upperMag'] = frequencyPerYear;
    }
  }
  
  // คำนวณโอกาสเกิดแผ่นดินไหวในบริเวณใกล้เคียง
  Map<String, dynamic> calculateEarthquakeProbability(double latitude, double longitude) {
    if (_historicalEarthquakes.isEmpty) {
      return {
        'probabilityPercentage': 0.0,
        'confidenceLevel': 'ต่ำ',
        'recommendation': 'กรุณาดึงข้อมูลประวัติแผ่นดินไหวก่อน',
        'historicalData': {
          'total': 0,
          'frequency': _regionalFrequency,
        }
      };
    }
    
    // นับจำนวนแผ่นดินไหวทั้งหมดในพื้นที่
    final totalEarthquakes = _historicalEarthquakes.length;
    
    // คำนวณระยะเวลาเฉลี่ยระหว่างแผ่นดินไหวแต่ละครั้ง (หน่วยเป็นวัน)
    double averageTimeBetweenEvents = 0;
    
    if (totalEarthquakes > 1) {
      final firstEvent = _historicalEarthquakes.last.time;
      final lastEvent = _historicalEarthquakes.first.time;
      final totalDays = lastEvent.difference(firstEvent).inDays;
      
      if (totalDays > 0) {
        averageTimeBetweenEvents = totalDays / (totalEarthquakes - 1);
      }
    }
    
    // คำนวณโอกาสเกิดแผ่นดินไหวต่อปี (%)
    double annualProbability = 0;
    if (averageTimeBetweenEvents > 0) {
      // จำนวนเหตุการณ์ต่อปีโดยเฉลี่ย
      final eventsPerYear = 365 / averageTimeBetweenEvents;
      
      // โอกาสที่จะเกิดอย่างน้อย 1 ครั้งต่อปี (%)
      annualProbability = (1 - math.pow(1 - (1/365), eventsPerYear)) * 100;
    }
    
    // ดูแผ่นดินไหวล่าสุดในพื้นที่
    final latestEvent = _historicalEarthquakes.isNotEmpty ? _historicalEarthquakes.first : null;
    
    // คำนวณระดับความเชื่อมั่น
    String confidenceLevel = 'ปานกลาง';
    if (totalEarthquakes < 5) {
      confidenceLevel = 'ต่ำ';
    } else if (totalEarthquakes > 20) {
      confidenceLevel = 'สูง';
    }
    
    // สร้างคำแนะนำตามความถี่
    String recommendation;
    if (annualProbability < 5) {
      recommendation = 'บริเวณนี้มีความเสี่ยงต่ำ แต่ควรรู้วิธีรับมือแผ่นดินไหวไว้';
    } else if (annualProbability < 30) {
      recommendation = 'บริเวณนี้มีโอกาสเกิดแผ่นดินไหวปานกลาง ควรระมัดระวังและเตรียมพร้อมรับมือ';
    } else {
      recommendation = 'บริเวณนี้มีโอกาสเกิดแผ่นดินไหวสูง ควรเตรียมพร้อมรับมือและศึกษาแผนอพยพ';
    }
    
    return {
      'probabilityPercentage': annualProbability,
      'confidenceLevel': confidenceLevel,
      'recommendation': recommendation,
      'historicalData': {
        'total': totalEarthquakes,
        'frequency': _regionalFrequency,
        'latestEvent': latestEvent != null ? {
          'time': latestEvent.time.toIso8601String(),
          'magnitude': latestEvent.magnitude,
          'location': latestEvent.location,
        } : null,
      }
    };
  }
  
  // วิเคราะห์แนวโน้มแผ่นดินไหวในพื้นที่
  Map<String, dynamic> analyzeEarthquakeTrends() {
    if (_historicalEarthquakes.isEmpty) {
      return {
        'trend': 'ไม่มีข้อมูลเพียงพอสำหรับการวิเคราะห์',
        'severity': 'ไม่สามารถระบุได้',
      };
    }
    
    // แบ่งประวัติเป็นครึ่งแรกและครึ่งหลัง
    final midPoint = _historicalEarthquakes.length ~/ 2;
    final firstHalf = _historicalEarthquakes.sublist(midPoint);
    final secondHalf = _historicalEarthquakes.sublist(0, midPoint);
    
    // คำนวณค่าเฉลี่ยขนาดแผ่นดินไหวในแต่ละช่วง
    double firstHalfAvgMag = firstHalf.fold(0.0, (sum, quake) => sum + quake.magnitude) / firstHalf.length;
    double secondHalfAvgMag = secondHalf.fold(0.0, (sum, quake) => sum + quake.magnitude) / secondHalf.length;
    
    // คำนวณความถี่ในแต่ละช่วง (จำนวนต่อปี)
    final firstDate = _historicalEarthquakes.last.time;
    final midDate = _historicalEarthquakes[midPoint].time;
    final lastDate = _historicalEarthquakes.first.time;
    
    final firstPeriodYears = midDate.difference(firstDate).inDays / 365.0;
    final secondPeriodYears = lastDate.difference(midDate).inDays / 365.0;
    
    final firstHalfFrequency = firstHalf.length / (firstPeriodYears > 0 ? firstPeriodYears : 1);
    final secondHalfFrequency = secondHalf.length / (secondPeriodYears > 0 ? secondPeriodYears : 1);
    
    // วิเคราะห์แนวโน้ม
    String trend;
    if (secondHalfFrequency > firstHalfFrequency * 1.2) {
      trend = 'เพิ่มขึ้น: ความถี่ของแผ่นดินไหวในพื้นที่มีแนวโน้มเพิ่มสูงขึ้น';
    } else if (secondHalfFrequency < firstHalfFrequency * 0.8) {
      trend = 'ลดลง: ความถี่ของแผ่นดินไหวในพื้นที่มีแนวโน้มลดลง';
    } else {
      trend = 'คงที่: ความถี่ของแผ่นดินไหวในพื้นที่ค่อนข้างคงที่';
    }
    
    // ประเมินความรุนแรง
    String severity;
    final maxMagnitude = _historicalEarthquakes.fold(0.0, (max, quake) => math.max(max, quake.magnitude));
    
    if (maxMagnitude < 4.0) {
      severity = 'ต่ำ: แผ่นดินไหวส่วนใหญ่มีขนาดเล็ก ผลกระทบไม่รุนแรง';
    } else if (maxMagnitude < 6.0) {
      severity = 'ปานกลาง: เคยมีแผ่นดินไหวขนาดปานกลาง อาจส่งผลกระทบได้';
    } else {
      severity = 'สูง: เคยเกิดแผ่นดินไหวขนาดใหญ่ในพื้นที่ ควรระมัดระวัง';
    }
    
    return {
      'trend': trend,
      'severity': severity,
      'data': {
        'firstHalfAvgMagnitude': firstHalfAvgMag,
        'secondHalfAvgMagnitude': secondHalfAvgMag,
        'firstHalfFrequency': firstHalfFrequency,
        'secondHalfFrequency': secondHalfFrequency,
        'maxMagnitude': maxMagnitude,
      }
    };
  }
  
  // ดึงข้อมูลโซนแผ่นดินไหวสำคัญทั่วโลก
  List<Map<String, dynamic>> getGlobalSeismicZones() {
    return [
      {
        'name': 'วงแหวนแห่งไฟ (Ring of Fire)',
        'description': 'บริเวณรอบมหาสมุทรแปซิฟิก พบแผ่นดินไหวประมาณ 90% ของทั้งโลก',
        'riskLevel': 'สูงมาก',
      },
      {
        'name': 'เขตรอยเลื่อนแม่น้ำแดง (Mae Nam Khong Fault)',
        'description': 'รอยเลื่อนในภาคเหนือของไทย พาดผ่านจังหวัดเชียงราย',
        'riskLevel': 'ปานกลาง',
      },
      {
        'name': 'เขตรอยเลื่อนศรีสวัสดิ์ (Sri Sawat Fault)',
        'description': 'รอยเลื่อนในภาคตะวันตกของไทย ที่เคยเกิดแผ่นดินไหวในจังหวัดกาญจนบุรี',
        'riskLevel': 'ปานกลาง',
      },
      {
        'name': 'เขตรอยเลื่อนเมย-อุทัยธานี (Moei-Uthai Thani Fault)',
        'description': 'รอยเลื่อนในภาคกลางและภาคตะวันตกของไทย',
        'riskLevel': 'ปานกลาง-ต่ำ',
      },
      {
        'name': 'เขตรอยเลื่อนเจดีย์สามองค์ (Three Pagodas Fault)',
        'description': 'รอยเลื่อนตามแนวชายแดนไทย-เมียนมาร์',
        'riskLevel': 'ปานกลาง',
      },
      {
        'name': 'แนวรอยเลื่อนสุมาตรา (Sumatra Fault)',
        'description': 'รอยเลื่อนใกล้ชายฝั่งตะวันตกของไทย ที่มักก่อให้เกิดแผ่นดินไหวที่ส่งผลถึงภาคใต้ของไทย',
        'riskLevel': 'สูง',
      },
    ];
  }
} 