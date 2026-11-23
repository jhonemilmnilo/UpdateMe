import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/data/auth_service.dart';

class CoupleService {
  static final CoupleService _instance = CoupleService._internal();
  factory CoupleService() => _instance;
  CoupleService._internal();

  static const String _backendBaseUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';

  /// Link current user with partner using partner's pair code (e.g. UM-7X9B)
  Future<UserModel> pairWithPartner({
    required String currentUserId,
    required String pairCode,
  }) async {
    final cleanCode = pairCode.trim().toUpperCase();

    final response = await http.post(
      Uri.parse('$_backendBaseUrl/api/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': currentUserId,
        'pairCode': cleanCode,
      }),
    );

    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      final errorMsg = data['error'] ?? 'Failed to pair with partner.';
      throw Exception(errorMsg);
    }

    final partnerData = data['partner'] as Map<String, dynamic>;

    // Construct updated current user with partner link
    final currentUser = AuthService().currentUser;
    if (currentUser == null) {
      throw Exception('Active session not found.');
    }

    final updatedUser = UserModel(
      id: currentUser.id,
      email: currentUser.email,
      username: currentUser.username,
      displayName: currentUser.displayName,
      avatarUrl: currentUser.avatarUrl,
      pairCode: currentUser.pairCode,
      partnerId: partnerData['id'] as String?,
      havePassword: currentUser.havePassword,
      partner: partnerData,
    );

    // Update active session locally
    await AuthService().activateUserSession(updatedUser);
    debugPrint('[CoupleService] Successfully paired with: ${partnerData['display_name'] ?? partnerData['email']}');

    // Notify partner's device in real-time via Supabase broadcast channel (zero polling, sub-100ms)
    try {
      final partnerId = partnerData['id'] as String?;
      if (partnerId != null && partnerId.isNotEmpty) {
        final partnerChannel = Supabase.instance.client.channel('user-channel-$partnerId');
        partnerChannel.subscribe();
        await partnerChannel.sendBroadcastMessage(
          event: 'paired',
          payload: {
            'partnerId': currentUser.id,
            'pairedAt': DateTime.now().toIso8601String(),
          },
        );
        debugPrint('[CoupleService] Dispatched live "paired" broadcast to partner channel: user-channel-$partnerId! ⚡');
      }
    } catch (e) {
      debugPrint('[CoupleService] Note: Broadcast channel send error: $e');
    }

    return updatedUser;
  }
}
