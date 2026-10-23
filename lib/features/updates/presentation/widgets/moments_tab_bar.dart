import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class MomentsTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const MomentsTabBar({
    super.key,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildPillButton(
          title: 'From Partner',
          isSelected: selectedIndex == 0,
          onTap: () => onTabSelected(0),
        ),
        const SizedBox(width: 10),
        _buildPillButton(
          title: 'Sent Moments',
          isSelected: selectedIndex == 1,
          onTap: () => onTabSelected(1),
        ),
      ],
    );
  }

  Widget _buildPillButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryAccent : AppColors.secondarySurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryAccent
                : AppColors.supportingText.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? AppColors.textHighContrast
                : AppColors.supportingText,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
