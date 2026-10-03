package com.viplayer.viplayer

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Lets LAN sync receive UDP broadcasts: many Android devices drop them
 * unless the app holds a Wi-Fi multicast lock.
 *
 * Dart side: lib/core/sync/sync_providers.dart
 */
class NetworkChannel(private val context: Context) {
    private var lock: WifiManager.MulticastLock? = null

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        if (lock == null) {
                            val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            lock = wifi.createMulticastLock("viplayer-sync").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        lock?.release()
                        lock = null
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        const val CHANNEL = "viplayer/network"
    }
}
