import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/earthquake.dart';
import '../services/earthquake_service.dart';
import '../utils/country_helper.dart';
import 'line_chart_screen.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({super.key});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  bool _isLoading = false;
  List<String> _countries = [];
  Map<String, List<Earthquake>> _earthquakesByCountry = {};
  Map<String, String> _countryCodeMap = {};

  @override
  void initState() {
    super.initState();
    _loadCountryData();
  }

  void _loadCountryData() {
    setState(() {
      _isLoading = true;
    });

    // ดึงข้อมูลแผ่นดินไหวโดยไม่ส่งการแจ้งเตือน
    final earthquakeService = Provider.of<EarthquakeService>(context, listen: false);
    
    // อาจต้องมีการรีเฟรชข้อมูลก่อน
    earthquakeService.forceCheckImmediate().then((_) {
      
      final earthquakes = earthquakeService.getFilteredEarthquakes();

      // Group earthquakes by country
      final map = <String, List<Earthquake>>{};
      final codeMap = <String, String>{};
      
      for (final earthquake in earthquakes) {
        final countryCode = CountryHelper.getCountryCode(earthquake.location);
        String countryName = '';
        
        if (countryCode != null) {
          // ตั้งชื่อประเทศตามรหัส
          switch (countryCode) {
            case 'TH': countryName = 'ไทย'; break;
            case 'JP': countryName = 'ญี่ปุ่น'; break;
            case 'ID': countryName = 'อินโดนีเซีย'; break;
            case 'PH': countryName = 'ฟิลิปปินส์'; break;
            case 'MM': countryName = 'พม่า'; break;
            case 'LA': countryName = 'ลาว'; break;
            case 'VN': countryName = 'เวียดนาม'; break;
            case 'MY': countryName = 'มาเลเซีย'; break;
            case 'KH': countryName = 'กัมพูชา'; break;
            case 'CN': countryName = 'จีน'; break;
            case 'TW': countryName = 'ไต้หวัน'; break;
            case 'US': countryName = 'สหรัฐอเมริกา'; break;
            case 'NZ': countryName = 'นิวซีแลนด์'; break;
            case 'AU': countryName = 'ออสเตรเลีย'; break;
            case 'RU': countryName = 'รัสเซีย'; break;
            case 'MP': countryName = 'หมู่เกาะมาเรียนา'; break;
            case 'IN': countryName = 'อินเดีย'; break;
            case 'PG': countryName = 'ปาปัวนิวกินี'; break;
            case 'FJ': countryName = 'ฟิจิ'; break;
            case 'TO': countryName = 'ตองกา'; break;
            case 'SB': countryName = 'หมู่เกาะโซโลมอน'; break;
            case 'VU': countryName = 'วานูอาตู'; break;
            case 'CL': countryName = 'ชิลี'; break;
            case 'PE': countryName = 'เปรู'; break;
            case 'MX': countryName = 'เม็กซิโก'; break;
            case 'CA': countryName = 'แคนาดา'; break;
            case 'GR': countryName = 'กรีซ'; break;
            case 'TR': countryName = 'ตุรกี'; break;
            case 'IT': countryName = 'อิตาลี'; break;
            case 'IR': countryName = 'อิหร่าน'; break;
            case 'AF': countryName = 'อัฟกานิสถาน'; break;
            case 'PK': countryName = 'ปากีสถาน'; break;
            case 'NP': countryName = 'เนปาล'; break;
            case 'FR': countryName = 'ฝรั่งเศส'; break;
            case 'UK': countryName = 'สหราชอาณาจักร'; break;
            case 'GB': countryName = 'สหราชอาณาจักร'; break;
            case 'DE': countryName = 'เยอรมนี'; break;
            case 'WS': countryName = 'ซามัว'; break;
            case 'PW': countryName = 'ปาเลา'; break;
            case 'PR': countryName = 'เปอร์โตริโก'; break;
            case 'DO': countryName = 'สาธารณรัฐโดมินิกัน'; break;
            case 'HT': countryName = 'เฮติ'; break;
            case 'CU': countryName = 'คิวบา'; break;
            case 'JM': countryName = 'จาเมกา'; break;
            default: 
              // ใช้ชื่อทั่วไปสำหรับประเทศที่ไม่ได้ระบุใน case
              countryName = _getDefaultCountryName(countryCode);
          }
          
          codeMap[countryName] = countryCode;
        } else {
          // กรณีไม่ทราบประเทศให้ดูจากชื่อสถานที่แทน
          countryName = _getLocationBasedCountryName(earthquake.location);
          
          // ลองหารหัสประเทศจากชื่อสถานที่
          if (countryName == 'มหาสมุทรแปซิฟิก') {
            codeMap[countryName] = 'PF'; // ใช้รหัสของเฟรนช์โปลินีเซีย
          } else if (countryName == 'มหาสมุทรแอตแลนติก') {
            codeMap[countryName] = 'PT'; // ใช้รหัสของโปรตุเกส
          } else if (countryName == 'มหาสมุทรอินเดีย') {
            codeMap[countryName] = 'IN'; // ใช้รหัสของอินเดีย
          } else if (countryName == 'ทะเลจีนใต้') {
            codeMap[countryName] = 'CN'; // ใช้รหัสของจีน
          } else if (countryName == 'อ่าวไทย') {
            codeMap[countryName] = 'TH'; // ใช้รหัสของไทย
          } else if (countryName == 'ทะเลอันดามัน') {
            codeMap[countryName] = 'TH'; // ใช้รหัสของไทย
          } else if (countryName == 'เทือกเขาหิมาลัย') {
            codeMap[countryName] = 'NP'; // ใช้รหัสของเนปาล
          } else if (countryName == 'ญี่ปุ่น') {
            codeMap[countryName] = 'JP';
          } else if (countryName == 'ไทย') {
            codeMap[countryName] = 'TH';
          } else if (countryName == 'อินโดนีเซีย') {
            codeMap[countryName] = 'ID';
          } else if (countryName == 'ฟิลิปปินส์') {
            codeMap[countryName] = 'PH';
          } else if (countryName == 'ไต้หวัน') {
            codeMap[countryName] = 'TW';
          } else if (countryName == 'เม็กซิโก') {
            codeMap[countryName] = 'MX';
          } else if (countryName == 'ฟิจิ') {
            codeMap[countryName] = 'FJ';
          }
          
          // ถ้ายังไม่มีชื่อ ให้ใช้ชื่อสถานที่เลย
          if (countryName.isEmpty) {
            countryName = earthquake.location;
          }
        }
        
        if (!map.containsKey(countryName)) {
          map[countryName] = [];
        }
        map[countryName]!.add(earthquake);
      }

      // Sort countries by number of earthquakes (descending)
      final sortedCountries = map.keys.toList()
        ..sort((a, b) => map[b]!.length.compareTo(map[a]!.length));

      setState(() {
        _earthquakesByCountry = map;
        _countries = sortedCountries;
        _countryCodeMap = codeMap;
        _isLoading = false;
      });
    });
  }

  // ฟังก์ชันสำหรับการกำหนดชื่อประเทศเริ่มต้นจากรหัสประเทศ
  String _getDefaultCountryName(String countryCode) {
    // ใช้ข้อมูลมาตรฐาน ISO 3166 สำหรับชื่อประเทศทั่วไป
    final Map<String, String> commonCountryCodes = {
      'AD': 'อันดอร์รา',
      'AE': 'สหรัฐอาหรับเอมิเรตส์',
      'AG': 'แอนติกาและบาร์บูดา',
      'AL': 'แอลเบเนีย',
      'AM': 'อาร์เมเนีย',
      'AO': 'แองโกลา',
      'AR': 'อาร์เจนตินา',
      'AT': 'ออสเตรีย',
      'AZ': 'อาเซอร์ไบจาน',
      'BA': 'บอสเนียและเฮอร์เซโกวีนา',
      'BB': 'บาร์เบโดส',
      'BD': 'บังกลาเทศ',
      'BE': 'เบลเยียม',
      'BF': 'บูร์กินาฟาโซ',
      'BG': 'บัลแกเรีย',
      'BH': 'บาห์เรน',
      'BI': 'บุรุนดี',
      'BJ': 'เบนิน',
      'BN': 'บรูไน',
      'BO': 'โบลิเวีย',
      'BR': 'บราซิล',
      'BS': 'บาฮามาส',
      'BT': 'ภูฏาน',
      'BW': 'บอตสวานา',
      'BY': 'เบลารุส',
      'BZ': 'เบลีซ',
      'CD': 'คองโก',
      'CF': 'สาธารณรัฐแอฟริกากลาง',
      'CG': 'คองโก',
      'CH': 'สวิตเซอร์แลนด์',
      'CI': 'โกตดิวัวร์',
      'CM': 'แคเมอรูน',
      'CO': 'โคลอมเบีย',
      'CR': 'คอสตาริกา',
      'CV': 'เคปเวิร์ด',
      'CY': 'ไซปรัส',
      'CZ': 'สาธารณรัฐเช็ก',
      'DJ': 'จิบูตี',
      'DK': 'เดนมาร์ก',
      'DM': 'โดมินิกา',
      'DZ': 'แอลจีเรีย',
      'EC': 'เอกวาดอร์',
      'EE': 'เอสโตเนีย',
      'EG': 'อียิปต์',
      'ER': 'เอริเทรีย',
      'ES': 'สเปน',
      'ET': 'เอธิโอเปีย',
      'FI': 'ฟินแลนด์',
      'FM': 'ไมโครนีเซีย',
      'GA': 'กาบอง',
      'GD': 'เกรนาดา',
      'GE': 'จอร์เจีย',
      'GH': 'กานา',
      'GM': 'แกมเบีย',
      'GN': 'กินี',
      'GQ': 'อิเควทอเรียลกินี',
      'GT': 'กัวเตมาลา',
      'GW': 'กินี-บิสเซา',
      'GY': 'กายอานา',
      'HN': 'ฮอนดูรัส',
      'HR': 'โครเอเชีย',
      'HU': 'ฮังการี',
      'IE': 'ไอร์แลนด์',
      'IL': 'อิสราเอล',
      'IQ': 'อิรัก',
      'IS': 'ไอซ์แลนด์',
      'JO': 'จอร์แดน',
      'KE': 'เคนยา',
      'KG': 'คีร์กีซสถาน',
      'KM': 'คอโมโรส',
      'KN': 'เซนต์คิตส์และเนวิส',
      'KP': 'เกาหลีเหนือ',
      'KR': 'เกาหลีใต้',
      'KW': 'คูเวต',
      'KZ': 'คาซัคสถาน',
      'LB': 'เลบานอน',
      'LC': 'เซนต์ลูเซีย',
      'LI': 'ลิกเตนสไตน์',
      'LK': 'ศรีลังกา',
      'LR': 'ไลบีเรีย',
      'LS': 'เลโซโท',
      'LT': 'ลิทัวเนีย',
      'LU': 'ลักเซมเบิร์ก',
      'LV': 'ลัตเวีย',
      'LY': 'ลิเบีย',
      'MA': 'โมร็อกโก',
      'MC': 'โมนาโก',
      'MD': 'มอลโดวา',
      'ME': 'มอนเตเนโกร',
      'MG': 'มาดากัสการ์',
      'MH': 'หมู่เกาะมาร์แชลล์',
      'MK': 'มาซิโดเนียเหนือ',
      'ML': 'มาลี',
      'MN': 'มองโกเลีย',
      'MR': 'มอริเตเนีย',
      'MT': 'มอลตา',
      'MU': 'มอริเชียส',
      'MV': 'มัลดีฟส์',
      'MW': 'มาลาวี',
      'MZ': 'โมซัมบิก',
      'NA': 'นามิเบีย',
      'NE': 'ไนเจอร์',
      'NG': 'ไนจีเรีย',
      'NI': 'นิการากัว',
      'NL': 'เนเธอร์แลนด์',
      'NO': 'นอร์เวย์',
      'OM': 'โอมาน',
      'PA': 'ปานามา',
      'PF': 'เฟรนช์โปลินีเซีย',
      'PH': 'ฟิลิปปินส์',
      'PL': 'โปแลนด์',
      'PT': 'โปรตุเกส',
      'PY': 'ปารากวัย',
      'QA': 'กาตาร์',
      'RO': 'โรมาเนีย',
      'RS': 'เซอร์เบีย',
      'RW': 'รวันดา',
      'SA': 'ซาอุดีอาระเบีย',
      'SC': 'เซเชลส์',
      'SD': 'ซูดาน',
      'SE': 'สวีเดน',
      'SG': 'สิงคโปร์',
      'SI': 'สโลวีเนีย',
      'SK': 'สโลวาเกีย',
      'SL': 'เซียร์ราลีโอน',
      'SM': 'ซานมารีโน',
      'SN': 'เซเนกัล',
      'SO': 'โซมาเลีย',
      'SR': 'ซูรินาม',
      'SS': 'ซูดานใต้',
      'ST': 'เซาตูเมและปรินซิปี',
      'SV': 'เอลซัลวาดอร์',
      'SY': 'ซีเรีย',
      'SZ': 'เอสวาตีนี',
      'TD': 'ชาด',
      'TG': 'โตโก',
      'TJ': 'ทาจิกิสถาน',
      'TL': 'ติมอร์-เลสเต',
      'TM': 'เติร์กเมนิสถาน',
      'TN': 'ตูนิเซีย',
      'TT': 'ตรินิแดดและโตเบโก',
      'TV': 'ตูวาลู',
      'TZ': 'แทนซาเนีย',
      'UA': 'ยูเครน',
      'UG': 'ยูกันดา',
      'UY': 'อุรุกวัย',
      'UZ': 'อุซเบกิสถาน',
      'VA': 'วาติกัน',
      'VC': 'เซนต์วินเซนต์และเกรนาดีนส์',
      'VE': 'เวเนซุเอลา',
      'YE': 'เยเมน',
      'ZA': 'แอฟริกาใต้',
      'ZM': 'แซมเบีย',
      'ZW': 'ซิมบับเว',
    };
    
    return commonCountryCodes[countryCode] ?? 'ประเทศ $countryCode';
  }

  // ดึงชื่อประเทศจากชื่อสถานที่
  String _getLocationBasedCountryName(String location) {
    final locationLower = location.toLowerCase();
    
    if (locationLower.contains('pacific') || locationLower.contains('ocean')) {
      return 'มหาสมุทรแปซิฟิก';
    } else if (locationLower.contains('atlantic')) {
      return 'มหาสมุทรแอตแลนติก';
    } else if (locationLower.contains('indian ocean')) {
      return 'มหาสมุทรอินเดีย';
    } else if (locationLower.contains('south china sea')) {
      return 'ทะเลจีนใต้';
    } else if (locationLower.contains('sea')) {
      return 'ทะเล';
    } else if (locationLower.contains('gulf of thailand')) {
      return 'อ่าวไทย';
    } else if (locationLower.contains('andaman')) {
      return 'ทะเลอันดามัน';
    } else if (locationLower.contains('himalaya')) {
      return 'เทือกเขาหิมาลัย';
    } else if (locationLower.contains('near') || locationLower.contains('offshore')) {
      // ดึงชื่อประเทศจากส่วนที่ระบุว่า near หรือ offshore
      if (locationLower.contains('japan')) return 'ญี่ปุ่น';
      if (locationLower.contains('thailand')) return 'ไทย';
      if (locationLower.contains('indonesia')) return 'อินโดนีเซีย';
      if (locationLower.contains('philippines')) return 'ฟิลิปปินส์';
      if (locationLower.contains('taiwan')) return 'ไต้หวัน';
      if (locationLower.contains('mexico')) return 'เม็กซิโก';
      if (locationLower.contains('fiji')) return 'ฟิจิ';
    }
    
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final earthquakeService = Provider.of<EarthquakeService>(context);
    final selectedLocation = earthquakeService.selectedLocation;
    final starredLocation = earthquakeService.starredLocation;
    
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // พื้นหลังสีดำเหมือนหน้าอื่น
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212), // สีแถบด้านบนเป็นสีดำ
        title: const Text('สถิติแผ่นดินไหวตามประเทศ',
        style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white), // สีไอคอนเป็นขาว
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange)) // สีส้ม
          : _countries.isEmpty
              ? const Center(
                  child: Text(
                    'ไม่พบข้อมูลแผ่นดินไหว',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                )
              : Column(
                  children: [
                    // แสดงพื้นที่ที่กำลังกรอง
                    if (selectedLocation != null)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                        color: Colors.orange.shade800, // สีส้มแทนสีฟ้า
                        child: Row(
                          children: [
                            const Icon(Icons.place, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'กำลังแสดงเฉพาะ: $selectedLocation',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Colors.white),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                earthquakeService.setSelectedLocation(null);
                                _loadCountryData();
                              },
                              tooltip: 'ยกเลิกการกรอง',
                            ),
                          ],
                        ),
                      ),
                    
                    // รายการประเทศ
                    Expanded(
                      child: ListView.builder(
                        itemCount: _countries.length,
                        itemBuilder: (context, index) {
                          final country = _countries[index];
                          final earthquakes = _earthquakesByCountry[country] ?? [];
                          final count = earthquakes.length;
                          final maxMagnitude = earthquakes.isNotEmpty
                              ? earthquakes.map((e) => e.magnitude).reduce((a, b) => a > b ? a : b)
                              : 0.0;
                          final countryCode = _countryCodeMap[country];

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            color: const Color(0xFF1E1E1E), // สีเข้มกว่าพื้นหลังเล็กน้อย
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: countryCode != null 
                                ? CountryHelper.buildCountryFlag(countryCode, size: 32)
                                : const Icon(Icons.flag_outlined, size: 32, color: Colors.grey),
                              title: Text(
                                country,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'จำนวน $count ครั้ง | แรงสูงสุด $maxMagnitude',
                                      style: TextStyle(color: Colors.grey[400]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (starredLocation == country)
                                    const Icon(Icons.star, size: 14, color: Colors.orange),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios, 
                                size: 16, color: Colors.orange),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LineChartScreen(
                                      location: country,
                                      earthquakes: earthquakes,
                                      isCountry: true,
                                      countryCode: countryCode,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
} 