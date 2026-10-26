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
import org.json.JSONObject

class UpdateMeWidgetProvider : HomeWidgetProvider() {

    companion object {
        const val ACTION_REACT_MOMENT = "com.example.update_me.ACTION_REACT_MOMENT"
        const val TAG = "UpdateMeWidgetProvider"
        const val BACKEND_URL = "https://update-me-backend.nilojhonemil1.workers.dev"
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)

        if (intent.action == ACTION_REACT_MOMENT) {
            val widgetData = HomeWidgetPlugin.getData(context)
            val updateId = widgetData.getString("widget_update_id", null)
            val isAlreadyReacted = widgetData.getBoolean("widget_is_reacted", false)

            Log.d(TAG, "Reaction intent received for updateId: $updateId, isAlreadyReacted: $isAlreadyReacted")

            // Strict Rule: Once reacted, it CANNOT be unreacted
            if (isAlreadyReacted || updateId.isNullOrEmpty()) {
                Log.d(TAG, "Moment is already reacted or updateId is missing. Ignoring.")
                return
            }

            // 1. Immediately mark reacted in local SharedPreferences for zero-latency UI feedback
            widgetData.edit().putBoolean("widget_is_reacted", true).apply()

            // 2. Trigger widget view redraw on all instances
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, UpdateMeWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
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

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.update_me_widget)

            // 1. PendingIntent to launch app when tapping root area
            val appIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingAppIntent = PendingIntent.getActivity(
                context,
                0,
                appIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingAppIntent)

            // 2. Read metadata stored via HomeWidget in Flutter
            val imagePath = widgetData.getString("widget_image_path", null)
            val caption = widgetData.getString("widget_caption", null)
            val location = widgetData.getString("widget_location", null)
            val time = widgetData.getString("widget_time", null)
            val hasUpdate = widgetData.getBoolean("widget_has_update", false)
            val isReacted = widgetData.getBoolean("widget_is_reacted", false)

            if (hasUpdate && !imagePath.isNullOrEmpty() && File(imagePath).exists()) {
                try {
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap != null) {
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

            // 3. Location Badge
            if (!location.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_location_badge, location.uppercase())
                views.setViewVisibility(R.id.widget_location_badge, View.VISIBLE)
            } else {
                views.setTextViewText(R.id.widget_location_badge, "MOMENT")
                views.setViewVisibility(R.id.widget_location_badge, View.VISIBLE)
            }

            // 4. Time Badge
            if (!time.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_time_badge, time)
                views.setViewVisibility(R.id.widget_time_badge, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.widget_time_badge, View.GONE)
            }

            // 5. Caption Overlay
            if (!caption.isNullOrEmpty()) {
                views.setTextViewText(R.id.widget_caption, caption)
                views.setViewVisibility(R.id.widget_bottom_overlay, View.VISIBLE)
            } else {
                views.setTextViewText(R.id.widget_caption, "")
                views.setViewVisibility(R.id.widget_bottom_overlay, View.VISIBLE)
            }

            // 6. React Button State & Click Intent
            if (isReacted) {
                views.setImageViewResource(R.id.widget_react_btn, R.drawable.ic_heart_filled)
                // Cannot be unreacted once true: pass empty/null pending intent or non-react intent
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
        views.setViewVisibility(R.id.widget_bottom_overlay, View.GONE)
        views.setViewVisibility(R.id.widget_empty_state, View.VISIBLE)
    }
}
