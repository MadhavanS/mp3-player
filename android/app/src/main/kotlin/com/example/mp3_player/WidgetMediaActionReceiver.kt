package com.example.mp3_player

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat

// Routes widget transport buttons to AudioService's media session (same as notification).
class WidgetMediaActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        val pendingResult = goAsync()
        val appCtx = context.applicationContext
        val handler = Handler(Looper.getMainLooper())

        var browser: MediaBrowserCompat? = null

        val timeout = Runnable {
            try {
                browser?.disconnect()
            } catch (_: Exception) {
            }
            pendingResult.finish()
        }
        handler.postDelayed(timeout, 2500L)

        val callback = object : MediaBrowserCompat.ConnectionCallback() {
            override fun onConnected() {
                handler.removeCallbacks(timeout)
                try {
                    val controller = MediaControllerCompat(appCtx, browser!!.sessionToken)
                    val tc = controller.transportControls
                    when (action) {
                        ACTION_PLAY_PAUSE -> {
                            val st = controller.playbackState?.state ?: PlaybackStateCompat.STATE_NONE
                            val activelyPlaying =
                                st == PlaybackStateCompat.STATE_PLAYING ||
                                    st == PlaybackStateCompat.STATE_BUFFERING
                            if (activelyPlaying) tc.pause() else tc.play()
                        }
                        ACTION_SKIP_NEXT -> tc.skipToNext()
                        ACTION_SKIP_PREVIOUS -> tc.skipToPrevious()
                    }
                } catch (_: Exception) {
                } finally {
                    try {
                        browser?.disconnect()
                    } catch (_: Exception) {
                    }
                    Mp3PlayerAppWidget.refreshAll(appCtx)
                    pendingResult.finish()
                }
            }

            override fun onConnectionFailed() {
                handler.removeCallbacks(timeout)
                try {
                    browser?.disconnect()
                } catch (_: Exception) {
                }
                pendingResult.finish()
            }

            override fun onConnectionSuspended() {
                handler.removeCallbacks(timeout)
                try {
                    browser?.disconnect()
                } catch (_: Exception) {
                }
                pendingResult.finish()
            }
        }

        browser = MediaBrowserCompat(
            appCtx,
            ComponentName(appCtx, "com.ryanheise.audioservice.AudioService"),
            callback,
            null,
        )

        browser!!.connect()
    }

    companion object {
        const val ACTION_PLAY_PAUSE = "com.example.mp3_player.action.WIDGET_PLAY_PAUSE"
        const val ACTION_SKIP_NEXT = "com.example.mp3_player.action.WIDGET_SKIP_NEXT"
        const val ACTION_SKIP_PREVIOUS = "com.example.mp3_player.action.WIDGET_SKIP_PREVIOUS"
    }
}
