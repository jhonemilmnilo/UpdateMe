import 'dart:convert';
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

  /// Syncs all received moments for today to the Android Home Screen Widget
  Future<void> syncMomentsListToWidget({
    required List<UpdateModel> moments,
  }) async {
    if (moments.isEmpty) {
      await clearWidget();
      return;
    }

    try {
      debugPrint('[WidgetSyncService] Syncing ${moments.length} moments to home screen widget...');

      final docsDir = await getApplicationDocumentsDirectory();
      final List<Map<String, dynamic>> cachedList = [];

      for (int i = 0; i < moments.length; i++) {
        final moment = moments[i];
        final localImagePath = '${docsDir.path}/widget_moment_${moment.id}.jpg';
        final file = File(localImagePath);

        try {
          // If image is already cached locally, reuse it without redownloading to eliminate latency & flickering
          if (!file.existsSync() || file.lengthSync() == 0) {
            final response = await http.get(Uri.parse(moment.imageUrl));
            if (response.statusCode == 200) {
              await file.writeAsBytes(response.bodyBytes);
            }
          }

          if (file.existsSync() && file.lengthSync() > 0) {
            final phTimeString = DateFormat('h:mm a').format(moment.createdAt.toLocal());

            cachedList.add({
              'id': moment.id,
              'image_path': localImagePath,
              'caption': moment.caption ?? '',
              'location': moment.locationName ?? 'MOMENT',
              'time': phTimeString,
              'is_reacted': moment.isReacted,
            });
          }
        } catch (e) {
          debugPrint('[WidgetSyncService] Failed to cache moment $i: $e');
        }
      }

      if (cachedList.isEmpty) return;

      final jsonString = jsonEncode(cachedList);

      // Preserve active viewing index if valid, otherwise point to latest
      final existingIndex = await HomeWidget.getWidgetData<int>('widget_current_index');
      int targetIndex = cachedList.length - 1;
      if (existingIndex != null && existingIndex >= 0 && existingIndex < cachedList.length) {
        targetIndex = existingIndex;
      }

      // Save moments list and index
      await HomeWidget.saveWidgetData<String>('widget_moments_json', jsonString);
      await HomeWidget.saveWidgetData<int>('widget_current_index', targetIndex);
      await HomeWidget.saveWidgetData<bool>('widget_has_update', true);

      // Also set the currently displayed moment data for fallback
      final activeMoment = cachedList[targetIndex];
      await HomeWidget.saveWidgetData<String>('widget_update_id', activeMoment['id'] as String);
      await HomeWidget.saveWidgetData<bool>('widget_is_reacted', activeMoment['is_reacted'] as bool);
      await HomeWidget.saveWidgetData<String>('widget_image_path', activeMoment['image_path'] as String);
      await HomeWidget.saveWidgetData<String>('widget_caption', activeMoment['caption'] as String);
      await HomeWidget.saveWidgetData<String>('widget_location', activeMoment['location'] as String);
      await HomeWidget.saveWidgetData<String>('widget_time', activeMoment['time'] as String);

      await HomeWidget.updateWidget(name: _androidWidgetName);

      debugPrint('[WidgetSyncService] Home screen widget synced with ${cachedList.length} moments at index $targetIndex! 🌲');
    } catch (e) {
      debugPrint('[WidgetSyncService] Error syncing moments list: $e');
    }
  }

  /// Appends a new incoming moment to existing widget moments carousel without overwriting
  Future<void> appendMomentToWidget({required UpdateModel moment}) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final localImagePath = '${docsDir.path}/widget_moment_${moment.id}.jpg';

      final response = await http.get(Uri.parse(moment.imageUrl));
      if (response.statusCode != 200) {
        debugPrint('[WidgetSyncService] Failed to download moment image for append: ${response.statusCode}');
        return;
      }

      final file = File(localImagePath);
      await file.writeAsBytes(response.bodyBytes);

      final phTimeString = DateFormat('h:mm a').format(moment.createdAt.toLocal());
      final newEntry = {
        'id': moment.id,
        'image_path': localImagePath,
        'caption': moment.caption ?? '',
        'location': moment.locationName ?? 'MOMENT',
        'time': phTimeString,
        'is_reacted': moment.isReacted,
      };

      // Retrieve existing cached carousel
      final cachedJson = await HomeWidget.getWidgetData<String>('widget_moments_json');
      List<dynamic> list = [];
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          list = jsonDecode(cachedJson) as List<dynamic>;
        } catch (_) {}
      }

      // Check if moment already exists in list
      final existingIndex = list.indexWhere((m) => m is Map && m['id'] == moment.id);
      if (existingIndex >= 0) {
        list[existingIndex] = newEntry;
      } else {
        list.add(newEntry);
      }

      final jsonString = jsonEncode(list);

      await HomeWidget.saveWidgetData<String>('widget_moments_json', jsonString);
      await HomeWidget.saveWidgetData<int>('widget_current_index', list.length - 1);
      await HomeWidget.saveWidgetData<bool>('widget_has_update', true);

      // Set fallback latest
      await HomeWidget.saveWidgetData<String>('widget_update_id', moment.id);
      await HomeWidget.saveWidgetData<bool>('widget_is_reacted', moment.isReacted);
      await HomeWidget.saveWidgetData<String>('widget_image_path', localImagePath);
      await HomeWidget.saveWidgetData<String>('widget_caption', moment.caption ?? '');
      await HomeWidget.saveWidgetData<String>('widget_location', moment.locationName ?? 'MOMENT');
      await HomeWidget.saveWidgetData<String>('widget_time', phTimeString);

      await HomeWidget.updateWidget(name: _androidWidgetName);

      debugPrint('[WidgetSyncService] Appended moment ${moment.id} to widget! Total moments: ${list.length} 🌲');
    } catch (e) {
      debugPrint('[WidgetSyncService] Error appending moment to widget: $e');
    }
  }

  /// Single moment sync (routes to appendMomentToWidget so carousel is preserved)
  Future<void> syncLatestMomentToWidget({required UpdateModel moment}) async {
    await appendMomentToWidget(moment: moment);
  }

  /// Clears widget state or displays default empty state
  Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<bool>('widget_has_update', false);
      await HomeWidget.saveWidgetData<String?>('widget_moments_json', null);
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
