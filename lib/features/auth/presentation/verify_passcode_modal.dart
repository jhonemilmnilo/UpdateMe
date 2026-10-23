import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_service.dart';

class VerifyPasscodeModal extends StatefulWidget {
  final UserModel user;

  const VerifyPasscodeModal({
    super.key,
    required this.user,
  });

  static Future<bool?> show(BuildContext context, {required UserModel user}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => VerifyPasscodeModal(user: user),
    );
  }

  @override
  State<VerifyPasscodeModal> createState() => _VerifyPasscodeModalState();
}

class _VerifyPasscodeModalState extends State<VerifyPasscodeModal> {
  final TextEditingController _passcodeController = TextEditingController();
  bool _obscurePasscode = true;
  bool _isLoading = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _passcodeController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    if (_serverError != null) {
      setState(() => _serverError = null);
    }
  }

  @override
  void dispose() {
    _passcodeController.removeListener(_onInputChanged);
    _passcodeController.dispose();
    super.dispose();
  }

  bool get _isLengthValid {
    final len = _passcodeController.text.trim().length;
    return len >= 4 && len <= 8;
  }

  Future<void> _handleSubmit() async {
    final passcode = _passcodeController.text.trim();

    if (!_isLengthValid) {
      setState(() => _serverError = 'Passcode must be between 4 and 8 digits.');
      return;
    }

    setState(() {
      _isLoading = true;
      _serverError = null;
    });

    try {
      await AuthService().verifyMasterPasscode(
        userId: widget.user.id,
        password: passcode,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _serverError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final passcodeLen = _passcodeController.text.trim().length;

    // Small persistent note below input
    String? validationNote;
    if (passcodeLen > 0 && passcodeLen < 4) {
      validationNote = 'Passcode must be between 4 and 8 digits';
    } else if (passcodeLen == 0) {
      validationNote = 'Enter your 4 to 8 digit passcode';
    }

    return Container(
      padding: EdgeInsets.only(
        top: 24,
        left: 28,
        right: 28,
        bottom: bottomInset + 32,
      ),
      decoration: const BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag indicator line
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.supportingText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Header
          const Center(
            child: Text(
              'Enter your passcode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textHighContrast,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(height: 8),

          const Center(
            child: Text(
              'Verify your passcode to access your shared moments.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.supportingText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Label: Passcode
          const Text(
            'PASSCODE',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Field: Passcode
          TextField(
            controller: _passcodeController,
            obscureText: _obscurePasscode,
            keyboardType: TextInputType.number,
            autofocus: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            style: TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 18,
              letterSpacing: _obscurePasscode ? 6 : 2,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: '••••',
              hintStyle: const TextStyle(
                color: AppColors.supportingText,
                letterSpacing: 6,
              ),
              filled: true,
              fillColor: AppColors.background.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePasscode = !_obscurePasscode),
                icon: Icon(
                  _obscurePasscode ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: AppColors.supportingText,
                  size: 20,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.supportingText.withValues(alpha: 0.25),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: AppColors.supportingText.withValues(alpha: 0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primaryAccent,
                  width: 1.5,
                ),
              ),
            ),
          ),

          // Persistent small note below input
          if (validationNote != null) ...[
            const SizedBox(height: 12),
            Text(
              validationNote,
              style: TextStyle(
                color: passcodeLen > 0 && passcodeLen < 4
                    ? const Color(0xFFEF9A9A) // Red warning if < 4
                    : AppColors.supportingText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          // Server Error Message if any
          if (_serverError != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text(
                _serverError!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFEF9A9A),
                  fontSize: 13,
                ),
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLengthValid && !_isLoading ? _handleSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.textHighContrast,
                disabledBackgroundColor: AppColors.primaryAccent.withValues(alpha: 0.35),
                disabledForegroundColor: AppColors.textHighContrast.withValues(alpha: 0.4),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textHighContrast,
                      ),
                    )
                  : const Text(
                      'Unlock Space',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
