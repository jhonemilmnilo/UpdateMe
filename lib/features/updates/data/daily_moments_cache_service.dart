import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'reply_outbox_service.dart';
import 'update_model.dart';

class DailyMomentsCacheService {
  static final DailyMomentsCacheService _instance =
      DailyMomentsCacheService._internal();
  factory DailyMomentsCacheService() => _instance;
  DailyMomentsCacheService._internal();

  Future<Directory> _getCacheDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${docsDir.path}/daily_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Strictly checks if a moment matches the user's current local calendar day (PH Time)
  /// Moments from yesterday (even if within 24 hours) are strictly excluded
  bool isSameCalendarDay(DateTime dt, DateTime now) {
    final localDt = dt.toLocal();
    final localNow = now.toLocal();
    return localDt.year == localNow.year &&
        localDt.month == localNow.month &&
        localDt.day == localNow.day;
  }

  /// Purges any cached images or metadata files that are not strictly from today's local calendar day
  Future<void> purgeOutdatedMoments() async {
    try {
      final cacheDir = await _getCacheDir();
      final entities = await cacheDir.list().toList();
      final now = DateTime.now();

      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is File) {
          // If it's a metadata file, inspect its creation dates
          if (entity.path.endsWith('.json')) {
            try {
              final content = await entity.readAsString();
              final List list = jsonDecode(content);
              // Filter out items not matching today's local date
              final todayItems = list.where((itemJson) {
                final dt = DateTime.parse(itemJson['created_at']);
                return isSameCalendarDay(dt, now);
              }).toList();

              if (todayItems.isEmpty) {
                await entity.delete();
                deletedCount++;
              } else if (todayItems.length != list.length) {
                await entity.writeAsString(jsonEncode(todayItems));
              }
            } catch (e) {
              await entity.delete();
              deletedCount++;
            }
          } else if (entity.path.endsWith('.jpg')) {
            // For jpg files, check last modified time
            final stat = await entity.stat();
            if (!isSameCalendarDay(stat.modified, now)) {
              await entity.delete();
              deletedCount++;
            }
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint(
            '[DailyMomentsCacheService] Cleaned up $deletedCount outdated cache files from previous days. Storage is 100% lean! 🌿');
      }
    } catch (e) {
      debugPrint('[DailyMomentsCacheService] Error during daily cache purge: $e');
    }
  }

  /// Downloads a remote image URL and saves it locally in daily_cache
  Future<String?> cacheImageLocally({
    required String updateId,
    required String remoteUrl,
  }) async {
    try {
      if (!remoteUrl.startsWith('http')) {
        // Already a local path
        return remoteUrl;
      }

      final cacheDir = await _getCacheDir();
      final localFilePath = '${cacheDir.path}/img_$updateId.jpg';
      final file = File(localFilePath);

      // Return immediately if already cached
      if (await file.exists() && await file.length() > 0) {
        return localFilePath;
      }

      final response = await http.get(Uri.parse(remoteUrl));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return localFilePath;
      }
      return null;
    } catch (e) {
      debugPrint(
          '[DailyMomentsCacheService] Could not cache image for $updateId: $e');
      return null;
    }
  }

  /// Saves today's moments to the local cache, mirroring remote images to local files
  Future<List<UpdateModel>> cacheTodayMoments({
    required String type, // 'received' or 'sent'
    required List<UpdateModel> moments,
  }) async {
    try {
      final cacheDir = await _getCacheDir();
      final now = DateTime.now();

      // Read existing cached items to merge without dropping
      final existingCached = await getTodayCachedMoments(type: type);
      final Map<String, UpdateModel> existingMap = {
        for (final m in existingCached) m.id: m,
      };

      // Only preserve moments that match today's exact local calendar day
      final todayMoments = moments
          .where((m) => isSameCalendarDay(m.createdAt, now))
          .toList();

      final Set<String> serverMomentIds = todayMoments.map((m) => m.id).toSet();
      final Map<String, UpdateModel> mergedMap = {};

      // 1. Download images in parallel so all moments are cached fast without blocking
      await Future.wait(
        todayMoments.map((m) async {
          final existing = existingMap[m.id];
          String effectiveImageUrl = existing?.imageUrl ?? m.imageUrl;

          // If cached local path no longer exists on disk, fall back to remote URL for re-download
          if (!effectiveImageUrl.startsWith('http') && !await File(effectiveImageUrl).exists()) {
            effectiveImageUrl = m.imageUrl;
          }

          if (effectiveImageUrl.startsWith('http')) {
            final cachedPath = await cacheImageLocally(
              updateId: m.id,
              remoteUrl: m.imageUrl,
            );
            if (cachedPath != null) {
              effectiveImageUrl = cachedPath;
            }
          }

          // Protect local pending reply: do NOT overwrite with server's null reply if unsynced
          final preservePendingReply = existing != null &&
              existing.isPendingReply &&
              (m.replyText == null || m.replyText!.trim().isEmpty);

          mergedMap[m.id] = m.copyWith(
            imageUrl: effectiveImageUrl,
            replyText: preservePendingReply ? existing.replyText : m.replyText,
            replyCreatedAt: preservePendingReply ? existing.replyCreatedAt : m.replyCreatedAt,
            isReplied: preservePendingReply ? true : m.isReplied,
            isPendingReply: preservePendingReply ? true : m.isPendingReply,
          );
        }),
      );

      // 2. Preserve only pending local moments that have NOT yet reached the server;
      //    prune server-deleted moments and clean up their orphaned image files & stale reply outbox entries
      int prunedCount = 0;
      for (final local in existingCached) {
        if (!serverMomentIds.contains(local.id)) {
          if (local.isPending) {
            mergedMap[local.id] = local;
          } else {
            prunedCount++;
            // Clean up orphaned cached image file if inside daily_cache
            final orphanImage = File('${cacheDir.path}/img_${local.id}.jpg');
            if (await orphanImage.exists()) {
              await orphanImage.delete();
            }
            // Remove any stale pending reply targeting this server-deleted moment
            if (type == 'received') {
              await ReplyOutboxService().removeItem(local.id);
            }
          }
        }
      }

      if (prunedCount > 0) {
        debugPrint(
            '[DailyMomentsCacheService] Pruned $prunedCount server-deleted moment(s) from "$type" cache! 🧹');
      }

      // Filter mergedMap to strictly retain only today's local calendar moments
      final localizedMoments = mergedMap.values
          .where((m) => isSameCalendarDay(m.createdAt, now))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Save localized metadata JSON
      final metaFile = File('${cacheDir.path}/cache_$type.json');
      final jsonList = localizedMoments.map((m) => m.toJson()).toList();
      await metaFile.writeAsString(jsonEncode(jsonList));

      debugPrint(
          '[DailyMomentsCacheService] Cached ${localizedMoments.length} moments for "$type" 📦');
      return localizedMoments;
    } catch (e) {
      debugPrint('[DailyMomentsCacheService] Error caching moments for $type: $e');
      return moments;
    }
  }

  /// Loads today's cached moments from disk immediately (0ms network delay, 100% offline-ready)
  Future<List<UpdateModel>> getTodayCachedMoments({
    required String type, // 'received' or 'sent'
  }) async {
    try {
      final cacheDir = await _getCacheDir();
      final metaFile = File('${cacheDir.path}/cache_$type.json');

      if (!await metaFile.exists()) {
        return [];
      }

      final content = await metaFile.readAsString();
      final List list = jsonDecode(content);
      final now = DateTime.now();

      final List<UpdateModel> validToday = [];
      for (final item in list) {
        final model = UpdateModel.fromJson(item as Map<String, dynamic>);
        if (isSameCalendarDay(model.createdAt, now)) {
          validToday.add(model);
        }
      }

      // Sort descending by createdAt (newest/most recent first!)
      validToday.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return validToday;
    } catch (e) {
      debugPrint(
          '[DailyMomentsCacheService] Error reading cached moments for $type: $e');
      return [];
    }
  }

  /// Updates the reaction state of a specific moment in local cache immediately
  Future<void> updateMomentReaction({
    required String type, // 'received' or 'sent'
    required String updateId,
    required bool isReacted,
  }) async {
    try {
      final cacheDir = await _getCacheDir();
      final metaFile = File('${cacheDir.path}/cache_$type.json');
      if (!await metaFile.exists()) return;

      final content = await metaFile.readAsString();
      final List list = jsonDecode(content);
      bool modified = false;

      final updatedList = list.map((item) {
        if (item is Map<String, dynamic> && item['id'] == updateId) {
          modified = true;
          return {
            ...item,
            'is_reacted': isReacted,
          };
        }
        return item;
      }).toList();

      if (modified) {
        await metaFile.writeAsString(jsonEncode(updatedList));
        debugPrint(
            '[DailyMomentsCacheService] Locally updated reaction for moment $updateId in cache_$type.json! ❤️');
      }
    } catch (e) {
      debugPrint('[DailyMomentsCacheService] Error updating reaction in cache: $e');
    }
  }

  /// Updates the reply state of a specific moment in local cache immediately (offline-first)
  Future<void> updateMomentReply({
    required String type, // 'received' or 'sent'
    required String updateId,
    required String replyText,
    required DateTime replyCreatedAt,
    bool isPendingReply = false,
  }) async {
    try {
      final cacheDir = await _getCacheDir();
      final metaFile = File('${cacheDir.path}/cache_$type.json');
      if (!await metaFile.exists()) return;

      final content = await metaFile.readAsString();
      final List list = jsonDecode(content);
      bool modified = false;

      final updatedList = list.map((item) {
        if (item is Map<String, dynamic> && item['id'] == updateId) {
          modified = true;
          return {
            ...item,
            'reply_text': replyText,
            'reply_created_at': replyCreatedAt.toUtc().toIso8601String(),
            'is_replied': true,
            'is_pending_reply': isPendingReply,
          };
        }
        return item;
      }).toList();

      if (modified) {
        await metaFile.writeAsString(jsonEncode(updatedList));
        debugPrint(
            '[DailyMomentsCacheService] Locally updated reply for moment $updateId (isPending=$isPendingReply) in cache_$type.json! 💬');
      }
    } catch (e) {
      debugPrint('[DailyMomentsCacheService] Error updating reply in cache: $e');
    }
  }
}
