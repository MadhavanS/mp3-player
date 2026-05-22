package com.example.mp3_player

import com.ryanheise.audioservice.AudioServiceActivity
import com.ryanheise.audioservice.AudioServicePlugin
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine

/**
 * Launcher activity for apps using audio_service: registers Flutter plugins via [AudioServiceActivity]
 * and attaches our widget [MethodChannel] (main [MainActivity] is not used in the manifest).
 *
 * Uses the cached audio_service Flutter engine and must not destroy it with the activity
 * (otherwise reopening the app shows a black screen while the service keeps playing).
 */
class Mp3PlayerAudioServiceActivity : AudioServiceActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        readWidgetLaunchAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readWidgetLaunchAction(intent)
    }

    private fun readWidgetLaunchAction(intent: Intent?) {
        val action = intent?.getStringExtra(WidgetLaunchBridge.EXTRA_WIDGET_ACTION)?.trim()
        if (!action.isNullOrEmpty()) {
            WidgetLaunchBridge.setPendingAction(action)
        }
    }

    override fun getCachedEngineId(): String {
        AudioServicePlugin.getFlutterEngine(this)
        return AudioServicePlugin.getFlutterEngineId()
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Mp3PlayerWidgetMethodChannel.attach(flutterEngine, applicationContext)
        WidgetLaunchBridge.attach(flutterEngine)
        AppTaskMethodChannel.attach(flutterEngine, this)
    }
}
