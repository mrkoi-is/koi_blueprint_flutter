package com.example.platform_lab
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONObject

class KoiHomeWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
    val snapshot = runCatching { JSONObject(data.getString("koi_snapshot", "{}") ?: "{}") }.getOrNull()
    for (id in ids) {
      val views = RemoteViews(context.packageName, R.layout.koi_home_widget)
      val valid = snapshot?.optInt("version") == 1
      views.setTextViewText(R.id.koi_widget_title, if (valid) snapshot!!.optString("title") else "Workspace")
      views.setTextViewText(R.id.koi_widget_detail, if (valid) "${snapshot!!.optInt("completed")} · ${snapshot.optString("updatedAt")}" else "Open the app to publish a snapshot")
      views.setOnClickPendingIntent(R.id.koi_widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
      manager.updateAppWidget(id, views)
    }
  }
}
