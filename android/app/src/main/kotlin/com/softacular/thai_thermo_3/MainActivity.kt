package com.softacular.thai_thermo_3

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import android.os.Bundle
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import android.util.Log

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)
        
        // ตั้งค่า notification channel ให้มี behavior ที่ถูกต้อง
        NotificationChannelManager.setupChannels(applicationContext)
    }
}

object NotificationChannelManager {
    private const val TAG = "NotificationChannelMgr"
    
    fun setupChannels(context: Context) {
        // ตรวจสอบเวอร์ชัน Android ก่อนเรียกใช้งาน
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                
                // ตรวจสอบว่ามี channel หรือยัง
                val existingChannels = notificationManager.notificationChannels
                for (channel in existingChannels) {
                    Log.d(TAG, "Found existing channel: ${channel.id}, name: ${channel.name}")
                }
                
                // ตั้งค่าให้แต่ละ channel มีการจัดกลุ่มที่ถูกต้อง
                val earthquakeChannelId = "earthquake_alerts"
                val earthquakeChannel = notificationManager.getNotificationChannel(earthquakeChannelId)
                
                if (earthquakeChannel != null) {
                    Log.d(TAG, "Configuring earthquake channel: $earthquakeChannelId")
                    // ตั้งค่าการแสดงการแจ้งเตือนแบบกลุ่มเพื่อป้องกันการซ้ำ
                    earthquakeChannel.group = "earthquake_group"
                }
                
                Log.d(TAG, "Notification channels configured successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error setting up notification channels: ${e.message}")
            }
        }
    }
} 