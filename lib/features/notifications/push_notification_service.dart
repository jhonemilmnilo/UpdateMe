import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../auth/data/auth_service.dart';
import '../updates/data/update_model.dart';
import '../updates/data/widget_sync_service.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM Background] Message received: ${message.messageId}');

  // If payload contains moment data, automatically sync to Android Home Screen Widget in the background!
  final data = message.data;
  final momentId = data['updateId'] ?? data['id'];
  if (data.containsKey('imageUrl') && momentId != null) {
    try {
      final moment = UpdateModel(
        id: momentId,
        senderId: data['senderId'] ?? '',
        receiverId: data['receiverId'] ?? '',
        imageUrl: data['imageUrl'] ?? '',
        caption: data['caption'],
        locationName: data['locationName'],
        isRead: false,
        isReacted: false,
        createdAt: DateTime.now(),
      );

      await WidgetSyncService().syncLatestMomentToWidget(moment: moment);
      debugPrint('[FCM Background] Widget auto-synced from background push! 🌲');
    } catch (e) {
      debugPrint('[FCM Background] Error syncing widget from push: $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const String _backendBaseUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Initializes FCM permissions, retrieves token, and binds listeners
  Future<void> initialize() async {
    try {
      // 1. Request notification permissions (Android 13+ & iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // Set foreground notification options so heads-up alerts display even while app is open
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

      // 2. Fetch unique device token
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[FCM] Device Token: $token');
        await _saveTokenToBackend(token);
      }

      // 3. Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token refreshed: $newToken');
        _saveTokenToBackend(newToken);
      });

      // 4. Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM Foreground] Received: ${message.notification?.title} - ${message.notification?.body}');

        final data = message.data;
        final momentId = data['updateId'] ?? data['id'];
        if (data.containsKey('imageUrl') && momentId != null) {
          final moment = UpdateModel(
            id: momentId,
            senderId: data['senderId'] ?? '',
            receiverId: data['receiverId'] ?? '',
            imageUrl: data['imageUrl'] ?? '',
            caption: data['caption'],
            locationName: data['locationName'],
            isRead: false,
            isReacted: false,
            createdAt: DateTime.now(),
          );
          WidgetSyncService().syncLatestMomentToWidget(moment: moment);
        }
      });
    } catch (e) {
      debugPrint('[FCM] Error initializing push notifications: $e');
    }
  }

  /// Explicitly re-sync device token to backend for currently authenticated user
  Future<void> registerDeviceToken({String? userId}) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('[FCM] Registering device token for active user ($userId)...');
        await _saveTokenToBackend(token, explicitUserId: userId);
      }
    } catch (e) {
      debugPrint('[FCM] Error registering device token: $e');
    }
  }

  /// Sends device FCM token to backend to update user profile
  Future<void> _saveTokenToBackend(String token, {String? explicitUserId}) async {
    final targetUserId = explicitUserId ?? AuthService().currentUser?.id;
    if (targetUserId == null) {
      debugPrint('[FCM] No authenticated user found yet. Will register token upon login.');
      return;
    }

    try {
      final response = await http.patch(
        Uri.parse('$_backendBaseUrl/api/users/$targetUserId/fcm-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        debugPrint('[FCM] Token successfully registered with user in backend! 🌲');
      } else {
        debugPrint('[FCM] Failed to register token with backend: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[FCM] Error saving token to backend: $e');
    }
  }
}
