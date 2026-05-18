package com.example.mp3_player

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.io.File

class Mp3PlayerGlassCardWidget : AppWidgetProvider() {

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
        private const val TAG = "Mp3PlayerGlassCard"

        fun refreshAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val cn = ComponentName(context, Mp3PlayerGlassCardWidget::class.java)
            for (appWidgetId in mgr.getAppWidgetIds(cn)) {
                updateAppWidget(context, mgr, appWidgetId)
            }
        }

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            try {
                applyWidget(context, appWidgetManager, appWidgetId)
            } catch (e: Exception) {
                Log.e(TAG, "Widget update failed for id=$appWidgetId", e)
            }
        }

        private fun applyWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val prefs = context.getSharedPreferences(Mp3PlayerWidgetPrefs.PREFS_NAME, Context.MODE_PRIVATE)
            val hasTrack = prefs.getBoolean(Mp3PlayerWidgetPrefs.HAS_TRACK, false)
            val title = prefs.getString(Mp3PlayerWidgetPrefs.TITLE, "") ?: ""
            val album = prefs.getString(Mp3PlayerWidgetPrefs.ALBUM, "") ?: ""
            val artPath = prefs.getString(Mp3PlayerWidgetPrefs.ART_PATH, "") ?: ""
            val playing = prefs.getBoolean(Mp3PlayerWidgetPrefs.PLAYING, false)
            val positionMs = prefs.getLong(Mp3PlayerWidgetPrefs.POSITION_MS, 0L)
            val durationMs = prefs.getLong(Mp3PlayerWidgetPrefs.DURATION_MS, 0L)
            val canSkipNext = prefs.getBoolean(Mp3PlayerWidgetPrefs.CAN_SKIP_NEXT, true)

            val views = RemoteViews(context.packageName, R.layout.widget_mp3_player_glass_card)

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent()
            val launchPending = PendingIntent.getActivity(
                context,
                10,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_glass_card_art, launchPending)
            views.setOnClickPendingIntent(R.id.widget_glass_card_text_column, launchPending)

            if (!hasTrack) {
                views.setTextViewText(R.id.widget_glass_card_title, context.getString(R.string.widget_idle_title))
                views.setTextViewText(R.id.widget_glass_card_artist, context.getString(R.string.widget_idle_subtitle))
                views.setImageViewResource(R.id.widget_glass_card_art, R.mipmap.ic_launcher)
                views.setViewVisibility(R.id.widget_glass_card_controls_row, View.GONE)
                views.setViewVisibility(R.id.widget_glass_card_progress, View.GONE)
            } else {
                views.setTextViewText(
                    R.id.widget_glass_card_title,
                    title.ifBlank { context.getString(R.string.widget_unknown_title) },
                )
                views.setTextViewText(
                    R.id.widget_glass_card_artist,
                    album.ifBlank { context.getString(R.string.widget_unknown_album) },
                )

                val artBitmap = loadRoundedArtOrPlaceholder(prefs, artPath, hasTrack = true)
                if (artBitmap != null) {
                    views.setImageViewBitmap(R.id.widget_glass_card_art, artBitmap)
                } else {
                    views.setImageViewResource(R.id.widget_glass_card_art, R.mipmap.ic_launcher)
                }

                views.setViewVisibility(R.id.widget_glass_card_controls_row, View.VISIBLE)
                views.setViewVisibility(R.id.widget_glass_card_progress, if (durationMs > 0L) View.VISIBLE else View.GONE)
                if (durationMs > 0L) {
                    val max = 1000
                    val progress = ((positionMs.coerceAtLeast(0L) * max) / durationMs.coerceAtLeast(1L))
                        .toInt()
                        .coerceIn(0, max)
                    views.setProgressBar(R.id.widget_glass_card_progress, max, progress, false)
                }

                views.setImageViewResource(
                    R.id.widget_glass_card_btn_play_pause,
                    if (playing) R.drawable.widget_ic_pause else R.drawable.widget_ic_play,
                )
                views.setInt(R.id.widget_glass_card_btn_next, "setImageAlpha", if (canSkipNext) 255 else 77)
            }

            views.setOnClickPendingIntent(
                R.id.widget_glass_card_btn_prev,
                mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_SKIP_PREVIOUS, 11),
            )
            views.setOnClickPendingIntent(
                R.id.widget_glass_card_btn_play_pause,
                mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_PLAY_PAUSE, 12),
            )
            views.setOnClickPendingIntent(
                R.id.widget_glass_card_btn_next,
                mediaActionPendingIntent(context, WidgetMediaActionReceiver.ACTION_SKIP_NEXT, 13),
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun loadRoundedArtOrPlaceholder(
            prefs: android.content.SharedPreferences,
            artPath: String,
            hasTrack: Boolean,
        ): Bitmap? {
            val file = loadRoundedArtBitmap(artPath)
            if (file != null) return file
            if (!hasTrack) return null
            return WidgetArtPlaceholderBitmap.fromPrefs(
                prefs,
                320,
                WidgetArtPlaceholderBitmap.Shape.ROUNDED_SQUARE,
            )
        }

        private fun loadRoundedArtBitmap(path: String): Bitmap? {
            if (path.isBlank()) return null
            val file = File(path)
            if (!file.isFile || !file.canRead()) return null
            return try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                val maxPx = 320
                var sampleSize = 1
                var w = bounds.outWidth
                var h = bounds.outHeight
                while (w > maxPx * 2 || h > maxPx * 2) {
                    sampleSize *= 2
                    w /= 2
                    h /= 2
                }

                val raw = BitmapFactory.decodeFile(
                    file.absolutePath,
                    BitmapFactory.Options().apply { inSampleSize = sampleSize },
                ) ?: return null

                val size = minOf(raw.width, raw.height)
                val xOff = (raw.width - size) / 2
                val yOff = (raw.height - size) / 2
                val square = Bitmap.createBitmap(raw, xOff, yOff, size, size)
                if (square !== raw) raw.recycle()

                val target = 320
                val scaled = if (square.width == target && square.height == target) {
                    square
                } else {
                    Bitmap.createScaledBitmap(square, target, target, true).also {
                        if (it !== square) square.recycle()
                    }
                }

                val output = Bitmap.createBitmap(target, target, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(output)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                val radius = target * 0.12f
                canvas.drawRoundRect(RectF(0f, 0f, target.toFloat(), target.toFloat()), radius, radius, paint)
                paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                canvas.drawBitmap(scaled, 0f, 0f, paint)
                scaled.recycle()
                output
            } catch (e: Exception) {
                Log.w(TAG, "loadRoundedArtBitmap failed for $path", e)
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
