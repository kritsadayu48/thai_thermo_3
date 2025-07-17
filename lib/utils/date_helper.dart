import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// ตัวช่วยสำหรับจัดการเกี่ยวกับวันที่
class DateHelper {
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  
  /// คืนค่าวันที่เริ่มต้นของวันนี้
  static DateTime getStartOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  
  /// คืนค่าวันที่เริ่มต้นของสัปดาห์นี้ (วันจันทร์)
  static DateTime getStartOfWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // ย้อนไปเริ่มต้นที่วันจันทร์ (วันจันทร์คือวันที่ 1 ในสัปดาห์)
    return today.subtract(Duration(days: today.weekday - 1));
  }
  
  /// คืนค่าวันที่เริ่มต้นของเดือนนี้
  static DateTime getStartOfMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }
  
  /// คืนค่าวันที่เริ่มต้นของ 3 เดือนย้อนหลัง
  static DateTime getStartOfThreeMonthsAgo() {
    final now = DateTime.now();
    // ย้อนหลังไป 3 เดือน
    if (now.month > 3) {
      return DateTime(now.year, now.month - 3, 1);
    } else {
      // กรณีต้องข้ามปี
      return DateTime(now.year - 1, now.month + 9, 1);
    }
  }
  
  /// แปลงวันที่เป็นข้อความแสดงเวลาที่ผ่านมา เช่น "3 นาทีที่แล้ว", "2 ชั่วโมงที่แล้ว", "5 วันที่แล้ว"
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} วินาทีที่แล้ว';
    } 
    
    if (difference.inMinutes < 60) {
      return '${difference.inMinutes} นาทีที่แล้ว';
    } 
    
    if (difference.inHours < 24) {
      return '${difference.inHours} ชั่วโมงที่แล้ว';
    } 
    
    if (difference.inDays < 30) {
      return '${difference.inDays} วันที่แล้ว';
    }
    
    if (difference.inDays < 365) {
      return '${(difference.inDays / 30).floor()} เดือนที่แล้ว';
    }
    
    return '${(difference.inDays / 365).floor()} ปีที่แล้ว';
  }
  
  /// แปลงวันที่เป็นข้อความในรูปแบบ dd/MM/yyyy
  static String formatDate(DateTime dateTime) {
    return _dateFormat.format(dateTime);
  }
  
  /// แปลงวันที่เป็นข้อความในรูปแบบ dd/MM/yyyy HH:mm
  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormat.format(dateTime);
  }
} 