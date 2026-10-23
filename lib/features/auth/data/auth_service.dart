import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class UserModel {
  final String id;
  final String email;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String pairCode;
  final String? partnerId;
  final Map<String, dynamic>? partner;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    this.displayName,
    this.avatarUrl,
    required this.pairCode,
    this.partnerId,
    this.partner,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? partnerMap;
    if (json['partner'] is Map<String, dynamic>) {
      partnerMap = json['partner'] as Map<String, dynamic>;
    } else if (json['partner'] is List && (json['partner'] as List).isNotEmpty) {
      partnerMap = (json['partner'] as List).first as Map<String, dynamic>?;
    }

    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String? ?? json['email'].split('@')[0],
      displayName: json['display_name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      pairCode: json['pair_code'] as String? ?? '',
      partnerId: json['partner_id'] as String?,
      partner: partnerMap,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'pair_code': pairCode,
      'partner_id': partnerId,
      'partner': partner,
    };
  }

  bool get isPaired => partnerId != null;
}

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _backendBaseUrl = 'https://update-me-backend.nilojhonemil1.workers.dev';
  static const String _prefUserKey = 'update_me_active_user';

  // Frictionless Google Sign-In instance without serverClientId constraint
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  final ValueNotifier<UserModel?> currentUserNotifier = ValueNotifier<UserModel?>(null);

  UserModel? get currentUser => currentUserNotifier.value;
  bool get isAuthenticated => currentUserNotifier.value != null;

  /// Initialize local session from cache
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_prefUserKey);
      if (userJson != null) {
        final Map<String, dynamic> data = jsonDecode(userJson);
        currentUserNotifier.value = UserModel.fromJson(data);
        debugPrint('[AuthService] Restored local session for: ${currentUserNotifier.value?.email}');
      }
    } catch (e) {
      debugPrint('[AuthService] Failed to restore local session: $e');
    }
  }

  /// Frictionless native Google Account selection and backend profile sync
  Future<UserModel> signInWithGoogle() async {
    // 1. Force fresh account picker without stale cache
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    // 2. Open Native Android modal dialog
    final GoogleSignInAccount? account = await _googleSignIn.signIn();

    if (account == null) {
      throw Exception('Sign in aborted by user.');
    }

    debugPrint('[AuthService] Selected Google account: ${account.email}');

    // 3. Sync profile with backend
    final response = await http.post(
      Uri.parse('$_backendBaseUrl/api/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': account.email,
        'displayName': account.displayName,
        'avatarUrl': account.photoUrl,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint('[AuthService] Backend sync failed: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to synchronize user profile. Please try again.');
    }

    final data = jsonDecode(response.body);
    if (data['user'] == null) {
      throw Exception(data['error'] ?? 'Invalid response from server.');
    }

    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

    // 4. Cache user locally
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUserKey, jsonEncode(user.toJson()));

    currentUserNotifier.value = user;
    return user;
  }

  /// Optional OAuth fallback
  Future<void> signInWithOAuth(dynamic provider) async {
    // Reserved for secondary providers if needed
    throw Exception('Please use Google Sign-In.');
  }

  /// Sign out and clear active session
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserKey);

    currentUserNotifier.value = null;
    debugPrint('[AuthService] User signed out cleanly.');
  }
}
