import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_session.dart';
import '../state/downloads.dart';
import '../theme.dart';

/// A book cover loaded from the server, with a fade-in and a placeholder.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.itemId,
    this.radius = 12,
    this.width = 400,
    this.fit = BoxFit.cover,
  });

  final String itemId;
  final double radius;
  final int width;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final session = context.read<AppSession>();
    final api = session.api;
    // Downloaded books keep a copy of their cover; use it when offline.
    final localCover = session.offline ? context.read<DownloadManager>().coverPath(itemId) : null;
    if (localCover != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(localCover),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const CoverPlaceholder(),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: api == null || session.offline
          ? const CoverPlaceholder()
          : Image.network(
              api.coverUri(itemId, width: width).toString(),
              headers: api.authHeaders,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const CoverPlaceholder(),
              frameBuilder: (_, child, frame, wasSync) => wasSync
                  ? child
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      child: child,
                    ),
            ),
    );
  }
}

class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [context.colors.surfaceHigh, context.colors.surface],
        ),
      ),
      child: Center(
        child: Icon(Icons.headphones_rounded, color: context.colors.muted, size: 36),
      ),
    );
  }
}

/// Forgets every downloaded image so changed covers and author photos are
/// fetched again (their web addresses stay the same after an edit).
void refreshImages() {
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
}
