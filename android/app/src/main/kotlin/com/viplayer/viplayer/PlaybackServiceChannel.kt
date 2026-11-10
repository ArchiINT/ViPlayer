package com.viplayer.viplayer

import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Lets a long pause leave the foreground.
 *
 * ViPlayer keeps audio_service in the foreground while paused
 * (androidStopForegroundOnPause = false): Android 16 mutes apps that start
 * playing from the background, which is what resuming after a call or
 * another app's sound is. Staying foreground forever would hold a wake lock,
 * so after a long pause Dart calls [releaseForeground] — audio_service's own
 * exitForegroundState() (stop foreground, keep the notification, release the
 * wake lock). Playing again re-enters the foreground as usual.
 *
 * The method is private in audio_service 0.18, hence reflection; the class is
 * kept from R8 in proguard-rules.pro. If it ever fails, the app just stays
 * foreground while paused.
 *
 * Dart side: lib/core/player/audio_handler.dart
 */
class PlaybackServiceChannel {
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "releaseForeground" -> result.success(releaseForeground())
                    else -> result.notImplemented()
                }
            }
    }

    private fun releaseForeground(): Boolean = try {
        val cls = Class.forName("com.ryanheise.audioservice.AudioService")
        val service = cls.getDeclaredField("instance")
            .apply { isAccessible = true }
            .get(null)
        if (service == null) {
            false
        } else {
            cls.getDeclaredMethod("exitForegroundState")
                .apply { isAccessible = true }
                .invoke(service)
            true
        }
    } catch (e: Exception) {
        Log.w("ViPlayer", "releaseForeground failed", e)
        false
    }

    companion object {
        const val CHANNEL = "viplayer/playback_service"
    }
}
