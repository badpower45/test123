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
        private const val PERSISTENT_PREFS = "persistent_pulse_service"
        private const val EXTRA_EMPLOYEE_ID = "employeeId"
        private const val EXTRA_ATTENDANCE_ID = "attendanceId"
        private const val EXTRA_BRANCH_ID = "branchId"
        private const val EXTRA_INTERVAL = "interval"
        private const val EXTRA_BRANCH_LAT = "branchLatitude"
        private const val EXTRA_BRANCH_LNG = "branchLongitude"
        private const val EXTRA_BRANCH_RADIUS = "branchRadius"
    }
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        
        Log.d(TAG, "Boot receiver triggered with action: $action")
        
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.d(TAG, "Device booted or app updated - restoring native pulse service if needed")

                val prefs = context.getSharedPreferences(PERSISTENT_PREFS, Context.MODE_PRIVATE)
                val employeeId = prefs.getString(EXTRA_EMPLOYEE_ID, null)
                val attendanceId = prefs.getString(EXTRA_ATTENDANCE_ID, null)

                if (employeeId.isNullOrEmpty() || attendanceId.isNullOrEmpty()) {
                    Log.d(TAG, "No persisted active attendance found, skipping service restore")
                    return
                }

                val branchId = prefs.getString(EXTRA_BRANCH_ID, "") ?: ""
                val interval = prefs.getInt(EXTRA_INTERVAL, 5).coerceAtLeast(1)
                val branchLatitude = java.lang.Double.longBitsToDouble(
                    prefs.getLong(EXTRA_BRANCH_LAT, java.lang.Double.doubleToRawLongBits(0.0))
                )
                val branchLongitude = java.lang.Double.longBitsToDouble(
                    prefs.getLong(EXTRA_BRANCH_LNG, java.lang.Double.doubleToRawLongBits(0.0))
                )
                val branchRadius = java.lang.Double.longBitsToDouble(
                    prefs.getLong(EXTRA_BRANCH_RADIUS, java.lang.Double.doubleToRawLongBits(100.0))
                )

                val params = mapOf(
                    "employeeId" to employeeId,
                    "attendanceId" to attendanceId,
                    "branchId" to branchId,
                    "interval" to interval,
                    "branchLatitude" to branchLatitude,
                    "branchLongitude" to branchLongitude,
                    "branchRadius" to branchRadius
                )

                PersistentPulseService.start(context, params)
                Log.d(TAG, "PersistentPulseService restored after reboot/update")
            }
        }
    }
}
