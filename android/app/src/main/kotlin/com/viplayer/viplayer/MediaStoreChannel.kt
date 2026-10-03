package com.viplayer.viplayer

import android.content.Context
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Lists the device's music from Android's MediaStore index, so the library
 * finds songs anywhere on the phone without a full file-system walk and
 * without the broad "all files" permission.
 *
 * Dart side: lib/core/library/media_store.dart
 */
class MediaStoreChannel(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listAudio" -> executor.execute {
                        try {
                            val files = listAudio()
                            runOnMain { result.success(files) }
                        } catch (e: SecurityException) {
                            runOnMain { result.error("PERMISSION", e.message, null) }
                        } catch (e: Exception) {
                            runOnMain { result.error("QUERY_FAILED", e.message, null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** One map per audio file: path, size (bytes), modified (ms since epoch). */
    private fun listAudio(): List<Map<String, Any>> {
        val files = mutableListOf<Map<String, Any>>()
        val projection = arrayOf(
            // DATA is deprecated for writing but still the reliable way to get
            // a readable path; apps with READ_MEDIA_AUDIO may read it.
            @Suppress("DEPRECATION") MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
        )
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            // Skip ringtones, notification sounds, voice recordings etc.
            "${MediaStore.Audio.Media.IS_MUSIC} != 0",
            null,
            null,
        )?.use { cursor ->
            val pathCol = cursor.getColumnIndexOrThrow(projection[0])
            val sizeCol = cursor.getColumnIndexOrThrow(projection[1])
            val modifiedCol = cursor.getColumnIndexOrThrow(projection[2])
            while (cursor.moveToNext()) {
                val path = cursor.getString(pathCol) ?: continue
                files.add(
                    mapOf(
                        "path" to path,
                        "size" to cursor.getLong(sizeCol),
                        "modified" to cursor.getLong(modifiedCol) * 1000,
                    )
                )
            }
        }
        return files
    }

    private fun runOnMain(block: () -> Unit) =
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)

    companion object {
        const val CHANNEL = "viplayer/media_store"
    }
}
