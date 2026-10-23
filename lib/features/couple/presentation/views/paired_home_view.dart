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
      padding: const EdgeInsets.only(left: 28.0, right: 28.0, top: 8.0, bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paired with\n$partnerName',
            style: const TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),

          const Text(
            'Your home screen widgets are actively linked. Ready to send moments.',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const Spacer(),

          // Minimalist Floating Camera Action Button (Bottom-Right, 78x78 Flagship)
          Align(
            alignment: Alignment.bottomRight,
            child: GestureDetector(
              onTap: _isOpeningCamera ? null : _captureAndSendUpdate,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryAccent,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.secondarySurface,
                    width: 4,
                  ),
                ),
                child: Center(
                  child: _isOpeningCamera
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.textHighContrast,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt_rounded,
                          color: AppColors.textHighContrast,
                          size: 38,
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
