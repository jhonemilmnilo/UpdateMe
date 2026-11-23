import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/daily_moments_cache_service.dart';
import '../../data/reply_outbox_service.dart';
import '../../data/update_model.dart';
import '../../data/update_service.dart';
import '../../data/widget_sync_service.dart';
import '../modals/reply_moment_modal.dart';

class FullscreenMomentsViewerScreen extends StatefulWidget {
  final List<UpdateModel> moments;
  final int initialIndex;
  final String currentUserId;

  const FullscreenMomentsViewerScreen({
    super.key,
    required this.moments,
    required this.initialIndex,
    required this.currentUserId,
  });

  @override
  State<FullscreenMomentsViewerScreen> createState() =>
      _FullscreenMomentsViewerScreenState();
}

class _FullscreenMomentsViewerScreenState
    extends State<FullscreenMomentsViewerScreen> {
  final UpdateService _updateService = UpdateService();
  late PageController _pageController;
  late List<UpdateModel> _currentMoments;
  late int _currentIndex;
  StreamSubscription<MomentReplyEvent>? _replySubscription;

  @override
  void initState() {
    super.initState();
    _currentMoments = List.from(widget.moments);
    _currentIndex = widget.initialIndex.clamp(
      0,
      _currentMoments.isNotEmpty ? _currentMoments.length - 1 : 0,
    );
    _pageController = PageController(initialPage: _currentIndex);
    _subscribeToLiveReplies();
  }

  void _subscribeToLiveReplies() {
    _replySubscription = _updateService.momentRepliedStream.listen((event) {
      if (!mounted) return;
      bool updated = false;
      final newList = _currentMoments.map((m) {
        if (m.id == event.updateId) {
          updated = true;
          return m.copyWith(
            replyText: event.replyText,
            replyCreatedAt: event.replyCreatedAt,
            isReplied: true,
            isPendingReply: false,
          );
        }
        return m;
      }).toList();

      if (updated) {
        HapticFeedback.lightImpact();
        setState(() {
          _currentMoments = newList;
        });
        debugPrint('[FullscreenMomentsViewer] Live moment_replied applied to photo ${event.updateId}! 💬⚡');
      }
    });
  }

  @override
  void dispose() {
    _replySubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _toggleHeart(int index) async {
    if (index >= _currentMoments.length) return;

    final item = _currentMoments[index];
    if (item.senderId == widget.currentUserId) return; // Sender cannot react to own moment
    if (item.isReacted) return; // One-way reaction: cannot unreact

    HapticFeedback.mediumImpact();
    const newReactionState = true;

    // Optimistic UI update
    setState(() {
      _currentMoments[index] = item.copyWith(isReacted: newReactionState);
    });

    final success = await _updateService.toggleReaction(
      updateId: item.id,
      isReacted: newReactionState,
    );

    if (!success && mounted) {
      setState(() {
        _currentMoments[index] = item;
      });
    }
  }

  Future<void> _handleSendReply(int index) async {
    if (index >= _currentMoments.length) return;
    final moment = _currentMoments[index];
    if (moment.senderId == widget.currentUserId) return;
    if (moment.isReplied) return;

    HapticFeedback.lightImpact();
    final reply = await ReplyMomentModal.show(context, partnerName: 'Partner');
    if (reply != null && reply.isNotEmpty && mounted) {
      final replyCreatedAt = DateTime.now();

      // 1. Immediate UI Reflection in Fullscreen Viewer
      final pendingReplyModel = moment.copyWith(
        replyText: reply,
        replyCreatedAt: replyCreatedAt,
        isReplied: true,
        isPendingReply: true,
      );
      setState(() {
        _currentMoments[index] = pendingReplyModel;
      });

      // 2. Persist to Disk (daily_cache & reply_outbox)
      final cacheService = DailyMomentsCacheService();
      await cacheService.updateMomentReply(
        type: 'received',
        updateId: moment.id,
        replyText: reply,
        replyCreatedAt: replyCreatedAt,
        isPendingReply: true,
      );
      await ReplyOutboxService().enqueue(
        updateId: moment.id,
        replyText: reply,
        replyCreatedAt: replyCreatedAt,
      );

      // Reflect pending reply on homescreen widget immediately (received moments only)
      final pendingReceivedOnly = _currentMoments
          .where((m) => m.senderId != widget.currentUserId)
          .toList();
      if (pendingReceivedOnly.isNotEmpty) {
        WidgetSyncService().syncMomentsListToWidget(
          moments: pendingReceivedOnly,
          userId: widget.currentUserId,
        );
      }

      // 3. Attempt immediate delivery if online
      final success = await _updateService.sendReply(
        updateId: moment.id,
        replyText: reply,
        replyCreatedAt: replyCreatedAt,
      );

      if (!mounted) return;

      if (success) {
        await ReplyOutboxService().removeItem(moment.id);
        await cacheService.updateMomentReply(
          type: 'received',
          updateId: moment.id,
          replyText: reply,
          replyCreatedAt: replyCreatedAt,
          isPendingReply: false,
        );

        if (mounted) {
          setState(() {
            _currentMoments[index] = pendingReplyModel.copyWith(
              isPendingReply: false,
            );
          });
          // Instant sync confirmed reply to homescreen widget (received moments only)
          final confirmedReceivedOnly = _currentMoments
              .where((m) => m.senderId != widget.currentUserId)
              .toList();
          if (confirmedReceivedOnly.isNotEmpty) {
            WidgetSyncService().syncMomentsListToWidget(
              moments: confirmedReceivedOnly,
              userId: widget.currentUserId,
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentMoments.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No moments available',
                style: TextStyle(color: AppColors.supportingText, fontSize: 14),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Close', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_currentMoments);
        }
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Fullscreen PageView with Pinch-to-Zoom
          PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            itemCount: _currentMoments.length,
            itemBuilder: (context, index) {
              final moment = _currentMoments[index];
              final isSender = moment.senderId == widget.currentUserId;

              final isLocalFile = !moment.imageUrl.startsWith('http');

              Widget imageWidget;
              if (isLocalFile) {
                imageWidget = Image.file(
                  File(moment.imageUrl),
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 1080,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: Text(
                        'Unable to load moment',
                        style: TextStyle(color: AppColors.supportingText),
                      ),
                    ),
                  ),
                );
              } else {
                imageWidget = CachedNetworkImage(
                  imageUrl: moment.imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  memCacheWidth: 1080,
                  placeholder: (context, url) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryAccent,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.black,
                    child: const Center(
                      child: Text(
                        'Unable to load moment',
                        style: TextStyle(color: AppColors.supportingText),
                      ),
                    ),
                  ),
                );
              }

              return GestureDetector(
                onDoubleTap: isSender ? null : () => _toggleHeart(index),
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 3.5,
                  child: Center(child: imageWidget),
                ),
              );
            },
          ),

          // 2. Invisible Tap Zones for Previous / Next
          if (_currentMoments.length > 1) ...[
            // Left Tap Zone (Previous)
            Positioned(
              top: 100,
              bottom: 150,
              left: 0,
              width: 90,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_pageController.hasClients && _currentIndex > 0) {
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              ),
            ),
            // Right Tap Zone (Next)
            Positioned(
              top: 100,
              bottom: 150,
              right: 0,
              width: 90,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_pageController.hasClients &&
                      _currentIndex < _currentMoments.length - 1) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
              ),
            ),
          ],

          // 3. Top Vignette Scrim for legibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 4. Top Overlay Header: Close Button, Story Bars & Metadata
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Story Progress Bars
                    if (_currentMoments.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Row(
                          children: List.generate(_currentMoments.length, (index) {
                            final isActive = index == _currentIndex;
                            final isPast = index < _currentIndex;
                            return Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(horizontal: 2.0),
                                decoration: BoxDecoration(
                                  color: isPast
                                      ? Colors.white
                                      : (isActive
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.35)),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                    // Top Bar Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Close Button (Rounded pill)
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(_currentMoments),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),

                        // Location & Counter Badge
                        Row(
                          children: [
                            if (_currentMoments[_currentIndex].locationName != null &&
                                _currentMoments[_currentIndex]
                                    .locationName!
                                    .trim()
                                    .isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _currentMoments[_currentIndex]
                                      .locationName!
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.textHighContrast,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            if (_currentMoments[_currentIndex].senderId != widget.currentUserId &&
                                !_currentMoments[_currentIndex].isReplied) ...[
                              GestureDetector(
                                onTap: () => _handleSendReply(_currentIndex),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E2622).withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.primaryAccent.withValues(alpha: 0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: const Text(
                                    'Reply',
                                    style: TextStyle(
                                      color: AppColors.textHighContrast,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${_currentIndex + 1}/${_currentMoments.length}',
                                style: const TextStyle(
                                  color: AppColors.textHighContrast,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Bottom Vignette Scrim for Caption & React
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 180,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 6. Bottom Information & React Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Caption & Time on Left
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_currentMoments[_currentIndex].caption != null &&
                              _currentMoments[_currentIndex].caption!.trim().isNotEmpty) ...[
                            Text(
                              _currentMoments[_currentIndex].caption!,
                              style: const TextStyle(
                                color: AppColors.textHighContrast,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (_currentMoments[_currentIndex].replyText != null &&
                              _currentMoments[_currentIndex].replyText!.trim().isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: RichText(
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      text: TextSpan(
                                        children: [
                                          TextSpan(
                                            text: _currentMoments[_currentIndex].senderId == widget.currentUserId
                                                ? 'Partner: '
                                                : 'You: ',
                                            style: TextStyle(
                                              color: _currentMoments[_currentIndex].isPendingReply
                                                  ? const Color(0xFFE5A93C)
                                                  : AppColors.primaryAccent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          TextSpan(
                                            text: _currentMoments[_currentIndex].replyText!,
                                            style: const TextStyle(
                                              color: AppColors.textHighContrast,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              height: 1.25,
                                            ),
                                          ),
                                          if (_currentMoments[_currentIndex].replyCreatedAt != null)
                                            TextSpan(
                                              text: _currentMoments[_currentIndex].isPendingReply
                                                  ? ' • Syncing...'
                                                  : ' • ${DateFormat('h:mm a').format(_currentMoments[_currentIndex].replyCreatedAt!.toLocal())}',
                                              style: TextStyle(
                                                color: _currentMoments[_currentIndex].isPendingReply
                                                    ? const Color(0xFFE5A93C).withValues(alpha: 0.9)
                                                    : AppColors.supportingText.withValues(alpha: 0.8),
                                                fontSize: 11,
                                                fontWeight: _currentMoments[_currentIndex].isPendingReply
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_currentMoments[_currentIndex].isPendingReply) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.sync_rounded,
                                      size: 14,
                                      color: const Color(0xFFE5A93C).withValues(alpha: 0.9),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          Text(
                            DateFormat('h:mm a').format(
                              _currentMoments[_currentIndex].createdAt.toLocal(),
                            ),
                            style: const TextStyle(
                              color: AppColors.supportingText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Heart Reaction on Right
                    GestureDetector(
                      onTap: _currentMoments[_currentIndex].senderId == widget.currentUserId
                          ? null
                          : () => _toggleHeart(_currentIndex),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                        ),
                        child: Center(
                          child: Icon(
                            _currentMoments[_currentIndex].isReacted
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: _currentMoments[_currentIndex].isReacted
                                ? const Color(0xFFFF5252)
                                : Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
