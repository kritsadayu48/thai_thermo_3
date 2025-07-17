// lib/models/earthquake.dart
import 'dart:math' as math;

class Earthquake {
  final String id;
  final double magnitude;
  final DateTime time;
  final double latitude;
  final double longitude;
  final double depth;
  final String location;
  final Map<String, dynamic>? properties; // เพิ่มฟิลด์ properties เพื่อเก็บข้อมูลเพิ่มเติม
  
  Earthquake({
    required this.id,
    required this.magnitude,
    required this.time,
    required this.latitude,
    required this.longitude,
    required this.depth,
    required this.location,
    this.properties,
  });
  
  // เพิ่มเมธอด toJson เพื่อแปลงข้อมูลเป็น Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'magnitude': magnitude.toString(),
      'time': time.toIso8601String(),
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'depth': depth.toString(),
      'location': location,
      'properties': properties,
    };
  }
  
  factory Earthquake.fromJson(Map<String, dynamic> json) {
    // รองรับข้อมูลที่มาจาก GeoJSON โดยตรง (เช่นที่ดึงมาจาก eventid)
    if (json.containsKey('type') && json['type'] == 'Feature') {
      final properties = json['properties'];
      final geometry = json['geometry'];
      
      final magnitudeValue = properties['mag'];
      final double magnitude = magnitudeValue is int 
          ? magnitudeValue.toDouble() 
          : magnitudeValue?.toDouble() ?? 0.0;
          
      final timeValue = properties['time'];
      final DateTime time = timeValue != null 
          ? DateTime.fromMillisecondsSinceEpoch(timeValue) 
          : DateTime.now();
          
      final coordinates = geometry['coordinates'];
      final double longitude = coordinates[0] is int 
          ? (coordinates[0] as int).toDouble() 
          : coordinates[0]?.toDouble() ?? 0.0;
          
      final double latitude = coordinates[1] is int 
          ? (coordinates[1] as int).toDouble() 
          : coordinates[1]?.toDouble() ?? 0.0;
          
      final double depth = coordinates[2] is int 
          ? (coordinates[2] as int).toDouble() 
          : coordinates[2]?.toDouble() ?? 0.0;
      
      return Earthquake(
        id: properties['id'] ?? properties['code'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        magnitude: magnitude,
        time: time,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        location: properties['place'] ?? 'ไม่ทราบตำแหน่ง',
        properties: properties,
      );
    }
    // รองรับการแปลงข้อมูลจาก feature ใน features array
    else if (json.containsKey('properties') && json.containsKey('geometry')) {
      final magnitudeValue = json['properties']['mag'];
      final double magnitude = magnitudeValue is int 
          ? magnitudeValue.toDouble() 
          : magnitudeValue?.toDouble() ?? 0.0;
          
      final timeValue = json['properties']['time'];
      final DateTime time = timeValue != null 
          ? DateTime.fromMillisecondsSinceEpoch(timeValue) 
          : DateTime.now();
          
      final coordinates = json['geometry']['coordinates'];
      final double longitude = coordinates[0] is int 
          ? (coordinates[0] as int).toDouble() 
          : coordinates[0]?.toDouble() ?? 0.0;
          
      final double latitude = coordinates[1] is int 
          ? (coordinates[1] as int).toDouble() 
          : coordinates[1]?.toDouble() ?? 0.0;
          
      final double depth = coordinates[2] is int 
          ? (coordinates[2] as int).toDouble() 
          : coordinates[2]?.toDouble() ?? 0.0;
      
      return Earthquake(
        id: json['id'] ?? json['properties']['id'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        magnitude: magnitude,
        time: time,
        latitude: latitude,
        longitude: longitude,
        depth: depth,
        location: json['properties']['place'] ?? 'ไม่ทราบตำแหน่ง',
        properties: json['properties'],
      );
    }
    // รองรับข้อมูลที่มาจาก FCM payload
    else {
      return Earthquake(
        id: json['id'] ?? 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        magnitude: double.tryParse(json['magnitude']?.toString() ?? '0') ?? 0.0,
        time: json['time'] != null ? DateTime.parse(json['time']) : DateTime.now(),
        latitude: double.tryParse(json['latitude']?.toString() ?? '0') ?? 0.0,
        longitude: double.tryParse(json['longitude']?.toString() ?? '0') ?? 0.0,
        depth: double.tryParse(json['depth']?.toString() ?? '0') ?? 0.0,
        location: json['place'] ?? json['location'] ?? 'ไม่ทราบตำแหน่ง',
        properties: json,
      );
    }
  }
  
  // คำนวณระยะทางจากจุดที่กำหนด
  double distanceFrom(double userLat, double userLong) {
    const R = 6371.0; // Earth's radius in kilometers
    
    double lat1 = userLat * (math.pi / 180.0);
    double lon1 = userLong * (math.pi / 180.0);
    double lat2 = latitude * (math.pi / 180.0);
    double lon2 = longitude * (math.pi / 180.0);
    
    double dlon = lon2 - lon1;
    double dlat = lat2 - lat1;
    
    double a = math.sin(dlat / 2.0) * math.sin(dlat / 2.0) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) * math.sin(dlon / 2.0);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return R * c;
  }
  
  @override
  String toString() {
    return 'Earthquake(id: $id, magnitude: $magnitude, location: $location, time: $time)';
  }
}