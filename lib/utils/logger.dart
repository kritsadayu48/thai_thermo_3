// lib/utils/logger.dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

// สร้าง instance ของ Logger เพื่อนำไปใช้ทั่วทั้งโปรเจ็กต์
class ReleaseAwareFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // ปิดทั้งหมดใน release
    return !kReleaseMode;
  }
}

var logger = Logger(
  filter: ReleaseAwareFilter(),
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
);