class UpdateModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String imageUrl;
  final String? caption;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  final bool isRead;
  final bool isReacted;
  final String? replyText;
  final DateTime? replyCreatedAt;
  final bool isReplied;
  final DateTime createdAt;
  final Map<String, dynamic>? sender;
  final bool isPending;
  final bool isPendingReply;

  const UpdateModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.imageUrl,
    this.caption,
    this.locationName,
    this.latitude,
    this.longitude,
    required this.isRead,
    this.isReacted = false,
    this.replyText,
    this.replyCreatedAt,
    this.isReplied = false,
    required this.createdAt,
    this.sender,
    this.isPending = false,
    this.isPendingReply = false,
  });

  bool get isLocalImage => !imageUrl.startsWith('http');

  factory UpdateModel.fromJson(Map<String, dynamic> json) {
    return UpdateModel(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      imageUrl: json['image_url'] as String,
      caption: json['caption'] as String?,
      locationName: json['location_name'] as String?,
      latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
      isRead: json['is_read'] as bool? ?? false,
      isReacted: json['is_reacted'] as bool? ?? false,
      replyText: json['reply_text'] as String?,
      replyCreatedAt: json['reply_created_at'] != null ? parseUtcToLocal(json['reply_created_at']) : null,
      isReplied: json['is_replied'] as bool? ?? (json['reply_text'] != null),
      createdAt: parseUtcToLocal(json['created_at']),
      sender: json['sender'] as Map<String, dynamic>?,
      isPendingReply: json['is_pending_reply'] as bool? ?? false,
    );
  }

  UpdateModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? imageUrl,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    bool? isRead,
    bool? isReacted,
    String? replyText,
    DateTime? replyCreatedAt,
    bool? isReplied,
    DateTime? createdAt,
    Map<String, dynamic>? sender,
    bool? isPending,
    bool? isPendingReply,
  }) {
    return UpdateModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      imageUrl: imageUrl ?? this.imageUrl,
      caption: caption ?? this.caption,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isRead: isRead ?? this.isRead,
      isReacted: isReacted ?? this.isReacted,
      replyText: replyText ?? this.replyText,
      replyCreatedAt: replyCreatedAt ?? this.replyCreatedAt,
      isReplied: isReplied ?? this.isReplied,
      createdAt: createdAt ?? this.createdAt,
      sender: sender ?? this.sender,
      isPending: isPending ?? this.isPending,
      isPendingReply: isPendingReply ?? this.isPendingReply,
    );
  }

  /// Reliably parses UTC database timestamps (with or without 'Z') and converts to device local time (PH Time UTC+8)
  static DateTime parseUtcToLocal(dynamic rawDate) {
    if (rawDate == null) return DateTime.now();
    if (rawDate is DateTime) return rawDate.toLocal();
    String raw = rawDate.toString().trim();
    if (raw.isEmpty) return DateTime.now();

    // Replace whitespace with 'T' if format is 'YYYY-MM-DD HH:MM:SS'
    if (raw.contains(' ') && !raw.contains('T')) {
      raw = raw.replaceFirst(' ', 'T');
    }

    // If string has no timezone identifier ('Z' or '+' or trailing '-HH:MM'),
    // Postgres TIMESTAMP is UTC, so append 'Z' so Dart parses it as UTC.
    final hasTimezone = raw.endsWith('Z') ||
        raw.contains('+') ||
        RegExp(r'-\d{2}(:\d{2})?$').hasMatch(raw);

    if (!hasTimezone) {
      raw = '${raw}Z';
    }

    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'image_url': imageUrl,
      'caption': caption,
      'location_name': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'is_read': isRead,
      'is_reacted': isReacted,
      'reply_text': replyText,
      'reply_created_at': replyCreatedAt?.toUtc().toIso8601String(),
      'is_replied': isReplied,
      'is_pending_reply': isPendingReply,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
