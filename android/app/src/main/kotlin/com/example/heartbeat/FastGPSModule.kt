package com.example.heartbeat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.*
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat

/**
 * 🚀 Fast GPS Module
 * 
 * This module provides ultra-fast location retrieval by:
 * 1. Using cached location first (if available and recent)
 * 2. Preferring NETWORK_PROVIDER for speed (1-3 seconds)
 * 3. Updating with GPS_PROVIDER in background for accuracy
 * 4. Short timeout (5 seconds) to avoid blocking
 * 
 * Much faster than geolocator plugin on old devices!
 */
class FastGPSModule(private val context: Context) {
    
    private val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var cachedLocation: Location? = null
    private var cacheTimestamp: Long = 0
    private val handler = Handler(Looper.getMainLooper())
    
    companion object {
        private const val TAG = "FastGPSModule"
        private const val CACHE_DURATION_MS = 60_000L // 1 minute
        private const val TIMEOUT_MS = 5_000L // 5 seconds
    }
    
    /**
     * Get location fast with fallback strategy:
     * 1. Cached location (if valid)
     * 2. Network provider (fast)
     * 3. Last known location (fallback)
     * 4. GPS provider (background update)
     */
    fun getLocationFast(callback: (Location?) -> Unit) {
        Log.d(TAG, "🎯 Getting location fast...")
        
        // 1. Check permissions
        if (!hasLocationPermission()) {
            Log.e(TAG, "❌ Location permission not granted")
            callback(null)
            return
        }
        
        // 2. Use cache if valid
        if (isCacheValid()) {
            Log.d(TAG, "✅ Using cached location (${cachedLocation!!.accuracy}m accuracy)")
            callback(cachedLocation)
            // Still update in background
            updateGPSInBackground()
            return
        }
        
        // 3. Try Network Provider first (fastest)
        Log.d(TAG, "📡 Requesting Network location...")
        tryNetworkProvider(callback)
    }
    
    /**
     * Try to get location from Network Provider (WiFi/Cell towers)
     * This is much faster than GPS (1-3 seconds vs 15-30 seconds)
     */
    private fun tryNetworkProvider(callback: (Location?) -> Unit) {
        var locationReceived = false
        val timeoutRunnable = Runnable {
            if (!locationReceived) {
                Log.w(TAG, "⏱️ Network location timeout, using last known")
                locationManager.removeUpdates(networkListener)
                useLastKnownLocation(callback)
            }
        }
        
        val networkListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                if (!locationReceived) {
                    locationReceived = true
                    handler.removeCallbacks(timeoutRunnable)
                    
                    // Cache the location
                    cachedLocation = location
                    cacheTimestamp = System.currentTimeMillis()
                    
                    Log.d(TAG, "✅ Network location: ${location.latitude}, ${location.longitude} (${location.accuracy}m)")
                    callback(location)
                    
                    // Clean up
                    locationManager.removeUpdates(this)
                    
                    // Update with GPS in background for better accuracy
                    updateGPSInBackground()
                }
            }
            
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                if (provider == LocationManager.NETWORK_PROVIDER && !locationReceived) {
                    Log.w(TAG, "⚠️ Network provider disabled")
                    handler.removeCallbacks(timeoutRunnable)
                    useLastKnownLocation(callback)
                }
            }
        }
        
        try {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                // Check if provider is available
                if (!locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) {
                    Log.w(TAG, "⚠️ Network provider not available, using last known")
                    useLastKnownLocation(callback)
                    return
                }
                
                // Request location update
                locationManager.requestLocationUpdates(
                    LocationManager.NETWORK_PROVIDER,
                    0L,
                    0f,
                    networkListener,
                    Looper.getMainLooper()
                )
                
                // Set timeout
                handler.postDelayed(timeoutRunnable, TIMEOUT_MS)
                
                Log.d(TAG, "📡 Network location request sent (timeout: ${TIMEOUT_MS}ms)")
            } else {
                Log.e(TAG, "❌ Fine location permission not granted")
                callback(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting network location: ${e.message}", e)
            handler.removeCallbacks(timeoutRunnable)
            useLastKnownLocation(callback)
        }
    }
    
    /**
     * Fallback: Use last known location from any provider
     */
    private fun useLastKnownLocation(callback: (Location?) -> Unit) {
        try {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                val lastGPS = locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                val lastNetwork = locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                
                // Choose the most recent one
                val bestLocation = when {
                    lastGPS != null && lastNetwork != null -> {
                        if (lastGPS.time > lastNetwork.time) {
                            Log.d(TAG, "📍 Using last GPS location")
                            lastGPS
                        } else {
                            Log.d(TAG, "📍 Using last Network location")
                            lastNetwork
                        }
                    }
                    lastGPS != null -> {
                        Log.d(TAG, "📍 Using last GPS location")
                        lastGPS
                    }
                    lastNetwork != null -> {
                        Log.d(TAG, "📍 Using last Network location")
                        lastNetwork
                    }
                    else -> {
                        Log.w(TAG, "⚠️ No last known location available")
                        null
                    }
                }
                
                if (bestLocation != null) {
                    cachedLocation = bestLocation
                    cacheTimestamp = System.currentTimeMillis()
                    
                    val age = System.currentTimeMillis() - bestLocation.time
                    Log.d(TAG, "✅ Last known location (${age / 1000}s old, ${bestLocation.accuracy}m accuracy)")
                }
                
                callback(bestLocation)
                
                // Try to update with fresh GPS in background
                updateGPSInBackground()
            } else {
                Log.e(TAG, "❌ Location permission not granted")
                callback(null)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting last known location: ${e.message}", e)
            callback(null)
        }
    }
    
    /**
     * Update location using GPS in background (doesn't block)
     * This provides more accurate location for next time
     */
    private fun updateGPSInBackground() {
        Log.d(TAG, "🛰️ Requesting GPS update in background...")
        
        val gpsListener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                cachedLocation = location
                cacheTimestamp = System.currentTimeMillis()
                
                Log.d(TAG, "🛰️ GPS location updated (${location.accuracy}m accuracy)")
                locationManager.removeUpdates(this)
            }
            
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {
                Log.w(TAG, "⚠️ GPS provider disabled")
                locationManager.removeUpdates(this)
            }
        }
        
        try {
            if (ActivityCompat.checkSelfPermission(
                    context,
                    Manifest.permission.ACCESS_FINE_LOCATION
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                // Check if GPS is available
                if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                    Log.w(TAG, "⚠️ GPS provider not available")
                    return
                }
                
                // Request single update (won't block)
                locationManager.requestSingleUpdate(
                    LocationManager.GPS_PROVIDER,
                    gpsListener,
                    Looper.getMainLooper()
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting GPS update: ${e.message}", e)
        }
    }
    
    /**
     * Check if location permission is granted
     */
    private fun hasLocationPermission(): Boolean {
        return ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Check if cached location is still valid
     */
    private fun isCacheValid(): Boolean {
        return cachedLocation != null &&
                (System.currentTimeMillis() - cacheTimestamp) < CACHE_DURATION_MS
    }
    
    /**
     * Convert Location to Map for MethodChannel
     */
    fun locationToMap(location: Location): Map<String, Any> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "accuracy" to location.accuracy.toDouble(),
            "altitude" to location.altitude,
            "heading" to location.bearing.toDouble(),
            "speed" to location.speed.toDouble(),
            "timestamp" to location.time,
            "isMocked" to location.isFromMockProvider
        )
    }
}
