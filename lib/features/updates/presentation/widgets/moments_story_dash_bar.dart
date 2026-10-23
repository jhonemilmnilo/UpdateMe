import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class MomentsStoryDashBar extends StatelessWidget {
  final int totalCount;
  final int currentIndex;

  const MomentsStoryDashBar({
    super.key,
    required this.totalCount,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 1) return const SizedBox.shrink();

    return Row(
      children: List.generate(totalCount, (index) {
        final isCompletedOrActive = index <= currentIndex;
        final isActive = index == currentIndex;

        return Expanded(
          child: Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isCompletedOrActive
                  ? (isActive ? AppColors.textHighContrast : AppColors.textHighContrast.withValues(alpha: 0.6))
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
