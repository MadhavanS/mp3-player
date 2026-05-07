package com.example.mp3_player

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Launcher activity for apps using audio_service: registers Flutter plugins via [AudioServiceActivity]
 * and attaches our widget [MethodChannel] (main [MainActivity] is not used in the manifest).
 */
class Mp3PlayerAudioServiceActivity : AudioServiceActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Mp3PlayerWidgetMethodChannel.attach(flutterEngine, applicationContext)
    }
}
