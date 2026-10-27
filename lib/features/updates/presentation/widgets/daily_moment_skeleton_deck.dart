import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class DailyMomentSkeletonDeck extends StatefulWidget {
  const DailyMomentSkeletonDeck({super.key});

  @override
  State<DailyMomentSkeletonDeck> createState() =>
      _DailyMomentSkeletonDeckState();
}

class _DailyMomentSkeletonDeckState extends State<DailyMomentSkeletonDeck>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    required double borderRadius,
    required double animationValue,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment(-1.5 + (animationValue * 3.0), -0.3),
          end: Alignment(0.5 + (animationValue * 3.0), 0.3),
          colors: const [
            Color(0xFF1E2622),
            Color(0xFF2C3831),
            Color(0xFF1E2622),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, child) {
          final anim = _shimmerController.value;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Counter Header Skeleton Placeholder
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: _buildShimmerBox(
                width: 64,
                height: 14,
                borderRadius: 4,
                animationValue: anim,
              ),
            ),

            // Card Skeleton Frame
            LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final calculatedHeight = (constraints.maxWidth * 1.25)
                    .clamp(400.0, screenHeight * 0.62);

                return Container(
                  height: calculatedHeight,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF141A17),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Stack(
                      children: [
                        // Sweeping Full Background Shimmer
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment(
                                    -1.5 + (anim * 3.0), -0.3),
                                end: Alignment(
                                    0.5 + (anim * 3.0), 0.3),
                                colors: const [
                                  Color(0xFF18201C),
                                  Color(0xFF26322B),
                                  Color(0xFF18201C),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Top Badges Placeholder
                        Positioned(
                          top: 18,
                          left: 18,
                          right: 18,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Location Pill Placeholder
                              _buildShimmerBox(
                                width: 110,
                                height: 26,
                                borderRadius: 13,
                                animationValue: anim,
                              ),
                              // "TODAY" Badge Placeholder
                              _buildShimmerBox(
                                width: 68,
                                height: 26,
                                borderRadius: 13,
                                animationValue: anim,
                              ),
                            ],
                          ),
                        ),

                        // Bottom Gradient Scrim
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 180,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.8),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Bottom Caption & Time Metadata Placeholders
                        Positioned(
                          bottom: 24,
                          left: 20,
                          right: 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Caption line 1
                              _buildShimmerBox(
                                width: double.infinity,
                                height: 16,
                                borderRadius: 4,
                                animationValue: anim,
                              ),
                              const SizedBox(height: 8),
                              // Caption line 2 (shorter)
                              _buildShimmerBox(
                                width: 140,
                                height: 14,
                                borderRadius: 4,
                                animationValue: anim,
                              ),
                              const SizedBox(height: 12),
                              // Time indicator
                              Row(
                                children: [
                                  _buildShimmerBox(
                                    width: 90,
                                    height: 12,
                                    borderRadius: 3,
                                    animationValue: anim,
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.primaryAccent
                                          .withValues(alpha: 0.4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Floating Heart Button Placeholder
                        Positioned(
                          bottom: 22,
                          right: 20,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E2622)
                                  .withValues(alpha: 0.75),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.favorite_rounded,
                                size: 22,
                                color: AppColors.supportingText
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    ),
  );
}
}
