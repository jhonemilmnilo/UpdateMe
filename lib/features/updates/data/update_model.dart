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
  final DateTime createdAt;
  final Map<String, dynamic>? sender;

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
    required this.createdAt,
    this.sender,
  });

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
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      sender: json['sender'] as Map<String, dynamic>?,
    );
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
      'created_at': createdAt.toIso8601String(),
    };
  }
}
