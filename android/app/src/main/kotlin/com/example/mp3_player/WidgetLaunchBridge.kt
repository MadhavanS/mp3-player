package com.example.mp3_player

import android.content.Context
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Passes home-widget transport intents to Flutter when AudioService is not running. */
object WidgetLaunchBridge {
    const val EXTRA_WIDGET_ACTION = "com.example.mp3_player.extra.WIDGET_ACTION"

    const val ACTION_PLAY = "play"
    const val ACTION_SKIP_NEXT = "skip_next"
    const val ACTION_SKIP_PREVIOUS = "skip_previous"

    private const val CHANNEL = "com.example.mp3_player/widget_launch"

    @Volatile
    private var pendingAction: String? = null

    fun setPendingAction(action: String) {
        pendingAction = action
    }

    fun consumePendingAction(): String? {
        val action = pendingAction
        pendingAction = null
        return action
    }

    fun launchAppForAction(context: Context, action: String) {
        setPendingAction(action)
        val launch = Intent(context, Mp3PlayerAudioServiceActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            putExtra(EXTRA_WIDGET_ACTION, action)
        }
        context.startActivity(launch)
    }

    fun launchMainTask(context: Context) {
        val launch = Intent(context, Mp3PlayerAudioServiceActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        context.startActivity(launch)
    }

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeLaunchAction" -> result.success(consumePendingAction())
                    else -> result.notImplemented()
                }
            }
    }
}
