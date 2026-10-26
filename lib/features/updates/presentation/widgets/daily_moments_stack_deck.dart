import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/update_model.dart';

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
  int _topCardIndex = 0;

  @override
  void didUpdateWidget(covariant DailyMomentsStackDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.updates != widget.updates) {
      _topCardIndex = 0;
    }
  }

  void _undoPreviousCard() {
    if (_topCardIndex > 0) {
      setState(() {
        _topCardIndex--;
      });
    }
  }

  void _dismissCurrentCard() {
    if (_topCardIndex < widget.updates.length) {
      setState(() {
        _topCardIndex++;
      });
    }
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

    final remainingCount = widget.updates.length - _topCardIndex;

    // When all cards have been swiped away
    if (remainingCount <= 0) {
      return SizedBox(
        height: 360,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'You’ve viewed all moments for today.',
                style: TextStyle(
                  color: AppColors.supportingText,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => setState(() => _topCardIndex = 0),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textHighContrast,
                  side: BorderSide(
                    color: AppColors.supportingText.withValues(alpha: 0.35),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Start from First Photo'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Counter & Undo Return Button Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${_topCardIndex + 1} of ${widget.updates.length}',
              style: const TextStyle(
                color: AppColors.supportingText,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),

            // Undo / Return Previous Card Button
            if (_topCardIndex > 0)
              GestureDetector(
                onTap: _undoPreviousCard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.secondarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.supportingText.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.replay_rounded,
                        color: AppColors.textHighContrast,
                        size: 15,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Previous',
                        style: TextStyle(
                          color: AppColors.textHighContrast,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const SizedBox.shrink(),
          ],
        ),
        const SizedBox(height: 10),

        // Stacked Card Deck Area with Sleek Modern Squircles (Responsive Layout)
        LayoutBuilder(
          builder: (context, constraints) {
            // Responsive height: Maintain a lush 4:5 aspect ratio or clamp gracefully between 420dp and 560dp
            final screenHeight = MediaQuery.of(context).size.height;
            final calculatedHeight = (constraints.maxWidth * 1.25).clamp(400.0, screenHeight * 0.62);

            return SizedBox(
              height: calculatedHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 3rd Card in Background (flat, subtle peek)
                  if (_topCardIndex + 2 < widget.updates.length)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      bottom: 0,
                      child: _buildStaticCard(widget.updates[_topCardIndex + 2], opacity: 0.45),
                    ),

                  // 2nd Card in Middle (flat, subtle peek)
                  if (_topCardIndex + 1 < widget.updates.length)
                    Positioned(
                      top: 6,
                      left: 6,
                      right: 6,
                      bottom: 0,
                      child: _buildStaticCard(widget.updates[_topCardIndex + 1], opacity: 0.75),
                    ),

                  // Top Card: Dismissible only if NOT the last photo
                  Positioned.fill(
                    child: _topCardIndex < widget.updates.length - 1
                        ? Dismissible(
                            key: Key(widget.updates[_topCardIndex].id),
                            direction: DismissDirection.horizontal,
                            onDismissed: (direction) {
                              _dismissCurrentCard();
                            },
                            child: _buildCardContent(widget.updates[_topCardIndex]),
                          )
                        : _buildCardContent(widget.updates[_topCardIndex]),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStaticCard(UpdateModel update, {required double opacity}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondarySurface.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Opacity(
          opacity: opacity,
          child: CachedNetworkImage(
            imageUrl: update.imageUrl,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildCardContent(UpdateModel update) {
    // Format to user's device local time (already UTC+8 in PH)
    final formattedTime = DateFormat('h:mm a').format(update.createdAt.toLocal());

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
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

            // Story Progress Dashes (Top Edge)
            if (widget.updates.length > 1)
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  children: List.generate(widget.updates.length, (index) {
                    final isActive = index == _topCardIndex;
                    final isPast = index < _topCardIndex;
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

            // Top Badges: Location & TODAY (No duplicate time here)
            Positioned(
              top: widget.updates.length > 1 ? 26 : 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Location Only (clean and concise, no time clutter)
                  if (update.locationName != null && update.locationName!.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 0.8,
                        ),
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
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
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
              right: 20,
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Received $formattedTime',
                        style: TextStyle(
                          color: AppColors.supportingText.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
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
          ],
        ),
      ),
    );
  }
}
