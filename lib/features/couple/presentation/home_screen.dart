import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../../auth/data/auth_service.dart';
import 'views/paired_home_view.dart';
import 'views/unpaired_pairing_view.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _handleSignOut(BuildContext context) async {
    await AuthService().signOut();
    if (context.mounted) {
      AppToast.info(context, 'You have been signed out.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserModel?>(
      valueListenable: AuthService().currentUserNotifier,
      builder: (context, user, _) {
        if (user == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryAccent),
            ),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Minimalist Top Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 14.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Branding Title
                      const Text(
                        'UPDATEME',
                        style: TextStyle(
                          color: AppColors.textHighContrast,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                        ),
                      ),

                      // Sign Out Trigger (Clean minimalist outlined button)
                      GestureDetector(
                        onTap: () => _handleSignOut(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.secondarySurface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.supportingText.withValues(alpha: 0.25),
                            ),
                          ),
                          child: const Text(
                            'Sign Out',
                            style: TextStyle(
                              color: AppColors.supportingText,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0x1AFFFFFF),
                ),

                // Main Content View (Switches automatically based on user.isPaired)
                Expanded(
                  child: user.isPaired
                      ? PairedHomeView(user: user)
                      : UnpairedPairingView(user: user),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
