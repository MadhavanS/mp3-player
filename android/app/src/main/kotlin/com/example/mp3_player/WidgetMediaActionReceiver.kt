package com.example.mp3_player

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
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
                var finishDeferred = false
                try {
                    val controller = MediaControllerCompat(appCtx, browser!!.sessionToken)
                    val tc = controller.transportControls
                    when (action) {
                        ACTION_PLAY_PAUSE -> {
                            val st = controller.playbackState?.state ?: PlaybackStateCompat.STATE_NONE
                            val activelyPlaying =
                                st == PlaybackStateCompat.STATE_PLAYING ||
                                    st == PlaybackStateCompat.STATE_BUFFERING
                            val nextPlaying = !activelyPlaying
                            context.getSharedPreferences(
                                Mp3PlayerWidgetPrefs.PREFS_NAME,
                                Context.MODE_PRIVATE,
                            )
                                .edit()
                                .putBoolean(Mp3PlayerWidgetPrefs.PLAYING, nextPlaying)
                                .apply()
                            if (activelyPlaying) tc.pause() else tc.play()
                        }
                        ACTION_SKIP_NEXT -> {
                            tc.skipToNext()
                            finishDeferred = true
                            refreshAfterMetadataSettles(appCtx, handler, pendingResult, browser, controller)
                        }
                        ACTION_SKIP_PREVIOUS -> {
                            tc.skipToPrevious()
                            finishDeferred = true
                            refreshAfterMetadataSettles(appCtx, handler, pendingResult, browser, controller)
                        }
                    }
                } catch (_: Exception) {
                } finally {
                    if (finishDeferred) return
                    try {
                        browser?.disconnect()
                    } catch (_: Exception) {
                    }
                    Mp3PlayerAppWidget.refreshAll(appCtx)
                    Mp3PlayerGlassCardWidget.refreshAll(appCtx)
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

        private fun refreshAfterMetadataSettles(
            context: Context,
            handler: Handler,
            pendingResult: PendingResult,
            browser: MediaBrowserCompat?,
            controller: MediaControllerCompat,
        ) {
            // The media session metadata usually updates just after skipToNext/Previous
            // returns. Wait briefly, then copy the new metadata into widget prefs so
            // artwork/title/album repaint together instead of reusing stale art_path.
            handler.postDelayed(
                {
                    try {
                        syncPrefsFromController(context, controller)
                        Mp3PlayerAppWidget.refreshAll(context)
                        Mp3PlayerGlassCardWidget.refreshAll(context)
                    } finally {
                        try {
                            browser?.disconnect()
                        } catch (_: Exception) {
                        }
                        pendingResult.finish()
                    }
                },
                450L,
            )
        }

        private fun syncPrefsFromController(context: Context, controller: MediaControllerCompat) {
            val metadata = controller.metadata ?: return
            val state = controller.playbackState?.state ?: PlaybackStateCompat.STATE_NONE
            val playing = state == PlaybackStateCompat.STATE_PLAYING ||
                state == PlaybackStateCompat.STATE_BUFFERING

            val editor = context.getSharedPreferences(
                Mp3PlayerWidgetPrefs.PREFS_NAME,
                Context.MODE_PRIVATE,
            ).edit()

            val title = metadata.firstString(
                MediaMetadataCompat.METADATA_KEY_TITLE,
                MediaMetadataCompat.METADATA_KEY_DISPLAY_TITLE,
            )
            val artist = metadata.firstString(
                MediaMetadataCompat.METADATA_KEY_ARTIST,
                MediaMetadataCompat.METADATA_KEY_DISPLAY_SUBTITLE,
            )
            val album = metadata.firstString(MediaMetadataCompat.METADATA_KEY_ALBUM)
            val artPath = metadata.firstFilePath(
                MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI,
                MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI,
                MediaMetadataCompat.METADATA_KEY_ART_URI,
            )
            val duration = metadata.getLong(MediaMetadataCompat.METADATA_KEY_DURATION)

            editor.putBoolean(Mp3PlayerWidgetPrefs.HAS_TRACK, true)
            if (title.isNotBlank()) editor.putString(Mp3PlayerWidgetPrefs.TITLE, title)
            if (artist.isNotBlank()) editor.putString(Mp3PlayerWidgetPrefs.ARTIST, artist)
            if (album.isNotBlank()) editor.putString(Mp3PlayerWidgetPrefs.ALBUM, album)
            if (artPath.isNotBlank()) editor.putString(Mp3PlayerWidgetPrefs.ART_PATH, artPath)
            if (duration > 0L) editor.putLong(Mp3PlayerWidgetPrefs.DURATION_MS, duration)
            editor.putBoolean(Mp3PlayerWidgetPrefs.PLAYING, playing)
            editor.apply()
        }

        private fun MediaMetadataCompat.firstString(vararg keys: String): String {
            for (key in keys) {
                val value = getString(key)?.trim()
                if (!value.isNullOrEmpty()) return value
            }
            return ""
        }

        private fun MediaMetadataCompat.firstFilePath(vararg keys: String): String {
            for (key in keys) {
                val value = getString(key)?.trim()
                if (value.isNullOrEmpty()) continue
                if (value.startsWith("file://")) {
                    return Uri.parse(value).path ?: ""
                }
                return value
            }
            return ""
        }
    }
}
