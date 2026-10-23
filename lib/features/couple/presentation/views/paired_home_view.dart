import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_service.dart';

class PairedHomeView extends StatelessWidget {
  final UserModel user;

  const PairedHomeView({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final partnerName = user.partner?['display_name'] ?? user.partner?['email'] ?? 'Your Partner';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          // Connection Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF81C784).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'CONNECTED',
              style: TextStyle(
                color: Color(0xFF81C784),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 12),

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
          const SizedBox(height: 8),

          const Text(
            'Your home screen widgets are actively linked. Ready to send moments.',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const Spacer(),

          // Placeholder for sending widget update photo (Next Feature!)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.secondarySurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.supportingText.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SEND UPDATE TO WIDGET',
                  style: TextStyle(
                    color: AppColors.supportingText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Capture a photo with your live location badge and instant caption.',
                  style: TextStyle(
                    color: AppColors.textHighContrast,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      // Will connect to Photo Capture flow
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: AppColors.textHighContrast,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Take a Photo',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
