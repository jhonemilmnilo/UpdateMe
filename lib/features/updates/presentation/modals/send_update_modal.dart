import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/outbox_service.dart';
import '../../data/sync_engine.dart';
import '../../data/update_service.dart';

class SendUpdateModal extends StatefulWidget {
  final File initialImage;
  final VoidCallback? onUpdateSent;

  const SendUpdateModal({
    super.key,
    required this.initialImage,
    this.onUpdateSent,
  });

  static Future<void> show({
    required BuildContext context,
    required File initialImage,
    VoidCallback? onUpdateSent,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SendUpdateModal(
        initialImage: initialImage,
        onUpdateSent: onUpdateSent,
      ),
    );
  }

  @override
  State<SendUpdateModal> createState() => _SendUpdateModalState();
}

class _SendUpdateModalState extends State<SendUpdateModal> {
  late File _currentImage;
  final TextEditingController _captionController = TextEditingController();
  final UpdateService _updateService = UpdateService();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSending = false;
  bool _isLoadingLocation = true;
  String? _detectedLocation;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _currentImage = widget.initialImage;
    _detectLocation();
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _detectLocation() async {
    final loc = await _updateService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _isLoadingLocation = false;
        if (loc != null) {
          _detectedLocation = loc['location_name'] as String?;
          _latitude = loc['latitude'] as double?;
          _longitude = loc['longitude'] as double?;
        }
      });
    }
  }

  Future<void> _retakePhoto() async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 80,
    );
    if (photo != null && mounted) {
      setState(() {
        _currentImage = File(photo.path);
      });
    }
  }

  Future<void> _handleSend() async {
    if (_isSending) return;

    final currentUser = AuthService().currentUser;
    if (currentUser == null) {
      AppToast.error(context, 'User session not found.');
      return;
    }

    setState(() => _isSending = true);

    try {
      final now = DateTime.now();
      // Generate standard RFC 4122 UUID v4 matching PostgreSQL UUID type
      final updateId = OutboxService.newUuid();

      // 1. Instantly save to local outbox (captures exact local time)
      await OutboxService().enqueue(
        id: updateId,
        senderId: currentUser.id,
        originalImageFile: _currentImage,
        caption: _captionController.text.trim().isNotEmpty
            ? _captionController.text.trim()
            : null,
        locationName: _detectedLocation,
        latitude: _latitude,
        longitude: _longitude,
        createdAt: now,
      );

      if (mounted) {
        Navigator.of(context).pop();
        AppToast.success(context, 'Update saved! Sending to partner...');
        widget.onUpdateSent?.call();
      }

      // 2. Fire and forget sync engine in background
      SyncEngine().processQueue(onSyncComplete: () {
        widget.onUpdateSent?.call();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Minimal Drag Handle
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
              const SizedBox(height: 14),

              // Image Thumbnail Card with Close (X) button & Location Pill
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _isSending ? null : _retakePhoto,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.supportingText.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          _currentImage,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),

                  // Floating 'X' Dismiss / Retake Button on top-right of thumbnail
                  Positioned(
                    top: -6,
                    right: -6,
                    child: GestureDetector(
                      onTap: _isSending ? null : () => Navigator.of(context).pop(),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E3832),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            '✕',
                            style: TextStyle(
                              color: AppColors.textHighContrast,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Location Badge on bottom of thumbnail
                  Positioned(
                    bottom: 6,
                    left: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _isLoadingLocation ? null : _detectLocation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2622).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _isLoadingLocation
                              ? 'Locating...'
                              : (_detectedLocation ?? 'Add location'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textHighContrast,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Modern Input Field with Embedded Send Button inside
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppColors.supportingText.withValues(alpha: 0.25),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Expanded text input
                    Expanded(
                      child: TextField(
                        controller: _captionController,
                        maxLength: 140,
                        maxLines: 3,
                        minLines: 1,
                        style: const TextStyle(
                          color: AppColors.textHighContrast,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add caption to widget...',
                          hintStyle: TextStyle(
                            color: AppColors.supportingText.withValues(alpha: 0.45),
                            fontSize: 13,
                          ),
                          counterText: '', // Hide default counter to keep input clean
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Embedded Send Action Button (Clean, backgroundless Instagram Direct paper plane)
                    GestureDetector(
                      onTap: _isSending ? null : _handleSend,
                      child: Container(
                        width: 38,
                        height: 38,
                        color: Colors.transparent,
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primaryAccent,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: AppColors.primaryAccent,
                                  size: 24,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
