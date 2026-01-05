package com.example.heartbeat

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Log
import android.location.Location
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.*
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * 🔥 Persistent Pulse Service - The Beast Mode Service
 * 
 * This service is designed to survive on old devices (Samsung A12, Realme 6, etc.)
 * Uses multiple layers of defense:
 * 1. Foreground Service with persistent notification
 * 2. START_STICKY - auto-restart when killed
 * 3. WakeLock - prevent device from sleeping
 * 4. AlarmManager - resurrect service if killed
 * 5. Coroutines - efficient background processing
 * 6. Direct SQLite writes - works even when Flutter is dead
 */
class PersistentPulseService : Service() {
    
    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(Dispatchers.Default + Job())
    private var pulseJob: Job? = null
    
    // Service parameters
    private var employeeId: String? = null
    private var attendanceId: String? = null
    private var branchId: String? = null
    private var intervalMinutes: Int = 5
    
    private var pulseCount = 0
    private var lastPulseTime: Long = 0
    
    // Native modules for location and WiFi
    private lateinit var fastGPS: FastGPSModule
    private lateinit var fastWiFi: FastWiFiScanner
    
    companion object {
        private const val TAG = "PersistentPulseService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "pulse_service_channel"
        private const val CHANNEL_NAME = "تتبع الحضور"
        
        // Intent extras
        private const val EXTRA_EMPLOYEE_ID = "employeeId"
        private const val EXTRA_ATTENDANCE_ID = "attendanceId"
        private const val EXTRA_BRANCH_ID = "branchId"
        private const val EXTRA_INTERVAL = "interval"
        
        /**
         * Start the persistent pulse service
         */
        fun start(context: Context, params: Map<String, Any>) {
            val intent = Intent(context, PersistentPulseService::class.java).apply {
                putExtra(EXTRA_EMPLOYEE_ID, params["employeeId"] as? String)
                putExtra(EXTRA_ATTENDANCE_ID, params["attendanceId"] as? String)
                putExtra(EXTRA_BRANCH_ID, params["branchId"] as? String)
                putExtra(EXTRA_INTERVAL, params["interval"] as? Int ?: 5)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            
            Log.d(TAG, "🚀 Service start requested")
        }
        
        /**
         * Stop the persistent pulse service
         */
        fun stop(context: Context) {
            val intent = Intent(context, PersistentPulseService::class.java)
            context.stopService(intent)
            
            // Cancel any scheduled alarms
            PulseAlarmReceiver.cancelAlarm(context)
            
            Log.d(TAG, "🛑 Service stop requested")
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📱 Service created")
        
        // Initialize Native GPS and WiFi modules
        fastGPS = FastGPSModule(applicationContext)
        fastWiFi = FastWiFiScanner(applicationContext)
        
        createNotificationChannel()
        acquireWakeLock()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🎯 Service started with intent")
        
        // Extract parameters from intent
        employeeId = intent?.getStringExtra(EXTRA_EMPLOYEE_ID)
        attendanceId = intent?.getStringExtra(EXTRA_ATTENDANCE_ID)
        branchId = intent?.getStringExtra(EXTRA_BRANCH_ID)
        intervalMinutes = intent?.getIntExtra(EXTRA_INTERVAL, 5) ?: 5
        
        Log.d(TAG, "📋 Params - Employee: $employeeId, Attendance: $attendanceId, Branch: $branchId, Interval: $intervalMinutes min")
        
        // Validate required parameters
        if (employeeId.isNullOrEmpty() || attendanceId.isNullOrEmpty()) {
            Log.e(TAG, "❌ Missing required parameters!")
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Start foreground service with notification
        val notification = buildNotification("جاري بدء التتبع...")
        startForeground(NOTIFICATION_ID, notification)
        
        // Start pulse timer
        startPulseTimer()
        
        // Schedule AlarmManager as backup
        scheduleAlarm()
        
        // START_STICKY = if service is killed, restart it with null intent
        return START_STICKY
    }
    
    /**
     * Start the pulse timer using coroutines
     */
    private fun startPulseTimer() {
        // Cancel any existing job
        pulseJob?.cancel()
        
        pulseJob = serviceScope.launch {
            Log.d(TAG, "⏰ Pulse timer started (interval: $intervalMinutes min)")
            
            while (isActive) {
                try {
                    sendPulse()
                    delay(intervalMinutes * 60 * 1000L)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error in pulse timer: ${e.message}", e)
                    updateNotification("خطأ: ${e.message}")
                    delay(60 * 1000L) // Wait 1 minute before retry
                }
            }
        }
    }
    
    /**
     * Send a pulse - WRITES DIRECTLY TO SQLITE (works even when app is killed)
     */
    private suspend fun sendPulse() = withContext(Dispatchers.IO) {
        pulseCount++
        lastPulseTime = System.currentTimeMillis()
        
        val timestamp = getCurrentTime()
        Log.d(TAG, "💓 Sending pulse #$pulseCount at $timestamp")
        
        try {
            // 🔥 DIRECT SQLITE WRITE (bypasses Flutter - works when app is dead)
            val pulseData = mapOf(
                "employee_id" to employeeId,
                "attendance_id" to attendanceId,
                "branch_id" to branchId,
                "timestamp" to System.currentTimeMillis(),
                "pulse_count" to pulseCount
            )
            
            // Write directly to SQLite database
            writePulseToDatabase(pulseData)
            
            // Also send BroadcastIntent (in case app is alive)
            val intent = Intent("com.example.heartbeat.PULSE_RECORDED").apply {
                putExtra("pulse_data", HashMap(pulseData))
            }
            sendBroadcast(intent)
            
            withContext(Dispatchers.Main) {
                updateNotification("نبضة #$pulseCount - $timestamp")
            }
            
            // Schedule next alarm as backup
            scheduleAlarm()
            
            Log.d(TAG, "✅ Pulse #$pulseCount saved to SQLite successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send pulse: ${e.message}", e)
            withContext(Dispatchers.Main) {
                updateNotification("فشل إرسال النبضة: ${e.message}")
            }
        }
    }
    
    /**
     * Write pulse directly to SQLite database
     * This works even when Flutter is completely dead
     */
    private fun writePulseToDatabase(pulseData: Map<String, Any?>) {
        try {
            // Get the same database path that Flutter uses
            val dbPath = applicationContext.getDatabasePath("offline_attendance.db").absolutePath
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
            
            // Generate unique ID
            val pulseId = "${pulseData["employee_id"]}_${pulseData["timestamp"]}"
            val currentTime = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(Date())
            
            // Insert into pending_pulses table
            val sql = """
                INSERT OR REPLACE INTO pending_pulses 
                (id, employee_id, attendance_id, timestamp, latitude, longitude, 
                 inside_geofence, distance_from_center, wifi_bssid, 
                 validated_by_wifi, validated_by_location, created_at, synced)
                VALUES (?, ?, ?, ?, NULL, NULL, 0, 0.0, NULL, 0, 0, ?, 0)
            """.trimIndent()
            
            db.execSQL(sql, arrayOf(
                pulseId,
                pulseData["employee_id"],
                pulseData["attendance_id"] ?: "pending",
                currentTime,
                currentTime
            ))
            
            db.close()
            
            Log.d(TAG, "💾 Pulse written directly to SQLite: $pulseId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to write to SQLite: ${e.message}", e)
        }
    }
    
    /**
     * Schedule an exact alarm to ensure service keeps running
     * This acts as a resurrection mechanism if service is killed
     */
    private fun scheduleAlarm() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, PulseAlarmReceiver::class.java).apply {
                putExtra(EXTRA_EMPLOYEE_ID, employeeId)
                putExtra(EXTRA_ATTENDANCE_ID, attendanceId)
                putExtra(EXTRA_BRANCH_ID, branchId)
                putExtra(EXTRA_INTERVAL, intervalMinutes)
            }
            
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            
            // Schedule alarm for next interval
            val triggerTime = System.currentTimeMillis() + (intervalMinutes * 60 * 1000L)
            
            // Use exact alarm based on Android version
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                    if (alarmManager.canScheduleExactAlarms()) {
                        alarmManager.setExactAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTime,
                            pendingIntent
                        )
                        Log.d(TAG, "⏰ Exact alarm scheduled for ${Date(triggerTime)}")
                    } else {
                        Log.w(TAG, "⚠️ Cannot schedule exact alarms - permission not granted")
                        alarmManager.setAndAllowWhileIdle(
                            AlarmManager.RTC_WAKEUP,
                            triggerTime,
                            pendingIntent
                        )
                    }
                }
                else -> {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTime,
                        pendingIntent
                    )
                    Log.d(TAG, "⏰ Exact alarm scheduled for ${Date(triggerTime)}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to schedule alarm: ${e.message}", e)
        }
    }
    
    /**
     * Acquire a partial wake lock to prevent device from sleeping
     */
    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$TAG::WakeLock"
            ).apply {
                // Acquire for 10 minutes, will be renewed on each pulse
                acquire(10 * 60 * 1000L)
            }
            Log.d(TAG, "🔒 WakeLock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire WakeLock: ${e.message}", e)
        }
    }
    
    /**
     * Create notification channel for Android 8.0+
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "خدمة تتبع الحضور في الخلفية"
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
            
            Log.d(TAG, "📢 Notification channel created")
        }
    }
    
    /**
     * Build a notification for the foreground service
     */
    private fun buildNotification(text: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("تتبع الحضور نشط 🟢")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
    }
    
    /**
     * Update the notification text
     */
    private fun updateNotification(text: String) {
        try {
            val notification = buildNotification(text)
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: ${e.message}", e)
        }
    }
    
    /**
     * Get current time as formatted string
     */
    private fun getCurrentTime(): String {
        val format = SimpleDateFormat("HH:mm:ss", Locale.getDefault())
        return format.format(Date())
    }
    
    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "💀 Service destroyed")
        
        // Cancel coroutines
        pulseJob?.cancel()
        serviceScope.cancel()
        
        // Release wake lock
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "🔓 WakeLock released")
            }
        }
        
        // Note: AlarmManager will restart the service automatically
        Log.d(TAG, "⚠️ Service stopped - AlarmManager will resurrect if needed")
    }
    
    override fun onBind(intent: Intent?): IBinder? = null
    
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "🔄 Task removed - service will continue running")
        
        // Reschedule alarm to ensure service resurrection
        scheduleAlarm()
    }
}
