import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'update_model.dart';

class WidgetSyncService {
  static final WidgetSyncService _instance = WidgetSyncService._internal();
  factory WidgetSyncService() => _instance;
  WidgetSyncService._internal();

  static const String _androidWidgetName = 'UpdateMeWidgetProvider';

  /// Syncs the latest partner moment to the Android Home Screen Widget
  Future<void> syncLatestMomentToWidget({required UpdateModel moment}) async {
    try {
      debugPrint('[WidgetSyncService] Syncing moment (${moment.id}) to home screen widget...');

      // 1. Download image from Supabase storage and save locally to cache
      final tempDir = await getTemporaryDirectory();
      final localImagePath = '${tempDir.path}/widget_moment.jpg';

      final response = await http.get(Uri.parse(moment.imageUrl));
      if (response.statusCode == 200) {
        final file = File(localImagePath);
        await file.writeAsBytes(response.bodyBytes);
      } else {
        debugPrint('[WidgetSyncService] Failed to download image for widget: ${response.statusCode}');
        return;
      }

      // 2. Format Philippine Time (PST: UTC+8)
      final phTimeString = DateFormat('h:mm a').format(moment.createdAt.toLocal());

      await HomeWidget.saveWidgetData<String>('widget_update_id', moment.id);
      await HomeWidget.saveWidgetData<bool>('widget_is_reacted', moment.isReacted);
      await HomeWidget.saveWidgetData<String>('widget_image_path', localImagePath);
      await HomeWidget.saveWidgetData<String>('widget_caption', moment.caption ?? '');
      await HomeWidget.saveWidgetData<String>('widget_location', moment.locationName ?? 'MOMENT');
      await HomeWidget.saveWidgetData<String>('widget_time', phTimeString);
      await HomeWidget.saveWidgetData<bool>('widget_has_update', true);

      // 4. Request Android AppWidgetManager to update the widget
      await HomeWidget.updateWidget(
        name: _androidWidgetName,
      );

      debugPrint('[WidgetSyncService] Home screen widget updated successfully! 🌲');
    } catch (e) {
      debugPrint('[WidgetSyncService] Error updating home screen widget: $e');
    }
  }

  /// Clears widget state or displays default empty state
  Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<bool>('widget_has_update', false);
      await HomeWidget.saveWidgetData<String?>('widget_image_path', null);
      await HomeWidget.saveWidgetData<String?>('widget_caption', null);
      await HomeWidget.saveWidgetData<String?>('widget_location', null);
      await HomeWidget.saveWidgetData<String?>('widget_time', null);

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
      );
    } catch (e) {
      debugPrint('[WidgetSyncService] Error clearing widget: $e');
    }
  }
}
