import 'dart:io';
import 'package:flutter/foundation.dart';
import 'daily_moments_cache_service.dart';
import 'outbox_service.dart';
import 'update_service.dart';

class SyncResult {
  final int syncedCount;
  final int failedCount;
  final bool isOffline;

  const SyncResult({
    this.syncedCount = 0,
    this.failedCount = 0,
    this.isOffline = false,
  });
}

class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final OutboxService _outbox = OutboxService();
  final UpdateService _updateService = UpdateService();

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  /// Notifier for real-time UI updates (e.g., pending moments list)
  final ValueNotifier<List<OutboxItem>> pendingItemsNotifier =
      ValueNotifier<List<OutboxItem>>([]);

  /// Refreshes the pending list from disk
  Future<void> refreshPendingItems() async {
    final items = await _outbox.getPendingItems();
    pendingItemsNotifier.value = items;
  }

  /// Drains the outbox FIFO queue sequentially upon user refresh
  Future<SyncResult> processQueue({VoidCallback? onSyncComplete}) async {
    if (_isSyncing) {
      debugPrint('[SyncEngine] Already syncing. Skipping duplicate trigger. 🚦');
      return const SyncResult();
    }

    _isSyncing = true;
    int syncedCount = 0;
    int failedCount = 0;
    bool isOffline = false;

    try {
      final items = await _outbox.getPendingItems();
      pendingItemsNotifier.value = items;

      if (items.isEmpty) {
        debugPrint('[SyncEngine] Outbox is empty. Nothing to sync. ✨');
        _isSyncing = false;
        return const SyncResult();
      }

      debugPrint('[SyncEngine] Found ${items.length} pending offline items. Syncing on-demand... 🚀');

      for (final item in items) {
        // Guard against legacy non-UUID items from previous iterations
        final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(item.id);
        if (!isUuid) {
          debugPrint('[SyncEngine] Found legacy non-UUID item ${item.id}. Purging to unblock queue.');
          await _outbox.removeItem(item);
          continue;
        }

        final imageFile = File(item.localImagePath);
        if (!await imageFile.exists()) {
          debugPrint('[SyncEngine] Image file missing for item ${item.id}. Purging outbox record.');
          await _outbox.removeItem(item);
          continue;
        }

        try {
          // 1. Mark status as syncing
          await _outbox.updateItem(item.copyWith(status: 'syncing'));
          await refreshPendingItems();

          // 2. Upload image to Supabase Storage
          debugPrint('[SyncEngine] Uploading image for item ${item.id} (captured: ${item.createdAt})...');
          final publicUrl = await _updateService.uploadUpdatePhoto(
            imageFile: imageFile,
            userId: item.senderId,
          );

          // 3. Post to backend with client-generated id and original createdAt
          debugPrint('[SyncEngine] Posting update to Cloudflare backend with original createdAt ${item.createdAt.toIso8601String()}...');
          final createdUpdate = await _updateService.sendUpdate(
            id: item.id,
            createdAt: item.createdAt,
            senderId: item.senderId,
            imageUrl: publicUrl,
            caption: item.caption,
            locationName: item.locationName,
            latitude: item.latitude,
            longitude: item.longitude,
          );

          // 4. Save directly into DailyMomentsCacheService so it persists offline immediately everywhere
          final cacheService = DailyMomentsCacheService();
          final existingSent = await cacheService.getTodayCachedMoments(type: 'sent');
          final updatedSentList = [
            ...existingSent.where((m) => m.id != item.id),
            createdUpdate.copyWith(imageUrl: item.localImagePath), // Preserve local image path for instant 0ms offline display
          ];
          await cacheService.cacheTodayMoments(type: 'sent', moments: updatedSentList);

          // 5. Mark as synced locally so it will NEVER be uploaded again
          await _outbox.updateItem(item.copyWith(
            status: 'synced',
            isSynced: true,
          ));

          // 6. On success: purge from outbox (removes outbox JSON metadata)
          await _outbox.removeItem(item);
          debugPrint('[SyncEngine] Successfully synced item ${item.id} with isSynced=true and cached to daily_cache! 🎉');
          syncedCount++;
          await refreshPendingItems();

          onSyncComplete?.call();
        } catch (e) {
          debugPrint('[SyncEngine] Network failure syncing item ${item.id}: $e');
          failedCount++;
          isOffline = true;
          // Mark failed without hammering or continuous retrying
          await _outbox.updateItem(item.copyWith(
            status: 'failed',
            retryCount: item.retryCount + 1,
          ));
          await refreshPendingItems();
          // Stop queue processing on network failure to avoid CPU & network throttling
          break;
        }
      }

      return SyncResult(
        syncedCount: syncedCount,
        failedCount: failedCount,
        isOffline: isOffline,
      );
    } finally {
      _isSyncing = false;
      await refreshPendingItems();
    }
  }
}
