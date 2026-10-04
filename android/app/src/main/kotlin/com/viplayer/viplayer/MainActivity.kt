package com.viplayer.viplayer

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity (a FlutterActivity) shares its engine with the
// background playback service, so playback survives leaving the app.
class MainActivity : AudioServiceActivity() {
    private var mediaStore: MediaStoreChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaStore = MediaStoreChannel(applicationContext, this).also {
            it.register(flutterEngine)
        }
        NetworkChannel(applicationContext).register(flutterEngine)
    }

    @Deprecated("Needed for startIntentSenderForResult (MediaStore delete)")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (mediaStore?.onActivityResult(requestCode, resultCode) != true) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
