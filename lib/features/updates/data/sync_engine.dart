import 'dart:io';
import 'package:flutter/foundation.dart';
import 'outbox_service.dart';
import 'update_service.dart';

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

  /// Drains the outbox FIFO queue
  Future<void> processQueue({VoidCallback? onSyncComplete}) async {
    if (_isSyncing) {
      debugPrint('[SyncEngine] Already syncing. Skipping duplicate trigger. 🚦');
      return;
    }

    _isSyncing = true;
    try {
      final items = await _outbox.getPendingItems();
      pendingItemsNotifier.value = items;

      if (items.isEmpty) {
        debugPrint('[SyncEngine] Outbox is empty. Nothing to sync. ✨');
        _isSyncing = false;
        return;
      }

      debugPrint('[SyncEngine] Found ${items.length} pending offline items. Starting sync... 🚀');

      for (final item in items) {
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
          await _updateService.sendUpdate(
            id: item.id,
            createdAt: item.createdAt,
            senderId: item.senderId,
            imageUrl: publicUrl,
            caption: item.caption,
            locationName: item.locationName,
            latitude: item.latitude,
            longitude: item.longitude,
          );

          // 4. Mark as synced locally so it will NEVER be uploaded again
          await _outbox.updateItem(item.copyWith(
            status: 'synced',
            isSynced: true,
          ));

          // 5. On success: purge from outbox (removes both JSON and cached jpg)
          await _outbox.removeItem(item);
          debugPrint('[SyncEngine] Successfully synced item ${item.id} with isSynced=true! 🎉');
          await refreshPendingItems();

          onSyncComplete?.call();
        } catch (e) {
          debugPrint('[SyncEngine] Failed to sync item ${item.id}: $e');
          // Increment retry count & mark failed
          await _outbox.updateItem(item.copyWith(
            status: 'failed',
            retryCount: item.retryCount + 1,
          ));
          await refreshPendingItems();
          // Stop queue processing on network failure to avoid hammering
          break;
        }
      }
    } finally {
      _isSyncing = false;
      await refreshPendingItems();
    }
  }
}
