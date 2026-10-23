import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/update_model.dart';
import 'moments_story_dash_bar.dart';

class DailyMomentsCarousel extends StatefulWidget {
  final List<UpdateModel> updates;
  final String emptyMessage;

  const DailyMomentsCarousel({
    super.key,
    required this.updates,
    required this.emptyMessage,
  });

  @override
  State<DailyMomentsCarousel> createState() => _DailyMomentsCarouselState();
}

class _DailyMomentsCarouselState extends State<DailyMomentsCarousel> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToNext() {
    if (_currentIndex < widget.updates.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.updates.isEmpty) {
      return Container(
        height: 280,
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
      children: [
        // Story Dash Indicators
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: MomentsStoryDashBar(
            totalCount: widget.updates.length,
            currentIndex: _currentIndex,
          ),
        ),
        const SizedBox(height: 6),

        // Carousel Container
        SizedBox(
          height: 340,
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.updates.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final update = widget.updates[index];
              final timeString = DateFormat('h:mm a').format(update.createdAt.toLocal());

              return ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Main Image
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

                    // Top Badges Overlay: Location (Left) & Time (Right)
                    Positioned(
                      top: 14,
                      left: 14,
                      right: 14,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (update.locationName != null && update.locationName!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E2622).withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                update.locationName!,
                                style: const TextStyle(
                                  color: AppColors.textHighContrast,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          else
                            const SizedBox.shrink(),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E2622).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              timeString,
                              style: const TextStyle(
                                color: AppColors.textHighContrast,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Caption Overlay (Frosted pill)
                    if (update.caption != null && update.caption!.trim().isNotEmpty)
                      Positioned(
                        bottom: 14,
                        left: 14,
                        right: 14,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E2622).withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            update.caption!,
                            style: const TextStyle(
                              color: AppColors.textHighContrast,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),

                    // Left & Right Dedicated Return / Advance Floating Nav Buttons
                    if (widget.updates.length > 1) ...[
                      // Previous Return Button (Left)
                      if (_currentIndex > 0)
                        Positioned(
                          left: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: _goToPrevious,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.chevron_left_rounded,
                                    color: AppColors.textHighContrast,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // Next Advance Button (Right)
                      if (_currentIndex < widget.updates.length - 1)
                        Positioned(
                          right: 12,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: _goToNext,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2622).withValues(alpha: 0.75),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppColors.textHighContrast,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
