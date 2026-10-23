import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/auth_service.dart';
import 'create_passcode_modal.dart';
import 'verify_passcode_modal.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoadingGoogle = false;
  String? _errorMessage;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoadingGoogle = true;
      _errorMessage = null;
    });

    try {
      final user = await _authService.signInWithGoogle();

      if (!mounted) return;
      setState(() => _isLoadingGoogle = false);

      // Clean separated modal flow:
      // If havePassword is false -> Open dedicated CreatePasscodeModal
      // If havePassword is true -> Open dedicated VerifyPasscodeModal
      final bool? success;
      if (!user.havePassword) {
        success = await CreatePasscodeModal.show(context, user: user);
      } else {
        success = await VerifyPasscodeModal.show(context, user: user);
      }

      if (success == true) {
        if (mounted) {
          AppToast.success(context, 'You have successfully signed in.');
        }
      } else {
        if (mounted) {
          AppToast.info(context, 'Sign in was canceled.');
        }
      }
    } catch (e, stack) {
      debugPrint('[GoogleSignIn Error]: $e');
      debugPrint('[GoogleSignIn Stack]: $stack');
      if (mounted) {
        setState(() {
          _isLoadingGoogle = false;
          final errorStr = e.toString();
          if (errorStr.contains('aborted') || errorStr.contains('cancelled') || errorStr.contains('canceled')) {
            _errorMessage = null;
          } else {
            _errorMessage = errorStr.replaceAll('Exception: ', '');
            AppToast.error(context, _errorMessage!);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isLoadingGoogle;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // Centered Main Headlines
              const Text(
                'Stay close,\nwherever you are.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textHighContrast,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  height: 1.25,
                ),
              ),

              const SizedBox(height: 16),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  'Share moments throughout your day, right on each other’s home screen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.supportingText,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Error notification if any (Pure typography, no card)
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFEF9A9A),
                      fontSize: 13,
                    ),
                  ),
                ),

              // Primary Action: Continue with Google (Centered, No Icons)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: AppColors.textHighContrast,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoadingGoogle
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textHighContrast,
                          ),
                        )
                      : const Text(
                          'Continue with Google',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                ),
              ),

              const Spacer(flex: 3),

              // Footer Note
              const Text(
                'A private space made only for the two of you.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.supportingText,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
