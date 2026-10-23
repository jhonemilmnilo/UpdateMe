import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoadingGoogle = false;
  bool _isLoadingFacebook = false;
  String? _errorMessage;

  Future<void> _signInWithProvider(OAuthProvider provider) async {
    setState(() {
      if (provider == OAuthProvider.google) _isLoadingGoogle = true;
      if (provider == OAuthProvider.facebook) _isLoadingFacebook = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signInWithOAuth(
        provider,
        redirectTo: 'io.supabase.updateme://login-callback',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingGoogle = false;
          _isLoadingFacebook = false;
          _errorMessage = 'Unable to connect. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isLoadingGoogle || _isLoadingFacebook;

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
                  onPressed: isBusy ? null : () => _signInWithProvider(OAuthProvider.google),
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

              const SizedBox(height: 12),

              // Secondary Action: Continue with Facebook (Minimalist border, No Icons)
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: isBusy ? null : () => _signInWithProvider(OAuthProvider.facebook),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textHighContrast,
                    side: BorderSide(
                      color: AppColors.supportingText.withValues(alpha: 0.35),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isLoadingFacebook
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textHighContrast,
                          ),
                        )
                      : const Text(
                          'Continue with Facebook',
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
