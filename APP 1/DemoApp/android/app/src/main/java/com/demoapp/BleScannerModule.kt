package com.demoapp

import android.bluetooth.le.*
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import android.os.Handler
import android.os.Looper
import androidx.annotation.RequiresApi
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import java.util.*

class BleScannerModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  private val bluetoothAdapter: BluetoothAdapter by lazy {
    val manager = reactContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    manager.adapter
  }
  private var scanner: BluetoothLeScanner? = null
  private var callback: ScanCallback? = null
  private var namePrefix: String? = null // Store name prefix for filtering
  
  // Use a main thread handler for consistent timing
  private val mainHandler = Handler(Looper.getMainLooper())
  private var scanRestartRunnable: Runnable? = null
  private var scanDebounceMap = HashMap<String, Long>()

  override fun getName(): String = "BleScanner"

  @ReactMethod
  fun addListener(eventName: String?) {
    // Required by React Native
  }

  @ReactMethod
  fun removeListeners(count: Int) {
    // Required by React Native
  }

  @ReactMethod
  fun startScan(config: ReadableMap?) {
    // Cancel any pending scan restarts
    scanRestartRunnable?.let { mainHandler.removeCallbacks(it) }
    
    scanner = bluetoothAdapter.bluetoothLeScanner

    // Stop any existing scan before starting a new one
    callback?.let { scanner?.stopScan(it) }

    // Clear debounce map for fresh start
    scanDebounceMap.clear()

    val scanMode = when (config?.getString("scanMode")) {
      "LOW_POWER" -> ScanSettings.SCAN_MODE_LOW_POWER
      "LOW_LATENCY" -> ScanSettings.SCAN_MODE_LOW_LATENCY
      else -> ScanSettings.SCAN_MODE_BALANCED
    }

    // Capture the name prefix filter if provided
    namePrefix = config?.getString("namePrefix")
    
    // Set up scan settings with appropriate params based on environment
    val scanPeriod = config?.getInt("scanPeriod") ?: 6000
    val scanInterval = config?.getInt("scanInterval") ?: 1000
    
    // Use SCAN_MODE_LOW_LATENCY, match report delay to Android's hardware capabilities
    val settings = ScanSettings.Builder()
      .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY) // Always use maximum power for reliable scanning
      .setReportDelay(0) // No batching for real-time processing
      
    // On Android 8.0+ we can use additional settings for more aggressive scanning
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      settings.setLegacy(false) // Use newer scanning if available
        .setPhy(ScanSettings.PHY_LE_ALL_SUPPORTED) // Scan on all PHYs
        .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES) // Report all advertisements
    }
    
    // On Android 10+ we can set the match mode for more matches
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      settings.setMatchMode(ScanSettings.MATCH_MODE_AGGRESSIVE) // Be very aggressive with matching
    }
    
    val builtSettings = settings.build()
    
    // Create a minimal filter list to focus only on our devices
    val filters = mutableListOf<ScanFilter>()
    
    // We'll only add name filters if specified, otherwise perform the filtering in callback
    // to make sure we don't miss anything (since filter lists are applied with OR, not AND)
    
    callback = object : ScanCallback() {
      override fun onScanResult(callbackType: Int, result: ScanResult) {
        val device = result.device
        val deviceName = device.name ?: ""
        val rssi = result.rssi
        val deviceAddress = device.address
                
        // Apply name prefix filter - only emit events for matching devices
        if (namePrefix != null && namePrefix!!.isNotEmpty()) {
          if (!deviceName.lowercase().startsWith(namePrefix!!.lowercase())) {
            return // Skip devices that don't match prefix
          }
        }
        
        // Use a minimal debounce only for the same device - 100ms
        val currentTimeMs = System.currentTimeMillis()
        val lastSeenTime = scanDebounceMap[deviceAddress] ?: 0L
        if (currentTimeMs - lastSeenTime < 100) {
            return // Skip very rapid updates for the same device
        }
        
        // Update last seen time
        scanDebounceMap[deviceAddress] = currentTimeMs

        val params = Arguments.createMap().apply {
          putString("id", deviceAddress)
          putString("name", deviceName)
          putInt("rssi", rssi)
          
          // Add manufacturerData if available
          result.scanRecord?.manufacturerSpecificData?.let { data ->
            if (data.size() > 0) {
              val manufacturerData = Arguments.createMap()
              for (i in 0 until data.size()) {
                val key = data.keyAt(i)
                val value = data.get(key)
                if (value != null) {
                  manufacturerData.putString(key.toString(), bytesToHex(value))
                }
              }
              putMap("manufacturerData", manufacturerData)
            }
          }
        }

        try {
          reactApplicationContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit("BleScanResult", params)
        } catch (e: Exception) {
          // Ignore failures if JS layer isn't ready
        }
      }
      
      // Handle scan failures by attempting to restart
      override fun onScanFailed(errorCode: Int) {
        // Try to restart scan after a brief pause if there's an error
        mainHandler.postDelayed({
          try {
            scanner?.startScan(null, builtSettings, this)
          } catch (e: Exception) {
            // Silently handle failures
          }
        }, 500)
      }
    }

    // Start initial scan - prefer no filters for maximum discovery
    try {
      scanner?.startScan(null, builtSettings, callback)
    } catch (e: Exception) {
      // Fallback to a more conservative approach if initial scan fails
      try {
        val backupSettings = ScanSettings.Builder()
          .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
          .build()
        scanner?.startScan(null, backupSettings, callback)
      } catch (e2: Exception) {
        // Last attempt with no settings
        try {
          scanner?.startScan(callback)
        } catch (e3: Exception) {
          // Give up if all attempts fail
        }
      }
    }
    
    // Set up continuous scanning with restart to overcome Android's BLE scan throttling
    // This uses a combination of short scan cycles rather than stopping completely
    scanRestartRunnable = object : Runnable {
      override fun run() {
        try {
          // Start a new scan without stopping the current one
          // This helps prevent gaps in scanning
          scanner?.startScan(null, builtSettings, callback)
          
          // Schedule next restart
          mainHandler.postDelayed(this, 2000) // Restart every 2 seconds
        } catch (e: Exception) {
          // If we hit errors (like throttling), try again after a pause
          mainHandler.postDelayed(this, 500)
        }
      }
    }
    
    // Start scan cycling immediately
    mainHandler.postDelayed(scanRestartRunnable!!, 2000) // First restart after 2s
  }

  @ReactMethod
  fun stopScan() {
    // Remove any pending scan restarts
    scanRestartRunnable?.let { mainHandler.removeCallbacks(it) }
    
    // Stop current scan
    try {
      callback?.let { scanner?.stopScan(it) }
    } catch (e: Exception) {
      // Ignore errors on stop
    }
    
    // Clear resources
    scanDebounceMap.clear()
    scanRestartRunnable = null
  }
  
  // Helper function to convert byte array to hex string
  private fun bytesToHex(bytes: ByteArray): String {
    val hexArray = "0123456789ABCDEF".toCharArray()
    val hexChars = CharArray(bytes.size * 2)
    for (j in bytes.indices) {
      val v = bytes[j].toInt() and 0xFF
      hexChars[j * 2] = hexArray[v ushr 4]
      hexChars[j * 2 + 1] = hexArray[v and 0x0F]
    }
    return String(hexChars)
  }
}
