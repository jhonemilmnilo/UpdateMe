import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'update_model.dart';

enum ReplyDeliveryStatus {
  synced,
  alreadyReplied,
  notFound,
  failed,
}

class MomentReplyEvent {
  final String updateId;
  final String replyText;
  final DateTime replyCreatedAt;

  const MomentReplyEvent({
    required this.updateId,
    required this.replyText,
    required this.replyCreatedAt,
  });
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _backendBaseUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';
  final SupabaseClient _supabase = Supabase.instance.client;

  final StreamController<MomentReplyEvent> _momentRepliedController =
      StreamController<MomentReplyEvent>.broadcast();

  Stream<MomentReplyEvent> get momentRepliedStream => _momentRepliedController.stream;

  void emitMomentReplied({
    required String updateId,
    required String replyText,
    required DateTime replyCreatedAt,
  }) {
    if (!_momentRepliedController.isClosed) {
      _momentRepliedController.add(MomentReplyEvent(
        updateId: updateId,
        replyText: replyText,
        replyCreatedAt: replyCreatedAt,
      ));
    }
  }

  /// Fetch current GPS position and reverse-geocode to human readable place
  Future<Map<String, dynamic>?> getCurrentLocation() async {
    try {
      // 1. Check if GPS / Location services are enabled on device
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[UpdateService] Location service is disabled on device');
        // Will still try to proceed if permission is available, or prompt user
      }

      // 2. Check & Request Permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[UpdateService] Location permission denied by user');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[UpdateService] Location permission permanently denied');
        return null;
      }

      // 3. Acquire current or last known position
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (e) {
        debugPrint('[UpdateService] getCurrentPosition timeout/error, checking last known position: $e');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return null;
      }

      // 4. Reverse Geocode Coordinates into Clean City/District String
      String? locationName;
      try {
        final List<Placemark> placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          debugPrint('[UpdateService] Raw placemark: locality=${place.locality}, subAdmin=${place.subAdministrativeArea}, admin=${place.administrativeArea}, subLocality=${place.subLocality}, name=${place.name}');

          final locality = place.locality?.trim();
          final subLocality = place.subLocality?.trim();
          final subAdmin = place.subAdministrativeArea?.trim();
          final admin = place.administrativeArea?.trim();

          // Construct intuitive couple-style badge (e.g., "Taguig, Metro Manila" or "Makati, Metro Manila")
          if (locality != null && locality.isNotEmpty && admin != null && admin.isNotEmpty) {
            locationName = '$locality, $admin';
          } else if (subAdmin != null && subAdmin.isNotEmpty && admin != null && admin.isNotEmpty) {
            locationName = '$subAdmin, $admin';
          } else if (subLocality != null && subLocality.isNotEmpty && locality != null && locality.isNotEmpty) {
            locationName = '$subLocality, $locality';
          } else {
            locationName = locality ?? subAdmin ?? admin ?? place.name;
          }
        }
      } catch (e) {
        debugPrint('[UpdateService] Geocoding reverse lookup error: $e');
      }

      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'location_name': locationName,
      };
    } catch (e) {
      debugPrint('[UpdateService] Location detection failed: $e');
      return null;
    }
  }

  /// Uploads compressed image file to Supabase Storage 'updates' bucket
  Future<String> uploadUpdatePhoto({
    required File imageFile,
    required String userId,
  }) async {
    try {
      final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'photos/$fileName';

      final bytes = await imageFile.readAsBytes();

      await _supabase.storage.from('UpdateMe').uploadBinary(
        storagePath,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: true,
        ),
      );

      final publicUrl = _supabase.storage.from('UpdateMe').getPublicUrl(storagePath);
      return publicUrl;
    } catch (e) {
      debugPrint('[UpdateService] Storage upload failed: $e');
      throw Exception('Failed to upload photo to storage: $e');
    }
  }

  /// Send update record to Cloudflare Worker backend
  Future<UpdateModel> sendUpdate({
    required String senderId,
    String? receiverId,
    required String imageUrl,
    String? caption,
    String? locationName,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
    String? id,
  }) async {
    final response = await http.post(
      Uri.parse('$_backendBaseUrl/api/updates'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'senderId': senderId,
        'receiverId': receiverId,
        'imageUrl': imageUrl,
        'caption': caption,
        'locationName': locationName,
        'latitude': latitude,
        'longitude': longitude,
        if (createdAt != null) 'createdAt': createdAt.toUtc().toIso8601String(),
        if (id != null) 'id': id,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200 || data['success'] != true) {
      final errorMessage = data['error'] ?? 'Failed to send update to partner';
      throw Exception(errorMessage);
    }

    return UpdateModel.fromJson(data['update']);
  }

  /// Fetch couple's recent updates feed
  Future<List<UpdateModel>> getFeed(String userId) async {
    final response = await http.get(
      Uri.parse('$_backendBaseUrl/api/updates/feed/$userId'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load updates feed');
    }

    final data = jsonDecode(response.body);
    final List list = data['updates'] ?? [];
    return list.map((item) => UpdateModel.fromJson(item)).toList();
  }

  /// Fetch latest update received by user (for Homescreen widget preview)
  Future<UpdateModel?> getLatestUpdate(String userId) async {
    final response = await http.get(
      Uri.parse('$_backendBaseUrl/api/updates/latest/$userId'),
    );

    if (response.statusCode != 200) {
      return null;
    }

    final data = jsonDecode(response.body);
    if (data['latestUpdate'] == null) return null;
    return UpdateModel.fromJson(data['latestUpdate']);
  }

  /// Fetch today's moments (strictly current date in UTC, filtered by type: 'received' or 'sent')
  Future<List<UpdateModel>> getTodayUpdates({
    required String userId,
    required String type, // 'received' or 'sent'
  }) async {
    final response = await http.get(
      Uri.parse('$_backendBaseUrl/api/updates/today/$userId?type=$type'),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load today moments');
    }

    final data = jsonDecode(response.body);
    final List list = data['updates'] ?? [];
    return list.map((item) => UpdateModel.fromJson(item)).toList();
  }

  /// Toggle reaction on an update
  Future<bool> toggleReaction({
    required String updateId,
    required bool isReacted,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_backendBaseUrl/api/updates/$updateId/react'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'isReacted': isReacted}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('[UpdateService] Failed to toggle reaction: $e');
      return false;
    }
  }

  /// Send an intimate reply to an update (Strict 1-is-to-1 gate) with detailed status
  Future<ReplyDeliveryStatus> sendReplyWithStatus({
    required String updateId,
    required String replyText,
    DateTime? replyCreatedAt,
  }) async {
    try {
      final effectiveTimestamp = (replyCreatedAt ?? DateTime.now()).toUtc().toIso8601String();
      final response = await http.post(
        Uri.parse('$_backendBaseUrl/api/updates/$updateId/reply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'replyText': replyText.trim(),
          'replyCreatedAt': effectiveTimestamp,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['success'] == true
            ? ReplyDeliveryStatus.synced
            : ReplyDeliveryStatus.failed;
      } else if (response.statusCode == 409) {
        debugPrint('[UpdateService] sendReply returned 409 (already replied): ${response.body}');
        return ReplyDeliveryStatus.alreadyReplied;
      } else if (response.statusCode == 404) {
        debugPrint('[UpdateService] sendReply returned 404 (moment deleted): ${response.body}');
        return ReplyDeliveryStatus.notFound;
      } else {
        debugPrint('[UpdateService] sendReply returned ${response.statusCode}: ${response.body}');
        return ReplyDeliveryStatus.failed;
      }
    } catch (e) {
      debugPrint('[UpdateService] Error sending reply: $e');
      return ReplyDeliveryStatus.failed;
    }
  }

  /// Send an intimate reply to an update (Strict 1-is-to-1 gate)
  Future<bool> sendReply({
    required String updateId,
    required String replyText,
    DateTime? replyCreatedAt,
  }) async {
    final status = await sendReplyWithStatus(
      updateId: updateId,
      replyText: replyText,
      replyCreatedAt: replyCreatedAt,
    );
    return status == ReplyDeliveryStatus.synced ||
        status == ReplyDeliveryStatus.alreadyReplied;
  }
}
