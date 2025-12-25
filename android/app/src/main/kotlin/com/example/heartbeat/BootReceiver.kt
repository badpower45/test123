package com.example.heartbeat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Boot Receiver - Handles device boot completion
 * 
 * This receiver is triggered when the device boots up or when the app is updated.
 * It helps restart background tracking services for old devices like Realme 6, Galaxy A12, etc.
 * 
 * For Flutter apps, the main restart logic is handled by Flutter plugins.
 * This receiver just ensures the app is awakened.
 */
class BootReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "BootReceiver"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        
        Log.d(TAG, "Boot receiver triggered with action: $action")
        
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "Device booted or app updated - checking for active attendance")
                
                // The actual restart logic is handled by Flutter when the app opens
                // This receiver just logs the boot event
                
                // Check SharedPreferences for active attendance
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val hasActiveAttendance = prefs.contains("flutter.active_employee_id")
                
                if (hasActiveAttendance) {
                    Log.d(TAG, "Active attendance found - app should auto-resume tracking when opened")
                    
                    // Optionally, we could start the MainActivity here to trigger Flutter
                    // But that might be intrusive, so we just log it
                    // The FlutterForegroundTask plugin should handle auto-restart if configured
                }
            }
        }
    }
}
