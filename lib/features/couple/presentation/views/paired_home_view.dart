import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_service.dart';
import '../../../updates/data/update_model.dart';
import '../../../updates/data/update_service.dart';
import '../../../updates/data/widget_sync_service.dart';
import '../../../updates/presentation/modals/send_update_modal.dart';
import '../../../updates/presentation/widgets/daily_moments_stack_deck.dart';
import '../../../updates/presentation/widgets/moments_tab_bar.dart';

class PairedHomeView extends StatefulWidget {
  final UserModel user;

  const PairedHomeView({
    super.key,
    required this.user,
  });

  @override
  State<PairedHomeView> createState() => _PairedHomeViewState();
}

class _PairedHomeViewState extends State<PairedHomeView> {
  final ImagePicker _imagePicker = ImagePicker();
  final UpdateService _updateService = UpdateService();
  final WidgetSyncService _widgetSyncService = WidgetSyncService();

  int _selectedTabIndex = 0; // 0: From Partner, 1: Sent Moments
  bool _isLoadingMoments = true;
  List<UpdateModel> _receivedMoments = [];
  List<UpdateModel> _sentMoments = [];
  bool _isOpeningCamera = false;

  RealtimeChannel? _updatesChannel;

  @override
  void initState() {
    super.initState();
    _loadTodayMoments();
    _subscribeToRealtimeUpdates();
  }

  @override
  void dispose() {
    _updatesChannel?.unsubscribe();
    super.dispose();
  }

  /// Supabase WebSocket Realtime Channel for instant live updates and reactions
  void _subscribeToRealtimeUpdates() {
    try {
      _updatesChannel = Supabase.instance.client
          .channel('updates-realtime-${widget.user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'Updates',
            callback: (payload) {
              debugPrint('[Realtime] Live event received: ${payload.eventType} -> new: ${payload.newRecord}');
              // Re-fetch today moments immediately without pull-to-refresh
              _loadTodayMoments(isBackgroundSync: true);
            },
          )
          .subscribe((status, [error]) {
            debugPrint('[Realtime] Channel status: $status, error: $error');
          });
      debugPrint('[Realtime] Subscribed to Updates table live channel! ⚡');
    } catch (e) {
      debugPrint('[Realtime] Error subscribing to channel: $e');
    }
  }

  Future<void> _loadTodayMoments({bool isBackgroundSync = false}) async {
    try {
      if (!isBackgroundSync) {
        setState(() => _isLoadingMoments = true);
      }

      final received = await _updateService.getTodayUpdates(
        userId: widget.user.id,
        type: 'received',
      );

      final sent = await _updateService.getTodayUpdates(
        userId: widget.user.id,
        type: 'sent',
      );

      if (mounted) {
        setState(() {
          _receivedMoments = received;
          _sentMoments = sent;
          _isLoadingMoments = false;
        });

        // Automatically update the Android Home Screen Widget with today's received moments
        if (_receivedMoments.isNotEmpty) {
          _widgetSyncService.syncMomentsListToWidget(moments: _receivedMoments);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMoments = false);
      }
    }
  }

  Future<void> _captureAndSendUpdate() async {
    if (_isOpeningCamera) return;

    try {
      setState(() => _isOpeningCamera = true);

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );

      if (photo != null && mounted) {
        SendUpdateModal.show(
          context: context,
          initialImage: File(photo.path),
          onUpdateSent: () {
            setState(() {
              _selectedTabIndex = 1; // Switch to Sent Moments tab
            });
            _loadTodayMoments();
          },
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Unable to open camera: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningCamera = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = widget.user.partner?['display_name'] ?? widget.user.partner?['email'] ?? 'Your Partner';
    final currentList = _selectedTabIndex == 0 ? _receivedMoments : _sentMoments;
    final emptyMessage = _selectedTabIndex == 0
        ? 'No updates received from $partnerName yet today.'
        : 'You haven’t sent any moments today yet.';

    return Stack(
      children: [
        // Main Scrollable Area
        RefreshIndicator(
          onRefresh: _loadTodayMoments,
          color: AppColors.primaryAccent,
          backgroundColor: AppColors.secondarySurface,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 8.0, bottom: 120.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Typography
                Text(
                  'Paired with\n$partnerName',
                  style: const TextStyle(
                    color: AppColors.textHighContrast,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 18),

                // Standalone Pill Buttons (From Partner | Sent Moments)
                MomentsTabBar(
                  selectedIndex: _selectedTabIndex,
                  onTabSelected: (index) {
                    setState(() => _selectedTabIndex = index);
                  },
                ),
                const SizedBox(height: 20),

                // Layered Stacked Cards Deck
                if (_isLoadingMoments)
                  const SizedBox(
                    height: 320,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryAccent,
                      ),
                    ),
                  )
                else
                  DailyMomentsStackDeck(
                    updates: currentList,
                    emptyMessage: emptyMessage,
                    currentUserId: widget.user.id,
                  ),
              ],
            ),
          ),
        ),

        // Pinned Bottom-Right Floating Camera Button
        Positioned(
          bottom: 24,
          right: 24,
          child: GestureDetector(
            onTap: _isOpeningCamera ? null : _captureAndSendUpdate,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryAccent,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: AppColors.secondarySurface,
                  width: 4,
                ),
              ),
              child: Center(
                child: _isOpeningCamera
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.textHighContrast,
                        ),
                      )
                    : const Icon(
                        Icons.camera_alt_rounded,
                        color: AppColors.textHighContrast,
                        size: 36,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
