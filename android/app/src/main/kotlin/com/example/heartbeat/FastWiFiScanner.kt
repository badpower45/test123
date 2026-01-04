package com.example.heartbeat

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat

/**
 * 🔍 Fast WiFi Scanner
 * 
 * This module provides fast WiFi BSSID detection by:
 * 1. Reading current connection info first (fastest)
 * 2. Performing WiFi scan only if needed
 * 3. Handling Android 10+ location requirement
 * 4. Avoiding "02:00:00:00:00:00" placeholder
 * 
 * Much more reliable than network_info_plus on old devices!
 */
class FastWiFiScanner(private val context: Context) {
    
    private val wifiManager = context.applicationContext
        .getSystemService(Context.WIFI_SERVICE) as WifiManager
    
    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    
    companion object {
        private const val TAG = "FastWiFiScanner"
        private const val PLACEHOLDER_BSSID = "02:00:00:00:00:00"
    }
    
    /**
     * Get WiFi BSSID fast
     * Returns null if WiFi is off, permissions denied, or location disabled (Android 10+)
     */
    fun getBSSIDFast(callback: (String?) -> Unit) {
        Log.d(TAG, "📡 Getting WiFi BSSID...")
        
        // 1. Check if WiFi is enabled
        if (!wifiManager.isWifiEnabled) {
            Log.w(TAG, "⚠️ WiFi is disabled")
            callback(null)
            return
        }
        
        // 2. Check permissions
        if (!hasWiFiPermissions()) {
            Log.e(TAG, "❌ WiFi permissions not granted")
            callback(null)
            return
        }
        
        // 3. Android 10+ requires location to be enabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (!isLocationEnabled()) {
                Log.e(TAG, "❌ Location must be enabled for WiFi scanning on Android 10+")
                callback(null)
                return
            }
        }
        
        // 4. Try to get current connection BSSID
        val bssid = getCurrentBSSID()
        if (bssid != null && bssid != PLACEHOLDER_BSSID) {
            Log.d(TAG, "✅ Current WiFi BSSID: $bssid")
            callback(bssid)
            return
        }
        
        // 5. Fallback: Perform WiFi scan
        Log.d(TAG, "🔍 Current BSSID not available, performing scan...")
        scanWiFiNetworks(callback)
    }
    
    /**
     * Get BSSID from current WiFi connection
     */
    private fun getCurrentBSSID(): String? {
        try {
            val wifiInfo = wifiManager.connectionInfo
            val bssid = wifiInfo?.bssid
            
            if (bssid != null && bssid != PLACEHOLDER_BSSID) {
                Log.d(TAG, "📶 Connected to: ${wifiInfo.ssid}, BSSID: $bssid")
                return bssid
            } else {
                Log.w(TAG, "⚠️ BSSID is placeholder or null: $bssid")
                return null
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting current BSSID: ${e.message}", e)
            return null
        }
    }
    
    /**
     * Perform WiFi scan to find strongest network
     */
    private fun scanWiFiNetworks(callback: (String?) -> Unit) {
        var scanCompleted = false
        
        val scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (!scanCompleted) {
                    scanCompleted = true
                    
                    val success = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                    Log.d(TAG, "📡 Scan completed, success: $success")
                    
                    if (success) {
                        try {
                            val results = wifiManager.scanResults
                            Log.d(TAG, "📡 Found ${results.size} networks")
                            
                            // Find strongest network
                            val strongest = results.maxByOrNull { it.level }
                            
                            if (strongest != null) {
                                Log.d(TAG, "✅ Strongest network: ${strongest.SSID}, BSSID: ${strongest.BSSID}, Signal: ${strongest.level}")
                                callback(strongest.BSSID)
                            } else {
                                Log.w(TAG, "⚠️ No networks found in scan")
                                callback(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Error processing scan results: ${e.message}", e)
                            callback(null)
                        }
                    } else {
                        Log.w(TAG, "⚠️ Scan failed")
                        callback(null)
                    }
                    
                    // Unregister receiver
                    try {
                        context.unregisterReceiver(this)
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ Receiver already unregistered")
                    }
                }
            }
        }
        
        try {
            // Register receiver
            val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
            context.registerReceiver(scanReceiver, filter)
            
            // Start scan
            val scanStarted = wifiManager.startScan()
            Log.d(TAG, "📡 Scan started: $scanStarted")
            
            if (!scanStarted) {
                Log.w(TAG, "⚠️ Failed to start scan")
                context.unregisterReceiver(scanReceiver)
                callback(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting WiFi scan: ${e.message}", e)
            callback(null)
        }
    }
    
    /**
     * Get WiFi information (SSID, BSSID, signal strength)
     */
    fun getWiFiInfo(callback: (Map<String, Any>?) -> Unit) {
        Log.d(TAG, "📡 Getting WiFi info...")
        
        // Check permissions and WiFi state
        if (!wifiManager.isWifiEnabled) {
            Log.w(TAG, "⚠️ WiFi is disabled")
            callback(null)
            return
        }
        
        if (!hasWiFiPermissions()) {
            Log.e(TAG, "❌ WiFi permissions not granted")
            callback(null)
            return
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !isLocationEnabled()) {
            Log.e(TAG, "❌ Location must be enabled on Android 10+")
            callback(null)
            return
        }
        
        try {
            val wifiInfo = wifiManager.connectionInfo
            val bssid = wifiInfo?.bssid
            
            if (bssid != null && bssid != PLACEHOLDER_BSSID) {
                val info = mapOf(
                    "ssid" to (wifiInfo.ssid?.replace("\"", "") ?: ""),
                    "bssid" to bssid,
                    "signalStrength" to wifiInfo.rssi,
                    "linkSpeed" to wifiInfo.linkSpeed,
                    "frequency" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        wifiInfo.frequency
                    } else {
                        0
                    },
                    "networkId" to wifiInfo.networkId
                )
                
                Log.d(TAG, "✅ WiFi info: $info")
                callback(info)
            } else {
                Log.w(TAG, "⚠️ Not connected to WiFi or BSSID not available")
                callback(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting WiFi info: ${e.message}", e)
            callback(null)
        }
    }
    
    /**
     * Check if required WiFi permissions are granted
     */
    private fun hasWiFiPermissions(): Boolean {
        // Android 10+ requires location permission for WiFi scanning
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            ActivityCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_WIFI_STATE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }
    
    /**
     * Check if location is enabled (required for WiFi on Android 10+)
     */
    private fun isLocationEnabled(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager.isLocationEnabled
        } else {
            val mode = try {
                android.provider.Settings.Secure.getInt(
                    context.contentResolver,
                    android.provider.Settings.Secure.LOCATION_MODE
                )
            } catch (e: Exception) {
                0
            }
            mode != android.provider.Settings.Secure.LOCATION_MODE_OFF
        }
    }
}
