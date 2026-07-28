package com.example.heartbeat

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.*
import android.content.pm.ServiceInfo
import android.util.Log
import android.location.Location
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.*
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.media.MediaPlayer

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
 * 7. 🎵 Sticky Audio - Silent MediaPlayer prevents Deep Sleep (Samsung/Realme killer)
 */
class PersistentPulseService : Service() {
    
    private var wakeLock: PowerManager.WakeLock? = null
    private val serviceScope = CoroutineScope(Dispatchers.Default + Job())
    private var pulseJob: Job? = null
    
    // 🎵 NEW: Silent audio player for preventing Deep Sleep
    private lateinit var mediaPlayer: MediaPlayer
    
    // Service parameters
    private var employeeId: String? = null
    private var attendanceId: String? = null
    private var branchId: String? = null
    private var intervalMinutes: Int = 5
    private var shiftEndTimeEpoch: Long = 0L
    
    // Branch location for geofence check
    private var branchLatitude: Double = 0.0
    private var branchLongitude: Double = 0.0
    private var branchRadius: Double = 100.0
    
    private var pulseCount = 0
    private var lastPulseTime: Long = 0
    private var serviceStartTime: Long = 0L
    
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
        private const val EXTRA_BRANCH_LAT = "branchLatitude"
        private const val EXTRA_BRANCH_LNG = "branchLongitude"
        private const val EXTRA_BRANCH_RADIUS = "branchRadius"
        private const val EXTRA_SHIFT_END_TIME = "shiftEndTimeEpoch"
        private const val PREFS_NAME = "persistent_pulse_service"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"
        private const val FLUTTER_PULSE_ACTIVE_KEY = "flutter.pulse_tracking_active"
        private const val FLUTTER_LAST_PULSE_TS_KEY = "flutter.last_pulse_timestamp"
        private const val FLUTTER_SKIP_WINDOW_MS = 4 * 60 * 1000L
        private const val FLUTTER_STALE_LIMIT_MS = 7 * 60 * 1000L
        
        /**
         * Start the persistent pulse service
         */
        fun start(context: Context, params: Map<String, Any>) {
            val intent = Intent(context, PersistentPulseService::class.java).apply {
                putExtra(EXTRA_EMPLOYEE_ID, params["employeeId"] as? String)
                putExtra(EXTRA_ATTENDANCE_ID, params["attendanceId"] as? String)
                putExtra(EXTRA_BRANCH_ID, params["branchId"] as? String)
                putExtra(EXTRA_INTERVAL, params["interval"] as? Int ?: 5)
                putExtra(EXTRA_BRANCH_LAT, params["branchLatitude"] as? Double ?: 0.0)
                putExtra(EXTRA_BRANCH_LNG, params["branchLongitude"] as? Double ?: 0.0)
                putExtra(EXTRA_BRANCH_RADIUS, params["branchRadius"] as? Double ?: 100.0)
                putExtra(EXTRA_SHIFT_END_TIME, params["shiftEndTimeEpoch"] as? Long ?: 0L)
                putExtra("fromAlarm", params["fromAlarm"] as? Boolean ?: false)
            }
            
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "🚀 Service start requested successfully")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to start service: ${e.message}", e)
                try {
                    context.startService(intent)
                } catch (se: Exception) {
                    Log.e(TAG, "❌ Fallback startService also failed: ${se.message}")
                }
            }
        }
        
        /**
         * Stop the persistent pulse service
         */
        fun stop(context: Context) {
            val intent = Intent(context, PersistentPulseService::class.java)
            context.stopService(intent)
            
            // Cancel any scheduled alarms
            PulseAlarmReceiver.cancelAlarm(context)

            // Clear persisted params to avoid stale service restarts after checkout
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .apply()
            
            Log.d(TAG, "🛑 Service stop requested")
        }
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📱 Service created")
        
        // 🎵 Initialize Silent Media Player (prevents Deep Sleep on Samsung/Realme)
        try {
            mediaPlayer = MediaPlayer.create(this, R.raw.silent)
            mediaPlayer.isLooping = true // يشتغل للأبد في دائرة
            mediaPlayer.setVolume(0f, 0f) // صامت تماماً - مش هيسمع حاجة
            Log.d(TAG, "🎵 Silent MediaPlayer initialized")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to initialize MediaPlayer: ${e.message}")
            // Create fallback - not critical if it fails
        }
        
        // Initialize Native GPS and WiFi modules
        fastGPS = FastGPSModule(applicationContext)
        fastWiFi = FastWiFiScanner(applicationContext)
        
        createNotificationChannel()
        acquireWakeLock()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🎯 Service started with intent")
        if (serviceStartTime == 0L) {
            serviceStartTime = System.currentTimeMillis()
        }

        // START_STICKY can restart service with null intent, so restore the last known params.
        val loadedFromIntent = loadParametersFromIntent(intent)
        if (!loadedFromIntent) {
            if (!restorePersistedParameters()) {
                Log.e(TAG, "❌ Missing required parameters and no persisted backup available")
                stopSelf()
                return START_NOT_STICKY
            }
            Log.w(TAG, "♻️ Restored service params from persisted storage")
        } else {
            persistCurrentParameters()
        }
        
        Log.d(TAG, "📋 Params - Employee: $employeeId, Attendance: $attendanceId, Branch: $branchId, Interval: $intervalMinutes min, ShiftEnd: $shiftEndTimeEpoch")
        
        // Immediate check if shift has already ended
        // IF-BLOCK DISABLED BY POLICY: shift-end auto checkout is completely disabled.
        /*
        if (shiftEndTimeEpoch > 0 && System.currentTimeMillis() >= shiftEndTimeEpoch) {
            Log.d(TAG, "🚨 Service started but shift already ended. Triggering auto-checkout immediately.")
            serviceScope.launch(Dispatchers.IO) {
                writeCheckoutToDatabase("SHIFT_END_AUTO_CHECKOUT")
                
                // Cancel alarms
                PulseAlarmReceiver.cancelAlarm(applicationContext)
                
                // Clear service parameters from SharedPreferences
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .clear()
                    .apply()
                    
                // Clear tracking active flag in Flutter shared preferences
                try {
                    getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(FLUTTER_PULSE_ACTIVE_KEY, false)
                        .apply()
                } catch (e: Exception) {
                    Log.e(TAG, "Error clearing flutter pulse active key: ${e.message}")
                }
                
                // Send Broadcast for Flutter UI
                val broadcastIntent = Intent("com.example.heartbeat.AUTO_CHECKOUT_TRIGGERED").apply {
                    putExtra("reason", "SHIFT_END_AUTO_CHECKOUT")
                }
                sendBroadcast(broadcastIntent)
                
                withContext(Dispatchers.Main) {
                    stopSelf()
                }
            }
            return START_NOT_STICKY
        }
        */
        
        // Validate required parameters
        if (employeeId.isNullOrEmpty() || attendanceId.isNullOrEmpty()) {
            Log.e(TAG, "❌ Missing required parameters!")
            stopSelf()
            return START_NOT_STICKY
        }
        
        // Start foreground service with notification
        val notification = buildNotification("جاري بدء التتبع...")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, 
                notification, 
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID, 
                notification, 
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        
        // 🎵 Start silent audio playback (prevents Deep Sleep)
        try {
            if (::mediaPlayer.isInitialized && !mediaPlayer.isPlaying) {
                mediaPlayer.start()
                Log.d(TAG, "🎵 Silent audio started - Deep Sleep prevention activated")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start MediaPlayer: ${e.message}")
        }
        
        // Check if started from AlarmManager resurrection
        val fromAlarm = intent?.getBooleanExtra("fromAlarm", false) ?: false
        if (fromAlarm) {
            Log.d(TAG, "⏰ Started from AlarmManager resurrection - triggering immediate background pulse check")
            serviceScope.launch {
                sendPulse()
            }
        }
        
        // Start pulse timer only if not already active to prevent coroutine reset
        if (pulseJob == null || pulseJob?.isActive == false) {
            Log.d(TAG, "⏰ Starting a new pulse timer coroutine")
            startPulseTimer()
        } else {
            Log.d(TAG, "⏰ Pulse timer is already active - skipping restart to prevent timer reset")
        }
        
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
                    delay(intervalMinutes * 60 * 1000L)
                    sendPulse()
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error in pulse timer: ${e.message}", e)
                    updateNotification("خطأ: ${e.message}")
                }
            }
        }
    }
    
    /**
     * Send a pulse - WRITES DIRECTLY TO SQLITE (works even when app is killed)
     */
    private fun getAllowedBssidsFromDb(db: SQLiteDatabase): List<String> {
        val allowedBssids = mutableListOf<String>()
        val safeEmployeeId = employeeId ?: return allowedBssids
        var cursor: android.database.Cursor? = null
        try {
            cursor = db.query(
                "branch_cache",
                arrayOf("wifi_bssids"),
                "employee_id = ?",
                arrayOf(safeEmployeeId),
                null, null, null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val wifiBssidsJson = cursor.getString(cursor.getColumnIndexOrThrow("wifi_bssids"))
                if (!wifiBssidsJson.isNullOrEmpty()) {
                    Log.d(TAG, "📡 Found wifi_bssids JSON in database: $wifiBssidsJson")
                    val cleaned = wifiBssidsJson
                        .replace("[", "")
                        .replace("]", "")
                        .replace("\"", "")
                        .replace("'", "")
                    val bssids = cleaned.split(",")
                    for (bssid in bssids) {
                        val trimmed = bssid.trim().uppercase(Locale.US)
                        if (trimmed.isNotEmpty()) {
                            allowedBssids.add(trimmed)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading wifi_bssids from SQLite: ${e.message}", e)
        } finally {
            cursor?.close()
        }
        Log.d(TAG, "📋 Allowed BSSIDs from DB: $allowedBssids")
        return allowedBssids
    }

    data class SuperBranch(
        val branchId: String,
        val branchName: String,
        val allowedBssids: List<String>,
        val latitude: Double,
        val longitude: Double,
        val radius: Double
    )

    private fun getSuperEmployeeBranches(db: SQLiteDatabase): List<SuperBranch> {
        val list = mutableListOf<SuperBranch>()
        val safeEmployeeId = employeeId ?: return list
        var cursor: android.database.Cursor? = null
        try {
            // Check if super_employee_branches table exists first
            val tableExistsCursor = db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='super_employee_branches'", 
                null
            )
            val exists = tableExistsCursor.use { it.count > 0 }
            if (!exists) {
                return list
            }

            cursor = db.query(
                "super_employee_branches",
                arrayOf("branch_id", "branch_name", "wifi_bssids", "latitude", "longitude", "geofence_radius"),
                "employee_id = ?",
                arrayOf(safeEmployeeId),
                null, null, null
            )
            while (cursor != null && cursor.moveToNext()) {
                val bId = cursor.getString(cursor.getColumnIndexOrThrow("branch_id"))
                val bName = cursor.getString(cursor.getColumnIndexOrThrow("branch_name")) ?: ""
                val wifiBssidsJson = cursor.getString(cursor.getColumnIndexOrThrow("wifi_bssids"))
                val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                val lng = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                val rad = cursor.getDouble(cursor.getColumnIndexOrThrow("geofence_radius"))

                val allowedBssids = mutableListOf<String>()
                if (!wifiBssidsJson.isNullOrEmpty()) {
                    val cleaned = wifiBssidsJson
                        .replace("[", "")
                        .replace("]", "")
                        .replace("\"", "")
                        .replace("'", "")
                    val bssids = cleaned.split(",")
                    for (bssid in bssids) {
                        val trimmed = bssid.trim().uppercase(Locale.US)
                        if (trimmed.isNotEmpty()) {
                            allowedBssids.add(trimmed)
                        }
                    }
                }

                list.add(SuperBranch(bId, bName, allowedBssids, lat, lng, rad))
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error reading super_employee_branches from SQLite: ${e.message}", e)
        } finally {
            cursor?.close()
        }
        Log.d(TAG, "⭐ Loaded ${list.size} super employee branches from SQLite")
        return list
    }

    /**
     * Send a pulse - WRITES DIRECTLY TO SQLITE (works even when app is killed)
     */
    private suspend fun sendPulse() = withContext(Dispatchers.IO) {
        // IF-BLOCK DISABLED BY POLICY: shift-end auto checkout is completely disabled.
        /*
        if (shiftEndTimeEpoch > 0 && System.currentTimeMillis() >= shiftEndTimeEpoch) {
            Log.d(TAG, "🚨 Shift end time reached ($shiftEndTimeEpoch). Triggering auto-checkout.")
            writeCheckoutToDatabase("SHIFT_END_AUTO_CHECKOUT")
            
            // Cancel alarms
            PulseAlarmReceiver.cancelAlarm(applicationContext)
            
            // Clear service parameters from SharedPreferences
            getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .apply()
                
            // Clear tracking active flag in Flutter shared preferences
            try {
                getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
                    .edit()
                    .putBoolean(FLUTTER_PULSE_ACTIVE_KEY, false)
                    .apply()
            } catch (e: Exception) {
                Log.e(TAG, "Error clearing flutter pulse active key: ${e.message}")
            }
            
            // Send Broadcast for Flutter UI
            val broadcastIntent = Intent("com.example.heartbeat.AUTO_CHECKOUT_TRIGGERED").apply {
                putExtra("reason", "SHIFT_END_AUTO_CHECKOUT")
            }
            sendBroadcast(broadcastIntent)
            
            withContext(Dispatchers.Main) {
                stopSelf()
            }
            return@withContext
        }
        */

        if (shouldSkipBecauseFlutterActive()) {
            Log.d(TAG, "⏭️ Skipping native pulse - Flutter tracker is active")
            return@withContext
        }

        pulseCount++
        lastPulseTime = System.currentTimeMillis()
        
        val timestamp = getCurrentTime()
        Log.d(TAG, "💓 Sending pulse #$pulseCount at $timestamp")
        
        // Directive 2: Acquire CPU Partial WakeLock to hold CPU awake during BSSID & SQLite writes
        acquireTransientWakeLock(10000L)
        
        try {
            var currentLocation: Location? = null
            var distance = 0.0
            var isInsideGeofence = false
            
            // Check if break is active in Flutter SharedPreferences
            var isOnBreak = false
            try {
                val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                isOnBreak = flutterPrefs.getBoolean("flutter.is_break_active", false)
                Log.d(TAG, "☕ isOnBreak: $isOnBreak")
            } catch (e: Exception) {
                Log.e(TAG, "Error checking break status: ${e.message}")
            }

            val dbPath = applicationContext.getDatabasePath("offline_attendance.db").absolutePath
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
            val superBranches = getSuperEmployeeBranches(db)
            
            // Resolve effective branch variables
            var effectiveBranchId = branchId
            var effectiveBranchLat = branchLatitude
            var effectiveBranchLng = branchLongitude
            var effectiveBranchRadius = branchRadius

            // Check WiFi validation
            var currentBssid: String? = null
            var wifiValidated = false
            try {
                currentBssid = fastWiFi.getCurrentBSSID()
                if (!currentBssid.isNullOrEmpty()) {
                    val normalizedCurrentBssid = currentBssid.uppercase(Locale.US)
                    if (superBranches.isNotEmpty()) {
                        for (branch in superBranches) {
                            if (branch.allowedBssids.contains(normalizedCurrentBssid)) {
                                wifiValidated = true
                                effectiveBranchId = branch.branchId
                                effectiveBranchLat = branch.latitude
                                effectiveBranchLng = branch.longitude
                                effectiveBranchRadius = branch.radius
                                Log.d(TAG, "📶 Super WiFi Validated: Connected to branch WiFi ($currentBssid) for branch ${branch.branchName}")
                                break
                            }
                        }
                    } else {
                        val allowedBssids = getAllowedBssidsFromDb(db)
                        if (allowedBssids.contains(normalizedCurrentBssid)) {
                            wifiValidated = true
                            Log.d(TAG, "📶 WiFi Validated: Connected to branch WiFi ($currentBssid)")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error checking WiFi validation in background: ${e.message}")
            }

            if (isOnBreak) {
                isInsideGeofence = true
                distance = 0.0
                Log.d(TAG, "☕ Break is active: overriding geofence to INSIDE")
            } else if (wifiValidated) {
                isInsideGeofence = true
                distance = 0.0
                Log.d(TAG, "📶 WiFi check passed: overriding geofence to INSIDE")
            } else {
                try {
                    currentLocation = fastGPS.getCurrentLocation()
                    if (currentLocation != null) {
                        if (superBranches.isNotEmpty()) {
                            var minDistance = Double.MAX_VALUE
                            var closestBranch: SuperBranch? = null
                            var isInsideAny = false
                            
                            for (branch in superBranches) {
                                val branchLocation = Location("").apply {
                                    latitude = branch.latitude
                                    longitude = branch.longitude
                                }
                                val d = currentLocation.distanceTo(branchLocation).toDouble()
                                if (d < minDistance) {
                                    minDistance = d
                                    closestBranch = branch
                                }
                                
                                val accuracy = currentLocation.accuracy
                                val isInside = if (accuracy > 150f) {
                                    (d - accuracy) <= branch.radius
                                } else {
                                    d <= branch.radius
                                }
                                
                                if (isInside) {
                                    isInsideAny = true
                                    isInsideGeofence = true
                                    distance = d
                                    effectiveBranchId = branch.branchId
                                    effectiveBranchLat = branch.latitude
                                    effectiveBranchLng = branch.longitude
                                    effectiveBranchRadius = branch.radius
                                    Log.d(TAG, "📍 Super GPS Validated: Inside branch ${branch.branchName} geofence")
                                    break
                                }
                            }
                            
                            if (!isInsideAny) {
                                isInsideGeofence = false
                                distance = minDistance
                                closestBranch?.let {
                                    effectiveBranchId = it.branchId
                                    effectiveBranchLat = it.latitude
                                    effectiveBranchLng = it.longitude
                                    effectiveBranchRadius = it.radius
                                }
                                Log.d(TAG, "📏 Super GPS: Outside all geofences, closest branch: ${closestBranch?.branchName} at ${minDistance.toInt()}m")
                            }
                        } else {
                            if (branchLatitude != 0.0 && branchLongitude != 0.0) {
                                val branchLocation = Location("").apply {
                                    latitude = branchLatitude
                                    longitude = branchLongitude
                                }
                                distance = currentLocation.distanceTo(branchLocation).toDouble()
                                
                                val accuracy = currentLocation.accuracy
                                if (accuracy > 150f) {
                                    isInsideGeofence = (distance - accuracy) <= branchRadius
                                    Log.w(TAG, "⚠️ Weak GPS accuracy ($accuracy m > 150m) - applying overlap check: $isInsideGeofence")
                                } else {
                                    isInsideGeofence = distance <= branchRadius
                                    Log.d(TAG, "📍 Location: (${currentLocation.latitude}, ${currentLocation.longitude}), Accuracy: $accuracy m")
                                    Log.d(TAG, "📏 Distance from branch: ${distance.toInt()}m - ${if (isInsideGeofence) "✅ INSIDE" else "❌ OUTSIDE"}")
                                }
                            } else {
                                isInsideGeofence = false
                                distance = 0.0
                                Log.w(TAG, "⚠️ GPS query returned null or coords missing. Defaulting to OUTSIDE.")
                                sendLocationFailureNotification()
                            }
                        }
                    } else {
                        isInsideGeofence = false
                        distance = 0.0
                        Log.w(TAG, "⚠️ GPS query returned null. Defaulting to OUTSIDE.")
                        sendLocationFailureNotification()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Error getting location: ${e.message}")
                    isInsideGeofence = true
                    distance = 0.0
                    currentLocation = Location("gps").apply {
                        latitude = effectiveBranchLat
                        longitude = effectiveBranchLng
                        accuracy = 0.0f
                    }
                }
            }
            db.close()
            
            // 🔥 DIRECT SQLITE WRITE (bypasses Flutter - works when app is dead)
            val pulseData = mapOf(
                "employee_id" to employeeId,
                "attendance_id" to attendanceId,
                "branch_id" to effectiveBranchId,
                "timestamp" to System.currentTimeMillis(),
                "pulse_count" to pulseCount,
                "latitude" to (if (wifiValidated || isOnBreak) null else currentLocation?.latitude),
                "longitude" to (if (wifiValidated || isOnBreak) null else currentLocation?.longitude),
                "distance" to distance,
                "inside_geofence" to isInsideGeofence,
                "wifi_bssid" to currentBssid,
                "validated_by_wifi" to (if (wifiValidated) 1 else 0),
                "validated_by_location" to (if (!wifiValidated && !isOnBreak && currentLocation != null) 1 else 0),
                "validation_method" to (if (wifiValidated) "WIFI" else if (isOnBreak) "BREAK" else if (currentLocation != null) "LOCATION" else "UNKNOWN")
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

    private fun shouldSkipBecauseFlutterActive(): Boolean {
        return try {
            val prefs = getSharedPreferences(FLUTTER_PREFS, MODE_PRIVATE)
            val flutterActive = prefs.getBoolean(FLUTTER_PULSE_ACTIVE_KEY, false)
            if (!flutterActive) {
                return false
            }

            val lastFlutterPulse = prefs.getLong(FLUTTER_LAST_PULSE_TS_KEY, 0L)
            if (lastFlutterPulse <= 0L) {
                return false
            }

            val ageMs = System.currentTimeMillis() - lastFlutterPulse
            if (ageMs <= FLUTTER_SKIP_WINDOW_MS) {
                return true
            }

            ageMs < FLUTTER_STALE_LIMIT_MS
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Failed to read Flutter pulse flags: ${e.message}")
            false
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
            
            // Extract location data
            val latitude = pulseData["latitude"] as? Double
            val longitude = pulseData["longitude"] as? Double
            val distance = pulseData["distance"] as? Double ?: 0.0
            val insideGeofence = if (pulseData["inside_geofence"] as? Boolean == true) 1 else 0
            
            val wifiBssid = pulseData["wifi_bssid"] as? String
            val validationMethod = pulseData["validation_method"] as? String ?: (if (latitude != null && longitude != null) "LOCATION" else "UNKNOWN")
            val validatedByWifi = pulseData["validated_by_wifi"] as? Int ?: 0
            val validatedByLocation = pulseData["validated_by_location"] as? Int ?: (if (latitude != null && longitude != null) 1 else 0)

            // Insert into pending_pulses table
            val sql = """
                INSERT OR REPLACE INTO pending_pulses 
                (id, employee_id, attendance_id, timestamp, latitude, longitude, 
                 inside_geofence, distance_from_center, wifi_bssid, validation_method,
                 validated_by_wifi, validated_by_location, created_at, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """.trimIndent()
            
            db.execSQL(sql, arrayOf(
                pulseId,
                pulseData["employee_id"],
                pulseData["attendance_id"] ?: "pending",
                currentTime,
                latitude,
                longitude,
                insideGeofence,
                distance,
                wifiBssid,
                validationMethod,
                validatedByWifi,
                validatedByLocation,
                currentTime
            ))
            
            db.close()
            
            Log.d(TAG, "💾 Pulse written directly to SQLite: $pulseId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to write to SQLite: ${e.message}", e)
        }
    }
    
    /**
     * Write checkout record directly to SQLite database
     */
    private fun writeCheckoutToDatabase(reason: String) {
        try {
            val dbPath = applicationContext.getDatabasePath("offline_attendance.db").absolutePath
            val db = SQLiteDatabase.openOrCreateDatabase(dbPath, null)
            
            val checkoutId = "${employeeId}_${System.currentTimeMillis()}"
            val currentTime = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(Date())
            
            // Query total pulses for this attendance session to estimate work hours
            var calculatedWorkHours = 0.0
            var pulseCount = 0
            var cursor: android.database.Cursor? = null
            try {
                cursor = db.rawQuery(
                    "SELECT COUNT(*) FROM pending_pulses WHERE attendance_id = ? AND inside_geofence = 1",
                    arrayOf(attendanceId)
                )
                if (cursor != null && cursor.moveToFirst()) {
                    pulseCount = cursor.getInt(0)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to query pulses for work hours: ${e.message}")
            } finally {
                cursor?.close()
            }
            // Each inside pulse represents 5 minutes (intervalMinutes)
            calculatedWorkHours = (pulseCount * intervalMinutes) / 60.0

            val sql = """
                INSERT OR REPLACE INTO pending_checkouts 
                (id, employee_id, attendance_id, timestamp, latitude, longitude, 
                 notes, work_hours, created_at, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
            """.trimIndent()
            
            db.execSQL(sql, arrayOf(
                checkoutId,
                employeeId,
                attendanceId,
                currentTime,
                null,
                null,
                reason,
                calculatedWorkHours,
                currentTime
            ))
            
            db.close()
            Log.d(TAG, "💾 Auto-checkout written directly to SQLite: $checkoutId, work hours: $calculatedWorkHours")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to write auto-checkout to SQLite: ${e.message}", e)
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
                putExtra(EXTRA_BRANCH_LAT, branchLatitude)
                putExtra(EXTRA_BRANCH_LNG, branchLongitude)
                putExtra(EXTRA_BRANCH_RADIUS, branchRadius)
                putExtra(EXTRA_SHIFT_END_TIME, shiftEndTimeEpoch)
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

    private fun loadParametersFromIntent(intent: Intent?): Boolean {
        if (intent == null) {
            return false
        }

        val intentEmployeeId = intent.getStringExtra(EXTRA_EMPLOYEE_ID)
        val intentAttendanceId = intent.getStringExtra(EXTRA_ATTENDANCE_ID)
        if (intentEmployeeId.isNullOrEmpty() || intentAttendanceId.isNullOrEmpty()) {
            return false
        }

        employeeId = intentEmployeeId
        attendanceId = intentAttendanceId
        branchId = intent.getStringExtra(EXTRA_BRANCH_ID)
        intervalMinutes = intent.getIntExtra(EXTRA_INTERVAL, 5).coerceAtLeast(1)
        branchLatitude = intent.getDoubleExtra(EXTRA_BRANCH_LAT, 0.0)
        branchLongitude = intent.getDoubleExtra(EXTRA_BRANCH_LNG, 0.0)
        branchRadius = intent.getDoubleExtra(EXTRA_BRANCH_RADIUS, 100.0)
        shiftEndTimeEpoch = intent.getLongExtra(EXTRA_SHIFT_END_TIME, 0L)
        return true
    }

    private fun persistCurrentParameters() {
        val safeEmployeeId = employeeId ?: return
        val safeAttendanceId = attendanceId ?: return

        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .edit()
            .putString(EXTRA_EMPLOYEE_ID, safeEmployeeId)
            .putString(EXTRA_ATTENDANCE_ID, safeAttendanceId)
            .putString(EXTRA_BRANCH_ID, branchId)
            .putInt(EXTRA_INTERVAL, intervalMinutes.coerceAtLeast(1))
            .putLong(EXTRA_BRANCH_LAT, java.lang.Double.doubleToRawLongBits(branchLatitude))
            .putLong(EXTRA_BRANCH_LNG, java.lang.Double.doubleToRawLongBits(branchLongitude))
            .putLong(EXTRA_BRANCH_RADIUS, java.lang.Double.doubleToRawLongBits(branchRadius))
            .putLong(EXTRA_SHIFT_END_TIME, shiftEndTimeEpoch)
            .apply()
    }

    private fun restorePersistedParameters(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

        val savedEmployeeId = prefs.getString(EXTRA_EMPLOYEE_ID, null)
        val savedAttendanceId = prefs.getString(EXTRA_ATTENDANCE_ID, null)
        if (savedEmployeeId.isNullOrEmpty() || savedAttendanceId.isNullOrEmpty()) {
            return false
        }

        employeeId = savedEmployeeId
        attendanceId = savedAttendanceId
        branchId = prefs.getString(EXTRA_BRANCH_ID, null)
        intervalMinutes = prefs.getInt(EXTRA_INTERVAL, 5).coerceAtLeast(1)
        branchLatitude = java.lang.Double.longBitsToDouble(
            prefs.getLong(EXTRA_BRANCH_LAT, java.lang.Double.doubleToRawLongBits(0.0))
        )
        branchLongitude = java.lang.Double.longBitsToDouble(
            prefs.getLong(EXTRA_BRANCH_LNG, java.lang.Double.doubleToRawLongBits(0.0))
        )
        branchRadius = java.lang.Double.longBitsToDouble(
            prefs.getLong(EXTRA_BRANCH_RADIUS, java.lang.Double.doubleToRawLongBits(100.0))
        )
        shiftEndTimeEpoch = prefs.getLong(EXTRA_SHIFT_END_TIME, 0L)
        return true
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
     * Directive 2: Acquire transient CPU Partial WakeLock during BSSID & SQLite writes
     */
    private fun acquireTransientWakeLock(timeoutMs: Long = 10000L) {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            val transientLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$TAG::TransientPulseLock"
            )
            transientLock.acquire(timeoutMs)
            Log.d(TAG, "🔒 Transient CPU Partial WakeLock acquired for ${timeoutMs}ms")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to acquire transient WakeLock: ${e.message}")
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
        
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("the work is active")
            .setContentText("the work is active")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setAutoCancel(false)
            
        return builder.build()
    }
    
    /**
     * Update the notification text
     */
    private fun updateNotification(text: String) {
        try {
            val notification = buildNotification("the work is active")
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: ${e.message}", e)
        }
    }
    
    /**
     * Send a high-priority warning notification when location detection fails
     */
    private fun sendLocationFailureNotification() {
        try {
            val notificationIntent = Intent(this, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                notificationIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            
            val warningChannelId = "warning_channel"
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    warningChannelId,
                    "تنبيهات الموقع",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "تنبيهات عند فشل تحديد الموقع"
                    enableLights(true)
                    enableVibration(true)
                }
                val manager = getSystemService(NotificationManager::class.java)
                manager?.createNotificationChannel(channel)
            }
            
            val notification = NotificationCompat.Builder(this, warningChannelId)
                .setContentTitle("⚠️ فشل تحديد الموقع!")
                .setContentText("لم نتمكن من تحديد موقعك بالخلفية. افتح التطبيق فوراً لضمان احتساب وقت العمل.")
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentIntent(pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .build()
                
            val manager = getSystemService(NotificationManager::class.java)
            manager?.notify(1002, notification)
            Log.d(TAG, "📢 High-priority location warning notification sent")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send warning notification: ${e.message}", e)
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
        serviceStartTime = 0L
        
        // 🎵 Stop and release MediaPlayer
        try {
            if (::mediaPlayer.isInitialized) {
                if (mediaPlayer.isPlaying) {
                    mediaPlayer.stop()
                }
                mediaPlayer.release()
                Log.d(TAG, "🎵 MediaPlayer stopped and released")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing MediaPlayer: ${e.message}")
        }
        
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
