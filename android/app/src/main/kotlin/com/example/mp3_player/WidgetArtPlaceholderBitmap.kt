package com.example.mp3_player

import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader

/**
 * Theme-aligned placeholder when there is no album art file, matching Flutter [TrackAlbumArt]:
 * - `daisy`: warm vertical paper tones + outline
 * - `silver`: cool grey diagonal + dark stroke
 * - `gradient`: diagonal gradient from [color0] to [color1] (per-track [TrackItem.artColors])
 */
internal object WidgetArtPlaceholderBitmap {

    enum class Shape {
        CIRCLE,
        ROUNDED_SQUARE,
    }

    fun fromPrefs(prefs: SharedPreferences, sizePx: Int, shape: Shape): Bitmap {
        val placeholderStyle =
            prefs.getString(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_STYLE, "gradient") ?: "gradient"
        val c0 = prefs.getInt(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_C0, 0)
        val c1 = prefs.getInt(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_C1, 0)
        return create(placeholderStyle, c0, c1, sizePx, shape)
    }

    fun create(placeholderStyle: String, color0: Int, color1: Int, sizePx: Int, shape: Shape): Bitmap {
        val s = sizePx.coerceIn(64, 512)
        val bmp = Bitmap.createBitmap(s, s, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val fill = Paint(Paint.ANTI_ALIAS_FLAG)

        when (placeholderStyle) {
            "daisy" -> {
                val c0 = 0xFFE5D8C4.toInt()
                val c1 = 0xFFD3C0A7.toInt()
                fill.shader = LinearGradient(
                    0f,
                    0f,
                    0f,
                    s.toFloat(),
                    intArrayOf(c0, c1),
                    null,
                    Shader.TileMode.CLAMP,
                )
            }
            "silver" -> {
                val c0 = 0xFFC4C0BA.toInt()
                val c1 = 0xFFB8B4AE.toInt()
                fill.shader = LinearGradient(
                    0f,
                    0f,
                    s.toFloat(),
                    s.toFloat(),
                    intArrayOf(c0, c1),
                    null,
                    Shader.TileMode.CLAMP,
                )
            }
            else -> {
                val c0safe = if (color0 == 0) 0xFFA18CD1.toInt() else color0
                val c1safe = if (color1 == 0) c0safe else color1
                fill.shader = LinearGradient(
                    0f,
                    0f,
                    s.toFloat(),
                    s.toFloat(),
                    intArrayOf(c0safe, c1safe),
                    null,
                    Shader.TileMode.CLAMP,
                )
            }
        }

        drawShape(canvas, fill, s, shape)

        // Outline: Daisy / Silver match Flutter placeholder borders.
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            shader = null
        }
        when (placeholderStyle) {
            "daisy" -> {
                stroke.strokeWidth = maxOf(2f, s / 128f)
                stroke.color = 0xE62B2117.toInt()
                drawShapeOutline(canvas, stroke, s, shape)
            }
            "silver" -> {
                stroke.strokeWidth = maxOf(3f, s / 90f)
                stroke.color = 0xFF0A0A0A.toInt()
                drawShapeOutline(canvas, stroke, s, shape)
            }
            else -> { /* gradient: no border */ }
        }

        return bmp
    }

    private fun drawShape(canvas: Canvas, paint: Paint, s: Int, shape: Shape) {
        when (shape) {
            Shape.CIRCLE -> canvas.drawOval(RectF(0f, 0f, s.toFloat(), s.toFloat()), paint)
            Shape.ROUNDED_SQUARE -> {
                val r = s * 0.12f
                canvas.drawRoundRect(RectF(0f, 0f, s.toFloat(), s.toFloat()), r, r, paint)
            }
        }
    }

    private fun drawShapeOutline(canvas: Canvas, paint: Paint, s: Int, shape: Shape) {
        val inset = paint.strokeWidth * 0.5f
        when (shape) {
            Shape.CIRCLE -> canvas.drawOval(
                RectF(inset, inset, s - inset, s - inset),
                paint,
            )
            Shape.ROUNDED_SQUARE -> {
                val r = s * 0.12f
                val ri = (r - inset).coerceAtLeast(1f)
                canvas.drawRoundRect(
                    RectF(inset, inset, s - inset, s - inset),
                    ri,
                    ri,
                    paint,
                )
            }
        }
    }
}
