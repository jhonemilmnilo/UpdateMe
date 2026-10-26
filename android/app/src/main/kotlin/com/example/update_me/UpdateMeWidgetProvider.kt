package com.example.update_me

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class UpdateMeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.update_me_widget)

            // 1. PendingIntent to launch app on widget tap
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            // 2. Read metadata stored via HomeWidget in Flutter
            val imagePath = widgetData.getString("widget_image_path", null)
            val caption = widgetData.getString("widget_caption", null)
            val location = widgetData.getString("widget_location", null)
            val time = widgetData.getString("widget_time", null)
            val hasUpdate = widgetData.getBoolean("widget_has_update", false)

            if (hasUpdate && !imagePath.isNullOrEmpty() && File(imagePath).exists()) {
                try {
                    // Safe local bitmap decoding
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
                views.setViewVisibility(R.id.widget_bottom_overlay, View.GONE)
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
