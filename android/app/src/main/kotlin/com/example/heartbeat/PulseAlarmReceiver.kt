package com.example.heartbeat

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * 🔔 Pulse Alarm Receiver
 * 
 * This receiver is triggered by AlarmManager to:
 * 1. Ensure the PersistentPulseService is running
 * 2. Restart the service if it was killed
 * 3. Act as a resurrection mechanism
 */
class PulseAlarmReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "PulseAlarmReceiver"
        
        /**
         * Cancel any scheduled alarms
         */
        fun cancelAlarm(context: Context) {
            try {
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val intent = Intent(context, PulseAlarmReceiver::class.java)
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    0,
                    intent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
                
                Log.d(TAG, "⏰ Alarm cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to cancel alarm: ${e.message}", e)
            }
        }
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "⏰ Alarm received - checking service status")
        
        // Extract parameters from intent
        val employeeId = intent.getStringExtra("employeeId")
        val attendanceId = intent.getStringExtra("attendanceId")
        val branchId = intent.getStringExtra("branchId")
        val interval = intent.getIntExtra("interval", 5)
        val branchLatitude = intent.getDoubleExtra("branchLatitude", 0.0)
        val branchLongitude = intent.getDoubleExtra("branchLongitude", 0.0)
        val branchRadius = intent.getDoubleExtra("branchRadius", 100.0)
        
        Log.d(TAG, "📋 Params - Employee: $employeeId, Attendance: $attendanceId")
        
        // If we have valid parameters, ensure service is running
        if (!employeeId.isNullOrEmpty() && !attendanceId.isNullOrEmpty()) {
            val params = mapOf(
                "employeeId" to employeeId,
                "attendanceId" to attendanceId,
                "branchId" to (branchId ?: ""),
                "interval" to interval,
                "branchLatitude" to branchLatitude,
                "branchLongitude" to branchLongitude,
                "branchRadius" to branchRadius
            )
            
            // Restart the service
            PersistentPulseService.start(context, params)
            Log.d(TAG, "🔄 Service restart triggered")
        } else {
            Log.w(TAG, "⚠️ Missing parameters - cannot restart service")
        }
    }
}
