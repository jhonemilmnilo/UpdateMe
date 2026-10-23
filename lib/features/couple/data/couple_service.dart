import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

    return updatedUser;
  }
}
