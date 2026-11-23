import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/couple_service.dart';

class QrScannerModal extends StatefulWidget {
  const QrScannerModal({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QrScannerModal(),
    );
  }

  @override
  State<QrScannerModal> createState() => _QrScannerModalState();
}

class _QrScannerModalState extends State<QrScannerModal> {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  final ImagePicker _imagePicker = ImagePicker();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _processPairCode(String code) async {
    final rawValue = code.trim();
    if (rawValue.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final currentUser = AuthService().currentUser;
      if (currentUser == null) {
        throw Exception('User session not found.');
      }

      await CoupleService().pairWithPartner(
        currentUserId: currentUser.id,
        pairCode: rawValue,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
        AppToast.error(context, _errorMessage!);
      }
    }
  }

  Future<void> _handleBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    await _processPairCode(barcode.rawValue!);
  }

  // Pick an image from gallery and scan QR code from file
  Future<void> _pickAndScanFromGallery() async {
    if (_isProcessing) return;

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );

      if (pickedFile == null) return; // User cancelled picker

      setState(() => _isProcessing = true);

      final BarcodeCapture? capture = await _cameraController.analyzeImage(pickedFile.path);

      if (capture == null || capture.barcodes.isEmpty) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppToast.error(context, 'No QR code found in the selected image.');
        }
        return;
      }

      final code = capture.barcodes.first.rawValue;
      if (code == null || code.trim().isEmpty) {
        if (mounted) {
          setState(() => _isProcessing = false);
          AppToast.error(context, 'Invalid QR code in image.');
        }
        return;
      }

      await _processPairCode(code);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        AppToast.error(context, 'Failed to analyze gallery image.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.75;

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Drag indicator
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.supportingText.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          const Text(
            'Scan partner QR code',
            style: TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Align your partner’s QR code inside the frame.',
            style: TextStyle(
              color: AppColors.supportingText,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),

          // Viewfinder Container
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    MobileScanner(
                      controller: _cameraController,
                      onDetect: _handleBarcodeDetected,
                    ),

                    // Minimalist Target Guide Overlay
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primaryAccent.withValues(alpha: 0.8),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),

                    if (_isProcessing)
                      Container(
                        color: Colors.black.withValues(alpha: 0.6),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.textHighContrast,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Action Buttons: Upload from Gallery & Cancel
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _pickAndScanFromGallery,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryAccent,
                      foregroundColor: AppColors.textHighContrast,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textHighContrast,
                            ),
                          )
                        : const Text(
                            'Upload from Gallery',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textHighContrast,
                      side: BorderSide(
                        color: AppColors.supportingText.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
