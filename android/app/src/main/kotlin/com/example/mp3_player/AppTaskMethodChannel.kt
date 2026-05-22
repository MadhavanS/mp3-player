package com.example.mp3_player

import android.app.Activity
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object AppTaskMethodChannel {
    private const val CHANNEL = "com.example.mp3_player/app_task"

    fun attach(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "finishAndRemoveTask" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            activity.finishAndRemoveTask()
                        } else {
                            @Suppress("DEPRECATION")
                            activity.finishAffinity()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
