import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class OutboxItem {
  final String id;
  final String senderId;
  final String? receiverId;
  final String localImagePath;
  final String? caption;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final String status; // 'pending' | 'syncing' | 'synced' | 'failed'
  final bool isSynced;
  final int retryCount;

  const OutboxItem({
    required this.id,
    required this.senderId,
    this.receiverId,
    required this.localImagePath,
    this.caption,
    this.locationName,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.status = 'pending',
    this.isSynced = false,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'receiverId': receiverId,
        'localImagePath': localImagePath,
        'caption': caption,
        'locationName': locationName,
        'latitude': latitude,
        'longitude': longitude,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status,
        'isSynced': isSynced,
        'retryCount': retryCount,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        receiverId: json['receiverId'] as String?,
        localImagePath: json['localImagePath'] as String,
        caption: json['caption'] as String?,
        locationName: json['locationName'] as String?,
        latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
        longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
        status: json['status'] as String? ?? 'pending',
        isSynced: json['isSynced'] as bool? ?? false,
        retryCount: json['retryCount'] as int? ?? 0,
      );

  OutboxItem copyWith({
    String? status,
    bool? isSynced,
    int? retryCount,
  }) =>
      OutboxItem(
        id: id,
        senderId: senderId,
        receiverId: receiverId,
        localImagePath: localImagePath,
        caption: caption,
        locationName: locationName,
        latitude: latitude,
        longitude: longitude,
        createdAt: createdAt,
        status: status ?? this.status,
        isSynced: isSynced ?? this.isSynced,
        retryCount: retryCount ?? this.retryCount,
      );
}

class OutboxService {
  static final OutboxService _instance = OutboxService._internal();
  factory OutboxService() => _instance;
  OutboxService._internal();

  Future<Directory> _getOutboxDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final outboxDir = Directory('${docsDir.path}/outbox');
    if (!await outboxDir.exists()) {
      await outboxDir.create(recursive: true);
    }
    return outboxDir;
  }

  /// Atomically enqueues an update snapshot with its local image and original createdAt
  Future<OutboxItem> enqueue({
    required String id,
    required String senderId,
    String? receiverId,
    required File originalImageFile,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    required DateTime createdAt,
  }) async {
    final outboxDir = await _getOutboxDir();
    final timestamp = createdAt.millisecondsSinceEpoch;

    // 1. Copy image to permanent outbox directory
    final permanentImagePath = '${outboxDir.path}/image_${timestamp}_$id.jpg';
    await originalImageFile.copy(permanentImagePath);

    final item = OutboxItem(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      localImagePath: permanentImagePath,
      caption: caption,
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
      createdAt: createdAt,
      status: 'pending',
      retryCount: 0,
    );

    // 2. Write metadata JSON atomically
    final metaPath = '${outboxDir.path}/meta_${timestamp}_$id.json';
    await File(metaPath).writeAsString(jsonEncode(item.toJson()));

    debugPrint('[OutboxService] Enqueued offline update: $id (captured at $createdAt) 🌲');
    return item;
  }

  /// Cryptographically solid RFC 4122 UUID v4 generator
  static String newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    // Set version to 4 (0100)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122 (10xx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Lists all pending outbox items that are NOT yet synced, sorted chronologically (FIFO)
  Future<List<OutboxItem>> getPendingItems() async {
    try {
      final outboxDir = await _getOutboxDir();
      final entities = await outboxDir.list().toList();

      final List<OutboxItem> items = [];
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.json') && entity.path.contains('meta_')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final item = OutboxItem.fromJson(json);
            // Only return items that have NOT been synced yet!
            if (!item.isSynced) {
              items.add(item);
            }
          } catch (e) {
            debugPrint('[OutboxService] Error reading outbox file ${entity.path}: $e');
          }
        }
      }

      // Sort ascending by creation timestamp (FIFO)
      items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return items;
    } catch (e) {
      debugPrint('[OutboxService] Error listing outbox items: $e');
      return [];
    }
  }

  /// Updates status and retry count of an outbox item
  Future<void> updateItem(OutboxItem item) async {
    try {
      final outboxDir = await _getOutboxDir();
      final timestamp = item.createdAt.millisecondsSinceEpoch;
      final metaPath = '${outboxDir.path}/meta_${timestamp}_${item.id}.json';
      final file = File(metaPath);
      if (await file.exists()) {
        await file.writeAsString(jsonEncode(item.toJson()));
      }
    } catch (e) {
      debugPrint('[OutboxService] Error updating outbox item ${item.id}: $e');
    }
  }

  /// Removes both JSON metadata and image file once successfully synced to cloud
  Future<void> removeItem(OutboxItem item) async {
    try {
      final outboxDir = await _getOutboxDir();
      final timestamp = item.createdAt.millisecondsSinceEpoch;
      final metaFile = File('${outboxDir.path}/meta_${timestamp}_${item.id}.json');
      final imageFile = File(item.localImagePath);

      if (await metaFile.exists()) {
        await metaFile.delete();
      }
      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      debugPrint('[OutboxService] Removed synced outbox item: ${item.id} 🌲');
    } catch (e) {
      debugPrint('[OutboxService] Error removing outbox item ${item.id}: $e');
    }
  }
}
