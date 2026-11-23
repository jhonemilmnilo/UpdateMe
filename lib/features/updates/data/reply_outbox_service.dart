import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class ReplyOutboxItem {
  final String updateId;
  final String replyText;
  final DateTime replyCreatedAt;
  final String status; // 'pending' | 'syncing' | 'synced' | 'failed'
  final int retryCount;

  const ReplyOutboxItem({
    required this.updateId,
    required this.replyText,
    required this.replyCreatedAt,
    this.status = 'pending',
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'updateId': updateId,
        'replyText': replyText,
        'replyCreatedAt': replyCreatedAt.toUtc().toIso8601String(),
        'status': status,
        'retryCount': retryCount,
      };

  factory ReplyOutboxItem.fromJson(Map<String, dynamic> json) => ReplyOutboxItem(
        updateId: json['updateId'] as String,
        replyText: json['replyText'] as String,
        replyCreatedAt: DateTime.parse(json['replyCreatedAt'] as String).toLocal(),
        status: json['status'] as String? ?? 'pending',
        retryCount: json['retryCount'] as int? ?? 0,
      );

  ReplyOutboxItem copyWith({
    String? status,
    int? retryCount,
  }) =>
      ReplyOutboxItem(
        updateId: updateId,
        replyText: replyText,
        replyCreatedAt: replyCreatedAt,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
      );
}

class ReplyOutboxService {
  static final ReplyOutboxService _instance = ReplyOutboxService._internal();
  factory ReplyOutboxService() => _instance;
  ReplyOutboxService._internal();

  Future<Directory> _getReplyOutboxDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${docsDir.path}/outbox_replies');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Atomically enqueues a pending reply to disk
  Future<ReplyOutboxItem> enqueue({
    required String updateId,
    required String replyText,
    required DateTime replyCreatedAt,
  }) async {
    final dir = await _getReplyOutboxDir();
    final item = ReplyOutboxItem(
      updateId: updateId,
      replyText: replyText,
      replyCreatedAt: replyCreatedAt,
      status: 'pending',
      retryCount: 0,
    );

    final filePath = '${dir.path}/reply_$updateId.json';
    await File(filePath).writeAsString(jsonEncode(item.toJson()));
    debugPrint('[ReplyOutbox] Enqueued offline reply for update $updateId 💬📁');
    return item;
  }

  /// Lists all pending replies from disk (FIFO)
  Future<List<ReplyOutboxItem>> getPendingReplies() async {
    try {
      final dir = await _getReplyOutboxDir();
      final entities = await dir.list().toList();
      final List<ReplyOutboxItem> items = [];

      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json') && entity.path.contains('reply_')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            items.add(ReplyOutboxItem.fromJson(json));
          } catch (e) {
            debugPrint('[ReplyOutbox] Error reading reply outbox file: $e');
          }
        }
      }

      items.sort((a, b) => a.replyCreatedAt.compareTo(b.replyCreatedAt));
      return items;
    } catch (e) {
      debugPrint('[ReplyOutbox] Error listing pending replies: $e');
      return [];
    }
  }

  /// Checks if a specific update has a pending reply in queue
  Future<bool> hasPendingReply(String updateId) async {
    final dir = await _getReplyOutboxDir();
    final file = File('${dir.path}/reply_$updateId.json');
    return file.exists();
  }

  /// Updates status and retry count of a reply outbox item
  Future<void> updateItem(ReplyOutboxItem item) async {
    try {
      final dir = await _getReplyOutboxDir();
      final file = File('${dir.path}/reply_${item.updateId}.json');
      if (await file.exists()) {
        await file.writeAsString(jsonEncode(item.toJson()));
      }
    } catch (e) {
      debugPrint('[ReplyOutbox] Error updating item ${item.updateId}: $e');
    }
  }

  /// Removes synced reply file from disk
  Future<void> removeItem(String updateId) async {
    try {
      final dir = await _getReplyOutboxDir();
      final file = File('${dir.path}/reply_$updateId.json');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[ReplyOutbox] Removed synced reply for update $updateId ✨');
      }
    } catch (e) {
      debugPrint('[ReplyOutbox] Error removing reply item $updateId: $e');
    }
  }
}
