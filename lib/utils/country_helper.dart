// lib/utils/country_helper.dart
import 'package:flutter/material.dart';
import 'package:flag/flag.dart';
import 'package:flutter/foundation.dart';

/// ตัวช่วยสำหรับแสดงธงชาติจากข้อมูลตำแหน่งแผ่นดินไหว
class CountryHelper {
  /// รายการภูมิภาคที่ใช้งานในแอพ
  static final List<RegionOption> seaRegions = [
    const RegionOption(
      name: 'ทั้งหมด',
      code: 'all',
      description: 'แสดงข้อมูลแผ่นดินไหวทุกพื้นที่',
    ),
    const RegionOption(
      name: 'ประเทศไทย',
      code: 'th',
      description: 'แสดงเฉพาะแผ่นดินไหวในประเทศไทย',
    ),
    const RegionOption(
      name: 'เอเชียตะวันออกเฉียงใต้',
      code: 'sea',
      description: 'แสดงแผ่นดินไหวในภูมิภาคเอเชียตะวันออกเฉียงใต้',
    ),
    const RegionOption(
      name: 'จีน',
      code: 'cn',
      description: 'แสดงแผ่นดินไหวในประเทศจีน',
    ),
    const RegionOption(
      name: 'ญี่ปุ่น',
      code: 'jp',
      description: 'แสดงแผ่นดินไหวในประเทศญี่ปุ่น',
    ),
    const RegionOption(
      name: 'ฟิลิปปินส์',
      code: 'ph',
      description: 'แสดงแผ่นดินไหวในประเทศฟิลิปปินส์',
    ),
    const RegionOption(
      name: 'อินโดนีเซีย',
      code: 'id',
      description: 'แสดงแผ่นดินไหวในประเทศอินโดนีเซีย',
    ),
    const RegionOption(
      name: 'พม่า',
      code: 'mm',
      description: 'แสดงแผ่นดินไหวในประเทศพม่า',
    ),
  ];

  /// แปลงชื่อสถานที่เป็นรหัสประเทศ (ISO 3166-1 alpha-2)
  static String? getCountryCode(String location) {
    // ตรวจสอบนิวซีแลนด์
    if (location.contains('New Zealand') || location.contains('NZ')) {
      return 'NZ';
    }
    
    // ตรวจสอบญี่ปุ่น
    if (location.contains('Japan') || location.contains('Honshu') || 
        location.contains('Tokyo') || location.contains('Osaka')) {
      return 'JP';
    }
    
    // ตรวจสอบอินโดนีเซีย
    if (location.contains('Indonesia') || location.contains('Java') || 
        location.contains('Sumatra') || location.contains('Bali') || 
        location.contains('Sulawesi')) {
      return 'ID';
    }
    
    // ตรวจสอบฟิลิปปินส์
    if (location.contains('Philippines') || location.contains('Luzon') || 
        location.contains('Mindanao')) {
      return 'PH';
    }
    
    // ตรวจสอบไทย
    if (location.contains('Thailand') || location.contains('Bangkok') || 
        location.contains('Chiang Mai') || location.contains('Phuket')) {
      return 'TH';
    }
    
    // ตรวจสอบสหรัฐอเมริกา
    if (location.contains('United States') || location.contains(', CA') || 
        location.contains(', AK') || location.contains(', HI') || 
        location.contains('Alaska') || location.contains('Hawaii') || 
        location.contains('California') || location.contains('Nevada') || 
        location.contains('Washington') || location.contains('Oregon') || 
        location.contains('Idaho') || location.contains('Montana') || 
        location.contains('Wyoming') || location.contains('Utah') || 
        location.contains('Colorado') || location.contains('Arizona') || 
        location.contains('New Mexico')) {
      return 'US';
    }
    
    // ตรวจสอบชิลี
    if (location.contains('Chile') || location.contains('Santiago')) {
      return 'CL';
    }
    
    // ตรวจสอบเม็กซิโก
    if (location.contains('Mexico') || location.contains('Oaxaca') || 
        location.contains('Guerrero')) {
      return 'MX';
    }
    
    // ตรวจสอบแคนาดา
    if (location.contains('Canada') || location.contains('Vancouver') || 
        location.contains('British Columbia') || location.contains(', BC')) {
      return 'CA';
    }
    
    // ตรวจสอบจีน
    if (location.contains('China') || location.contains('Sichuan') || 
        location.contains('Yunnan') || location.contains('Tibet') || 
        location.contains('Xinjiang')) {
      return 'CN';
    }
    
    // ตรวจสอบออสเตรเลีย
    if (location.contains('Australia') || location.contains('Sydney') || 
        location.contains('Melbourne') || location.contains('Queensland')) {
      return 'AU';
    }
    
    // ตรวจสอบอิหร่าน
    if (location.contains('Iran') || location.contains('Tehran')) {
      return 'IR';
    }
    
    // ตรวจสอบตุรกี
    if (location.contains('Turkey') || location.contains('Istanbul') || 
        location.contains('Ankara')) {
      return 'TR';
    }
    
    // ตรวจสอบกรีซ
    if (location.contains('Greece') || location.contains('Athens') || 
        location.contains('Crete')) {
      return 'GR';
    }
    
    // ตรวจสอบอิตาลี
    if (location.contains('Italy') || location.contains('Rome') || 
        location.contains('Sicily') || location.contains('Naples')) {
      return 'IT';
    }
    
    // ตรวจสอบไต้หวัน
    if (location.contains('Taiwan')) {
      return 'TW';
    }
    
    // ตรวจสอบเปรู
    if (location.contains('Peru') || location.contains('Lima')) {
      return 'PE';
    }
    
    // ตรวจสอบอัฟกานิสถาน
    if (location.contains('Afghanistan') || location.contains('Kabul')) {
      return 'AF';
    }
    
    // ตรวจสอบปาปัวนิวกินี
    if (location.contains('Papua New Guinea') || location.contains('PNG')) {
      return 'PG';
    }
    
    // ตรวจสอบรัสเซีย
    if (location.contains('Russia') || location.contains('Kamchatka') || 
        location.contains('Siberia') || location.contains('Kuril')) {
      return 'RU';
    }
    
    // ตรวจสอบเนปาล
    if (location.contains('Nepal') || location.contains('Kathmandu')) {
      return 'NP';
    }
    
    // ตรวจสอบเวียดนาม
    if (location.contains('Vietnam') || location.contains('Hanoi') || 
        location.contains('Ho Chi Minh')) {
      return 'VN';
    }
    
    // ตรวจสอบมาเลเซีย
    if (location.contains('Malaysia') || location.contains('Kuala Lumpur') || 
        location.contains('Sabah') || location.contains('Sarawak')) {
      return 'MY';
    }
    
    // ตรวจสอบพม่า
    if (location.contains('Myanmar') || location.contains('Burma') || 
        location.contains('Yangon') || location.contains('Mandalay')) {
      return 'MM';
    }
    
    // ตรวจสอบลาว
    if (location.contains('Laos') || location.contains('Vientiane')) {
      return 'LA';
    }
    
    // ตรวจสอบกัมพูชา
    if (location.contains('Cambodia') || location.contains('Phnom Penh')) {
      return 'KH';
    }
    
    // ตรวจสอบอินเดีย
    if (location.contains('India') || location.contains('Delhi') || 
        location.contains('Mumbai') || location.contains('Himalaya')) {
      return 'IN';
    }
    
    // ตรวจสอบเอกวาดอร์
    if (location.contains('Ecuador') || location.contains('Quito')) {
      return 'EC';
    }
    
    // ตรวจสอบโคลอมเบีย
    if (location.contains('Colombia') || location.contains('Bogota')) {
      return 'CO';
    }
    
    // ตรวจสอบเวเนซุเอลา
    if (location.contains('Venezuela') || location.contains('Caracas')) {
      return 'VE';
    }
    
    // ตรวจสอบนิวซีแลนด์ (Kermadec Islands)
    if (location.contains('Kermadec')) {
      return 'NZ';
    }
    
    // ตรวจสอบโซโลมอน ไอส์แลนด์
    if (location.contains('Solomon Islands') || location.contains('Solomon')) {
      return 'SB';
    }
    
    // ตรวจสอบวานูอาตู
    if (location.contains('Vanuatu')) {
      return 'VU';
    }
    
    // ตรวจสอบฟิจิ
    if (location.contains('Fiji')) {
      return 'FJ';
    }
    
    // ตรวจสอบตองกา
    if (location.contains('Tonga')) {
      return 'TO';
    }
    
    // ตรวจสอบซามัว
    if (location.contains('Samoa')) {
      return 'WS';
    }
    
    // ตรวจสอบเม็กซิโก (Baja)
    if (location.contains('Baja')) {
      return 'MX';
    }
    
    // ตรวจสอบหมู่เกาะมาเรียนา (หมู่เกาะในมหาสมุทรแปซิฟิก)
    if (location.contains('Mariana Islands') || location.contains('Mariana')) {
      return 'MP'; // Northern Mariana Islands
    }
    
    // ตรวจสอบทะเลแคริบเบียน
    if (location.contains('Caribbean') || location.contains('Puerto Rico') || 
        location.contains('Dominican Republic')) {
      if (location.contains('Puerto Rico')) {
        return 'PR';
      } else if (location.contains('Dominican Republic')) {
        return 'DO';
      } else if (location.contains('Haiti')) {
        return 'HT';
      } else if (location.contains('Jamaica')) {
        return 'JM';
      } else if (location.contains('Cuba')) {
        return 'CU';
      } else {
        return 'PR'; // เป็นแค่ค่าเริ่มต้นหากไม่ทราบประเทศที่แน่ชัด
      }
    }
    
    return null; // หากไม่พบประเทศที่ตรงกัน
  }
  
  /// สร้าง Widget แสดงธงชาติจากชื่อสถานที่
  static Widget buildCountryFlag(String locationOrCode, {double size = 24.0}) {
    String? countryCode;
    
    // ตรวจสอบว่าข้อมูลที่ส่งมาเป็นรหัสประเทศ (มี 2 ตัวอักษร) หรือชื่อสถานที่
    if (locationOrCode.length == 2) {
      // ถ้าเป็นรหัสประเทศอยู่แล้ว ใช้เลย
      countryCode = locationOrCode;
    } else {
      // ถ้าเป็นชื่อสถานที่ ให้แปลงเป็นรหัสประเทศ
      countryCode = getCountryCode(locationOrCode);
    }
    
    if (countryCode != null) {
      try {
        return Flag.fromString(
          countryCode,
          height: size,
          width: size * 1.5,
          fit: BoxFit.contain,
          borderRadius: 4.0,
        );
      } catch (e) {
        // หากมีข้อผิดพลาดในการแสดงธง
        debugPrint('Error showing flag for code $countryCode: $e');
        return Icon(Icons.flag, size: size, color: Colors.grey);
      }
    }
    
    // หากไม่สามารถระบุประเทศได้
    return Icon(Icons.flag_outlined, size: size, color: Colors.grey);
  }

  /// Checks if a location contains text matching any Southeast Asian country
  static bool isInSoutheastAsia(String location) {
    final seaKeywords = [
      'Thailand', 'ไทย',
      'Indonesia', 'อินโดนีเซีย',
      'Malaysia', 'มาเลเซีย',
      'Singapore', 'สิงคโปร์',
      'Philippines', 'ฟิลิปปินส์',
      'Vietnam', 'เวียดนาม',
      'Myanmar', 'พม่า',
      'Cambodia', 'กัมพูชา',
      'Laos', 'ลาว',
      'Brunei', 'บรูไน',
      'East Timor', 'ติมอร์-เลสเต', 'ติมอร์ตะวันออก',
    ];

    final isMatch = seaKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
    
    if (isMatch && kDebugMode) {
      final matchedKeyword = seaKeywords.firstWhere(
        (keyword) => location.toLowerCase().contains(keyword.toLowerCase()),
        orElse: () => ''
      );
      debugPrint('Location "$location" matches Southeast Asia keyword: $matchedKeyword');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching Thailand
  static bool isInThailand(String location) {
    final thaiKeywords = ['Thailand', 'ไทย', 'Bangkok', 'Chiang Mai', 'Phuket', 'Krabi', 'Pattaya'];
    final isMatch = thaiKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches Thailand');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching China
  static bool isInChina(String location) {
    final chinaKeywords = ['China', 'จีน', 'Sichuan', 'Yunnan', 'Tibet', 'Xinjiang', 'Beijing', 'Shanghai'];
    final isMatch = chinaKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches China');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching Japan
  static bool isInJapan(String location) {
    final japanKeywords = ['Japan', 'ญี่ปุ่น', 'Honshu', 'Tokyo', 'Osaka', 'Kyoto', 'Hokkaido'];
    final isMatch = japanKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches Japan');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching Philippines
  static bool isInPhilippines(String location) {
    final phKeywords = ['Philippines', 'ฟิลิปปินส์', 'Luzon', 'Mindanao', 'Manila', 'Davao'];
    final isMatch = phKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches Philippines');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching Indonesia
  static bool isInIndonesia(String location) {
    final idKeywords = ['Indonesia', 'อินโดนีเซีย', 'Java', 'Sumatra', 'Bali', 'Sulawesi', 'Jakarta', 'Bandung'];
    final isMatch = idKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches Indonesia');
    }
    
    return isMatch;
  }

  /// Checks if a location contains text matching Myanmar
  static bool isInMyanmar(String location) {
    final mmKeywords = ['Myanmar', 'พม่า', 'Burma'];
    final isMatch = mmKeywords.any((keyword) => 
      location.toLowerCase().contains(keyword.toLowerCase()));
      
    if (isMatch && kDebugMode) {
      debugPrint('Location "$location" matches Myanmar');
    }
    
    return isMatch;
  }

  /// Get the appropriate filter function based on region code
  static bool Function(String) getFilterFunction(String regionCode) {
    debugPrint('Getting filter function for region code: $regionCode');
    
    switch (regionCode) {
      case 'th':
        return isInThailand;
      case 'sea':
        return isInSoutheastAsia;
      case 'cn':
        return isInChina;
      case 'jp':
        return isInJapan;
      case 'ph':
        return isInPhilippines;
      case 'id':
        return isInIndonesia;
      case 'mm':
        return isInMyanmar;
      case 'all':
      default:
        debugPrint('Using default "all" filter (no filtering)');
        return (_) => true; // No filtering
    }
  }
}

/// Class representing a region option for filtering
class RegionOption {
  final String name;
  final String code;
  final String description;

  const RegionOption({
    required this.name, 
    required this.code, 
    required this.description,
  });
}