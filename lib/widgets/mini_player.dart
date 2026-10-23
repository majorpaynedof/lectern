import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/player_screen.dart';
import '../state/player_controller.dart';
import '../state/theme_controller.dart' show TouchContext;
import '../theme.dart';
import 'cover.dart';

/// The bar along the bottom of the window while something is playing.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final s = player.session;
    final theme = Theme.of(context);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: s == null
          ? (player.loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox(width: double.infinity))
          : Container(
              height: context.isTouch ? 104 : 84,
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(top: BorderSide(color: context.colors.border)),
              ),
              child: Stack(
                children: [
                  // Thin progress line along the top edge.
                  ValueListenableBuilder<double>(
                    valueListenable: player.position,
                    builder: (_, pos, __) => LinearProgressIndicator(
                      value: s.duration > 0 ? (pos / s.duration).clamp(0.0, 1.0).toDouble() : 0,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                      color: context.colors.accent,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: () => openPlayer(context),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Hero(
                                      tag: 'now-playing-cover',
                                      child: Cover(itemId: s.libraryItemId, radius: 8, width: 120),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Flexible(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        ValueListenableBuilder<double>(
                                          valueListenable: player.position,
                                          builder: (_, pos, __) => Text(
                                            player.chapterAt(pos)?.title ?? s.author,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: context.colors.muted),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Previous chapter',
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: player.previousChapter,
                        ),
                        IconButton(
                          tooltip: 'Back 10s',
                          icon: const Icon(Icons.replay_10_rounded),
                          onPressed: () => player.skip(-10),
                        ),
                        const SizedBox(width: 6),
                        PlayPauseButton(size: context.isTouch ? 62 : 48),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Forward 30s',
                          icon: const Icon(Icons.forward_30_rounded),
                          onPressed: () => player.skip(30),
                        ),
                        IconButton(
                          tooltip: 'Next chapter',
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: player.nextChapter,
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${player.speed}×',
                                  style: theme.textTheme.labelLarge?.copyWith(color: context.colors.muted)),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Open player',
                                icon: const Icon(Icons.open_in_full_rounded, size: 20),
                                onPressed: () => openPlayer(context),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Round accent play/pause button shared by the mini and full players.
class PlayPauseButton extends StatelessWidget {
  const PlayPauseButton({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: context.colors.accent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: player.loading ? null : player.togglePlay,
          child: Center(
            child: player.loading
                ? SizedBox(
                    width: size * 0.4,
                    height: size * 0.4,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: context.colors.onAccent),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      key: ValueKey(player.playing),
                      size: size * 0.55,
                      color: context.colors.onAccent,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
