package com.example.heartbeat

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    
    private val PULSE_CHANNEL = "persistent_pulse"
    private val GPS_CHANNEL = "fast_gps"
    private val WIFI_CHANNEL = "fast_wifi"
    
    private lateinit var fastGPS: FastGPSModule
    private lateinit var fastWiFi: FastWiFiScanner
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize modules
        fastGPS = FastGPSModule(this)
        fastWiFi = FastWiFiScanner(this)
        
        // ========== Persistent Pulse Service Channel ==========
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PULSE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPersistentService" -> {
                    try {
                        val employeeId = call.argument<String>("employeeId")
                        val attendanceId = call.argument<String>("attendanceId")
                        val branchId = call.argument<String>("branchId")
                        val interval = call.argument<Int>("interval") ?: 5
                        
                        if (employeeId.isNullOrEmpty() || attendanceId.isNullOrEmpty()) {
                            result.error("INVALID_PARAMS", "Missing employeeId or attendanceId", null)
                            return@setMethodCallHandler
                        }
                        
                        val params = mapOf(
                            "employeeId" to employeeId,
                            "attendanceId" to attendanceId,
                            "branchId" to (branchId ?: ""),
                            "interval" to interval
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
