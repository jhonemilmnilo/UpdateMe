import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/update_model.dart';
import '../../data/update_service.dart';
import 'fullscreen_moments_viewer_screen.dart';

class TodayMomentsGridScreen extends StatefulWidget {
  final List<UpdateModel> moments;
  final String currentUserId;
  final String partnerName;

  const TodayMomentsGridScreen({
    super.key,
    required this.moments,
    required this.currentUserId,
    required this.partnerName,
  });

  @override
  State<TodayMomentsGridScreen> createState() => _TodayMomentsGridScreenState();
}

class _TodayMomentsGridScreenState extends State<TodayMomentsGridScreen> {
  late List<UpdateModel> _moments;
  StreamSubscription<MomentReplyEvent>? _replySubscription;

  @override
  void initState() {
    super.initState();
    _moments = List<UpdateModel>.from(widget.moments)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    _replySubscription = UpdateService().momentRepliedStream.listen((event) {
      if (!mounted) return;
      bool updated = false;
      final nextList = _moments.map((m) {
        if (m.id == event.updateId) {
          updated = true;
          return m.copyWith(
            replyText: event.replyText,
            replyCreatedAt: event.replyCreatedAt,
            isReplied: true,
            isPendingReply: false,
          );
        }
        return m;
      }).toList();

      if (updated) {
        setState(() => _moments = nextList);
      }
    });
  }

  @override
  void dispose() {
    _replySubscription?.cancel();
    super.dispose();
  }

  String get _partnerShortName {
    final trimmed = widget.partnerName.trim();
    if (trimmed.isEmpty) return 'Partner';
    return trimmed.split(' ').first;
  }

  Future<void> _openFullscreen(int index) async {
    HapticFeedback.selectionClick();
    final updatedList = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => FullscreenMomentsViewerScreen(
          moments: _moments,
          initialIndex: index,
          currentUserId: widget.currentUserId,
        ),
      ),
    );

    if (updatedList is List<UpdateModel> && mounted) {
      setState(() {
        _moments = List<UpdateModel>.from(updatedList)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayLabel = DateFormat('MMM d').format(DateTime.now());
    final countText =
        '${_moments.length} moment${_moments.length == 1 ? '' : 's'}';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_moments);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Minimalist Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop(_moments);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.secondarySurface,
                          border: Border.all(
                            color: AppColors.supportingText.withValues(alpha: 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.textHighContrast,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Today's Moments",
                            style: TextStyle(
                              color: AppColors.textHighContrast,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$todayLabel  •  $countText',
                            style: const TextStyle(
                              color: AppColors.supportingText,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                thickness: 1,
                color: Color(0x1AFFFFFF),
              ),

              // Body: Empty State or 2-Column Time-DESC Photo Grid
              Expanded(
                child: _moments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 36),
                          child: Text(
                            'No moments shared between you and $_partnerShortName today yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.supportingText,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      )
                    : GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _moments.length,
                        itemBuilder: (context, index) =>
                            _buildMomentTile(_moments[index], index),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMomentTile(UpdateModel moment, int index) {
    return GestureDetector(
      onTap: () => _openFullscreen(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: moment.isLocalImage
            ? Image.file(
                File(moment.imageUrl),
                fit: BoxFit.cover,
                cacheWidth: 300,
                cacheHeight: 300,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.secondarySurface,
                ),
              )
            : CachedNetworkImage(
                imageUrl: moment.imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                memCacheHeight: 300,
                placeholder: (context, url) => Container(
                  color: AppColors.secondarySurface,
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.secondarySurface,
                ),
              ),
      ),
    );
  }
}
