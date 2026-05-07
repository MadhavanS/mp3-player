package com.example.mp3_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

class Mp3PlayerAppWidget : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, Mp3PlayerAppWidget::class.java)
            val ids = mgr.getAppWidgetIds(cn)
            if (ids.isEmpty()) return
            for (appWidgetId in ids) {
                updateAppWidget(context, mgr, appWidgetId)
            }
        }

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(Mp3PlayerWidgetPrefs.PREFS_NAME, Context.MODE_PRIVATE)
            val hasTrack = prefs.getBoolean(Mp3PlayerWidgetPrefs.HAS_TRACK, false)
            val title = prefs.getString(Mp3PlayerWidgetPrefs.TITLE, "") ?: ""
            val artist = prefs.getString(Mp3PlayerWidgetPrefs.ARTIST, "") ?: ""
            val artPath = prefs.getString(Mp3PlayerWidgetPrefs.ART_PATH, "") ?: ""
            val playing = prefs.getBoolean(Mp3PlayerWidgetPrefs.PLAYING, false)
            val positionMs = prefs.getLong(Mp3PlayerWidgetPrefs.POSITION_MS, 0L)
            val durationMs = prefs.getLong(Mp3PlayerWidgetPrefs.DURATION_MS, 0L)
            val canSkipNext = prefs.getBoolean(Mp3PlayerWidgetPrefs.CAN_SKIP_NEXT, true)
            val isDark = prefs.getBoolean(Mp3PlayerWidgetPrefs.IS_DARK, true)

            val views = RemoteViews(context.packageName, R.layout.widget_mp3_player)

            val bgRes = if (isDark) R.drawable.widget_glass_dark else R.drawable.widget_glass_light
            views.setInt(R.id.widget_root, "setBackgroundResource", bgRes)

            val frameRes =
                if (isDark) R.drawable.widget_art_frame_dark else R.drawable.widget_art_frame_light
            views.setInt(R.id.widget_art, "setBackgroundResource", frameRes)

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent()

            val launchPending = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            views.setOnClickPendingIntent(R.id.widget_art, launchPending)
            views.setOnClickPendingIntent(R.id.widget_text_column, launchPending)

            val prevIcon =
                if (isDark) R.drawable.widget_ic_skip_previous else R.drawable.widget_ic_skip_previous_on_light
            val nextIcon =
                if (isDark) R.drawable.widget_ic_skip_next else R.drawable.widget_ic_skip_next_on_light

            views.setImageViewResource(R.id.widget_btn_prev, prevIcon)
            views.setImageViewResource(R.id.widget_btn_next, nextIcon)

            if (!hasTrack) {
                views.setViewVisibility(R.id.widget_controls_row, View.GONE)
                views.setViewVisibility(R.id.widget_progress, View.GONE)

                views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_idle_title))
                views.setTextViewText(
                    R.id.widget_subtitle,
                    context.getString(R.string.widget_idle_subtitle),
                )
                views.setInt(R.id.widget_title, "setTextColor", textPrimary(isDark))
                views.setInt(R.id.widget_subtitle, "setTextColor", textMuted(isDark))

                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            } else {
                views.setViewVisibility(R.id.widget_controls_row, View.VISIBLE)

                views.setTextViewText(
                    R.id.widget_title,
                    title.ifBlank { context.getString(R.string.widget_unknown_title) },
                )
                views.setTextViewText(R.id.widget_subtitle, artist)
                views.setInt(R.id.widget_title, "setTextColor", textPrimary(isDark))
                views.setInt(R.id.widget_subtitle, "setTextColor", textMuted(isDark))

                val bitmap = loadArtBitmap(artPath)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.widget_art, bitmap)
                } else {
                    views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
                }

                if (durationMs > 0L) {
                    views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                    val max = 1000
                    val progress = ((positionMs.coerceAtLeast(0L) * max) / durationMs.coerceAtLeast(1L))
                        .toInt()
                        .coerceIn(0, max)
                    views.setProgressBar(R.id.widget_progress, max, progress, false)
                } else {
                    views.setViewVisibility(R.id.widget_progress, View.GONE)
                }

                views.setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (playing) R.drawable.widget_ic_pause else R.drawable.widget_ic_play,
                )

                views.setOnClickPendingIntent(
                    R.id.widget_btn_prev,
                    mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_SKIP_PREVIOUS, 1),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_btn_play_pause,
                    mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_PLAY_PAUSE, 2),
                )
                views.setOnClickPendingIntent(
                    R.id.widget_btn_next,
                    mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_SKIP_NEXT, 3),
                )

                val nextAlpha = if (canSkipNext) 255 else 77
                views.setInt(R.id.widget_btn_next, "setImageAlpha", nextAlpha)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun textPrimary(isDark: Boolean): Int =
            if (isDark) 0xFFFFFFFF.toInt() else 0xDE000000.toInt()

        private fun textMuted(isDark: Boolean): Int =
            if (isDark) 0xB3FFFFFF.toInt() else 0x99000000.toInt()

        private fun loadArtBitmap(path: String): Bitmap? {
            if (path.isBlank()) return null
            val f = File(path)
            if (!f.isFile || !f.canRead()) return null
            return try {
                val opts = BitmapFactory.Options().apply { inSampleSize = 1 }
                BitmapFactory.decodeFile(f.absolutePath, opts)?.let { bmp ->
                    val max = 256
                    if (bmp.width <= max && bmp.height <= max) {
                        bmp
                    } else {
                        val scale = max.toFloat() / kotlin.math.max(bmp.width, bmp.height).toFloat()
                        val w = (bmp.width * scale).toInt().coerceAtLeast(1)
                        val h = (bmp.height * scale).toInt().coerceAtLeast(1)
                        Bitmap.createScaledBitmap(bmp, w, h, true).also {
                            if (it !== bmp) bmp.recycle()
                        }
                    }
                }
            } catch (_: Exception) {
                null
            }
        }

        private fun mediaActionPendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(action).setPackage(context.packageName)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
