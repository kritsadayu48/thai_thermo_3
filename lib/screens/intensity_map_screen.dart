// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'dart:math';
// import '../models/earthquake.dart';

// class IntensityMapScreen extends StatefulWidget {
//   final Earthquake earthquake;
//   final Map<String, dynamic>? shakemapData;
//   final Map<String, dynamic>? simulatedData;

//   const IntensityMapScreen({
//     Key? key,
//     required this.earthquake,
//     this.shakemapData,
//     this.simulatedData,
//   }) : super(key: key);

//   @override
//   _IntensityMapScreenState createState() => _IntensityMapScreenState();
// }

// class _IntensityMapScreenState extends State<IntensityMapScreen> {
//   final Completer<GoogleMapController> _controller = Completer();
//   final Map<PolygonId, Polygon> _polygons = {};
//   final Map<MarkerId, Marker> _markers = {};
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _processData();
//   }

//   void _processData() {
//     if (widget.shakemapData != null) {
//       _processShakemapData(widget.shakemapData!);
//     } else if (widget.simulatedData != null) {
//       _processSimulatedData(widget.simulatedData!);
//     } else {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   void _processShakemapData(Map<String, dynamic> data) {
//     try {
//       // แปลงข้อมูล GeoJSON เป็น Polygons
//       final features = data['features'] as List<dynamic>;
      
//       int polygonIndex = 0;
//       for (final feature in features) {
//         final properties = feature['properties'] as Map<String, dynamic>;
//         final geometry = feature['geometry'] as Map<String, dynamic>;
        
//         // ตรวจสอบว่าเป็น Polygon
//         if (geometry['type'] == 'Polygon' || geometry['type'] == 'MultiPolygon') {
//           final color = _getIntensityColor(properties['value'] ?? 0);
//           final coordinates = geometry['coordinates'] as List<dynamic>;
          
//           List<List<LatLng>> polygonCoords = [];
          
//           if (geometry['type'] == 'Polygon') {
//             for (final ring in coordinates) {
//               List<LatLng> points = [];
//               for (final coord in ring) {
//                 points.add(LatLng(coord[1], coord[0])); // [1] = lat, [0] = lng
//               }
//               polygonCoords.add(points);
//             }
//           } else { // MultiPolygon
//             for (final polygon in coordinates) {
//               for (final ring in polygon) {
//                 List<LatLng> points = [];
//                 for (final coord in ring) {
//                   points.add(LatLng(coord[1], coord[0]));
//                 }
//                 polygonCoords.add(points);
//               }
//             }
//           }
          
//           if (polygonCoords.isNotEmpty) {
//             final polygonId = PolygonId('intensity_$polygonIndex');
//             final polygon = Polygon(
//               polygonId: polygonId,
//               points: polygonCoords.first,  // ใช้เส้นขอบนอก
//               holes: polygonCoords.sublist(1),  // เส้นขอบด้านใน (ถ้ามี)
//               fillColor: color.withOpacity(0.5),
//               strokeColor: color,
//               strokeWidth: 1,
//             );
            
//             _polygons[polygonId] = polygon;
//             polygonIndex++;
//           }
//         }
//       }
      
//       // เพิ่ม marker จุดศูนย์กลาง
//       final epicenter = MarkerId('epicenter');
//       _markers[epicenter] = Marker(
//         markerId: epicenter,
//         position: LatLng(widget.earthquake.latitude, widget.earthquake.longitude),
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//         infoWindow: InfoWindow(
//           title: 'แผ่นดินไหว ${widget.earthquake.magnitude}',
//           snippet: widget.earthquake.location,
//         ),
//       );
      
//       setState(() {
//         _isLoading = false;
//       });
//     } catch (e) {
//       print('Error processing shakemap data: $e');
//       // หากประมวลผลข้อมูลจริงล้มเหลว ให้ใช้การจำลองแทน
//       if (widget.simulatedData != null) {
//         _processSimulatedData(widget.simulatedData!);
//       } else {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   void _processSimulatedData(Map<String, dynamic> data) {
//     try {
//       // เพิ่ม marker จุดศูนย์กลาง
//       final epicenter = MarkerId('epicenter');
//       _markers[epicenter] = Marker(
//         markerId: epicenter,
//         position: LatLng(widget.earthquake.latitude, widget.earthquake.longitude),
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//         infoWindow: InfoWindow(
//           title: 'แผ่นดินไหว ${widget.earthquake.magnitude}',
//           snippet: widget.earthquake.location,
//         ),
//       );
      
//       // สร้าง polygons วงกลมตามระยะทาง
//       final rings = data['rings'] as List<dynamic>;
      
//       for (int i = 0; i < rings.length; i++) {
//         final ring = rings[i];
//         final intensity = ring['intensity'];
//         final distance = ring['distance'];
        
//         final color = _getIntensityColor(intensity);
        
//         // สร้างวงกลมรอบจุดศูนย์กลาง
//         List<LatLng> circlePoints = _createCirclePoints(
//           widget.earthquake.latitude, 
//           widget.earthquake.longitude, 
//           distance * 1000  // แปลงเป็นเมตร
//         );
        
//         final polygonId = PolygonId('intensity_$i');
//         final polygon = Polygon(
//           polygonId: polygonId,
//           points: circlePoints,
//           fillColor: color.withOpacity(0.5),
//           strokeColor: color,
//           strokeWidth: 1,
//         );
        
//         _polygons[polygonId] = polygon;
//       }
      
//       setState(() {
//         _isLoading = false;
//       });
//     } catch (e) {
//       print('Error processing simulated data: $e');
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   // สร้างจุดวงกลมรอบศูนย์กลาง
//   List<LatLng> _createCirclePoints(double lat, double lng, double radius) {
//     List<LatLng> points = [];
    
//     // สร้างจุด 60 จุดรอบวงกลม (ทุกๆ 6 องศา)
//     for (int i = 0; i < 60; i++) {
//       double degree = (i * 6) * (pi / 180); // แปลงเป็น radians
//       double dx = radius * cos(degree);
//       double dy = radius * sin(degree);
      
//       // แปลงจากเมตรเป็นองศาละติจูด/ลองจิจูด
//       double newLat = lat + (dy / 111320); // 1 degree latitude = 111320 meters
//       double newLng = lng + (dx / (111320 * cos(lat * (pi / 180))));
      
//       points.add(LatLng(newLat, newLng));
//     }
    
//     return points;
//   }

//   // สีตามระดับความเข้ม MMI
//   Color _getIntensityColor(dynamic intensity) {
//     int mmi = 0;
//     if (intensity is double) {
//       mmi = intensity.round();
//     } else if (intensity is int) {
//       mmi = intensity;
//     } else {
//       return Colors.transparent;
//     }
    
//     switch (mmi) {
//       case 1: return Color(0xFFCCFFFF); // สีฟ้าอ่อนมาก
//       case 2: return Color(0xFF99EBFF); // สีฟ้าอ่อน
//       case 3: return Color(0xFF66D9FF); // สีฟ้า
//       case 4: return Color(0xFF33CCFF); // สีฟ้าเข้ม
//       case 5: return Color(0xFF00BFFF); // สีฟ้าเข้มมาก
//       case 6: return Color(0xFFFFFF00); // สีเหลือง
//       case 7: return Color(0xFFFFD700); // สีเหลืองทอง
//       case 8: return Color(0xFFFFA500); // สีส้ม
//       case 9: return Color(0xFFFF8C00); // สีส้มเข้ม
//       case 10: return Color(0xFFFF4500); // สีส้มแดง
//       case 11: return Color(0xFFFF0000); // สีแดง
//       case 12: return Color(0xFF8B0000); // สีแดงเข้ม
//       default: return Colors.transparent;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final CameraPosition initialPosition = CameraPosition(
//       target: LatLng(widget.earthquake.latitude, widget.earthquake.longitude),
//       zoom: 5,
//     );
    
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('แผนที่แรงกระเพื่อม'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.info_outline),
//             onPressed: () {
//               _showIntensityInfo();
//             },
//           ),
//         ],
//       ),
//       body: Stack(
//         children: [
//           GoogleMap(
//             initialCameraPosition: initialPosition,
//             mapType: MapType.normal,
//             onMapCreated: (GoogleMapController controller) {
//               _controller.complete(controller);
//             },
//             markers: Set<Marker>.of(_markers.values),
//             polygons: Set<Polygon>.of(_polygons.values),
//             myLocationEnabled: true,
//             myLocationButtonEnabled: false,
//           ),
//           if (_isLoading)
//             Center(
//               child: CircularProgressIndicator(),
//             ),
//           Positioned(
//             bottom: 16,
//             right: 16,
//             child: _buildLegend(),
//           ),
//         ],
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: () async {
//           final controller = await _controller.future;
//           controller.animateCamera(CameraUpdate.newLatLngZoom(
//             LatLng(widget.earthquake.latitude, widget.earthquake.longitude),
//             8,
//           ));
//         },
//         child: Icon(Icons.my_location),
//         tooltip: 'ไปยังจุดศูนย์กลาง',
//       ),
//     );
//   }

//   Widget _buildLegend() {
//     return Container(
//       padding: EdgeInsets.all(8),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(8),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black26,
//             blurRadius: 4,
//             offset: Offset(0, 2),
//           ),
//         ],
//       ),
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Text('ระดับความรุนแรง (MMI)', style: TextStyle(fontWeight: FontWeight.bold)),
//           SizedBox(height: 4),
//           for (int i = 1; i <= 12; i++)
//             Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   width: 16,
//                   height: 16,
//                   color: _getIntensityColor(i),
//                 ),
//                 SizedBox(width: 4),
//                 Text('$i'),
//               ],
//             ),
//         ],
//       ),
//     );
//   }

//   void _showIntensityInfo() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text('ระดับความรุนแรง (MMI)'),
//         content: SingleChildScrollView(
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text('I. ไม่รู้สึก (Not felt)'),
//               Text('II. รู้สึกได้เล็กน้อย (Weak)'),
//               Text('III. รู้สึกได้เบาๆ (Weak)'),
//               Text('IV. รู้สึกชัดเจน (Light)'),
//               Text('V. รู้สึกแรง (Moderate)'),
//               Text('VI. รู้สึกแรงมาก (Strong)'),
//               Text('VII. รุนแรง (Very strong)'),
//               Text('VIII. รุนแรงมาก (Severe)'),
//               Text('IX. รุนแรงมาก/โครงสร้างเสียหาย (Violent)'),
//               Text('X. รุนแรงรุนแรง/โครงสร้างพังทลาย (Extreme)'),
//               Text('XI-XII. รุนแรงถึงขั้นหายนะ (Extreme)'),
//             ],
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () {
//               Navigator.of(context).pop();
//             },
//             child: Text('ปิด'),
//           ),
//         ],
//       ),
//     );
//   }
// }