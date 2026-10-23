import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_service.dart';
import '../../../updates/presentation/modals/send_update_modal.dart';

class PairedHomeView extends StatefulWidget {
  final UserModel user;

  const PairedHomeView({
    super.key,
    required this.user,
  });

  @override
  State<PairedHomeView> createState() => _PairedHomeViewState();
}

class _PairedHomeViewState extends State<PairedHomeView> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isOpeningCamera = false;

  Future<void> _captureAndSendUpdate() async {
    if (_isOpeningCamera) return;

    try {
      setState(() => _isOpeningCamera = true);

      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );

      if (photo != null && mounted) {
        SendUpdateModal.show(
          context: context,
          initialImage: File(photo.path),
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Unable to open camera: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isOpeningCamera = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partnerName = widget.user.partner?['display_name'] ?? widget.user.partner?['email'] ?? 'Your Partner';

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

          // Sending widget update photo
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
                    onPressed: _isOpeningCamera ? null : _captureAndSendUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: AppColors.textHighContrast,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isOpeningCamera
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textHighContrast,
                            ),
                          )
                        : const Text(
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
