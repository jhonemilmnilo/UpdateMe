import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class ReplyMomentModal extends StatefulWidget {
  final String partnerName;
  final ValueChanged<String> onSendReply;

  const ReplyMomentModal({
    super.key,
    required this.partnerName,
    required this.onSendReply,
  });

  static Future<String?> show(BuildContext context, {required String partnerName}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReplyMomentModal(
        partnerName: partnerName,
        onSendReply: (text) => Navigator.of(context).pop(text),
      ),
    );
  }

  @override
  State<ReplyMomentModal> createState() => _ReplyMomentModalState();
}

class _ReplyMomentModalState extends State<ReplyMomentModal> {
  final TextEditingController _controller = TextEditingController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final isValid = _controller.text.trim().isNotEmpty;
      if (isValid != _canSend) {
        setState(() => _canSend = isValid);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.secondarySurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reply to ${widget.partnerName}',
                style: const TextStyle(
                  color: AppColors.textHighContrast,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.supportingText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Input Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primaryAccent.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 280,
                    style: const TextStyle(
                      color: AppColors.textHighContrast,
                      fontSize: 15,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type your intimate reply...',
                      hintStyle: TextStyle(
                        color: AppColors.supportingText,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Embedded Send Action Button (Clean, backgroundless paper plane matching SendUpdateModal)
                GestureDetector(
                  onTap: _canSend ? () => widget.onSendReply(_controller.text.trim()) : null,
                  child: Container(
                    width: 38,
                    height: 38,
                    color: Colors.transparent,
                    child: Center(
                      child: Icon(
                        Icons.send_rounded,
                        size: 24,
                        color: _canSend
                            ? AppColors.primaryAccent
                            : AppColors.supportingText.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
