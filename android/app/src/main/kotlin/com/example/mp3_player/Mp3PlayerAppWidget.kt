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

        private const val TAG = "Mp3PlayerWidget"

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
            // Wrap everything so a reapply() failure on an old widget instance
            // does not crash the host process.
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
            val artist = prefs.getString(Mp3PlayerWidgetPrefs.ARTIST, "") ?: ""
            val artPath = prefs.getString(Mp3PlayerWidgetPrefs.ART_PATH, "") ?: ""
            val playing = prefs.getBoolean(Mp3PlayerWidgetPrefs.PLAYING, false)
            val positionMs = prefs.getLong(Mp3PlayerWidgetPrefs.POSITION_MS, 0L)
            val durationMs = prefs.getLong(Mp3PlayerWidgetPrefs.DURATION_MS, 0L)
            val canSkipNext = prefs.getBoolean(Mp3PlayerWidgetPrefs.CAN_SKIP_NEXT, true)
            val isDark = prefs.getBoolean(Mp3PlayerWidgetPrefs.IS_DARK, true)

            val views = RemoteViews(context.packageName, R.layout.widget_mp3_player)

            // Background: the layout XML already defaults to widget_glass_dark.
            // Only override for the light theme — the dark path is intentionally
            // left as the XML default so the card always shows even if this call
            // is skipped by the launcher.
            if (!isDark) {
                views.setInt(R.id.widget_root, "setBackgroundResource", R.drawable.widget_glass_light)
            }

            // Open-app intent wired to art and text column
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

            // Skip icon drawables (dark vs light theme)
            val prevIcon = if (isDark) R.drawable.widget_ic_skip_previous else R.drawable.widget_ic_skip_previous_on_light
            val nextIcon = if (isDark) R.drawable.widget_ic_skip_next else R.drawable.widget_ic_skip_next_on_light
            views.setImageViewResource(R.id.widget_btn_prev, prevIcon)
            views.setImageViewResource(R.id.widget_btn_next, nextIcon)

            if (!hasTrack) {
                // ── Idle state ────────────────────────────────────────────
                views.setViewVisibility(R.id.widget_controls_row, View.GONE)
                views.setViewVisibility(R.id.widget_progress, View.GONE)
                views.setViewVisibility(R.id.widget_time_current, View.GONE)
                views.setViewVisibility(R.id.widget_time_total, View.GONE)

                views.setTextViewText(R.id.widget_label, context.getString(R.string.widget_title))
                views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_idle_title))
                views.setInt(R.id.widget_label, "setTextColor", textMuted(isDark))
                views.setInt(R.id.widget_title, "setTextColor", textPrimary(isDark))

                views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
            } else {
                // ── Active playback state ─────────────────────────────────
                views.setViewVisibility(R.id.widget_controls_row, View.VISIBLE)

                // "Now playing" label
                views.setTextViewText(R.id.widget_label, context.getString(R.string.widget_now_playlist))
                views.setInt(R.id.widget_label, "setTextColor", textMuted(isDark))

                // Track title
                views.setTextViewText(
                    R.id.widget_title,
                    title.ifBlank { context.getString(R.string.widget_unknown_title) },
                )
                views.setInt(R.id.widget_title, "setTextColor", textPrimary(isDark))

                // Circular album art
                val bitmap = loadCircularArtBitmap(artPath)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.widget_art, bitmap)
                } else {
                    views.setImageViewResource(R.id.widget_art, R.mipmap.ic_launcher)
                }

                // Progress bar + time labels
                if (durationMs > 0L) {
                    views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_time_current, View.VISIBLE)
                    views.setViewVisibility(R.id.widget_time_total, View.VISIBLE)

                    val max = 1000
                    val progress = ((positionMs.coerceAtLeast(0L) * max) / durationMs.coerceAtLeast(1L))
                        .toInt()
                        .coerceIn(0, max)
                    views.setProgressBar(R.id.widget_progress, max, progress, false)

                    views.setTextViewText(R.id.widget_time_current, formatMs(positionMs))
                    views.setTextViewText(R.id.widget_time_total, formatMs(durationMs))
                    views.setInt(R.id.widget_time_current, "setTextColor", textMuted(isDark))
                    views.setInt(R.id.widget_time_total, "setTextColor", textMuted(isDark))
                } else {
                    views.setViewVisibility(R.id.widget_progress, View.GONE)
                    views.setViewVisibility(R.id.widget_time_current, View.GONE)
                    views.setViewVisibility(R.id.widget_time_total, View.GONE)
                }

                // Play / pause icon
                views.setImageViewResource(
                    R.id.widget_btn_play_pause,
                    if (playing) R.drawable.widget_ic_pause else R.drawable.widget_ic_play,
                )

                // Control click intents
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

                // Dim next button when skipping is unavailable
                val nextAlpha = if (canSkipNext) 255 else 77
                views.setInt(R.id.widget_btn_next, "setImageAlpha", nextAlpha)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        // ── Helpers ──────────────────────────────────────────────────────────

        private fun textPrimary(isDark: Boolean): Int =
            if (isDark) 0xFFFFFFFF.toInt() else 0xDE000000.toInt()

        private fun textMuted(isDark: Boolean): Int =
            if (isDark) 0x99FFFFFF.toInt() else 0x99000000.toInt()

        /** Format milliseconds as M:SS (e.g. 3:07). */
        private fun formatMs(ms: Long): String {
            val totalSec = (ms / 1000L).coerceAtLeast(0L)
            val minutes = totalSec / 60
            val seconds = totalSec % 60
            return "$minutes:${seconds.toString().padStart(2, '0')}"
        }

        /**
         * Load album art from [path], downscale it to ≤ 256 px, and crop it to
         * a circle so it matches the circular ImageView in the widget layout.
         * Returns null on any error so the caller can fall back to the launcher icon.
         */
        private fun loadCircularArtBitmap(path: String): Bitmap? {
            if (path.isBlank()) return null
            val file = File(path)
            if (!file.isFile || !file.canRead()) return null
            return try {
                // First pass: measure dimensions without decoding pixels.
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(file.absolutePath, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                // Calculate an inSampleSize so the decoded bitmap fits within 256 px.
                val maxPx = 256
                var sampleSize = 1
                var w = bounds.outWidth
                var h = bounds.outHeight
                while (w > maxPx * 2 || h > maxPx * 2) {
                    sampleSize *= 2
                    w /= 2
                    h /= 2
                }

                // Second pass: decode at reduced resolution.
                val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
                val raw = BitmapFactory.decodeFile(file.absolutePath, opts) ?: return null

                // Fine-scale to exactly maxPx if still above that.
                val scaled = if (raw.width <= maxPx && raw.height <= maxPx) {
                    raw
                } else {
                    val scale = maxPx.toFloat() / maxOf(raw.width, raw.height).toFloat()
                    val sw = (raw.width * scale).toInt().coerceAtLeast(1)
                    val sh = (raw.height * scale).toInt().coerceAtLeast(1)
                    Bitmap.createScaledBitmap(raw, sw, sh, true).also {
                        if (it !== raw) raw.recycle()
                    }
                }

                // Centre-crop to square.
                val size = minOf(scaled.width, scaled.height)
                val xOff = (scaled.width - size) / 2
                val yOff = (scaled.height - size) / 2
                val square = Bitmap.createBitmap(scaled, xOff, yOff, size, size)
                if (square !== scaled) scaled.recycle()

                // Clip to circle via Porter-Duff SRC_IN.
                val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(output)
                val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                canvas.drawOval(RectF(0f, 0f, size.toFloat(), size.toFloat()), paint)
                paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
                canvas.drawBitmap(square, 0f, 0f, paint)
                square.recycle()
                output
            } catch (e: Exception) {
                Log.w(TAG, "loadCircularArtBitmap failed for $path", e)
                null
            }
        }

        private fun mediaActionPendingIntent(
            context: Context,
            action: String,
            requestCode: Int,
        ): PendingIntent {
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
