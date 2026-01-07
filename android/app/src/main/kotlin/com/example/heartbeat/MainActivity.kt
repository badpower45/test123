package com.example.heartbeat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {
    
    private val PULSE_CHANNEL = "persistent_pulse"
    private val GPS_CHANNEL = "fast_gps"
    private val WIFI_CHANNEL = "fast_wifi"
    private val BACKGROUND_PULSE_CHANNEL = "background_pulse_callback"
    
    private lateinit var fastGPS: FastGPSModule
    private lateinit var fastWiFi: FastWiFiScanner
    
    private var backgroundPulseMethodChannel: MethodChannel? = null
    
    // BroadcastReceiver to receive pulses from PersistentPulseService
    private val pulseReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.heartbeat.PULSE_RECORDED") {
                val pulseData = intent.getSerializableExtra("pulse_data") as? HashMap<String, Any>
                Log.d("MainActivity", "💓 Received pulse from native service: $pulseData")
                
                // Forward to Flutter
                backgroundPulseMethodChannel?.invokeMethod("onPulseRecorded", pulseData)
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Register BroadcastReceiver for pulses
        val filter = IntentFilter("com.example.heartbeat.PULSE_RECORDED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pulseReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pulseReceiver, filter)
        }
        Log.d("MainActivity", "✅ Pulse BroadcastReceiver registered")
    }
    
    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(pulseReceiver)
        } catch (e: Exception) {
            Log.e("MainActivity", "Error unregistering receiver: ${e.message}")
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize modules
        fastGPS = FastGPSModule(this)
        fastWiFi = FastWiFiScanner(this)
        
        // ========== Background Pulse Callback Channel ==========
        backgroundPulseMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, 
            BACKGROUND_PULSE_CHANNEL
        )
        
        // ========== Persistent Pulse Service Channel ==========
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PULSE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPersistentService" -> {
                    try {
                        val employeeId = call.argument<String>("employeeId")
                        val attendanceId = call.argument<String>("attendanceId")
                        val branchId = call.argument<String>("branchId")
                        val interval = call.argument<Int>("interval") ?: 5
                        val branchLatitude = call.argument<Double>("branchLatitude") ?: 0.0
                        val branchLongitude = call.argument<Double>("branchLongitude") ?: 0.0
                        val branchRadius = call.argument<Double>("branchRadius") ?: 100.0
                        
                        if (employeeId.isNullOrEmpty() || attendanceId.isNullOrEmpty()) {
                            result.error("INVALID_PARAMS", "Missing employeeId or attendanceId", null)
                            return@setMethodCallHandler
                        }
                        
                        val params = mapOf(
                            "employeeId" to employeeId,
                            "attendanceId" to attendanceId,
                            "branchId" to (branchId ?: ""),
                            "interval" to interval,
                            "branchLatitude" to branchLatitude,
                            "branchLongitude" to branchLongitude,
                            "branchRadius" to branchRadius
                        )
                        
                        PersistentPulseService.start(this, params)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                
                "stopPersistentService" -> {
                    try {
                        PersistentPulseService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // ========== Fast GPS Channel ==========
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GPS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getLocationFast" -> {
                    fastGPS.getLocationFast { location ->
                        if (location != null) {
                            result.success(fastGPS.locationToMap(location))
                        } else {
                            result.error("NO_LOCATION", "Could not get location", null)
                        }
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // ========== Fast WiFi Channel ==========
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBSSID" -> {
                    fastWiFi.getBSSIDFast { bssid ->
                        result.success(bssid)
                    }
                }
                
                "getWiFiInfo" -> {
                    fastWiFi.getWiFiInfo { info ->
                        result.success(info)
                    }
                }
                
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
