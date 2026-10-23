import 'package:flutter/material.dart';
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

  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final rawValue = barcode.rawValue!.trim();
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

          const SizedBox(height: 24),

          // Close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
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
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
