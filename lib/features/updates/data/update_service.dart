import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'update_model.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static const String _backendBaseUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';
  final SupabaseClient _supabase = Supabase.instance.client;

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
}
