package com.viplayer.viplayer

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App updates downloaded from the paired PC: reports this build's
 * versionCode and opens the system installer for a downloaded APK (the user
 * confirms there). Android installs it as an update — data kept — only if it
 * is signed with the same key and has a higher versionCode.
 *
 * The APK lies in the cache dir's `update/` folder, shared with the
 * installer through the FileProvider declared in AndroidManifest.xml
 * (res/xml/update_paths.xml).
 *
 * Dart side: lib/core/update/update_service.dart
 */
class UpdateChannel(private val activity: Activity) {
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versionCode" -> result.success(versionCode())
                    "install" -> result.success(install(call.argument<String>("path")))
                    else -> result.notImplemented()
                }
            }
    }

    private fun versionCode(): Int {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        return if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            info.versionCode
        }
    }

    private fun install(path: String?): String {
        if (path == null) return "error"
        val pm = activity.packageManager
        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) {
            // One-time permission: "Install unknown apps" for ViPlayer.
            activity.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ),
            )
            return "needPermission"
        }
        return try {
            val uri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.updates",
                File(path),
            )
            activity.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            "ok"
        } catch (e: Exception) {
            Log.w(TAG, "could not open the installer", e)
            "error"
        }
    }

    private companion object {
        const val CHANNEL = "viplayer/update"
        const val TAG = "ViPlayerUpdate"
    }
}
