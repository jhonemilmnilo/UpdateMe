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
import '../views/fullscreen_moments_viewer_screen.dart';

class DailyMomentsStackDeck extends StatefulWidget {
  final List<UpdateModel> updates;
  final String emptyMessage;
  final String currentUserId;
  final ValueChanged<List<UpdateModel>>? onUpdatesChanged;

  const DailyMomentsStackDeck({
    super.key,
    required this.updates,
    required this.emptyMessage,
    required this.currentUserId,
    this.onUpdatesChanged,
  });

  @override
  State<DailyMomentsStackDeck> createState() => _DailyMomentsStackDeckState();
}

class _DailyMomentsStackDeckState extends State<DailyMomentsStackDeck>
    with SingleTickerProviderStateMixin {
  final UpdateService _updateService = UpdateService();
  late PageController _pageController;
  late List<UpdateModel> _currentUpdates;
  int _currentPageIndex = 0;
  final Set<int> _sendingReplyIndices = {};
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _currentUpdates = List.from(widget.updates);
    _currentPageIndex = 0; // Index 0 is always the newest/pending moment
    _pageController = PageController(initialPage: 0);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients && _pageController.page?.round() != 0) {
        _pageController.jumpToPage(0);
      }
    });
  }

  @override
  void didUpdateWidget(covariant DailyMomentsStackDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isDifferentLength = widget.updates.length != oldWidget.updates.length;
    final isNewFirstItem = widget.updates.isNotEmpty &&
        oldWidget.updates.isNotEmpty &&
        widget.updates.first.id != oldWidget.updates.first.id;
    final shouldResetToFirst = isDifferentLength || isNewFirstItem;

    setState(() {
      _currentUpdates = List.from(widget.updates);
      if (_currentUpdates.isEmpty) {
        _currentPageIndex = 0;
      } else if (shouldResetToFirst) {
        _currentPageIndex = 0;
      } else {
        _currentPageIndex = _currentPageIndex.clamp(0, _currentUpdates.length - 1);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (shouldResetToFirst && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  Future<void> _toggleHeart(int index) async {
    if (index >= _currentUpdates.length) return;

    final item = _currentUpdates[index];
    // Guard 1: Only receiver can react! Sender cannot react to their own moment.
    if (item.senderId == widget.currentUserId) return;

    // Guard 2: One-way reaction rule: Once reacted, it CANNOT be unreacted
    if (item.isReacted) return;

    HapticFeedback.mediumImpact();
    const newReactionState = true;

    // Optimistic UI update
    setState(() {
      _currentUpdates[index] = item.copyWith(isReacted: newReactionState);
    });
    widget.onUpdatesChanged?.call(List.from(_currentUpdates));

    final success = await _updateService.toggleReaction(
      updateId: item.id,
      isReacted: newReactionState,
    );

    // Rollback if failed
    if (!success && mounted) {
      setState(() {
        _currentUpdates[index] = item;
      });
      widget.onUpdatesChanged?.call(List.from(_currentUpdates));
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentPageIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.updates.isEmpty) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          widget.emptyMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.supportingText,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Counter Header (Minimalist indicator, no redundant buttons)
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            '${_currentPageIndex + 1} of ${widget.updates.length}',
            style: const TextStyle(
              color: AppColors.supportingText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),

        // Responsive Swipeable PageView Deck
        LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = MediaQuery.of(context).size.height;
            final calculatedHeight = (constraints.maxWidth * 1.25).clamp(400.0, screenHeight * 0.62);

            return SizedBox(
              height: calculatedHeight,
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _currentUpdates.length,
                itemBuilder: (context, index) {
                  return _buildCardContent(_currentUpdates[index], index);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCardContent(UpdateModel update, int cardIndex) {
    final formattedTime = DateFormat('h:mm a').format(update.createdAt.toLocal());
    final isSender = update.senderId == widget.currentUserId;
    final hasReply = update.replyText != null && update.replyText!.trim().isNotEmpty;
    final isSendingReply = _sendingReplyIndices.contains(cardIndex);
    final replyTime = update.replyCreatedAt != null
        ? DateFormat('h:mm a').format(update.replyCreatedAt!.toLocal())
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FullscreenMomentsViewerScreen(
                moments: _currentUpdates,
                initialIndex: cardIndex,
                currentUserId: widget.currentUserId,
              ),
            ),
          ).then((updatedList) {
            // Re-sync local reaction & reply updates if sent in fullscreen
            if (updatedList is List<UpdateModel> && mounted) {
              setState(() {
                _currentUpdates = updatedList;
              });
              widget.onUpdatesChanged?.call(List.from(_currentUpdates));
            } else if (mounted) {
              setState(() {});
            }
          });
        },
        onDoubleTap: isSender ? null : () => _toggleHeart(cardIndex),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Moment Image (Memory-safe downsampled decode)
            update.isLocalImage
                ? Image.file(
                    File(update.imageUrl),
                    fit: BoxFit.cover,
                    cacheWidth: 720,
                    cacheHeight: 960,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.secondarySurface,
                      child: const Center(
                        child: Text(
                          'Local image not found',
                          style: TextStyle(color: AppColors.supportingText, fontSize: 13),
                        ),
                      ),
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: update.imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 720,
                    memCacheHeight: 960,
                    placeholder: (context, url) => Container(
                      color: AppColors.secondarySurface,
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryAccent,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: AppColors.secondarySurface,
                      child: const Center(
                        child: Text(
                          'Unable to load moment',
                          style: TextStyle(color: AppColors.supportingText, fontSize: 13),
                        ),
                      ),
                    ),
                  ),

            // Top Subtle Vignette for Badge & Story Bar Legibility
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 100,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Left & Right Tap Zones (Instagram Story style navigation)
            if (_currentUpdates.length > 1) ...[
              // Left Tap Zone (Previous moment)
              Positioned(
                top: 70,
                bottom: 120,
                left: 0,
                width: 80,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_pageController.hasClients && _currentPageIndex > 0) {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                ),
              ),
              // Right Tap Zone (Next moment)
              Positioned(
                top: 70,
                bottom: 120,
                right: 0,
                width: 80,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_pageController.hasClients && _currentPageIndex < _currentUpdates.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                ),
              ),
            ],

            // Story Progress Dashes (Top Edge, synchronized with active page)
            if (_currentUpdates.length > 1)
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  children: List.generate(_currentUpdates.length, (index) {
                    final isActive = index == _currentPageIndex;
                    final isPast = index < _currentPageIndex;
                    return Expanded(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        decoration: BoxDecoration(
                          color: isPast
                              ? Colors.white.withValues(alpha: 0.85)
                              : (isActive ? Colors.white : Colors.white.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Top Badges: Location & TODAY (Clean pill badges, zero stroke borders)
            Positioned(
              top: _currentUpdates.length > 1 ? 26 : 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Location Only
                  if (update.locationName != null && update.locationName!.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        update.locationName!.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textHighContrast,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  // Top-Right Badge: Reply → Sending → TODAY (smooth crossfade)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: (!isSender && !hasReply && !isSendingReply)
                        ? GestureDetector(
                            key: const ValueKey('reply_badge'),
                            onTap: () async {
                              HapticFeedback.lightImpact();
                              final reply = await ReplyMomentModal.show(context, partnerName: 'Partner');
                              if (reply != null && reply.isNotEmpty && mounted) {
                                final replyCreatedAt = DateTime.now();

                                // 1. Immediate Offline UI Reflection: render reply instantly
                                final pendingReplyModel = update.copyWith(
                                  replyText: reply,
                                  replyCreatedAt: replyCreatedAt,
                                  isReplied: true,
                                  isPendingReply: true,
                                );
                                setState(() {
                                  _currentUpdates[cardIndex] = pendingReplyModel;
                                  _sendingReplyIndices.add(cardIndex);
                                });
                                widget.onUpdatesChanged?.call(List.from(_currentUpdates));

                                // 2. Persist to Disk (daily_cache & reply_outbox)
                                final cacheService = DailyMomentsCacheService();
                                await cacheService.updateMomentReply(
                                  type: isSender ? 'sent' : 'received',
                                  updateId: update.id,
                                  replyText: reply,
                                  replyCreatedAt: replyCreatedAt,
                                  isPendingReply: true,
                                );
                                await ReplyOutboxService().enqueue(
                                  updateId: update.id,
                                  replyText: reply,
                                  replyCreatedAt: replyCreatedAt,
                                );

                                // Reflect pending reply on homescreen widget immediately (offline-first)
                                if (!isSender) {
                                  WidgetSyncService().syncMomentsListToWidget(
                                    moments: _currentUpdates,
                                    userId: widget.currentUserId,
                                  );
                                }

                                // 3. Attempt immediate delivery if online
                                final success = await _updateService.sendReply(
                                  updateId: update.id,
                                  replyText: reply,
                                  replyCreatedAt: replyCreatedAt,
                                );

                                if (!mounted) return;

                                setState(() {
                                  _sendingReplyIndices.remove(cardIndex);
                                });

                                if (success) {
                                  // Synced to cloud! Remove from outbox and mark isPendingReply=false
                                  await ReplyOutboxService().removeItem(update.id);
                                  await cacheService.updateMomentReply(
                                    type: isSender ? 'sent' : 'received',
                                    updateId: update.id,
                                    replyText: reply,
                                    replyCreatedAt: replyCreatedAt,
                                    isPendingReply: false,
                                  );

                                  if (mounted) {
                                    setState(() {
                                      _currentUpdates[cardIndex] = pendingReplyModel.copyWith(
                                        isPendingReply: false,
                                      );
                                    });
                                    widget.onUpdatesChanged?.call(List.from(_currentUpdates));
                                    // Instant sync confirmed reply to homescreen widget
                                    if (!isSender) {
                                      WidgetSyncService().syncMomentsListToWidget(
                                        moments: _currentUpdates,
                                        userId: widget.currentUserId,
                                      );
                                    }
                                  }
                                } else {
                                  // Offline / network failure: RETAIN reply in UI & cache!
                                  debugPrint('[DailyMomentsStackDeck] Offline/failed delivery for reply. Retained in local outbox queue! 📦');
                                }
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2622).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primaryAccent.withValues(alpha: 0.5),
                                  width: 1,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
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
                          )
                        : Container(
                            key: ValueKey(isSendingReply
                                ? 'sending_badge'
                                : (hasReply && isSender ? 'replied_badge' : 'today_badge')),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                              border: (hasReply && isSender)
                                  ? Border.all(
                                      color: AppColors.primaryAccent.withValues(alpha: 0.4),
                                      width: 1,
                                    )
                                  : null,
                            ),
                            child: Text(
                              isSendingReply
                                  ? 'SENDING...'
                                  : (hasReply && isSender ? 'REPLIED' : 'TODAY'),
                              style: TextStyle(
                                color: isSendingReply || (hasReply && isSender)
                                    ? AppColors.primaryAccent
                                    : AppColors.textHighContrast,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Bottom Cinematic Gradient Scrim (No box container, pure photography feel)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 220,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      const Color(0xFF141A17).withValues(alpha: 0.95),
                      const Color(0xFF141A17).withValues(alpha: 0.75),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // Bottom Prominent Caption & Intimate Note
            Positioned(
              bottom: 22,
              left: 20,
              right: 80, // Generous breathing room for floating heart
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Refined Compact Caption (smaller size for unobstructed photo viewing)
                  if (update.caption != null && update.caption!.trim().isNotEmpty) ...[
                    Text(
                      update.caption!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textHighContrast,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.1,
                        height: 1.3,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 6,
                            offset: Offset(0, 1.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],

                  // Reply Area: Real text or pending sync state (with sync icon/indicator)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: hasReply
                        ? Padding(
                            key: ValueKey('reply_${update.id}_${update.isPendingReply}'),
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
                                          text: isSender ? 'Partner: ' : 'You: ',
                                          style: TextStyle(
                                            color: update.isPendingReply
                                                ? const Color(0xFFE5A93C)
                                                : AppColors.primaryAccent,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                        TextSpan(
                                          text: update.replyText!,
                                          style: const TextStyle(
                                            color: AppColors.textHighContrast,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w400,
                                            height: 1.25,
                                          ),
                                        ),
                                        if (replyTime != null)
                                          TextSpan(
                                            text: update.isPendingReply
                                                ? ' • Syncing...'
                                                : ' • $replyTime',
                                            style: TextStyle(
                                              color: update.isPendingReply
                                                  ? const Color(0xFFE5A93C).withValues(alpha: 0.9)
                                                  : AppColors.supportingText.withValues(alpha: 0.8),
                                              fontSize: 10.5,
                                              fontWeight: update.isPendingReply
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (update.isPendingReply) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.sync_rounded,
                                    size: 14,
                                    color: const Color(0xFFE5A93C).withValues(alpha: 0.9),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('reply_empty')),
                  ),

                  // Single clean time metadata at the bottom
                  Row(
                    children: [
                      Text(
                        update.isPending
                            ? 'Saved $formattedTime (Syncing...)'
                            : (isSender ? 'Sent $formattedTime' : 'Received $formattedTime'),
                        style: TextStyle(
                          color: update.isPending
                              ? const Color(0xFFE5A93C)
                              : AppColors.supportingText.withValues(alpha: 0.85),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: update.isPending
                              ? const Color(0xFFE5A93C)
                              : AppColors.primaryAccent.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Floating Heart Reaction on Bottom-Right
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: isSender ? null : () => _toggleHeart(cardIndex),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.transparent,
                  child: Center(
                    child: Icon(
                      update.isReacted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: update.isReacted
                          ? const Color(0xFFFF5252)
                          : AppColors.textHighContrast.withValues(alpha: 0.85),
                      size: 28,
                      shadows: const [
                        Shadow(
                          color: Colors.black45,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
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
