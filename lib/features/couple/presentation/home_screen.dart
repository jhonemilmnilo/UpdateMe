import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/data/auth_service.dart';
import '../../updates/data/update_model.dart';
import '../../updates/data/update_service.dart';
import '../../updates/presentation/views/fullscreen_moments_viewer_screen.dart';
import '../../notifications/push_notification_service.dart';
import 'views/paired_home_view.dart';
import 'views/unpaired_pairing_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription<Uri?>? _widgetClickSubscription;
  final UpdateService _updateService = UpdateService();
  RealtimeChannel? _userRealtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkInitialWidgetLaunch();
    _listenToWidgetClicks();
    PushNotificationService().registerDeviceToken();
    _subscribeToUserRealtime();
    // Re-verify current session upon screen entry
    AuthService().refreshCurrentUser();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Whenever user switches back to the app, sync profile status
      AuthService().refreshCurrentUser();
    }
  }

  /// Listens to both live broadcast events and postgres row mutations
  /// When partner links, triggers instant zero-polling session refresh
  void _subscribeToUserRealtime() {
    final currentUser = AuthService().currentUser;
    if (currentUser == null) return;

    try {
      _userRealtimeChannel = Supabase.instance.client
          .channel('user-channel-${currentUser.id}')
          .onBroadcast(
            event: 'paired',
            callback: (payload) {
              debugPrint('[HomeScreen Realtime] Received live "paired" broadcast: $payload ⚡');
              AuthService().refreshCurrentUser();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'User',
            callback: (payload) {
              final newRec = payload.newRecord;
              if (newRec['id'] == currentUser.id) {
                debugPrint('[HomeScreen Realtime] User row updated: ${payload.eventType}');
                AuthService().refreshCurrentUser();
              }
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[HomeScreen Realtime] User channel status: $status, error: $error');
          });
      debugPrint('[HomeScreen Realtime] Subscribed to user broadcast and row events! ⚡');
    } catch (e) {
      debugPrint('[HomeScreen Realtime] Error subscribing to user channel: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userRealtimeChannel?.unsubscribe();
    _widgetClickSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialWidgetLaunch() async {
    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (uri != null) {
        _handleWidgetLaunchUri(uri);
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error checking initiallyLaunchedFromHomeWidget: $e');
    }
  }

  void _listenToWidgetClicks() {
    _widgetClickSubscription = HomeWidget.widgetClicked.listen((uri) {
      if (uri != null) {
        _handleWidgetLaunchUri(uri);
      }
    });
  }

  Future<void> _handleWidgetLaunchUri(Uri uri) async {
    debugPrint('[HomeScreen] Launched from widget with URI: $uri');
    if (uri.scheme == 'updateme' && uri.host == 'moment') {
      final currentUser = AuthService().currentUser;
      if (currentUser == null) return;

      final indexParam = uri.queryParameters['index'];
      final targetIndex = int.tryParse(indexParam ?? '0') ?? 0;

      // 1. Try instantaneous load from locally cached widget data (0ms latency!)
      try {
        final cachedJson = await HomeWidget.getWidgetData<String>('widget_moments_json');
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final List list = jsonDecode(cachedJson);
          final List<UpdateModel> cachedMoments = list.map<UpdateModel>((item) {
            DateTime itemCreatedAt = DateTime.now();
            if (item['created_at'] != null) {
              try {
                itemCreatedAt = DateTime.parse(item['created_at'] as String).toLocal();
              } catch (_) {}
            }

            return UpdateModel(
              id: item['id'] as String,
              senderId: '', // placeholder, receiver viewing
              receiverId: currentUser.id,
              imageUrl: item['image_path'] as String, // local file path for instant render
              caption: item['caption'] as String?,
              locationName: item['location'] as String?,
              isRead: true,
              isReacted: item['is_reacted'] as bool? ?? false,
              createdAt: itemCreatedAt,
            );
          }).toList();

          if (cachedMoments.isNotEmpty && mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => FullscreenMomentsViewerScreen(
                  moments: cachedMoments,
                  initialIndex: targetIndex,
                  currentUserId: currentUser.id,
                ),
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('[HomeScreen] Local cache parsing for deep link: $e');
      }

      // 2. Fallback to network fetch if cache not yet populated
      try {
        final receivedMoments = await _updateService.getTodayUpdates(
          userId: currentUser.id,
          type: 'received',
        );

        if (receivedMoments.isNotEmpty && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FullscreenMomentsViewerScreen(
                moments: receivedMoments,
                initialIndex: targetIndex,
                currentUserId: currentUser.id,
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('[HomeScreen] Failed to load moments for widget deep link: $e');
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    await AuthService().signOut();
    if (context.mounted) {
      AppToast.info(context, 'You have been signed out.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: AuthService().currentUserNotifier,
      builder: (context, user, _) {
        if (user == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryAccent),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Minimalist Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 14.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Branding Title
                      const Text(
                        'UPDATEME',
                        style: TextStyle(
                          color: AppColors.textHighContrast,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                        ),
                      ),

                      // Sign Out Trigger (Clean minimalist outlined button)
                      GestureDetector(
                        onTap: () => _handleSignOut(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.secondarySurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.supportingText.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Text(
                            'Sign Out',
                            style: TextStyle(
                              color: AppColors.supportingText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x1AFFFFFF),
                ),

                // Main Content View (Switches automatically based on user.isPaired)
                Expanded(
                  child: user.isPaired
                      ? PairedHomeView(user: user)
                      : UnpairedPairingView(user: user),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
