package com.viplayer.viplayer

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity (a FlutterActivity) shares its engine with the
// background playback service, so playback survives leaving the app.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaStoreChannel(applicationContext).register(flutterEngine)
    }
}
