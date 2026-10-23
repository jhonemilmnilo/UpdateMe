import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../data/auth_service.dart';

class CreatePasscodeModal extends StatefulWidget {
  final UserModel user;

  const CreatePasscodeModal({
    super.key,
    required this.user,
  });

  static Future<bool?> show(BuildContext context, {required UserModel user}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CreatePasscodeModal(user: user),
    );
  }

  @override
  State<CreatePasscodeModal> createState() => _CreatePasscodeModalState();
}

class _CreatePasscodeModalState extends State<CreatePasscodeModal> {
  final TextEditingController _passcodeController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _obscurePasscode = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _passcodeController.addListener(_onInputChanged);
    _confirmController.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    setState(() {
      _serverError = null;
    });
  }

  @override
  void dispose() {
    _passcodeController.removeListener(_onInputChanged);
    _confirmController.removeListener(_onInputChanged);
    _passcodeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // Real-time validation checks
  bool get _isLengthValid {
    final len = _passcodeController.text.trim().length;
    return len >= 4 && len <= 8;
  }

  bool get _isMatchValid {
    final passcode = _passcodeController.text.trim();
    final confirm = _confirmController.text.trim();
    if (confirm.isEmpty) return true; // Don't flag until user starts typing confirm
    return passcode == confirm;
  }

  bool get _canSubmit {
    final passcode = _passcodeController.text.trim();
    final confirm = _confirmController.text.trim();
    return _isLengthValid && confirm.isNotEmpty && passcode == confirm && !_isLoading;
  }

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _serverError = null;
    });

    try {
      await AuthService().setMasterPasscode(
        userId: widget.user.id,
        password: _passcodeController.text.trim(),
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
    final confirmText = _confirmController.text.trim();

    // Persistent conditional validation note
    String? validationNote;
    if (passcodeLen > 0 && passcodeLen < 4) {
      validationNote = 'Passcode must be between 4 and 8 digits';
    } else if (confirmText.isNotEmpty && !_isMatchValid) {
      validationNote = 'Passcodes do not match';
    } else if (passcodeLen == 0) {
      validationNote = 'Minimum of 4 digits required (maximum 8 digits)';
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
              'Create a passcode',
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
              'Set a private passcode to secure your shared space.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.supportingText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Label: New Passcode
          const Text(
            'NEW PASSCODE',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Field: New Passcode
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

          const SizedBox(height: 20),

          // Label: Confirm Passcode
          const Text(
            'CONFIRM PASSCODE',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Field: Confirm Passcode
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            style: TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 18,
              letterSpacing: _obscureConfirm ? 6 : 2,
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
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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
                color: (passcodeLen > 0 && passcodeLen < 4) || (confirmText.isNotEmpty && !_isMatchValid)
                    ? const Color(0xFFEF9A9A) // Subtle red warning
                    : AppColors.supportingText, // Calm helper text when empty
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],

          // Server error if any
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
              onPressed: _canSubmit ? _handleSubmit : null,
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
                      'Set Passcode',
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
