package com.example.mp3_player

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Home-screen widget sync from Flutter; must register on every [FlutterEngine] entrypoint. */
object Mp3PlayerWidgetMethodChannel {
    private const val CHANNEL = "com.example.mp3_player/widget"

    fun attach(flutterEngine: FlutterEngine, appContext: Context) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        Mp3PlayerWidgetSync.handleSync(appContext, args)
                        result.success(null)
                    }
                    "syncPlaybackProgress" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        Mp3PlayerWidgetSync.handlePlaybackProgress(appContext, args)
                        result.success(null)
                    }
                    "setPlaying" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        val playing = when (val v = args["playing"]) {
                            is Boolean -> v
                            is Number -> v.toInt() != 0
                            else -> false
                        }
                        Mp3PlayerWidgetSync.setPlayingIndicator(appContext, playing)
                        result.success(null)
                    }
                    "clearWidgetData" -> {
                        appContext.getSharedPreferences(
                            Mp3PlayerWidgetPrefs.PREFS_NAME,
                            Context.MODE_PRIVATE,
                        ).edit().clear().apply()
                        Mp3PlayerAppWidget.refreshAll(appContext)
                        Mp3PlayerGlassCardWidget.refreshAll(appContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
