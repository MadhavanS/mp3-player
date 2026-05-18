package com.example.mp3_player

import android.content.Context

@Suppress("UNCHECKED_CAST")
internal object Mp3PlayerWidgetSync {

    fun handleSync(context: Context, args: Map<*, *>) {
        val p = context.getSharedPreferences(Mp3PlayerWidgetPrefs.PREFS_NAME, Context.MODE_PRIVATE).edit()
        p.putBoolean(Mp3PlayerWidgetPrefs.HAS_TRACK, args.bool(Mp3PlayerWidgetPrefs.HAS_TRACK))
        p.putString(Mp3PlayerWidgetPrefs.TITLE, args.string(Mp3PlayerWidgetPrefs.TITLE))
        p.putString(Mp3PlayerWidgetPrefs.ARTIST, args.string(Mp3PlayerWidgetPrefs.ARTIST))
        p.putString(Mp3PlayerWidgetPrefs.ALBUM, args.string(Mp3PlayerWidgetPrefs.ALBUM))
        p.putString(Mp3PlayerWidgetPrefs.ART_PATH, args.string(Mp3PlayerWidgetPrefs.ART_PATH))
        p.putString(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_STYLE, args.string("art_placeholder_style").ifBlank { "gradient" })
        p.putInt(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_C0, args.int("art_placeholder_c0"))
        p.putInt(Mp3PlayerWidgetPrefs.ART_PLACEHOLDER_C1, args.int("art_placeholder_c1"))
        p.putBoolean(Mp3PlayerWidgetPrefs.PLAYING, args.bool(Mp3PlayerWidgetPrefs.PLAYING))
        p.putLong(Mp3PlayerWidgetPrefs.POSITION_MS, args.long(Mp3PlayerWidgetPrefs.POSITION_MS))
        p.putLong(Mp3PlayerWidgetPrefs.DURATION_MS, args.long(Mp3PlayerWidgetPrefs.DURATION_MS))
        p.putBoolean(Mp3PlayerWidgetPrefs.CAN_SKIP_NEXT, args.bool(Mp3PlayerWidgetPrefs.CAN_SKIP_NEXT, true))
        p.putBoolean(Mp3PlayerWidgetPrefs.IS_DARK, args.bool(Mp3PlayerWidgetPrefs.IS_DARK, true))
        p.commit()
        Mp3PlayerAppWidget.refreshAll(context)
        Mp3PlayerGlassCardWidget.refreshAll(context)
    }

    fun handlePlaybackProgress(context: Context, args: Map<*, *>) {
        val p = context.getSharedPreferences(Mp3PlayerWidgetPrefs.PREFS_NAME, Context.MODE_PRIVATE).edit()
        p.putBoolean(Mp3PlayerWidgetPrefs.PLAYING, args.bool(Mp3PlayerWidgetPrefs.PLAYING))
        p.putLong(Mp3PlayerWidgetPrefs.POSITION_MS, args.long(Mp3PlayerWidgetPrefs.POSITION_MS))
        p.putLong(Mp3PlayerWidgetPrefs.DURATION_MS, args.long(Mp3PlayerWidgetPrefs.DURATION_MS))
        p.commit()
        Mp3PlayerAppWidget.refreshAll(context)
        Mp3PlayerGlassCardWidget.refreshAll(context)
    }

    private fun Map<*, *>.bool(key: String, default: Boolean = false): Boolean {
        val v = this[key] ?: return default
        return when (v) {
            is Boolean -> v
            is Number -> v.toInt() != 0
            else -> default
        }
    }

    private fun Map<*, *>.string(key: String): String {
        val v = this[key] ?: return ""
        return v.toString()
    }

    private fun Map<*, *>.long(key: String): Long {
        val v = this[key] ?: return 0L
        return when (v) {
            is Number -> v.toLong()
            else -> v.toString().toLongOrNull() ?: 0L
        }
    }

    private fun Map<*, *>.int(key: String, default: Int = 0): Int {
        val v = this[key] ?: return default
        return when (v) {
            is Number -> v.toInt()
            else -> v.toString().toIntOrNull() ?: default
        }
    }
}
