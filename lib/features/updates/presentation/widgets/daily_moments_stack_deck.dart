import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/update_model.dart';
import '../../data/update_service.dart';

class DailyMomentsStackDeck extends StatefulWidget {
  final List<UpdateModel> updates;
  final String emptyMessage;

  const DailyMomentsStackDeck({
    super.key,
    required this.updates,
    required this.emptyMessage,
  });

  @override
  State<DailyMomentsStackDeck> createState() => _DailyMomentsStackDeckState();
}

class _DailyMomentsStackDeckState extends State<DailyMomentsStackDeck> {
  final UpdateService _updateService = UpdateService();
  late PageController _pageController;
  late List<UpdateModel> _currentUpdates;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentUpdates = List.from(widget.updates);
    _pageController = PageController(initialPage: 0);
  }

  @override
  void didUpdateWidget(covariant DailyMomentsStackDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      _currentUpdates = List.from(widget.updates);
      if (_currentPageIndex >= _currentUpdates.length) {
        _currentPageIndex = (_currentUpdates.length - 1).clamp(0, _currentUpdates.length);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentPageIndex);
        }
      }
    }
  }

  Future<void> _toggleHeart(int index) async {
    if (index >= _currentUpdates.length) return;

    HapticFeedback.mediumImpact();
    final item = _currentUpdates[index];
    final newReactionState = !item.isReacted;

    // Optimistic UI update
    setState(() {
      _currentUpdates[index] = item.copyWith(isReacted: newReactionState);
    });

    final success = await _updateService.toggleReaction(
      updateId: item.id,
      isReacted: newReactionState,
    );

    // Rollback if failed
    if (!success && mounted) {
      setState(() {
        _currentUpdates[index] = item;
      });
    }
  }

  @override
  void dispose() {
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
    // Format to user's device local time (already UTC+8 in PH)
    final formattedTime = DateFormat('h:mm a').format(update.createdAt.toLocal());

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: GestureDetector(
        onDoubleTap: () => _toggleHeart(cardIndex),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Moment Image
            CachedNetworkImage(
              imageUrl: update.imageUrl,
              fit: BoxFit.cover,
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

                  // "TODAY" Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'TODAY',
                      style: TextStyle(
                        color: AppColors.textHighContrast,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
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
              right: 80, // Leave generous room for floating heart button
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prominent Large Editorial Caption
                  if (update.caption != null && update.caption!.trim().isNotEmpty) ...[
                    Text(
                      update.caption!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textHighContrast,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        height: 1.25,
                        shadows: [
                          Shadow(
                            color: Colors.black45,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Single clean time metadata at the bottom
                  Row(
                    children: [
                      Text(
                        'Received $formattedTime',
                        style: TextStyle(
                          color: AppColors.supportingText.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryAccent.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Floating Heart Reaction Button (Exact position & style from flutter_01.png)
            Positioned(
              bottom: 20,
              right: 20,
              child: GestureDetector(
                onTap: () => _toggleHeart(cardIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: update.isReacted
                        ? const Color(0xFF1E2622).withValues(alpha: 0.95)
                        : const Color(0xFF1E2622).withValues(alpha: 0.75),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      update.isReacted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: update.isReacted ? const Color(0xFFFF5252) : AppColors.textHighContrast,
                      size: 26,
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
