package com.example.update_me

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject

class UpdateMeWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REACT_MOMENT = "com.example.update_me.ACTION_REACT_MOMENT"
        const val ACTION_PREV_MOMENT = "com.example.update_me.ACTION_PREV_MOMENT"
        const val ACTION_NEXT_MOMENT = "com.example.update_me.ACTION_NEXT_MOMENT"
        const val ACTION_REFRESH_MOMENTS = "com.example.update_me.ACTION_REFRESH_MOMENTS"
        const val TAG = "UpdateMeWidgetProvider"
        const val BACKEND_URL = "https://update-me-backend.nilojhonemil1.workers.dev"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        val widgetData = HomeWidgetPlugin.getData(context)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val componentName = ComponentName(context, UpdateMeWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)

        when (intent.action) {
            ACTION_PREV_MOMENT -> {
                val momentsJson = widgetData.getString("widget_moments_json", null)
                if (!momentsJson.isNullOrEmpty()) {
                    try {
                        val jsonArray = JSONArray(momentsJson)
                        if (jsonArray.length() > 1) {
                            var currentIndex = widgetData.getInt("widget_current_index", 0)
                            currentIndex = if (currentIndex <= 0) jsonArray.length() - 1 else currentIndex - 1
                            widgetData.edit().putInt("widget_current_index", currentIndex).apply()
                            onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in PREV_MOMENT: ${e.message}")
                    }
                }
            }

            ACTION_NEXT_MOMENT -> {
                val momentsJson = widgetData.getString("widget_moments_json", null)
                if (!momentsJson.isNullOrEmpty()) {
                    try {
                        val jsonArray = JSONArray(momentsJson)
                        if (jsonArray.length() > 1) {
                            var currentIndex = widgetData.getInt("widget_current_index", 0)
                            currentIndex = if (currentIndex >= jsonArray.length() - 1) 0 else currentIndex + 1
                            widgetData.edit().putInt("widget_current_index", currentIndex).apply()
                            onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in NEXT_MOMENT: ${e.message}")
                    }
                }
            }

            ACTION_REFRESH_MOMENTS -> {
                Log.d(TAG, "User triggered ACTION_REFRESH_MOMENTS from widget button 🔄")
                val userId = widgetData.getString("widget_user_id", null)

                // 1. Instant Visual Feedback: show REFRESHING on location badge
                for (appWidgetId in appWidgetIds) {
                    val views = RemoteViews(context.packageName, R.layout.update_me_widget)
                    views.setTextViewText(R.id.widget_location_badge, "SYNCING...")
                    appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
                }

                // 2. Background Thread Network Fetch
                if (!userId.isNullOrEmpty()) {
                    thread {
                        try {
                            val url = URL("$BACKEND_URL/api/updates/today/$userId?type=received")
                            val conn = url.openConnection() as HttpURLConnection
                            conn.requestMethod = "GET"
                            conn.connectTimeout = 8000
                            conn.readTimeout = 8000

                            if (conn.responseCode == 200) {
                                val responseText = conn.inputStream.bufferedReader().use { it.readText() }
                                val jsonResponse = JSONObject(responseText)
                                val updatesArray = jsonResponse.optJSONArray("updates")

                                if (updatesArray != null && updatesArray.length() > 0) {
                                    val newMomentsList = JSONArray()
                                    val filesDir = context.filesDir
                                    val nowCal = Calendar.getInstance()

                                    // Iterate newest-first so index 0 matches Flutter app ordering
                                    for (i in updatesArray.length() - 1 downTo 0) {
                                        val u = updatesArray.getJSONObject(i)
                                        val id = u.optNonNullString("id", "")
                                        val imageUrl = u.optNonNullString("image_url", "")
                                        if (id.isEmpty() || imageUrl.isEmpty()) continue

                                        val caption = u.optNonNullString("caption", "")
                                        val location = u.optNonNullString("location_name", "MOMENT").ifEmpty { "MOMENT" }
                                        val createdAt = u.optNonNullString("created_at", "")
                                        val isReacted = u.optBoolean("is_reacted", false)
                                        val replyText = u.optNonNullString("reply_text", "")
                                        val replyCreated = u.optNonNullString("reply_created_at", "")
                                        val isReplied = u.optBoolean("is_replied", false)

                                        // Parse UTC timestamp and filter strictly to today's local calendar day
                                        var timeStr = ""
                                        val createdDate = parseIsoUtc(createdAt)
                                        if (createdDate != null) {
                                            if (!isSameCalendarDay(createdDate, nowCal)) {
                                                continue
                                            }
                                            val sdfLocal = SimpleDateFormat("h:mm a", Locale.getDefault())
                                            timeStr = sdfLocal.format(createdDate)
                                        }

                                        var replyTimeStr = ""
                                        if (replyCreated.isNotEmpty()) {
                                            val replyDate = parseIsoUtc(replyCreated)
                                            if (replyDate != null) {
                                                val sdfLocal = SimpleDateFormat("h:mm a", Locale.getDefault())
                                                replyTimeStr = sdfLocal.format(replyDate)
                                            }
                                        }

                                        // Ensure image is downloaded locally for widget display
                                        val localImage = File(filesDir, "widget_moment_$id.jpg")
                                        if (!localImage.exists() || localImage.length() == 0L) {
                                            try {
                                                val imgUrl = URL(imageUrl)
                                                imgUrl.openStream().use { input ->
                                                    localImage.outputStream().use { output ->
                                                        input.copyTo(output)
                                                    }
                                                }
                                            } catch (e: Exception) {
                                                Log.e(TAG, "Error downloading widget moment image $id: ${e.message}")
                                            }
                                        }

                                        if (localImage.exists() && localImage.length() > 0L) {
                                            val entry = JSONObject().apply {
                                                put("id", id)
                                                put("image_path", localImage.absolutePath)
                                                put("caption", caption)
                                                put("location", location)
                                                put("time", timeStr)
                                                put("created_at", createdAt)
                                                put("is_reacted", isReacted)
                                                put("reply_text", replyText)
                                                put("reply_time", replyTimeStr)
                                                put("reply_created_at", replyCreated)
                                                put("is_replied", isReplied)
                                                put("is_pending_reply", false)
                                                put("is_sender", false)
                                            }
                                            newMomentsList.put(entry)
                                        }
                                    }

                                    if (newMomentsList.length() > 0) {
                                        val firstObj = newMomentsList.getJSONObject(0)
                                        widgetData.edit()
                                            .putString("widget_moments_json", newMomentsList.toString())
                                            .putInt("widget_current_index", 0)
                                            .putBoolean("widget_has_update", true)
                                            .putString("widget_update_id", firstObj.optNonNullString("id", ""))
                                            .putBoolean("widget_is_reacted", firstObj.optBoolean("is_reacted", false))
                                            .putString("widget_image_path", firstObj.optNonNullString("image_path", ""))
                                            .putString("widget_caption", firstObj.optNonNullString("caption", ""))
                                            .putString("widget_location", firstObj.optNonNullString("location", "MOMENT"))
                                            .putString("widget_time", firstObj.optNonNullString("time", ""))
                                            .commit()
                                        Log.d(TAG, "Refreshed widget data with ${newMomentsList.length()} moments! 🌲")
                                    } else {
                                        clearWidgetPrefs(widgetData)
                                        Log.d(TAG, "No moments left for today after refresh. Cleared widget state! 🧹")
                                    }
                                } else {
                                    // Server returned 0 updates (all deleted or none today) -> prune widget state
                                    clearWidgetPrefs(widgetData)
                                    Log.d(TAG, "Server returned 0 updates on refresh. Cleared widget state! 🧹")
                                }
                            }
                            conn.disconnect()
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to refresh widget in background: ${e.message}")
                        } finally {
                            // Redraw widget regardless of network outcome
                            onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
                        }
                    }
                } else {
                    // Fallback redraw if userId is null
                    onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
                }
            }

            ACTION_REACT_MOMENT -> {
                val updateId = widgetData.getString("widget_update_id", null)
                val isAlreadyReacted = widgetData.getBoolean("widget_is_reacted", false)

                Log.d(TAG, "Reaction intent received for updateId: $updateId, isAlreadyReacted: $isAlreadyReacted")

                // Strict Rule: Once reacted, it CANNOT be unreacted
                if (isAlreadyReacted || updateId.isNullOrEmpty()) {
                    Log.d(TAG, "Moment is already reacted or updateId is missing. Ignoring.")
                    return
                }

                // 1. Immediately mark reacted in local SharedPreferences for zero-latency UI feedback
                val momentsJson = widgetData.getString("widget_moments_json", null)
                var resolvedUpdateId = updateId

                if (!momentsJson.isNullOrEmpty()) {
                    try {
                        val jsonArray = JSONArray(momentsJson)
                        val currentIndex = widgetData.getInt("widget_current_index", 0)
                        if (currentIndex in 0 until jsonArray.length()) {
                            val obj = jsonArray.getJSONObject(currentIndex)
                            obj.put("is_reacted", true)
                            resolvedUpdateId = obj.optString("id", updateId)
                            jsonArray.put(currentIndex, obj)
                            widgetData.edit()
                                .putString("widget_moments_json", jsonArray.toString())
                                .putBoolean("widget_is_reacted", true)
                                .putString("widget_update_id", resolvedUpdateId)
                                .commit()
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating json array reaction: ${e.message}")
                        widgetData.edit().putBoolean("widget_is_reacted", true).commit()
                    }
                } else {
                    widgetData.edit().putBoolean("widget_is_reacted", true).commit()
                }

                // 2. Trigger widget view redraw on all instances immediately with zero latency
                onUpdate(context, appWidgetManager, appWidgetIds, widgetData)

                // 3. Perform asynchronous PATCH to backend worker in background thread
                thread {
                    try {
                        val url = URL("$BACKEND_URL/api/updates/$resolvedUpdateId/react")
                        val conn = url.openConnection() as HttpURLConnection
                        conn.requestMethod = "PATCH"
                        conn.setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                        conn.doOutput = true
                        conn.connectTimeout = 10000
                        conn.readTimeout = 10000

                        val jsonPayload = JSONObject().apply {
                            put("isReacted", true)
                        }

                        OutputStreamWriter(conn.outputStream).use { writer ->
                            writer.write(jsonPayload.toString())
                            writer.flush()
                        }

                        val responseCode = conn.responseCode
                        Log.d(TAG, "Backend reacted response code: $responseCode")
                        conn.disconnect()
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send reaction to backend: ${e.message}", e)
                    }
                }
            }
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        val hasUpdate = widgetData.getBoolean("widget_has_update", false)
        val momentsJson = widgetData.getString("widget_moments_json", null)

        var totalMoments = 1
        var activeIndex = 0
        var imagePath = widgetData.getString("widget_image_path", null)
        var caption = widgetData.getString("widget_caption", null)
        var location = widgetData.getString("widget_location", null)
        var time = widgetData.getString("widget_time", null)
        var isReacted = widgetData.getBoolean("widget_is_reacted", false)
        var currentUpdateId = widgetData.getString("widget_update_id", null)
        var replyText: String? = null
        var replyTime: String? = null
        var isPendingReply = false
        var isSender = false

        if (!momentsJson.isNullOrEmpty()) {
            try {
                val jsonArray = JSONArray(momentsJson)
                totalMoments = jsonArray.length()
                if (totalMoments > 0) {
                    activeIndex = widgetData.getInt("widget_current_index", 0)
                    if (activeIndex < 0 || activeIndex >= totalMoments) {
                        activeIndex = 0
                    }
                    val currentObj = jsonArray.getJSONObject(activeIndex)
                    currentUpdateId = currentObj.optString("id", currentUpdateId)
                    imagePath = currentObj.optString("image_path", imagePath)
                    caption = currentObj.optString("caption", caption)
                    location = currentObj.optString("location", location)
                    time = currentObj.optString("time", time)
                    isReacted = currentObj.optBoolean("is_reacted", false)

                    // Reply fields parsed directly from synced database record
                    replyText = currentObj.optNonNullString("reply_text", "").ifEmpty { null }
                    replyTime = currentObj.optNonNullString("reply_time", "").ifEmpty { null }
                    isPendingReply = currentObj.optBoolean("is_pending_reply", false)
                    isSender = currentObj.optBoolean("is_sender", false)

                    // Write current active id and reaction state to top level
                    widgetData.edit()
                        .putString("widget_update_id", currentUpdateId)
                        .putBoolean("widget_is_reacted", isReacted)
                        .apply()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing momentsJson: ${e.message}")
            }
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.update_me_widget)

            // 1. PendingIntent to launch app and deep-link to Fullscreen Viewer when tapping root area
            val deepLinkUri = android.net.Uri.parse("updateme://moment?id=${currentUpdateId ?: ""}&index=$activeIndex")
            val pendingAppIntent = es.antonborri.home_widget.HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                deepLinkUri
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingAppIntent)

            // 1b. PendingIntent for 4-box Grid Button -> deep-link directly to Today's Moments 4x4 Grid
            val gridDeepLinkUri = android.net.Uri.parse("updateme://today-grid")
            val pendingGridIntent = es.antonborri.home_widget.HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                gridDeepLinkUri
            )
            views.setOnClickPendingIntent(R.id.widget_grid_btn, pendingGridIntent)

            if (hasUpdate && !imagePath.isNullOrEmpty() && File(imagePath).exists()) {
                try {
                    // Memory-safe downsampled decode for RemoteViews (max 512x512)
                    // Prevents Binder IPC TransactionTooLargeException & low-end launcher OOM crashes
                    val rawBitmap = decodeSampledBitmapFromFile(imagePath, 512, 512)
                    if (rawBitmap != null) {
                        // Corner radius: 24dp converted to density pixels so it matches widget_background.xml on any screen
                        val cornerRadiusPx = 24f * context.resources.displayMetrics.density
                        val roundedBitmap = getRoundedCornerBitmap(rawBitmap, cornerRadiusPx)

                        // Ambient background fill (no gaps, clipped to rounded corners)
                        views.setImageViewBitmap(R.id.widget_blur_bg, roundedBitmap)
                        views.setViewVisibility(R.id.widget_blur_bg, View.VISIBLE)

                        // Main photo (preserves full vertical height, clipped to rounded corners)
                        views.setImageViewBitmap(R.id.widget_image, roundedBitmap)
                        views.setViewVisibility(R.id.widget_image, View.VISIBLE)
                        views.setViewVisibility(R.id.widget_empty_state, View.GONE)
                    } else {
                        showEmptyState(views)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error rendering widget bitmap: ${e.message}")
                    showEmptyState(views)
                }
            } else {
                showEmptyState(views)
            }

            // 2. Location Badge
            if (!location.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_location_badge, location.uppercase())
                views.setViewVisibility(R.id.widget_location_badge, View.VISIBLE)
            } else {
                views.setTextViewText(R.id.widget_location_badge, "MOMENT")
                views.setViewVisibility(R.id.widget_location_badge, View.VISIBLE)
            }

            // 3. Navigation Controls (< on left edge, > on right edge) & Refresh Intent
            val refreshIntent = Intent(context, UpdateMeWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_MOMENTS
            }
            val pendingRefresh = PendingIntent.getBroadcast(
                context,
                appWidgetId + 5000,
                refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_refresh_btn, pendingRefresh)

            if (totalMoments > 1) {
                views.setViewVisibility(R.id.widget_counter, View.VISIBLE)
                views.setViewVisibility(R.id.widget_prev_btn, View.VISIBLE)
                views.setViewVisibility(R.id.widget_next_btn, View.VISIBLE)
                views.setTextViewText(R.id.widget_counter, "${activeIndex + 1}/$totalMoments")

                // Prev Intent (Left button)
                val prevIntent = Intent(context, UpdateMeWidgetProvider::class.java).apply {
                    action = ACTION_PREV_MOMENT
                }
                val pendingPrev = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 3000,
                    prevIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_prev_btn, pendingPrev)

                // Next Intent (Right button)
                val nextIntent = Intent(context, UpdateMeWidgetProvider::class.java).apply {
                    action = ACTION_NEXT_MOMENT
                }
                val pendingNext = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 4000,
                    nextIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_next_btn, pendingNext)
            } else {
                views.setViewVisibility(R.id.widget_counter, View.GONE)
                views.setViewVisibility(R.id.widget_prev_btn, View.GONE)
                views.setViewVisibility(R.id.widget_next_btn, View.GONE)
            }

            // 4. Caption, Reply & Time Overlay
            if (!caption.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_caption, caption)
            } else {
                views.setTextViewText(R.id.widget_caption, "")
            }

            // Render partner/user reply with exact database time or sync state
            if (!replyText.isNullOrEmpty()) {
                val authorPrefix = if (isSender) "Partner: " else "You: "
                val timeSuffix = if (isPendingReply) " • Syncing..." else if (!replyTime.isNullOrEmpty()) " • $replyTime" else ""
                views.setTextViewText(R.id.widget_reply_text, "$authorPrefix$replyText$timeSuffix")
                views.setViewVisibility(R.id.widget_reply_text, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_reply_text, View.GONE)
            }

            if (!time.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_time_badge, time)
                views.setViewVisibility(R.id.widget_time_badge, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_time_badge, View.GONE)
            }
            views.setViewVisibility(R.id.widget_bottom_overlay, View.VISIBLE)

            // 5. React Button State & Click Intent
            if (isReacted) {
                views.setImageViewResource(R.id.widget_react_btn, R.drawable.ic_heart_filled)
                val disabledIntent = Intent(context, MainActivity::class.java)
                val pendingDisabled = PendingIntent.getActivity(
                    context,
                    appWidgetId + 2000,
                    disabledIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_react_btn, pendingDisabled)
            } else {
                views.setImageViewResource(R.id.widget_react_btn, R.drawable.ic_heart_outline)
                val reactIntent = Intent(context, UpdateMeWidgetProvider::class.java).apply {
                    action = ACTION_REACT_MOMENT
                }
                val pendingReactIntent = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 1000,
                    reactIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_react_btn, pendingReactIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun JSONObject.optNonNullString(key: String, fallback: String = ""): String {
        return if (isNull(key)) fallback else optString(key, fallback)
    }

    private fun parseIsoUtc(isoStr: String): Date? {
        if (isoStr.length < 19) return null
        return try {
            val sdfUtc = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
            sdfUtc.timeZone = TimeZone.getTimeZone("UTC")
            sdfUtc.parse(isoStr.substring(0, 19))
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing ISO timestamp '$isoStr': ${e.message}")
            null
        }
    }

    private fun isSameCalendarDay(date: Date, nowCal: Calendar): Boolean {
        val targetCal = Calendar.getInstance().apply { time = date }
        return targetCal.get(Calendar.YEAR) == nowCal.get(Calendar.YEAR) &&
            targetCal.get(Calendar.DAY_OF_YEAR) == nowCal.get(Calendar.DAY_OF_YEAR)
    }

    private fun clearWidgetPrefs(widgetData: android.content.SharedPreferences) {
        widgetData.edit()
            .putBoolean("widget_has_update", false)
            .remove("widget_moments_json")
            .remove("widget_image_path")
            .remove("widget_caption")
            .remove("widget_location")
            .remove("widget_time")
            .putInt("widget_current_index", 0)
            .remove("widget_update_id")
            .putBoolean("widget_is_reacted", false)
            .commit()
    }

    private fun showEmptyState(views: RemoteViews) {
        views.setViewVisibility(R.id.widget_image, View.GONE)
        views.setViewVisibility(R.id.widget_blur_bg, View.GONE)
        views.setViewVisibility(R.id.widget_bottom_overlay, View.GONE)
        views.setViewVisibility(R.id.widget_prev_btn, View.GONE)
        views.setViewVisibility(R.id.widget_next_btn, View.GONE)
        views.setViewVisibility(R.id.widget_counter, View.GONE)
        views.setViewVisibility(R.id.widget_empty_state, View.VISIBLE)
    }

    /**
     * Efficiently decodes and downsamples a bitmap from disk using inSampleSize.
     * Prevents loading huge 5MB-10MB bitmaps into launcher heap.
     */
    private fun decodeSampledBitmapFromFile(path: String, reqWidth: Int, reqHeight: Int): Bitmap? {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(path, options)

            // Calculate inSampleSize
            var inSampleSize = 1
            if (options.outHeight > reqHeight || options.outWidth > reqWidth) {
                val halfHeight = options.outHeight / 2
                val halfWidth = options.outWidth / 2
                while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                    inSampleSize *= 2
                }
            }

            options.inSampleSize = inSampleSize
            options.inJustDecodeBounds = false
            // Use RGB_565 for 50% less RAM allocation per pixel
            options.inPreferredConfig = Bitmap.Config.RGB_565

            BitmapFactory.decodeFile(path, options)
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "OutOfMemoryError decoding widget bitmap: ${e.message}")
            null
        } catch (e: Exception) {
            Log.e(TAG, "Exception decoding widget bitmap: ${e.message}")
            null
        }
    }

    /**
     * Clips any Bitmap to smooth rounded corners using hardware Canvas + SRC_IN transfer mode.
     * Guarantees 100% clean rounded corners across all Android OEM devices (Samsung, Xiaomi, TECNO, etc.)
     */
    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadiusPx: Float): Bitmap {
        val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint().apply {
            isAntiAlias = true
            isFilterBitmap = true
            isDither = true
        }
        val rect = Rect(0, 0, bitmap.width, bitmap.height)
        val rectF = RectF(rect)

        canvas.drawRoundRect(rectF, cornerRadiusPx, cornerRadiusPx, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rect, paint)

        return output
    }
}
