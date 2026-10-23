import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_service.dart';
import '../../data/couple_service.dart';
import '../modals/qr_scanner_modal.dart';

class UnpairedPairingView extends StatefulWidget {
  final UserModel user;

  const UnpairedPairingView({
    super.key,
    required this.user,
  });

  @override
  State<UnpairedPairingView> createState() => _UnpairedPairingViewState();
}

class _UnpairedPairingViewState extends State<UnpairedPairingView> {
  final GlobalKey _qrRepaintKey = GlobalKey();
  final TextEditingController _manualCodeController = TextEditingController();
  bool _isManualLoading = false;
  bool _isSavingImage = false;
  bool _isSharingImage = false;

  @override
  void dispose() {
    _manualCodeController.dispose();
    super.dispose();
  }

  // Copy pair code to clipboard
  void _copyPairCode() {
    Clipboard.setData(ClipboardData(text: widget.user.pairCode));
    AppToast.success(context, 'Pair code copied to clipboard.');
  }

  // Helper: capture the QR RepaintBoundary into PNG bytes
  Future<Uint8List?> _captureQrBytes() async {
    final boundary = _qrRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;

    return byteData.buffer.asUint8List();
  }

  // Share QR as an image file via native share sheet
  Future<void> _shareQrImage() async {
    if (_isSharingImage) return;

    try {
      setState(() => _isSharingImage = true);

      final pngBytes = await _captureQrBytes();
      if (pngBytes == null) {
        throw Exception('Unable to capture QR view.');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/updateme_pair_${widget.user.pairCode}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Connect with me on UpdateMe! My pair code: ${widget.user.pairCode}',
        subject: 'Connect with me on UpdateMe',
      );
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Failed to share QR image.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSharingImage = false);
      }
    }
  }

  // Direct save QR Code as image straight to Device Gallery
  Future<void> _saveQrImage() async {
    if (_isSavingImage) return;

    try {
      setState(() => _isSavingImage = true);

      final pngBytes = await _captureQrBytes();
      if (pngBytes == null) {
        throw Exception('Unable to capture QR view.');
      }

      // Check / request gallery access permission cleanly
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      // Save directly to the photo gallery (Pictures / DCIM)
      await Gal.putImageBytes(
        pngBytes,
        name: 'UpdateMe_Pair_${widget.user.pairCode}',
      );

      if (mounted) {
        AppToast.success(context, 'QR code saved to your gallery.');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Failed to save QR to gallery.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingImage = false);
      }
    }
  }

  // Submit manual code input
  Future<void> _submitManualCode() async {
    final code = _manualCodeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isManualLoading = true);

    try {
      await CoupleService().pairWithPartner(
        currentUserId: widget.user.id,
        pairCode: code,
      );
      if (mounted) {
        Navigator.of(context).pop(); // close manual input dialog
        AppToast.success(context, 'Connected with partner successfully.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isManualLoading = false);
        AppToast.error(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  // Dialog for manual pair code entry
  void _showManualInputDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.secondarySurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'Enter Partner Code',
            style: TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Type the 7-character code displayed on your partner’s screen.',
                style: TextStyle(color: AppColors.supportingText, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _manualCodeController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: AppColors.textHighContrast,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'UM-XXXX',
                  hintStyle: TextStyle(
                    color: AppColors.supportingText.withValues(alpha: 0.4),
                    letterSpacing: 2,
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: AppColors.supportingText.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: AppColors.supportingText)),
            ),
            ElevatedButton(
              onPressed: _isManualLoading ? null : _submitManualCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.textHighContrast,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isManualLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textHighContrast),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),

          // Headlines
          const Text(
            'Connect with your partner',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textHighContrast,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Share your code or scan theirs to link your home screen widgets.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.supportingText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // QR Code Card Wrapped in RepaintBoundary for Saving
          RepaintBoundary(
            key: _qrRepaintKey,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4F1), // Crisp high-contrast off-white canvas for QR
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: QrImageView(
                data: widget.user.pairCode,
                version: QrVersions.auto,
                size: 200.0,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF2E3832),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF2E3832),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Tappable Alphanumeric Pair Code Badge
          GestureDetector(
            onTap: _copyPairCode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.secondarySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.supportingText.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.user.pairCode,
                    style: const TextStyle(
                      color: AppColors.textHighContrast,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'TAP TO COPY',
                    style: TextStyle(
                      color: AppColors.supportingText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Secondary Action Row: Share QR & Save QR Image
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isSharingImage ? null : _shareQrImage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textHighContrast,
                      side: BorderSide(
                        color: AppColors.supportingText.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSharingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textHighContrast,
                            ),
                          )
                        : const Text(
                            'Share QR',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isSavingImage ? null : _saveQrImage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textHighContrast,
                      side: BorderSide(
                        color: AppColors.supportingText.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSavingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textHighContrast,
                            ),
                          )
                        : const Text(
                            'Save QR Image',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Manual code entry link
          TextButton(
            onPressed: _showManualInputDialog,
            child: const Text(
              'Enter partner code manually',
              style: TextStyle(
                color: AppColors.supportingText,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Primary Action: Floating / Solid Scan Partner QR Button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => QrScannerModal.show(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: AppColors.textHighContrast,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Scan Partner QR',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
