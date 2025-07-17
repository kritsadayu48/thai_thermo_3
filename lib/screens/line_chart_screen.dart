import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/earthquake.dart';
import '../services/earthquake_service.dart';
import '../utils/country_helper.dart';

class LineChartScreen extends StatefulWidget {
  final String location;
  final List<Earthquake> earthquakes;
  final bool isCountry;
  final String? countryCode;

  const LineChartScreen({
    super.key,
    required this.location,
    required this.earthquakes,
    this.isCountry = false,
    this.countryCode,
  });

  @override
  State<LineChartScreen> createState() => _LineChartScreenState();
}

class _LineChartScreenState extends State<LineChartScreen> {
  List<Earthquake> _sortedEarthquakes = [];
  bool _showLast7Days = true;
  double _maxY = 10.0;
  
  @override
  void initState() {
    super.initState();
    _prepareData();
  }
  
  void _prepareData() {
    // Sort earthquakes by time (ascending)
    final sortedData = List<Earthquake>.from(widget.earthquakes)
      ..sort((a, b) => a.time.compareTo(b.time));
    
    // Filter by time if needed
    final filteredData = _showLast7Days
        ? sortedData.where((e) => 
            DateTime.now().difference(e.time).inDays <= 7).toList()
        : sortedData;
    
    // Find the maximum magnitude for Y-axis scaling
    double maxMagnitude = 0;
    if (filteredData.isNotEmpty) {
      maxMagnitude = filteredData.map((e) => e.magnitude).reduce((a, b) => a > b ? a : b);
    }
    
    setState(() {
      _sortedEarthquakes = filteredData;
      _maxY = maxMagnitude > 0 ? (maxMagnitude.ceil() + 1).toDouble() : 10.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final earthquakeService = Provider.of<EarthquakeService>(context);
    final isStarred = earthquakeService.isLocationStarred(widget.location);
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // พื้นหลังสีดำ
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212), // แถบด้านบนสีดำ
        title: Row(
          children: [
            if (widget.isCountry && widget.countryCode != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: CountryHelper.buildCountryFlag(widget.countryCode!, size: 24),
              ),
            Expanded(
              child: Text(
                widget.location,
                style: const TextStyle(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white), // ไอคอนสีขาว
        actions: [
          // ปุ่มตั้งพื้นที่นี้เป็นค่าเริ่มต้น
          IconButton(
            icon: Icon(
              isStarred ? Icons.star : Icons.star_border,
              color: isStarred ? Colors.orange : Colors.white, // เปลี่ยนสีเป็นส้ม
            ),
            onPressed: () {
              earthquakeService.toggleStarredLocation(widget.location);
            },
            tooltip: isStarred ? 'ยกเลิกการติดดาวพื้นที่นี้' : 'ติดดาวพื้นที่นี้',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: () {
              setState(() {
                _showLast7Days = !_showLast7Days;
                _prepareData();
              });
            },
            tooltip: _showLast7Days ? '7 วันล่าสุด' : 'ทั้งหมด',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Chart info
            Card(
              elevation: 4,
              color: const Color(0xFF1E1E1E), // สีการ์ดเข้มกว่าพื้นหลังเล็กน้อย
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.isCountry 
                               ? 'แผ่นดินไหวในประเทศ${widget.location}'
                               : 'แผ่นดินไหวที่ ${widget.location}',
                            style: const TextStyle(
                              fontSize: 18, 
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isStarred)
                          const Icon(Icons.star, color: Colors.orange, size: 20), // เปลี่ยนสีเป็นส้ม
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'จำนวนเหตุการณ์: ${_sortedEarthquakes.length} ครั้ง',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    Text(
                      'ช่วงข้อมูล: ${_showLast7Days ? "7 วันล่าสุด" : "ทั้งหมด"}',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Filter switch
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Text(
                    'แสดงข้อมูล: ${_showLast7Days ? "7 วันล่าสุด" : "ทั้งหมด"}',
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                  const Spacer(),
                  Switch(
                    value: _showLast7Days,
                    activeColor: Colors.orange, // สีเมื่อเปิดใช้งาน
                    onChanged: (value) {
                      setState(() {
                        _showLast7Days = value;
                        _prepareData();
                      });
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Chart title
            const Text(
              'แนวโน้มความแรงของแผ่นดินไหว',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            
            // Line chart
            Expanded(
              child: _sortedEarthquakes.isEmpty
                  ? const Center(
                      child: Text(
                        'ไม่มีข้อมูลในช่วงเวลาที่เลือก',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: LineChart(
                        _buildLineChartData(),
                        duration: const Duration(milliseconds: 500),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildLineChartData() {
    return LineChartData(
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.grey.withOpacity(0.2),
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: _getTimeInterval(),
            getTitlesWidget: (value, meta) {
              if (value < 0 || value >= _sortedEarthquakes.length) {
                return const SizedBox.shrink();
              }
              final date = _sortedEarthquakes[value.toInt()].time;
              return Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  DateFormat('dd/MM').format(date),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(1),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      minX: 0,
      maxX: _sortedEarthquakes.length - 1.0,
      minY: 0,
      maxY: _maxY,
      lineBarsData: [
        LineChartBarData(
          spots: _createSpots(),
          isCurved: true,
          color: Colors.orange, // สีส้ม
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.orange.withOpacity(0.2), // สีส้มโปร่งแสง
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        enabled: true,
        touchTooltipData: LineTouchTooltipData(
          tooltipRoundedRadius: 8,
          getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
            return touchedBarSpots.map((barSpot) {
              final int index = barSpot.x.toInt();
              if (index >= 0 && index < _sortedEarthquakes.length) {
                final earthquake = _sortedEarthquakes[index];
                return LineTooltipItem(
                  '${earthquake.magnitude} แมกนิจูด\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: DateFormat('dd/MM/yyyy HH:mm').format(earthquake.time),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                );
              }
              return null;
            }).toList();
          },
        ),
      ),
    );
  }

  List<FlSpot> _createSpots() {
    final List<FlSpot> spots = [];
    for (int i = 0; i < _sortedEarthquakes.length; i++) {
      spots.add(FlSpot(i.toDouble(), _sortedEarthquakes[i].magnitude));
    }
    return spots;
  }
  
  double _getTimeInterval() {
    // Adjust the interval based on the number of data points
    if (_sortedEarthquakes.length <= 5) {
      return 1;
    } else if (_sortedEarthquakes.length <= 10) {
      return 2;
    } else if (_sortedEarthquakes.length <= 20) {
      return 4;
    } else {
      return (_sortedEarthquakes.length / 5).floorToDouble();
    }
  }
} 