package com.example.update_me

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject

class UpdateMeWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REACT_MOMENT = "com.example.update_me.ACTION_REACT_MOMENT"
        const val ACTION_PREV_MOMENT = "com.example.update_me.ACTION_PREV_MOMENT"
        const val ACTION_NEXT_MOMENT = "com.example.update_me.ACTION_NEXT_MOMENT"
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
                            var currentIndex = widgetData.getInt("widget_current_index", jsonArray.length() - 1)
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
                            var currentIndex = widgetData.getInt("widget_current_index", jsonArray.length() - 1)
                            currentIndex = if (currentIndex >= jsonArray.length() - 1) 0 else currentIndex + 1
                            widgetData.edit().putInt("widget_current_index", currentIndex).apply()
                            onUpdate(context, appWidgetManager, appWidgetIds, widgetData)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in NEXT_MOMENT: ${e.message}")
                    }
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
                        val currentIndex = widgetData.getInt("widget_current_index", jsonArray.length() - 1)
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
                        val url = URL("$BACKEND_URL/api/updates/$updateId/react")
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

        if (!momentsJson.isNullOrEmpty()) {
            try {
                val jsonArray = JSONArray(momentsJson)
                totalMoments = jsonArray.length()
                if (totalMoments > 0) {
                    activeIndex = widgetData.getInt("widget_current_index", totalMoments - 1)
                    if (activeIndex < 0 || activeIndex >= totalMoments) {
                        activeIndex = totalMoments - 1
                    }
                    val currentObj = jsonArray.getJSONObject(activeIndex)
                    currentUpdateId = currentObj.optString("id", currentUpdateId)
                    imagePath = currentObj.optString("image_path", imagePath)
                    caption = currentObj.optString("caption", caption)
                    location = currentObj.optString("location", location)
                    time = currentObj.optString("time", time)
                    isReacted = currentObj.optBoolean("is_reacted", false)

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

            if (hasUpdate && !imagePath.isNullOrEmpty() && File(imagePath).exists()) {
                try {
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap != null) {
                        // Ambient background fill (no gaps)
                        views.setImageViewBitmap(R.id.widget_blur_bg, bitmap)
                        views.setViewVisibility(R.id.widget_blur_bg, View.VISIBLE)

                        // Main photo (preserves full vertical height)
                        views.setImageViewBitmap(R.id.widget_image, bitmap)
                        views.setViewVisibility(R.id.widget_image, View.VISIBLE)
                        views.setViewVisibility(R.id.widget_empty_state, View.GONE)
                    } else {
                        showEmptyState(views)
                    }
                } catch (e: Exception) {
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

            // 3. Navigation Controls (< on left edge, > on right edge)
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

            // 4. Caption & Time Overlay
            if (!caption.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_caption, caption)
            } else {
                views.setTextViewText(R.id.widget_caption, "")
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

    private fun showEmptyState(views: RemoteViews) {
        views.setViewVisibility(R.id.widget_image, View.GONE)
        views.setViewVisibility(R.id.widget_blur_bg, View.GONE)
        views.setViewVisibility(R.id.widget_bottom_overlay, View.GONE)
        views.setViewVisibility(R.id.widget_prev_btn, View.GONE)
        views.setViewVisibility(R.id.widget_next_btn, View.GONE)
        views.setViewVisibility(R.id.widget_counter, View.GONE)
        views.setViewVisibility(R.id.widget_empty_state, View.VISIBLE)
    }
}
